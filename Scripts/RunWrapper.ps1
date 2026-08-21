# Runs the game inside DOSBox-X.
#
# This is a RunWrapper rather than a CommandTemplate, and that is not a stylistic
# choice. ProcessExecutionContext.ApplyCompatibilityOptions splits a CommandTemplate
# on its FIRST SPACE to get the process filename and does not honour quotes, so a
# template beginning {InstallDir}\.dosbox\dosbox-x.exe launches "C:\Games\Age" for
# any game installed under a path containing a space. There is also nowhere in a
# static template to express a config file that has to be regenerated from the
# per-game options on every launch, or an [autoexec] block built from the action's
# own executable and working directory. Both are below.
#
# GameClient awaits this script and then tears the session down -- heartbeat,
# save upload, AfterStop -- so it must not return until DOSBox-X has exited. That
# is what -Wait is doing, and removing it would end the session the instant the
# emulator window appeared.
#
# Working directory: {InstallDir}\.lancommander\{RedistributableId}\
# Available: $ExecutablePath, $Arguments, $WorkingDirectory, $InstallDirectory,
# $GameManifest, $RedistributableManifest

$ErrorActionPreference = 'Stop'

$dosbox = Join-Path $InstallDirectory '.dosbox'
$executable = Join-Path $dosbox 'dosbox-x.exe'
$template = Join-Path $dosbox 'dosbox-x.reference.conf'
$config = Join-Path $dosbox 'dosbox-x.conf'

if (-not (Test-Path -LiteralPath $executable)) {
    Write-Error "DOSBox-X is not deployed for this game: $executable is missing. Reinstall the game's redistributables."
    $Return = $false
    return
}

# --- Resolve the per-game options ------------------------------------------------

$options = Get-RedistributableOptions -Path $InstallDirectory -Id $GameManifest.Id -Name 'DOSBox-X'

# Mirrors ConvertTo-OptionKey in the packaging module, and Parse-Config.ps1 in this
# repository. All three have to agree or an option silently stops being applied.
function ConvertTo-Key {
    param([Parameter(Mandatory)][AllowEmptyString()][string] $Key)

    $sanitized = $Key -replace ' ', '' -replace '\.', '_' -replace '-', '_'
    $sanitized = $sanitized -replace '[^A-Za-z0-9_]', '_'

    if ([string]::IsNullOrEmpty($sanitized)) { return $sanitized }

    return $sanitized.Substring(0, 1).ToUpperInvariant() + $sanitized.Substring(1)
}

function Get-OptionValue {
    param([Parameter(Mandatory)][string] $Group, [Parameter(Mandatory)][string] $Key)

    if (-not $options) { return $null }

    $groupNode = $options.PSObject.Properties[$Group]
    if (-not $groupNode -or -not $groupNode.Value) { return $null }

    $leaf = $groupNode.Value.PSObject.Properties[$Key]
    if (-not $leaf) { return $null }

    return $leaf.Value
}

# --- Work out what to mount and what to run --------------------------------------

# DOSBox-X makes no host directory visible to the guest unless it is mounted, so
# the game's own directory has to become C: before anything can run.
#
# Path.Combine rather than Join-Path: GameClient has already expanded {InstallDir}
# in the action's path, so $ExecutablePath is usually absolute -- and Join-Path
# would happily concatenate the install directory onto the front of it, producing
# 'C:\Games\Doom\C:\Games\Doom\DOOM.EXE'. Combine returns the second path
# unchanged when it is rooted, and only joins when the action was written relative
# to the install directory.
$exePath = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($InstallDirectory, $ExecutablePath))
$exeDirectory = [System.IO.Path]::GetDirectoryName($exePath)
$exeName = [System.IO.Path]::GetFileName($exePath)

$separator = [System.IO.Path]::DirectorySeparatorChar

# Prefer the action's own working directory, so a game whose data lives a level
# above its executable still sees that data. Fall back to the executable's
# directory when the two are unrelated, because a mount that does not contain the
# program is useless.
$mount = $exeDirectory
$relative = ''

if (-not [string]::IsNullOrWhiteSpace($WorkingDirectory)) {
    $candidate = [System.IO.Path]::GetFullPath($WorkingDirectory).TrimEnd($separator)

    if ($exeDirectory -eq $candidate) {
        $mount = $candidate
    }
    elseif ($exeDirectory.StartsWith($candidate + $separator, [System.StringComparison]::OrdinalIgnoreCase)) {
        $mount = $candidate
        $relative = $exeDirectory.Substring($candidate.Length).Trim($separator)
    }
    else {
        Write-Warning "Working directory '$candidate' does not contain '$exeName'; mounting '$exeDirectory' instead"
    }
}

$autoexec = [System.Collections.Generic.List[string]]::new()
$autoexec.Add('@echo off')
$autoexec.Add("mount c `"$mount`"")
$autoexec.Add('c:')

if ($relative) { $autoexec.Add("cd \$relative") }

$command = if ([string]::IsNullOrWhiteSpace($Arguments)) { $exeName } else { "$exeName $Arguments" }

# CALL, for a batch file, and this is not optional. DOSBox-X feeds the [autoexec]
# lines to the shell as a batch, and DOS batch semantics say that invoking another
# batch file WITHOUT call transfers control to it and never returns. The 'exit'
# below would then never run, DOSBox-X would drop to its own DOS prompt, and
# Start-Process -Wait would sit there for as long as the LAN party lasted. An .EXE
# or .COM returns on its own and does not need this. Verified against 2026.08.02.
if ([System.IO.Path]::GetExtension($exeName) -in @('.bat', '.cmd')) {
    $command = "call $command"
}

$autoexec.Add($command)

# Without this DOSBox-X drops to its own DOS prompt when the game exits and the
# session never ends on its own.
$autoexec.Add('exit')

# --- Rewrite the config ----------------------------------------------------------

# Rewritten in one pass from upstream's own reference file rather than through
# Update-IniValue per key. There are close to four hundred keys, so that would be
# four hundred read-modify-write cycles on every single launch. Rewriting also
# keeps upstream's comments and ordering, so the file a curious administrator
# opens still looks like the documented one.
#
# The option path is derived from the config's own section and key rather than from
# a hard-coded table, using the same transformation the schema generator applied
# when it parsed this file. A key upstream adds is written out correctly as soon as
# it appears in the schema, with no change here.

if (-not (Test-Path -LiteralPath $template)) {
    Write-Error "dosbox-x.reference.conf is missing from $dosbox; the deployment is incomplete."
    $Return = $false
    return
}

$section = $null
$applied = 0
$inAutoexec = $false
$output = [System.Collections.Generic.List[string]]::new()

foreach ($rawLine in (Get-Content -LiteralPath $template)) {
    $trimmed = $rawLine.Trim()

    if ($trimmed.StartsWith('[') -and $trimmed.Contains(']')) {
        $section = $trimmed.TrimStart('[').Split(']')[0].Trim()
        $inAutoexec = $section -eq 'autoexec'

        $output.Add($rawLine)

        # Upstream's [autoexec] is a comment telling you to put MOUNT lines here.
        # Ours replaces it wholesale; everything else in the file is preserved,
        # including whatever sections follow.
        if ($inAutoexec) { $output.AddRange($autoexec) }

        continue
    }

    # Skip upstream's placeholder lines until the next section header.
    if ($inAutoexec) { continue }

    # Comments and blanks pass through untouched, which is what preserves upstream's
    # documentation in the generated file.
    if (-not $trimmed -or $trimmed.StartsWith('#') -or $trimmed.StartsWith(';')) {
        $output.Add($rawLine)
        continue
    }

    $eq = $rawLine.IndexOf('=')

    if ($eq -le 0 -or -not $section) {
        $output.Add($rawLine)
        continue
    }

    $key = $rawLine.Substring(0, $eq).Trim()
    $value = Get-OptionValue -Group (ConvertTo-Key -Key $section) -Key (ConvertTo-Key -Key $key)

    if ($null -eq $value) {
        # Excluded from the schema, or upstream added it since the last release.
        # Upstream's own default is the right answer in both cases.
        $output.Add($rawLine)
        continue
    }

    $text = [string] $value

    # OptionDefinition.Default is object-typed and GetDefaultAsString() calls
    # ToString(), so a boolean arrives as .NET's "True"/"False". DOSBox-X parses
    # only lowercase true/false and treats anything else as false, which would turn
    # every enabled toggle off.
    if ($text -in @('True', 'False')) { $text = $text.ToLowerInvariant() }

    # Preserve upstream's column alignment so the result still reads like the
    # original file rather than a machine-mangled version of it.
    $output.Add(('{0}= {1}' -f $rawLine.Substring(0, $eq), $text).TrimEnd())
    $applied++
}

# The reference config has no [autoexec] section at all only if upstream removed
# it. Appending one keeps the launch working rather than starting an emulator that
# sits at a DOS prompt.
if (-not ($output | Where-Object { $_.Trim() -eq '[autoexec]' })) {
    $output.Add('')
    $output.Add('[autoexec]')
    $output.AddRange($autoexec)
}

Set-Content -LiteralPath $config -Value $output -Encoding utf8

Write-Host "Wrote $config ($applied option(s) applied); mounting '$mount' as C: and running $command"

# --- Launch ----------------------------------------------------------------------

# -fastlaunch skips the BIOS splash and the welcome banner, which nobody launching
# from a game library wants to sit through.
#
# -exit closes DOSBox-X when the program it ran ends. The 'exit' line in [autoexec]
# already does that, so on the happy path this is redundant -- and it is here
# precisely because the failure mode when that path breaks is an emulator sitting at
# a DOS prompt while the LANCommander session hangs behind it, heartbeat and all.
# Two independent ways out is the right number for that.
#
# The arguments are built as one pre-quoted string rather than an array because the
# config path routinely contains spaces and this leaves no doubt about where the
# quoting ends up.
$process = Start-Process -FilePath $executable `
    -ArgumentList "-fastlaunch -exit -conf `"$config`"" `
    -WorkingDirectory $dosbox `
    -Wait -PassThru

Write-Host "DOSBox-X exited with code $($process.ExitCode)"

$Return = $true

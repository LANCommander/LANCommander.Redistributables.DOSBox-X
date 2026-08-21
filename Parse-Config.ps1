<#
.SYNOPSIS
    Parses dosbox-x.reference.conf into parsed option records.
.DESCRIPTION
    dosbox-x.reference.conf is INI-shaped, but its documentation is laid out in a
    way the shared INI parser cannot follow. Upstream documents a whole section at
    once, in a single comment block between the section header and a blank line:

        [sdl]
        #        fullscreen: Start DOSBox-X directly in fullscreen.
        #            output: What video system to use for output.
        #                      Possible values: default, surface, ttf, opengl.
        #
        # Advanced options (see full configuration reference file ...):
        # -> mapperfile_sdl1; mapperfile_sdl2; forcesquarecorner
        #

        fullscreen        = false
        output            = default

    ConvertFrom-IniConfig clears its comment buffer at the first blank line, since
    everywhere else a comment block belongs to the key directly beneath it. Here
    that drops every description and every choice list on the floor, which is why
    this file exists rather than a ChoiceCommentPattern.

    Each section is buffered whole, then processed in two passes: collect the
    key = value lines, then attribute the comment block to them.

    Attribution is by exact key match rather than by shape, and that matters.
    Upstream indents explanations of individual values the same way it indents a
    key, so a shape-based rule reads this:

        #   mouse_emulation: When is mouse emulated ?
        #                      integration: when not locked
        #                      locked:      when locked

    as four options, and hands mouse_emulation's own "Possible values" line to the
    last of the imposters. Since the real key list is already in hand, a comment
    line opens a new entry only when the text before its first colon is literally
    one of this section's keys. Everything else continues the entry above it.

    The trailing "Advanced options" block lists keys that live only in
    dosbox-x.reference.full.conf. None of them appear as key = value here, so they
    would be dropped anyway -- but the '-> a; b; c' line beneath the heading would
    first be glued onto the last real option's description, so the block ends
    parsing for the section outright.

    Nothing here is specific to a DOSBox-X version. Keys upstream adds are picked
    up on the next scheduled run along with whatever documentation they carry,
    which is the whole point of parsing rather than hand-writing the schema.
.PARAMETER Content
    Raw file contents, passed by ConvertTo-OptionSchema.
.PARAMETER Source
    File name, recorded on each record for provenance.
.OUTPUTS
    Records shaped like New-ParsedOption's output: Path, Segments, Type, Default,
    Choices, Comment, Source. Built by hand rather than through the module's own
    helper, because a repository-local parser should not depend on module internals.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][AllowEmptyString()][string] $Content,
    [string] $Source
)

$ErrorActionPreference = 'Stop'

# Mirrors ConvertTo-OptionKey in the shared module. The generated dot-path has to
# match what that would have produced, because Schema.Overlay.yml is keyed by it
# and RunWrapper.ps1 derives the same path from the same config key at runtime.
function ConvertTo-Key {
    param([Parameter(Mandatory)][AllowEmptyString()][string] $Key)

    $sanitized = $Key -replace ' ', '' -replace '\.', '_' -replace '-', '_'
    $sanitized = $sanitized -replace '[^A-Za-z0-9_]', '_'

    if ([string]::IsNullOrEmpty($sanitized)) { return $sanitized }

    return $sanitized.Substring(0, 1).ToUpperInvariant() + $sanitized.Substring(1)
}

# Same rules as Get-InferredOptionType: 0 and 1 stay int, because in an INI file
# they are genuinely ambiguous and mistyping an int as bool destroys the value.
# DOSBox-X writes real booleans as true/false, so this gets them right.
function Get-Type {
    param([AllowNull()][AllowEmptyString()][string] $Value)

    if ([string]::IsNullOrWhiteSpace($Value)) { return 'string' }

    $trimmed = $Value.Trim()

    if ($trimmed -in @('true', 'false')) { return 'bool' }

    $parsed = 0
    if ([int]::TryParse($trimmed, [ref] $parsed)) { return 'int' }

    return 'string'
}

# Upstream writes valid values as one line reading 'Possible values: a, b, c.'.
# All 107 of them in the 2026.08.02 reference config are a single line ending in a
# period, and the only periods inside a list sit between digits (sb1.0, sb2.01), so
# anchoring on the final period is safe and a great deal simpler than trying to
# tell a value's period from a sentence's.
$PossibleValues = '(?i)^\s*Possible values:\s*(?<choices>.+)\.\s*$'

<#
.SYNOPSIS
    Splits one section's buffered lines into its key list and its comment block.
#>
function Split-Section {
    param([Parameter(Mandatory)][AllowEmptyCollection()][AllowEmptyString()][string[]] $Lines)

    $comments = [System.Collections.Generic.List[string]]::new()
    $pairs = [System.Collections.Generic.List[object]]::new()
    $ended = $false

    foreach ($rawLine in $Lines) {
        $line = $rawLine.Trim()

        if ([string]::IsNullOrEmpty($line)) { continue }

        if ($line.StartsWith('#') -or $line.StartsWith(';')) {
            if ($ended) { continue }

            $text = $line -replace '^\s*[#;]', ''

            # Everything from the advanced-options heading to the end of the
            # section documents keys that only exist in the full reference config.
            if ($text -match '(?i)^\s*Advanced options') {
                $ended = $true
                continue
            }

            $comments.Add($text)
            continue
        }

        $eq = $line.IndexOf('=')
        if ($eq -le 0) { continue }

        $key = $line.Substring(0, $eq).Trim()
        if (-not $key) { continue }

        $pairs.Add([pscustomobject] @{
                Key   = $key
                Value = $line.Substring($eq + 1).Trim()
            })
    }

    return [pscustomobject] @{ Comments = $comments; Pairs = $pairs }
}

<#
.SYNOPSIS
    Attributes a section's comment block to its keys.
.DESCRIPTION
    Returns key -> { Description; Choices }. A comment line opens a new entry only
    when the text before its first colon is exactly one of $Keys; anything else
    continues whichever entry was opened last. Text appearing before the first
    real header is section-level preamble and belongs to no key.
#>
function Get-SectionDocumentation {
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][AllowEmptyString()][string[]] $Comments,
        [Parameter(Mandatory)][AllowEmptyCollection()][AllowEmptyString()][string[]] $Keys
    )

    $known = [System.Collections.Generic.HashSet[string]]::new(
        [string[]] $Keys, [System.StringComparer]::OrdinalIgnoreCase)

    $entries = [ordered] @{}
    $current = $null

    foreach ($comment in $Comments) {
        if ([string]::IsNullOrWhiteSpace($comment)) { continue }

        $colon = $comment.IndexOf(':')

        if ($colon -gt 0) {
            $candidate = $comment.Substring(0, $colon).Trim()

            if ($known.Contains($candidate)) {
                $current = $candidate

                if (-not $entries.Contains($current)) {
                    $entries[$current] = [pscustomobject] @{
                        Lines   = [System.Collections.Generic.List[string]]::new()
                        Choices = @()
                    }
                }

                $rest = $comment.Substring($colon + 1).Trim()
                if ($rest) { $entries[$current].Lines.Add($rest) }

                continue
            }
        }

        if (-not $current) { continue }

        $text = $comment.Trim()

        # The choice list is data, not prose. Harvesting it here and keeping it out
        # of the description stops the admin UI printing the dropdown twice. The
        # line is dropped either way: a list of fewer than two values is not a
        # dropdown, and upstream writes a bare 'Possible values:.' for options whose
        # range it cannot enumerate ([vsync] vsyncrate), which is not a sentence
        # anyone wants to read in the admin UI.
        if ($text -match '(?i)^\s*Possible values:') {
            if ($text -match $PossibleValues) {
                $choices = @($Matches['choices'] -split ',' |
                    ForEach-Object { $_.Trim() } |
                    Where-Object { $_ } |
                    Select-Object -Unique)

                if ($choices.Count -ge 2) { $entries[$current].Choices = $choices }
            }

            continue
        }

        $entries[$current].Lines.Add($text)
    }

    return $entries
}

$records = [System.Collections.Generic.List[object]]::new()
$seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)

$section = $null
$buffer = [System.Collections.Generic.List[string]]::new()

function Add-SectionRecords {
    param([AllowNull()][AllowEmptyString()][string] $Section, [Parameter(Mandatory)][AllowEmptyCollection()][AllowEmptyString()][string[]] $Lines)

    if (-not $Lines) { return }

    $split = Split-Section -Lines $Lines

    if ($split.Pairs.Count -eq 0) { return }

    $documentation = Get-SectionDocumentation `
        -Comments @($split.Comments) `
        -Keys @($split.Pairs | ForEach-Object { $_.Key })

    foreach ($pair in $split.Pairs) {
        $comment = ''
        $choices = @()

        if ($documentation.Contains($pair.Key)) {
            $entry = $documentation[$pair.Key]
            $choices = @($entry.Choices)

            # Collapse runs of whitespace so the reflowed block reads as a sentence
            # rather than carrying upstream's column alignment into the admin UI.
            $comment = (($entry.Lines -join ' ') -replace '\s+', ' ').Trim()
        }

        $type = if ($choices.Count -gt 0) { 'choice' } else { Get-Type -Value $pair.Value }

        # Match ConvertTo-OptionDefault: booleans are stored lowercase, so an
        # unquoted YAML boolean can never reach the SDK and come back as .NET's
        # "False".
        $default = if ($type -eq 'bool') { $pair.Value.ToLowerInvariant() } else { $pair.Value }

        $segments = if ($Section) {
            @((ConvertTo-Key -Key $Section), (ConvertTo-Key -Key $pair.Key))
        }
        else {
            @(ConvertTo-Key -Key $pair.Key)
        }

        $path = ($segments -join '.')

        # ConvertTo-OptionKey strips everything outside [A-Za-z0-9_], so the pairs
        # in [mapper] -- joy1deadzone0- and joy1deadzone0+ -- both sanitise to
        # Joy1deadzone0_. Emitting both would have the second silently overwrite
        # the first while building the nested schema. Dropping the later one makes
        # that deliberate instead of accidental: one option now covers both
        # directions of the axis, which is what an administrator wants anyway, and
        # RunWrapper writes the resolved value back to both config keys because it
        # forward-maps each line through the same transformation.
        if ($seen.Contains($path)) {
            Write-Verbose "Config key '$($pair.Key)' collides with an earlier key on path '$path'; keeping the first"
            continue
        }

        [void] $seen.Add($path)

        $records.Add([pscustomobject] @{
                Path     = $path
                Segments = $segments
                Type     = $type
                Default  = $default
                Choices  = $choices
                Comment  = $comment
                Source   = $Source
            })
    }
}

foreach ($rawLine in ($Content -split "`r?`n")) {
    $line = $rawLine.Trim()

    if ($line.StartsWith('[') -and $line.Contains(']')) {
        Add-SectionRecords -Section $section -Lines @($buffer)

        $section = $line.TrimStart('[').Split(']')[0].Trim()
        $buffer.Clear()
        continue
    }

    $buffer.Add($rawLine)
}

Add-SectionRecords -Section $section -Lines @($buffer)

return $records.ToArray()

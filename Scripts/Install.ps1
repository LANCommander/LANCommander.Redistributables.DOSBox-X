# Copies the DOSBox-X runtime into the game's own .dosbox directory.
#
# There is no installation in the usual sense. The upstream payload is the portable
# build: an executable and the assets its options can reach. Nothing is registered,
# nothing goes near System32, no PATH is touched and no elevation is needed, which
# is why there is no '#Requires -RunAsAdministrator' on this script.
#
# Keeping it inside the game directory rather than somewhere shared means the
# emulator is uninstalled with the game, two games can sit on different DOSBox-X
# versions, and a game copied to another machine carries its emulator with it.
#
# Working directory: {InstallDir}\.lancommander\{RedistributableId}\Files\
# -- the extracted upstream archive. Available: $InstallDirectory, $GameManifest,
# $RedistributableManifest

$ErrorActionPreference = 'Stop'

$metadata = Join-Path $InstallDirectory (Join-Path '.lancommander' $RedistributableManifest.Id)
$files = Join-Path $metadata 'Files'
$target = Join-Path $InstallDirectory '.dosbox'

if (-not (Test-Path -LiteralPath (Join-Path $files 'dosbox-x.exe'))) {
    Write-Error "dosbox-x.exe is not present in $files; the redistributable archive did not download or extract correctly"
    $Return = 1
    return
}

# Remove any previous deployment rather than copying over it. An upstream release
# that drops a shader or a language file would otherwise leave the old one behind
# for ever, and the version stamp would claim the directory was clean.
if (Test-Path -LiteralPath $target) {
    Remove-Item -LiteralPath $target -Recurse -Force
}

New-Item -ItemType Directory -Path $target -Force | Out-Null

Copy-Item -Path (Join-Path $files '*') -Destination $target -Recurse -Force

$copied = @(Get-ChildItem -LiteralPath $target -Recurse -File)

Write-Host "DOSBox-X $($RedistributableManifest.Version): deployed $($copied.Count) file(s) to $target"

# Written last, once the copy has succeeded. DetectInstall compares against this,
# so it must not exist unless the deployment is complete and usable.
Set-Content -LiteralPath (Join-Path $metadata 'InstalledVersion.txt') `
    -Value ([string] $RedistributableManifest.Version) -Encoding utf8 -NoNewline

$Return = 0

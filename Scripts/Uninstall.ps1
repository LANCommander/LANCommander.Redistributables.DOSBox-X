# Removes the .dosbox directory Install created, along with the config RunWrapper
# generates inside it.
#
# Unlike a shared system runtime, this deployment belongs to exactly one game, so
# removing it outright is correct rather than reckless -- there is no other game
# that could still be depending on it.
#
# Working directory: {InstallDir}\.lancommander\{RedistributableId}\Files\
# Available: $InstallDirectory, $GameManifest, $RedistributableManifest

$ErrorActionPreference = 'Stop'

$root = [System.IO.Path]::GetFullPath($InstallDirectory)
$target = [System.IO.Path]::GetFullPath((Join-Path $InstallDirectory '.dosbox'))

# The path is built from $InstallDirectory two lines above, so this can only fail
# if that variable is empty or something upstream changed. That is exactly when a
# recursive delete must not run.
if (-not $target.StartsWith($root.TrimEnd([System.IO.Path]::DirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar)) {
    Write-Error "Refusing to remove '$target': it is not inside the game's install directory '$root'"
    $Return = 1
    return
}

if (Test-Path -LiteralPath $target) {
    Remove-Item -LiteralPath $target -Recurse -Force
    Write-Host "Removed $target"
}

$stamp = Join-Path (Join-Path $InstallDirectory (Join-Path '.lancommander' $RedistributableManifest.Id)) 'InstalledVersion.txt'

if (Test-Path -LiteralPath $stamp) {
    Remove-Item -LiteralPath $stamp -Force
}

$Return = 0

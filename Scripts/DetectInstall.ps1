# DOSBox-X is deployed per game into the game's own .dosbox directory rather than
# system-wide, so detection is a file check plus a version stamp.
#
# The stamp is what makes a new upstream release install over an old one. Returning
# $true here skips the download AND the Install script, so a bare "the file exists"
# check would pin every client to the first version it ever installed.
#
# The executable is checked as well as the stamp, so a .dosbox directory an
# administrator deleted by hand is redeployed rather than assumed present.
#
# Working directory: {InstallDir}\.lancommander\{RedistributableId}\
# -- one level above Files\, which may not exist yet.
#
# Hard 10 second timeout and no network calls: this is two file reads.

$metadata = Join-Path $InstallDirectory (Join-Path '.lancommander' $RedistributableManifest.Id)
$executable = Join-Path (Join-Path $InstallDirectory '.dosbox') 'dosbox-x.exe'
$stamp = Join-Path $metadata 'InstalledVersion.txt'

$Return = $false

if ((Test-Path -LiteralPath $executable) -and (Test-Path -LiteralPath $stamp)) {
    $installed = ([string] (Get-Content -LiteralPath $stamp -Raw -ErrorAction SilentlyContinue)).Trim()

    # Install writes the stamp last, after everything else has succeeded, so a
    # matching version means the deployed copy is both current and usable.
    $Return = $installed -eq ([string] $RedistributableManifest.Version).Trim()
}

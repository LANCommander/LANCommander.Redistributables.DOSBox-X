<#
.SYNOPSIS
    Resolves and downloads the upstream release for DOSBox-X.
.DESCRIPTION
    Contract:
      -CheckOnly            write the upstream version to stdout and exit.
      -OutputPath <dir>     download and extract the payload there, then emit a
                            JSON object with Version and optionally Changelog.

    Two things here are specific to DOSBox-X.

    The version needs unwrapping. Resolve-UpstreamVersion strips exactly one
    leading 'v' from a tag, which is right for 'v1.4.4' and useless for
    'dosbox-x-v2026.08.02'. Both code paths below strip the project prefix so the
    version reported by -CheckOnly and the version stamped on the package can
    never disagree -- the scheduled upstream check compares the first against
    LastKnownVersion, and a mismatch would make it open a pull request every day.

    What survives from the archive is narrowed hard, because unlike a DLL shim
    this payload is copied into every DOS game's directory. The upstream zip is
    53 MB per build, of which 27 MB is CJK typography that a DOS game only touches
    under TrueType output with a CJK code page. Dropping those three files roughly
    halves the per-game cost; everything an ordinary game can reach -- shaders,
    GLSL shaders, language files, the default TTF font, the PC-98 character
    generator -- is kept.
#>
[CmdletBinding(DefaultParameterSetName = 'Download')]
param(
    [Parameter(ParameterSetName = 'Check')][switch] $CheckOnly,
    [Parameter(ParameterSetName = 'Download', Mandatory)][string] $OutputPath
)

$ErrorActionPreference = 'Stop'

# Upstream tags the release 'dosbox-x-v2026.08.02' but calls the version
# '2026.08.02' everywhere else, including in the config file it ships.
function ConvertTo-UpstreamVersion {
    param([Parameter(Mandatory)][AllowEmptyString()][string] $Tag)

    return ($Tag -replace '^dosbox-x-v?', '' -replace '^v', '')
}

$definition = Get-RedistributableDefinition -Path $PSScriptRoot
$source = $definition['Source']

$upstream = Resolve-UpstreamVersion `
    -Resolver ([string] $source['Resolver']) `
    -Url ([string] $source['Url']) `
    -AssetPattern ([string] $source['AssetPattern'])

$version = ConvertTo-UpstreamVersion -Tag $upstream.Version

if ($CheckOnly) {
    Write-Output $version
    return
}

if (-not $upstream.DownloadUrl) {
    throw "No asset matched $($source['AssetPattern']) on release $($upstream.Version)"
}

$archive = Join-Path ([System.IO.Path]::GetTempPath()) "DOSBox-X-$version.zip"
$extracted = Join-Path ([System.IO.Path]::GetTempPath()) "DOSBox-X-extract-$([guid]::NewGuid())"

try {
    Write-Verbose "Downloading $($upstream.DownloadUrl)"
    Invoke-WebRequest -Uri $upstream.DownloadUrl -OutFile $archive -MaximumRetryCount 3 -RetryIntervalSec 5

    Expand-Archive -Path $archive -DestinationPath $extracted -Force

    # The archive carries four builds -- 'Release' and 'Release SDL2' under an
    # architecture directory. 'Release' is the SDL1 build, which upstream treats as
    # the default on Windows. Locating it by searching for the executable rather
    # than by hard-coding bin/x64 means a layout change surfaces as a clear error
    # here instead of an empty payload downstream.
    $build = Get-ChildItem -LiteralPath $extracted -Directory -Recurse |
        Where-Object { $_.Name -eq 'Release' -and (Test-Path -LiteralPath (Join-Path $_.FullName 'dosbox-x.exe')) } |
        Select-Object -First 1

    if (-not $build) {
        throw "No 'Release' directory containing dosbox-x.exe was found in the upstream archive; its layout has changed"
    }

    Write-Verbose "Using build directory $($build.FullName)"

    # Runtime assets an exposed option can actually reach:
    #   dosbox-x.reference.conf  the config the option schema is generated from,
    #                            and the template RunWrapper rewrites at launch
    #   inpoutx64.dll            direct I/O port access for real parallel hardware
    #   Nouveau_IBM.ttf          default font for output=ttf
    #   FREECG98.BMP             PC-98 character generator, for machine=pc98
    #   shaders/                 Direct3D pixel shaders behind [render] pixelshader
    #   glshaders/               GLSL shaders behind [render] glshader
    #   languages/               language files behind [dosbox] language
    #   drivez/                  contents appear on the emulated Z: drive
    #
    # Deliberately left behind: dosbox-x.conf (a second config that would compete
    # with the generated one), dosbox-x.reference.full.conf, CHANGELOG.txt,
    # README.txt, scripts/ (Explorer shell integration installers), and the CJK
    # fonts SarasaGothicFixed.ttf, wqy_11pt.bdf and wqy_12pt.bdf.
    $files = @(
        'dosbox-x.exe'
        'dosbox-x.reference.conf'
        'inpoutx64.dll'
        'Nouveau_IBM.ttf'
        'FREECG98.BMP'
    )

    $directories = @('shaders', 'glshaders', 'languages', 'drivez')

    foreach ($file in $files) {
        $path = Join-Path $build.FullName $file

        if (-not (Test-Path -LiteralPath $path)) {
            # A missing shader or font is survivable; a missing executable or the
            # config the whole schema is generated from is not.
            if ($file -in @('dosbox-x.exe', 'dosbox-x.reference.conf')) {
                throw "Required file '$file' is missing from the upstream build directory"
            }

            Write-Warning "Upstream no longer ships '$file'; skipping it"
            continue
        }

        Copy-Item -LiteralPath $path -Destination (Join-Path $OutputPath $file) -Force
    }

    foreach ($directory in $directories) {
        $path = Join-Path $build.FullName $directory

        if (-not (Test-Path -LiteralPath $path)) {
            Write-Warning "Upstream no longer ships '$directory/'; skipping it"
            continue
        }

        Copy-Item -LiteralPath $path -Destination $OutputPath -Recurse -Force
    }

    # The upstream license travels with the binaries. GPL section 1 asks for it to
    # accompany the copies, not merely to sit in the repository that built them.
    $license = Join-Path $PSScriptRoot 'LICENSES/UPSTREAM-LICENSE.txt'

    if (Test-Path -LiteralPath $license) {
        Copy-Item -LiteralPath $license -Destination (Join-Path $OutputPath 'COPYING.txt') -Force
    }
}
finally {
    Remove-Item -LiteralPath $archive -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $extracted -Recurse -Force -ErrorAction SilentlyContinue
}

@{
    Version   = $version
    Changelog = $upstream.Changelog
} | ConvertTo-Json -Compress | Write-Output

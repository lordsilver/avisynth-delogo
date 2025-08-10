[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$SourceDirectory,
    [string]$OutputDirectory = (Join-Path $PSScriptRoot "..\..\dist"),
    [string]$Version = (Get-Date -Format "yyyy.MM.dd")
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$toolchainRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$resolvedSourceDirectory = (Resolve-Path -LiteralPath $SourceDirectory).Path
$stagingRoot = Join-Path ([IO.Path]::GetTempPath()) "avisynth-delogo-sources-$([Guid]::NewGuid().ToString('N'))"
$bundleName = "avisynth-delogo-sources-$Version"
$bundleRoot = Join-Path $stagingRoot $bundleName
$assetRoot = Join-Path $bundleRoot "assets"

function Get-Sha256 {
    param([Parameter(Mandatory)][string]$Path)

    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

New-Item -ItemType Directory -Path $OutputDirectory, $assetRoot -Force | Out-Null

try {
    $sourceAssets = @(Get-ChildItem -LiteralPath $resolvedSourceDirectory -File)
    if ($sourceAssets.Count -eq 0) {
        throw "No source assets were found in '$resolvedSourceDirectory'."
    }

    $sourceAssets | Copy-Item -Destination $assetRoot
    Copy-Item -LiteralPath (Join-Path $toolchainRoot "manifests\toolchain.lock.json") -Destination (Join-Path $bundleRoot "toolchain.lock.json")
    Copy-Item -LiteralPath (Join-Path $toolchainRoot "manifests\sources.yaml") -Destination (Join-Path $bundleRoot "sources.yaml")
    Copy-Item -LiteralPath (Join-Path $toolchainRoot "docs\source-bundle-readme.md") -Destination (Join-Path $bundleRoot "README.md")
    Copy-Item -LiteralPath (Join-Path $toolchainRoot "docs\third-party-notices.md") -Destination (Join-Path $bundleRoot "THIRD-PARTY-NOTICES.md")

    $archivePath = Join-Path ([IO.Path]::GetFullPath($OutputDirectory)) "$bundleName.zip"
    $sevenZip = Get-Command 7z, 7zz, 7za -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $sevenZip) {
        throw "7-Zip is required to create the source archive."
    }

    if (Test-Path -LiteralPath $archivePath) {
        Remove-Item -LiteralPath $archivePath -Force
    }

    Push-Location $stagingRoot
    try {
        & $sevenZip.Source a -tzip -mx=9 -mm=Deflate $archivePath $bundleName | Out-Null
        if ($LASTEXITCODE -ne 0) {
            throw "7-Zip failed with exit code $LASTEXITCODE while creating the source archive."
        }
    }
    finally {
        Pop-Location
    }

    $archiveHash = Get-Sha256 -Path $archivePath
    Set-Content -LiteralPath "$archivePath.sha256" -Value "$archiveHash  $([IO.Path]::GetFileName($archivePath))" -Encoding ascii
    Write-Host "Created source archive: $archivePath"
    Write-Host "SHA-256: $archiveHash"
}
finally {
    Remove-Item -LiteralPath $stagingRoot -Recurse -Force -ErrorAction SilentlyContinue
}

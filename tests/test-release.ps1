[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ToolchainArchive,
    [Parameter(Mandatory)][string]$SourceArchive
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$repositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$toolchainDirectory = Join-Path $repositoryRoot "toolchain"
$lock = Get-Content -LiteralPath (Join-Path $toolchainDirectory "manifests/toolchain.lock.json") -Raw | ConvertFrom-Json -Depth 20
$temporaryRoot = Join-Path ([IO.Path]::GetTempPath()) "avisynth-delogo-release-test-$([Guid]::NewGuid().ToString('N'))"

function Assert-FileHash {
    param([string]$Path, [string]$ExpectedHash)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Missing archive file: $Path"
    }
    $actual = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
    if ($actual -ne $ExpectedHash) {
        throw "Archive file hash mismatch: $Path"
    }
}

function Expand-CheckedArchive {
    param([string]$Archive, [string]$Directory)

    $archivePath = (Resolve-Path -LiteralPath $Archive).Path
    $checksum = (Get-Content -LiteralPath "$archivePath.sha256" -Raw).Trim() -split '\s+', 2
    if ($checksum.Count -ne 2 -or $checksum[1] -cne [IO.Path]::GetFileName($archivePath)) {
        throw "Invalid archive checksum sidecar: $archivePath.sha256"
    }
    Assert-FileHash -Path $archivePath -ExpectedHash $checksum[0]
    Expand-Archive -LiteralPath $archivePath -DestinationPath $Directory
    $entries = @(Get-ChildItem -LiteralPath $Directory -Force)
    if ($entries.Count -ne 1 -or -not $entries[0].PSIsContainer -or $entries[0].Name -cne [IO.Path]::GetFileNameWithoutExtension($archivePath)) {
        throw "Archive must contain one directory named after the ZIP: $archivePath"
    }
    return $entries[0].FullName
}

try {
    $bundleRoot = Expand-CheckedArchive -Archive $ToolchainArchive -Directory (Join-Path $temporaryRoot "binary")
    $sourceRoot = Expand-CheckedArchive -Archive $SourceArchive -Directory (Join-Path $temporaryRoot "sources")

    foreach ($root in @($bundleRoot, $sourceRoot)) {
        foreach ($manifest in @("toolchain.lock.json", "sources.yaml")) {
            $expectedHash = (Get-FileHash -LiteralPath (Join-Path $toolchainDirectory "manifests/$manifest") -Algorithm SHA256).Hash
            Assert-FileHash -Path (Join-Path $root $manifest) -ExpectedHash $expectedHash
        }
        $noticeHash = (Get-FileHash -LiteralPath (Join-Path $toolchainDirectory "THIRD-PARTY-NOTICES.md") -Algorithm SHA256).Hash
        Assert-FileHash -Path (Join-Path $root "THIRD-PARTY-NOTICES.md") -ExpectedHash $noticeHash
    }

    foreach ($entry in $lock.files) {
        if ($entry.required -or (Test-Path -LiteralPath (Join-Path $bundleRoot $entry.relative_path))) {
            Assert-FileHash -Path (Join-Path $bundleRoot $entry.relative_path) -ExpectedHash $entry.sha256
        }
    }
    foreach ($overlay in @(@{ name = "bundle"; root = $bundleRoot }, @{ name = "source-bundle"; root = $sourceRoot })) {
        $overlayRoot = Join-Path $toolchainDirectory $overlay.name
        foreach ($file in Get-ChildItem -LiteralPath $overlayRoot -Recurse -File -Force) {
            $relativePath = [IO.Path]::GetRelativePath($overlayRoot, $file.FullName)
            Assert-FileHash -Path (Join-Path $overlay.root $relativePath) -ExpectedHash (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash
        }
    }
    foreach ($unexpectedPath in @("Tools", "Plugins/plugins64+", "AvsPmod/AvsPmod_64", "scripts", "tests", ".github", ".scratch")) {
        if (Test-Path -LiteralPath (Join-Path $bundleRoot $unexpectedPath)) {
            throw "Unexpected directory in portable bundle: $unexpectedPath"
        }
    }

    $expectedAssets = @{}
    foreach ($entry in $lock.files) {
        $name = [IO.Path]::GetFileName(([Uri]$entry.source.uri).AbsolutePath)
        $expectedAssets[$name] = $entry.source.sha256
    }
    foreach ($package in $lock.packages) {
        $expectedAssets[$package.asset] = $package.sha256
    }
    $assetRoot = Join-Path $sourceRoot "assets"
    $assets = @(Get-ChildItem -LiteralPath $assetRoot -Force)
    if ($assets.Count -ne $expectedAssets.Count) {
        throw "Source archive does not contain exactly the locked upstream inputs."
    }
    foreach ($name in $expectedAssets.Keys) {
        Assert-FileHash -Path (Join-Path $assetRoot $name) -ExpectedHash $expectedAssets[$name]
    }

    $pwsh = (Get-Process -Id $PID).Path
    & $pwsh -NoProfile -File (Join-Path $bundleRoot "verify-toolchain.ps1") -ToolchainRoot $bundleRoot
    if ($LASTEXITCODE -ne 0) {
        throw "Bundled toolchain verification failed."
    }

    if ($IsWindows) {
        & $pwsh -NoProfile -File (Join-Path $PSScriptRoot "test-validate-render.ps1") -ToolchainRoot $bundleRoot -ValidatorPath (Join-Path $bundleRoot "validate-render.ps1")
        if ($LASTEXITCODE -ne 0) {
            throw "Bundled render validator regression tests failed."
        }
    }
    else {
        Write-Host "Native AviSynth and bundled FFmpeg execution require Windows; archive contents and hashes were checked."
    }

    Write-Host "Release archive tests: PASS"
}
finally {
    Remove-Item -LiteralPath $temporaryRoot -Recurse -Force -ErrorAction SilentlyContinue
}

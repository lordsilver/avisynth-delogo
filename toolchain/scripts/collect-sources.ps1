[CmdletBinding()]
param(
    [string]$CacheDirectory = (Join-Path ([IO.Path]::GetTempPath()) "avisynth-delogo-source-cache"),
    [string]$OutputDirectory = (Join-Path ([IO.Path]::GetTempPath()) "avisynth-delogo-source-assets"),
    [string]$OfflineCacheRoot = $env:AVISYNTH_DELOGO_OFFLINE_CACHE_ROOT,
    [string]$LockFile = (Join-Path $PSScriptRoot "..\manifests\toolchain.lock.json")
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Get-Sha256 {
    param([Parameter(Mandatory)][string]$Path)

    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Add-SourceInput {
    param(
        [Parameter(Mandatory)][hashtable]$Inputs,
        [Parameter(Mandatory)][string]$CachePath,
        [Parameter(Mandatory)][string]$Uri,
        [Parameter(Mandatory)][string]$Sha256,
        [Parameter(Mandatory)][string]$Asset,
        [Parameter(Mandatory)][bool]$Publish
    )

    if ($Inputs.ContainsKey($CachePath)) {
        $existing = $Inputs[$CachePath]
        if ($existing.Uri -ne $Uri -or $existing.Sha256 -ne $Sha256 -or $existing.Asset -ne $Asset -or $existing.Publish -ne $Publish) {
            throw "Conflicting source definitions for '$CachePath'."
        }
        return
    }

    $Inputs[$CachePath] = [pscustomobject]@{
        CachePath = $CachePath
        Uri       = $Uri
        Sha256    = $Sha256.ToLowerInvariant()
        Asset     = $Asset
        Publish   = $Publish
    }
}

if (-not (Test-Path -LiteralPath $LockFile -PathType Leaf)) {
    throw "Toolchain lock file not found: $LockFile"
}

$lock = Get-Content -LiteralPath $LockFile -Raw | ConvertFrom-Json -Depth 20
$inputs = @{}

foreach ($entry in $lock.files) {
    $source = $entry.source
    $uri = [Uri][string]$source.uri
    Add-SourceInput -Inputs $inputs -CachePath ([string]$source.cache_path) -Uri $uri.AbsoluteUri -Sha256 ([string]$source.sha256) -Asset ([IO.Path]::GetFileName($uri.AbsolutePath)) -Publish $true
}

foreach ($package in $lock.packages) {
    Add-SourceInput -Inputs $inputs -CachePath ([string]$package.cache_path) -Uri ([string]$package.source) -Sha256 ([string]$package.sha256) -Asset ([string]$package.asset) -Publish $true
}

New-Item -ItemType Directory -Path $CacheDirectory, $OutputDirectory -Force | Out-Null

$publishedAssets = @{}
foreach ($input in $inputs.Values | Sort-Object CachePath) {
    $cachedPath = Join-Path $CacheDirectory $input.CachePath
    New-Item -ItemType Directory -Path (Split-Path -Parent $cachedPath) -Force | Out-Null

    if (-not (Test-Path -LiteralPath $cachedPath -PathType Leaf)) {
        $offlinePath = if ($OfflineCacheRoot) { Join-Path $OfflineCacheRoot $input.CachePath } else { $null }
        if ($offlinePath -and (Test-Path -LiteralPath $offlinePath -PathType Leaf)) {
            Write-Host "Using cached input: $($input.CachePath)"
            Copy-Item -LiteralPath $offlinePath -Destination $cachedPath
        }
        else {
            Write-Host "Downloading input: $($input.CachePath) from $($input.Uri)"
            Invoke-WebRequest -Uri $input.Uri -OutFile $cachedPath -MaximumRetryCount 3 -RetryIntervalSec 2 -ConnectionTimeoutSeconds 600 -OperationTimeoutSeconds 60
        }
    }

    $actualHash = Get-Sha256 -Path $cachedPath
    if ($actualHash -ne $input.Sha256) {
        throw "Source hash mismatch for '$($input.CachePath)': expected $($input.Sha256), got $actualHash"
    }

    if ($input.Publish) {
        if ($publishedAssets.ContainsKey($input.Asset) -and $publishedAssets[$input.Asset] -ne $input.Sha256) {
            throw "Conflicting release assets named '$($input.Asset)'."
        }

        Copy-Item -LiteralPath $cachedPath -Destination (Join-Path $OutputDirectory $input.Asset) -Force
        $publishedAssets[$input.Asset] = $input.Sha256
    }
}

Write-Host "Prepared $($inputs.Count) verified build inputs and $($publishedAssets.Count) source release assets."

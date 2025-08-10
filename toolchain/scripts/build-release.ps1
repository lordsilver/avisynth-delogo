[CmdletBinding()]
param(
    [string]$OutputDirectory = (Join-Path $PSScriptRoot "..\..\dist"),
    [string]$OfflineCacheRoot = $env:AVISYNTH_DELOGO_OFFLINE_CACHE_ROOT,
    [string]$Version = (Get-Date -Format "yyyy.MM.dd")
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$toolchainRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$lockFile = Join-Path $toolchainRoot "manifests\toolchain.lock.json"
$lock = Get-Content -LiteralPath $lockFile -Raw | ConvertFrom-Json -Depth 20
$stagingRoot = Join-Path ([IO.Path]::GetTempPath()) "avisynth-delogo-release-$([Guid]::NewGuid().ToString('N'))"
$bundleName = "avisynth-delogo-x64-$Version"
$bundleRoot = Join-Path $stagingRoot $bundleName
$downloadRoot = Join-Path $stagingRoot "downloads"

function Get-Sha256 {
    param([Parameter(Mandatory)][string]$Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Resolve-PackageSource {
    param([Parameter(Mandatory)]$Package)

    if ($OfflineCacheRoot -and $Package.cache_path) {
        $cachedPath = Join-Path $OfflineCacheRoot ([string]$Package.cache_path)
        if (Test-Path -LiteralPath $cachedPath -PathType Leaf) {
            return (Resolve-Path -LiteralPath $cachedPath).Path
        }
    }

    $destination = Join-Path $downloadRoot ([string]$Package.asset)
    Invoke-WebRequest -Uri ([string]$Package.source) -OutFile $destination -MaximumRetryCount 3 -RetryIntervalSec 2 -ConnectionTimeoutSeconds 600 -OperationTimeoutSeconds 60
    return $destination
}

New-Item -ItemType Directory -Path $OutputDirectory, $bundleRoot, $downloadRoot -Force | Out-Null

try {
    & (Join-Path $PSScriptRoot "bootstrap-toolchain.ps1") -ToolchainRoot $bundleRoot -OfflineCacheRoot $OfflineCacheRoot -LockFile $lockFile

    foreach ($package in $lock.packages | Where-Object { $_.include_in_bundle }) {
        $sourcePath = Resolve-PackageSource -Package $package
        $actualHash = Get-Sha256 -Path $sourcePath
        if ($actualHash -ne ([string]$package.sha256).ToLowerInvariant()) {
            throw "Package hash mismatch for '$($package.component)': expected $($package.sha256), got $actualHash"
        }

        $destination = Join-Path $bundleRoot ([string]$package.install_subdirectory)
        New-Item -ItemType Directory -Path $destination -Force | Out-Null

        if ($package.archive_type -eq "file") {
            Copy-Item -LiteralPath $sourcePath -Destination (Join-Path $destination ([string]$package.asset)) -Force
        }
        elseif ($package.archive_type -eq "zip") {
            Expand-Archive -LiteralPath $sourcePath -DestinationPath $destination -Force
        }
        elseif ($package.archive_type -eq "7z") {
            $sevenZip = Get-Command 7z, 7zz, 7za -ErrorAction SilentlyContinue | Select-Object -First 1
            if (-not $sevenZip) {
                throw "7-Zip is required to extract '$($package.asset)'."
            }

            & $sevenZip.Source x -y "-o$destination" $sourcePath | Out-Null
            if ($LASTEXITCODE -ne 0) {
                throw "7-Zip failed with exit code $LASTEXITCODE for '$($package.asset)'."
            }
        }
        else {
            throw "Unsupported package archive type '$($package.archive_type)'."
        }

        if ($package.PSObject.Properties.Name -contains "exclude_paths") {
            $destinationRoot = [IO.Path]::GetFullPath($destination).TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
            foreach ($relativePath in @($package.exclude_paths)) {
                $excludedPath = [IO.Path]::GetFullPath((Join-Path $destination ([string]$relativePath)))
                if (-not $excludedPath.StartsWith($destinationRoot, [StringComparison]::OrdinalIgnoreCase)) {
                    throw "Package exclude path escapes its destination: $relativePath"
                }

                if (Test-Path -LiteralPath $excludedPath) {
                    Remove-Item -LiteralPath $excludedPath -Recurse -Force
                }
            }
        }
    }

    $avsPmodRoot = Join-Path $bundleRoot "AvsPmod"
    $extractedAvsPmodRoot = Join-Path $avsPmodRoot "AvsPmod_64"
    $extractedAvsPmodExecutable = Join-Path $extractedAvsPmodRoot "AvsPmod.exe"
    if (-not (Test-Path -LiteralPath $extractedAvsPmodExecutable -PathType Leaf)) {
        throw "Expected AvsPmod_64\AvsPmod.exe in the AvsPmod package."
    }

    Get-ChildItem -LiteralPath $extractedAvsPmodRoot -Force | Move-Item -Destination $avsPmodRoot -Force
    Remove-Item -LiteralPath $extractedAvsPmodRoot -Force
    Copy-Item -LiteralPath (Join-Path $toolchainRoot "config\avspmod-options.dat") -Destination (Join-Path $avsPmodRoot "options.dat") -Force
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot "activate.ps1") -Destination (Join-Path $bundleRoot "activate.ps1")
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot "Start-AvsPmod.cmd") -Destination (Join-Path $bundleRoot "Start-AvsPmod.cmd")
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot "verify-toolchain.ps1") -Destination (Join-Path $bundleRoot "verify-toolchain.ps1")
    Copy-Item -LiteralPath (Join-Path $toolchainRoot "docs\bundle-readme.md") -Destination (Join-Path $bundleRoot "README.md")
    Copy-Item -LiteralPath (Join-Path $toolchainRoot "docs\third-party-notices.md") -Destination (Join-Path $bundleRoot "THIRD-PARTY-NOTICES.md")
    Copy-Item -LiteralPath $lockFile -Destination (Join-Path $bundleRoot "toolchain.lock.json")
    Copy-Item -LiteralPath (Join-Path $toolchainRoot "manifests\sources.yaml") -Destination (Join-Path $bundleRoot "sources.yaml")

    & (Join-Path $PSScriptRoot "verify-toolchain.ps1") -ToolchainRoot $bundleRoot -LockFile $lockFile
    if ($LASTEXITCODE -ne 0) {
        throw "Toolchain verification failed with exit code $LASTEXITCODE."
    }

    $archivePath = Join-Path ([IO.Path]::GetFullPath($OutputDirectory)) "$bundleName.zip"
    $sevenZip = Get-Command 7z, 7zz, 7za -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $sevenZip) {
        throw "7-Zip is required to create the release archive."
    }

    if (Test-Path -LiteralPath $archivePath) {
        Remove-Item -LiteralPath $archivePath -Force
    }

    Push-Location $stagingRoot
    try {
        & $sevenZip.Source a -tzip -mx=9 -mm=Deflate $archivePath $bundleName | Out-Null
        if ($LASTEXITCODE -ne 0) {
            throw "7-Zip failed with exit code $LASTEXITCODE while creating the release archive."
        }
    }
    finally {
        Pop-Location
    }

    $archiveHash = Get-Sha256 -Path $archivePath
    Set-Content -LiteralPath "$archivePath.sha256" -Value "$archiveHash  $([IO.Path]::GetFileName($archivePath))" -Encoding ascii
    Write-Host "Created release archive: $archivePath"
    Write-Host "SHA-256: $archiveHash"
}
finally {
    Remove-Item -LiteralPath $stagingRoot -Recurse -Force -ErrorAction SilentlyContinue
}

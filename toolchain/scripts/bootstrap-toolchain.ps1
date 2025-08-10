[CmdletBinding()]
param(
    [string]$ToolchainRoot = $(if ($env:AVISYNTH_DELOGO_ROOT) { $env:AVISYNTH_DELOGO_ROOT } else { Join-Path ([Environment]::GetFolderPath("LocalApplicationData")) "avisynth-delogo" }),
    [string]$OfflineCacheRoot = $env:AVISYNTH_DELOGO_OFFLINE_CACHE_ROOT,
    [string]$LockFile = $(if (Test-Path -LiteralPath (Join-Path $PSScriptRoot "toolchain.lock.json")) { Join-Path $PSScriptRoot "toolchain.lock.json" } else { Join-Path $PSScriptRoot "..\manifests\toolchain.lock.json" })
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Get-Sha256 {
    param([Parameter(Mandatory)][string]$Path)

    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-OptionalProperty {
    param(
        [Parameter(Mandatory)]$Object,
        [Parameter(Mandatory)][string]$Name
    )

    $property = $Object.PSObject.Properties[$Name]
    if ($property) {
        return $property.Value
    }

    return $null
}

function Assert-LockEntry {
    param([Parameter(Mandatory)]$Entry)

    $requiredProperties = @("relative_path", "component", "version", "architecture", "sha256", "license", "required", "source")
    foreach ($property in $requiredProperties) {
        if ($null -eq $Entry.$property -or [string]::IsNullOrWhiteSpace([string]$Entry.$property)) {
            throw "Lock entry is missing required property '$property'."
        }
    }

    if ($Entry.sha256 -notmatch "^[0-9a-fA-F]{64}$") {
        throw "Invalid SHA-256 for '$($Entry.relative_path)'."
    }

    if ($Entry.architecture -notin @("x64", "x86", "any")) {
        throw "Unsupported architecture '$($Entry.architecture)' for '$($Entry.relative_path)'."
    }

    if ($Entry.source.type -notin @("file", "zip", "7z")) {
        throw "Unsupported source type '$($Entry.source.type)' for '$($Entry.relative_path)'."
    }

    $sourceUri = Get-OptionalProperty -Object $Entry.source -Name "uri"
    $cachePath = Get-OptionalProperty -Object $Entry.source -Name "cache_path"
    if ([string]::IsNullOrWhiteSpace([string]$sourceUri) -and [string]::IsNullOrWhiteSpace([string]$cachePath)) {
        throw "'$($Entry.relative_path)' needs source.uri, source.cache_path, or both."
    }
}

function Resolve-SourceFile {
    param(
        [Parameter(Mandatory)]$Entry,
        [Parameter(Mandatory)][string]$DownloadRoot
    )

    $cachePath = Get-OptionalProperty -Object $Entry.source -Name "cache_path"
    $sourceUri = Get-OptionalProperty -Object $Entry.source -Name "uri"

    if ($OfflineCacheRoot -and $cachePath) {
        $cachedPath = Join-Path $OfflineCacheRoot ([string]$cachePath)
        if (Test-Path -LiteralPath $cachedPath -PathType Leaf) {
            return (Resolve-Path -LiteralPath $cachedPath).Path
        }
    }

    if ([string]::IsNullOrWhiteSpace([string]$sourceUri)) {
        throw "Offline source for '$($Entry.relative_path)' was unavailable and no download URI is recorded."
    }

    $uri = [Uri]$sourceUri
    $fileName = [IO.Path]::GetFileName($uri.AbsolutePath)
    if ([string]::IsNullOrWhiteSpace($fileName)) {
        $fileName = "$($Entry.component)-source"
    }

    $downloadPath = Join-Path $DownloadRoot $fileName
    Invoke-WebRequest -Uri $uri -OutFile $downloadPath -MaximumRetryCount 3 -RetryIntervalSec 2 -ConnectionTimeoutSeconds 600 -OperationTimeoutSeconds 60
    return $downloadPath
}

if (-not (Test-Path -LiteralPath $LockFile -PathType Leaf)) {
    throw "Toolchain lock file not found: $LockFile"
}

$lock = Get-Content -LiteralPath $LockFile -Raw | ConvertFrom-Json -Depth 20
if ($lock.schema_version -ne 1) {
    throw "Unsupported toolchain lock schema version '$($lock.schema_version)'."
}

if (-not $lock.inventory_complete -or $lock.files.Count -eq 0) {
    throw "Toolchain inventory is incomplete. Generate toolchain.lock.json on the Windows source machine before bootstrapping."
}

$resolvedRoot = [IO.Path]::GetFullPath($ToolchainRoot)
$downloadRoot = Join-Path ([IO.Path]::GetTempPath()) "avisynth-delogo-downloads-$([Guid]::NewGuid().ToString('N'))"
$extractRoot = Join-Path ([IO.Path]::GetTempPath()) "avisynth-delogo-extract-$([Guid]::NewGuid().ToString('N'))"
New-Item -ItemType Directory -Path $resolvedRoot, $downloadRoot, $extractRoot -Force | Out-Null

try {
    foreach ($entry in $lock.files) {
        Assert-LockEntry -Entry $entry
        $destination = Join-Path $resolvedRoot ([string]$entry.relative_path)

        try {
            $sourceFile = Resolve-SourceFile -Entry $entry -DownloadRoot $downloadRoot
            $sourceSha256 = Get-OptionalProperty -Object $entry.source -Name "sha256"
            if ($sourceSha256) {
                $sourceHash = Get-Sha256 -Path $sourceFile
                if ($sourceHash -ne ([string]$sourceSha256).ToLowerInvariant()) {
                    throw "Source hash mismatch for '$($entry.relative_path)'."
                }
            }

            if ($entry.source.type -in @("zip", "7z")) {
                if ([string]::IsNullOrWhiteSpace([string]$entry.source.archive_path)) {
                    throw "Archive source for '$($entry.relative_path)' is missing source.archive_path."
                }

                $entryExtractRoot = Join-Path $extractRoot ([Guid]::NewGuid().ToString("N"))
                if ($entry.source.type -eq "zip") {
                    Expand-Archive -LiteralPath $sourceFile -DestinationPath $entryExtractRoot -Force
                }
                else {
                    $sevenZip = Get-Command 7z, 7zz, 7za -ErrorAction SilentlyContinue | Select-Object -First 1
                    if (-not $sevenZip) {
                        $sourceLabel = Get-OptionalProperty -Object $entry.source -Name "cache_path"
                        throw "7-Zip is required to extract '$sourceLabel' but 7z, 7zz, and 7za are unavailable."
                    }

                    & $sevenZip.Source x -y "-o$entryExtractRoot" $sourceFile | Out-Null
                    if ($LASTEXITCODE -ne 0) {
                        throw "7-Zip failed with exit code $LASTEXITCODE for '$($entry.relative_path)'."
                    }
                }

                $installSource = Join-Path $entryExtractRoot ([string]$entry.source.archive_path)
            }
            else {
                $installSource = $sourceFile
            }

            if (-not (Test-Path -LiteralPath $installSource -PathType Leaf)) {
                throw "Install source not found for '$($entry.relative_path)': $installSource"
            }

            $installHash = Get-Sha256 -Path $installSource
            if ($installHash -ne ([string]$entry.sha256).ToLowerInvariant()) {
                throw "Installed-file hash mismatch for '$($entry.relative_path)'."
            }

            New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force | Out-Null
            Copy-Item -LiteralPath $installSource -Destination $destination -Force
            Write-Host "Installed $($entry.relative_path) [$($entry.component) $($entry.version)]"
        }
        catch {
            if ($entry.required) {
                throw
            }

            Write-Warning "Optional file '$($entry.relative_path)' was not installed: $($_.Exception.Message)"
        }
    }
}
finally {
    Remove-Item -LiteralPath $downloadRoot, $extractRoot -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host "Toolchain installed at: $resolvedRoot"

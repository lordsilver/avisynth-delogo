[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$repositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$lockFile = Join-Path $repositoryRoot "toolchain\manifests\toolchain.lock.json"

function Invoke-CheckedCommand {
    param(
        [Parameter(Mandatory)][string]$Command,
        [Parameter(Mandatory)][string[]]$Arguments
    )

    & $Command @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "'$Command $($Arguments -join ' ')' failed with exit code $LASTEXITCODE."
    }
}

Push-Location $repositoryRoot
try {
    Invoke-CheckedCommand -Command "taplo" -Arguments @("format", "--check", "mise.toml")
    Invoke-CheckedCommand -Command "prettier" -Arguments @("--check", "README.md", "docs", "skills", "toolchain", ".github")
    Invoke-CheckedCommand -Command "actionlint" -Arguments @(".github/workflows/toolchain.yml")
    Invoke-CheckedCommand -Command "jq" -Arguments @("empty", "toolchain/manifests/toolchain.lock.json")
    Invoke-CheckedCommand -Command "yq" -Arguments @("eval", "... | select(false)", "toolchain/manifests/sources.yaml")
    Invoke-CheckedCommand -Command "gitleaks" -Arguments @("dir", ".", "--no-banner", "--redact", "--exit-code", "1")
}
finally {
    Pop-Location
}

$lock = Get-Content -LiteralPath $lockFile -Raw | ConvertFrom-Json -Depth 20

if (-not $lock.inventory_complete) {
    throw "Toolchain lock inventory is incomplete."
}

foreach ($entry in $lock.files) {
    if ($entry.sha256 -notmatch "^[0-9a-f]{64}$") {
        throw "Invalid installed-file SHA-256 for '$($entry.relative_path)'."
    }

    if ($entry.source.sha256 -notmatch "^[0-9a-f]{64}$") {
        throw "Invalid source SHA-256 for '$($entry.relative_path)'."
    }
}

$prohibitedPatterns = @("pb0", "YT_MEDIA", "C:\\Users\\", "C:\\Videos", "C:\\Projects", "D:\\VideoTools", "D:\\ARCHIVE")
$trackedText = Get-ChildItem -LiteralPath $repositoryRoot -Recurse -File | Where-Object { $_.FullName -notmatch "[\\/]\.git[\\/]" -and $_.FullName -notmatch "[\\/]\.scratch[\\/]" }
foreach ($file in $trackedText) {
    if ($file.FullName -eq $PSCommandPath) {
        continue
    }

    if ($file.Length -gt 5MB) {
        continue
    }

    $content = Get-Content -LiteralPath $file.FullName -Raw -ErrorAction SilentlyContinue
    foreach ($pattern in $prohibitedPatterns) {
        if ($content -match $pattern) {
            throw "Prohibited machine-specific path or tested filename '$pattern' found in '$($file.FullName)'."
        }
    }
}

Write-Host "Repository validation: PASS"

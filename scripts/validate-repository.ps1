[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$repositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
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
    Invoke-CheckedCommand -Command "mise" -Arguments @("run", "format:check")
    $workflows = @(Get-ChildItem -LiteralPath ".github/workflows" -File | Where-Object Extension -In @(".yml", ".yaml") | ForEach-Object FullName)
    Invoke-CheckedCommand -Command "actionlint" -Arguments $workflows
    Invoke-CheckedCommand -Command "jq" -Arguments @("empty", "toolchain/manifests/toolchain.lock.json")
    Invoke-CheckedCommand -Command "yq" -Arguments @("eval", "... | select(false)", "toolchain/manifests/sources.yaml")
    Invoke-CheckedCommand -Command "gitleaks" -Arguments @("dir", ".", "--no-banner", "--redact", "--exit-code", "1")

    # Include new source files, while keeping ignored media, caches, and ZIPs out of scans.
    $sourcePaths = @(& rg --files --hidden --glob '!.git/**')
    if ($LASTEXITCODE -ne 0) {
        throw "Could not enumerate repository source files."
    }
}
finally {
    Pop-Location
}

$lock = Get-Content -LiteralPath $lockFile -Raw | ConvertFrom-Json -Depth 20

if ($lock.schema_version -ne 1 -or -not $lock.inventory_complete -or $lock.files.Count -eq 0) {
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
$sourceFiles = @($sourcePaths | ForEach-Object { Get-Item -LiteralPath (Join-Path $repositoryRoot $_) -Force })
foreach ($file in $sourceFiles) {
    if ($file.Extension -eq ".ps1") {
        $tokens = $null
        $parseErrors = $null
        $null = [Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$parseErrors)
        if ($parseErrors.Count -gt 0) {
            throw "PowerShell syntax errors in '$($file.FullName)': $($parseErrors -join '; ')"
        }
    }

    if ($file.Length -gt 5MB -or $file.Extension -eq ".dat") {
        continue
    }

    $content = Get-Content -LiteralPath $file.FullName -Raw -ErrorAction SilentlyContinue
    if ($file.Extension -eq ".md") {
        # Check local inline links without fetching upstream sites during validation.
        $prose = [regex]::Replace($content, '(?ms)^```.*?^```[^\r\n]*', '')
        foreach ($link in [regex]::Matches($prose, '\[[^\]\r\n]+\]\(([^\s)]+)\)')) {
            $target = $link.Groups[1].Value
            if ($target -match '^(?:[a-zA-Z][a-zA-Z0-9+.-]*:|#|//)') {
                continue
            }
            $relativePath = [Uri]::UnescapeDataString(($target -split '#', 2)[0])
            if (-not (Test-Path -LiteralPath (Join-Path $file.DirectoryName $relativePath))) {
                throw "Broken local documentation link '$target' in '$($file.FullName)'."
            }
        }
    }

    if ($file.FullName -eq $PSCommandPath) {
        continue
    }

    foreach ($pattern in $prohibitedPatterns) {
        if ($content -match $pattern) {
            throw "Prohibited machine-specific path or tested filename '$pattern' found in '$($file.FullName)'."
        }
    }
}

Write-Host "Repository validation: PASS"

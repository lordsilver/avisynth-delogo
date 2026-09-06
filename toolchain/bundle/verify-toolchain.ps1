[CmdletBinding()]
param(
    [string]$ToolchainRoot = $(if ($env:AVISYNTH_DELOGO_ROOT) { $env:AVISYNTH_DELOGO_ROOT } else { Join-Path ([Environment]::GetFolderPath("LocalApplicationData")) "avisynth-delogo" }),
    [string]$LockFile = $(if (Test-Path -LiteralPath (Join-Path $PSScriptRoot "toolchain.lock.json")) { Join-Path $PSScriptRoot "toolchain.lock.json" } else { Join-Path $PSScriptRoot "..\manifests\toolchain.lock.json" })
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$failures = [Collections.Generic.List[string]]::new()
$warnings = [Collections.Generic.List[string]]::new()

function Add-Result {
    param(
        [Parameter(Mandatory)][ValidateSet("PASS", "WARN", "FAIL")][string]$Status,
        [Parameter(Mandatory)][string]$Message
    )

    Write-Host "[$Status] $Message"
    if ($Status -eq "FAIL") {
        $script:failures.Add($Message)
    }
    elseif ($Status -eq "WARN") {
        $script:warnings.Add($Message)
    }
}

if (-not (Test-Path -LiteralPath $LockFile -PathType Leaf)) {
    Add-Result -Status FAIL -Message "Toolchain lock file not found: $LockFile"
    exit 1
}

$lock = Get-Content -LiteralPath $LockFile -Raw | ConvertFrom-Json -Depth 20
if ($lock.schema_version -ne 1) {
    Add-Result -Status FAIL -Message "Unsupported lock schema version '$($lock.schema_version)'."
}

if (-not $lock.inventory_complete -or $lock.files.Count -eq 0) {
    Add-Result -Status FAIL -Message "Toolchain inventory is incomplete; generate the lock on the Windows source machine."
}

$resolvedRoot = [IO.Path]::GetFullPath($ToolchainRoot)
if (Test-Path -LiteralPath $resolvedRoot -PathType Container) {
    Add-Result -Status PASS -Message "Toolchain root exists: $resolvedRoot"
}
else {
    Add-Result -Status FAIL -Message "Toolchain root is missing: $resolvedRoot"
}

foreach ($legacyDirectory in @("Tools", "Plugins\plugins64+")) {
    if (Test-Path -LiteralPath (Join-Path $resolvedRoot $legacyDirectory)) {
        Add-Result -Status FAIL -Message "Legacy runtime directory is still present: $legacyDirectory"
    }
}

foreach ($entry in $lock.files) {
    $path = Join-Path $resolvedRoot ([string]$entry.relative_path)
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        $status = if ($entry.required) { "FAIL" } else { "WARN" }
        Add-Result -Status $status -Message "Missing $($entry.relative_path) [$($entry.component) $($entry.version)]"
        continue
    }

    $actualHash = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
    $expectedHash = ([string]$entry.sha256).ToLowerInvariant()
    if ($actualHash -eq $expectedHash) {
        Add-Result -Status PASS -Message "Verified $($entry.relative_path)"
    }
    else {
        $status = if ($entry.required) { "FAIL" } else { "WARN" }
        Add-Result -Status $status -Message "Hash mismatch for $($entry.relative_path): expected $expectedHash, got $actualHash"
    }
}

$aviSynthEntries = @($lock.files | Where-Object { $_.component -match "AviSynth" -and $_.required })
if ($aviSynthEntries.Count -gt 0 -and ($aviSynthEntries | Where-Object { Test-Path -LiteralPath (Join-Path $resolvedRoot ([string]$_.relative_path)) }).Count -gt 0) {
    Add-Result -Status PASS -Message "AviSynth+ required files are present."
}
else {
    Add-Result -Status FAIL -Message "AviSynth+ availability could not be established from required lock entries."
}

$toolchainCommands = @{}
foreach ($commandName in @("ffmpeg", "ffprobe")) {
    $toolchainCommand = Join-Path $resolvedRoot "$commandName.exe"
    if (Test-Path -LiteralPath $toolchainCommand -PathType Leaf) {
        $toolchainCommands[$commandName] = $toolchainCommand
        Add-Result -Status PASS -Message "$commandName is beside AviSynth.dll at the toolchain root."
    }
    else {
        Add-Result -Status FAIL -Message "$commandName.exe is missing from the toolchain root."
    }
}

$isWindowsPlatform = [Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT
$ffmpegCommand = $toolchainCommands["ffmpeg"]
if ($ffmpegCommand -and $isWindowsPlatform) {
    $smokeScript = Join-Path ([IO.Path]::GetTempPath()) "avisynth-delogo-verify-$([Guid]::NewGuid().ToString('N')).avs"
    try {
        Set-Content -LiteralPath $smokeScript -Value 'BlankClip(width=16, height=16, length=1, fps=1, pixel_type="YV12")' -Encoding ascii
        $smokeOutput = & $ffmpegCommand -hide_banner -loglevel error -nostdin -i $smokeScript -frames:v 1 -f null - 2>&1
        if ($LASTEXITCODE -eq 0) {
            Add-Result -Status PASS -Message "Root-level FFmpeg loaded the adjacent AviSynth.dll and rendered BlankClip()."
        }
        else {
            $smokeDetails = ($smokeOutput | Out-String).Trim()
            Add-Result -Status FAIL -Message "Bundled FFmpeg could not render BlankClip(): $smokeDetails"
        }
    }
    finally {
        Remove-Item -LiteralPath $smokeScript -Force -ErrorAction SilentlyContinue
    }
}

$avsPmodRoot = Join-Path $resolvedRoot "AvsPmod"
$avsPmodExecutable = Join-Path $avsPmodRoot "AvsPmod.exe"
if (-not (Test-Path -LiteralPath $avsPmodExecutable -PathType Leaf)) {
    Add-Result -Status FAIL -Message "AvsPmod.exe is missing from the toolchain."
}
elseif (-not (Test-Path -LiteralPath (Join-Path $avsPmodRoot "options.dat") -PathType Leaf)) {
    Add-Result -Status FAIL -Message "AvsPmod portable options.dat is missing."
}
elseif (-not (Test-Path -LiteralPath (Join-Path $resolvedRoot "Start-AvsPmod.cmd") -PathType Leaf)) {
    Add-Result -Status FAIL -Message "Start-AvsPmod.cmd is missing from the toolchain root."
}
else {
    Add-Result -Status PASS -Message "AvsPmod portable options and launcher are present."
}

Write-Host "Toolchain root: $resolvedRoot"
Write-Host "Summary: $($failures.Count) failure(s), $($warnings.Count) warning(s)"
if ($failures.Count -gt 0) {
    exit 1
}

exit 0

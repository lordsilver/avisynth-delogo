[CmdletBinding()]
param(
    [string]$ToolchainRoot,
    [string]$ValidatorPath
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Resolve-TestTool {
    param([Parameter(Mandatory)][string]$Name)

    if ($ToolchainRoot) {
        $resolvedRoot = (Resolve-Path -LiteralPath $ToolchainRoot).Path
        $candidate = Join-Path $resolvedRoot "$Name.exe"
        if (-not (Test-Path -LiteralPath $candidate -PathType Leaf)) {
            throw "Required test tool not found: $candidate"
        }
        return $candidate
    }

    $command = Get-Command "$Name.exe" -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $command) {
        $command = Get-Command $Name -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    }
    if (-not $command) {
        throw "Required test tool '$Name' was not found."
    }
    return [string]$command.Source
}

function Invoke-CheckedCommand {
    param(
        [Parameter(Mandatory)][string]$Command,
        [Parameter(Mandatory)][string[]]$Arguments,
        [Parameter(Mandatory)][string]$Label
    )

    & $Command @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "$Label failed with exit code $LASTEXITCODE."
    }
}

function Assert-CommandFails {
    param(
        [Parameter(Mandatory)][string]$Command,
        [Parameter(Mandatory)][string[]]$Arguments,
        [Parameter(Mandatory)][string]$Label
    )

    $previousErrorActionPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = "Continue"
        & $Command @Arguments *> $null
        $exitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }
    if ($exitCode -eq 0) {
        throw "$Label unexpectedly succeeded."
    }
}

if ($ToolchainRoot) {
    $ToolchainRoot = (Resolve-Path -LiteralPath $ToolchainRoot).Path
    $env:PATH = "$ToolchainRoot$([IO.Path]::PathSeparator)$ToolchainRoot$([IO.Path]::PathSeparator)$env:PATH"
}

$ffmpeg = Resolve-TestTool -Name "ffmpeg"
$pwsh = (Get-Process -Id $PID).Path
$validator = if ($ValidatorPath) { (Resolve-Path -LiteralPath $ValidatorPath).Path } else { Join-Path $PSScriptRoot "validate-render.ps1" }
$temporaryRoot = Join-Path ([IO.Path]::GetTempPath()) "avisynth-delogo-render-test-$([Guid]::NewGuid().ToString('N'))"
$metadataPath = Join-Path $temporaryRoot "metadata.txt"
$sourcePath = Join-Path $temporaryRoot "source.mkv"
$copiedAudioOutputPath = Join-Path $temporaryRoot "copied-audio-output.mkv"
$transcodedAudioOutputPath = Join-Path $temporaryRoot "transcoded-audio-output.mkv"

New-Item -ItemType Directory -Path $temporaryRoot | Out-Null
try {
    @"
;FFMETADATA1
title=Render validator fixture
[CHAPTER]
TIMEBASE=1/1000
START=0
END=500
title=First half
[CHAPTER]
TIMEBASE=1/1000
START=500
END=1000
title=Second half
"@ | Set-Content -LiteralPath $metadataPath -Encoding utf8NoBOM

    Invoke-CheckedCommand -Command $ffmpeg -Label "fixture generation" -Arguments @(
        "-hide_banner", "-loglevel", "error", "-y",
        "-f", "lavfi", "-i", "testsrc2=size=64x64:rate=10:duration=1",
        "-f", "lavfi", "-i", "sine=frequency=1000:sample_rate=48000:duration=1",
        "-f", "ffmetadata", "-i", $metadataPath,
        "-map", "0:v:0", "-map", "1:a:0", "-map_metadata", "2", "-map_chapters", "2",
        "-c:v", "libx264", "-preset", "ultrafast", "-crf", "18", "-pix_fmt", "yuv420p",
        "-c:a", "aac", "-b:a", "128k",
        $sourcePath
    )

    Invoke-CheckedCommand -Command $ffmpeg -Label "copied-audio output generation" -Arguments @(
        "-hide_banner", "-loglevel", "error", "-y", "-i", $sourcePath,
        "-map", "0:v:0", "-map", "0:a:0", "-map_metadata", "0", "-map_chapters", "0",
        "-c:v", "libx264", "-preset", "ultrafast", "-crf", "18", "-pix_fmt", "yuv420p",
        "-c:a", "copy",
        $copiedAudioOutputPath
    )

    Invoke-CheckedCommand -Command $pwsh -Label "copied-audio validation" -Arguments @(
        "-NoProfile", "-File", $validator,
        "-SourcePath", $sourcePath,
        "-OutputPath", $copiedAudioOutputPath
    )

    Invoke-CheckedCommand -Command $ffmpeg -Label "transcoded-audio output generation" -Arguments @(
        "-hide_banner", "-loglevel", "error", "-y", "-i", $sourcePath,
        "-map", "0:v:0", "-map", "0:a:0", "-map_metadata", "0", "-map_chapters", "0",
        "-c:v", "libx264", "-preset", "ultrafast", "-crf", "18", "-pix_fmt", "yuv420p",
        "-c:a", "pcm_s16le",
        $transcodedAudioOutputPath
    )

    Invoke-CheckedCommand -Command $pwsh -Label "transcoded-audio validation" -Arguments @(
        "-NoProfile", "-File", $validator,
        "-SourcePath", $sourcePath,
        "-OutputPath", $transcodedAudioOutputPath,
        "-SkipAudioIdentity"
    )

    Assert-CommandFails -Command $pwsh -Label "audio identity rejection" -Arguments @(
        "-NoProfile", "-File", $validator,
        "-SourcePath", $sourcePath,
        "-OutputPath", $transcodedAudioOutputPath
    )

    Write-Host "Render validator tests: PASS"
}
finally {
    Remove-Item -LiteralPath $temporaryRoot -Recurse -Force -ErrorAction SilentlyContinue
}

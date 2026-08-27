[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$SourcePath,
    [Parameter(Mandatory)][string]$OutputPath,
    [string]$ToolchainRoot,
    [switch]$SkipAudioIdentity
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Resolve-NativeTool {
    param([Parameter(Mandatory)][string]$Name)

    if ($ToolchainRoot) {
        $resolvedRoot = (Resolve-Path -LiteralPath $ToolchainRoot).Path
        $candidate = Join-Path $resolvedRoot "$Name.exe"
        if (-not (Test-Path -LiteralPath $candidate -PathType Leaf)) {
            throw "Required tool not found: $candidate"
        }
        return $candidate
    }

    $command = Get-Command "$Name.exe" -CommandType Application -ErrorAction SilentlyContinue
    if (-not $command) {
        $command = Get-Command $Name -CommandType Application -ErrorAction SilentlyContinue
    }
    if (-not $command) {
        throw "Required tool '$Name' was not found. Pass -ToolchainRoot or activate the portable toolchain."
    }
    return $command.Source
}

function Invoke-CapturedCommand {
    param(
        [Parameter(Mandatory)][string]$Command,
        [Parameter(Mandatory)][string[]]$Arguments,
        [Parameter(Mandatory)][string]$Label
    )

    $captured = @(& $Command @Arguments 2>&1)
    $exitCode = $LASTEXITCODE
    $text = ($captured | ForEach-Object { $_.ToString() }) -join [Environment]::NewLine
    if ($exitCode -ne 0) {
        throw "$Label failed with exit code $exitCode.$([Environment]::NewLine)$text"
    }
    return $text
}

function Get-Probe {
    param(
        [Parameter(Mandatory)][string]$Ffprobe,
        [Parameter(Mandatory)][string]$Path
    )

    $json = Invoke-CapturedCommand -Command $Ffprobe -Label "ffprobe metadata for '$Path'" -Arguments @(
        "-v", "error",
        "-show_streams",
        "-show_format",
        "-show_chapters",
        "-of", "json",
        $Path
    )
    return $json | ConvertFrom-Json -Depth 30
}

function Get-FrameCount {
    param(
        [Parameter(Mandatory)][string]$Ffprobe,
        [Parameter(Mandatory)][string]$Path
    )

    $json = Invoke-CapturedCommand -Command $Ffprobe -Label "exact frame count for '$Path'" -Arguments @(
        "-v", "error",
        "-count_frames",
        "-select_streams", "v:0",
        "-show_entries", "stream=nb_read_frames",
        "-of", "json",
        $Path
    )
    $probe = $json | ConvertFrom-Json -Depth 10
    $streams = @($probe.streams)
    if ($streams.Count -ne 1 -or $streams[0].nb_read_frames -notmatch "^\d+$") {
        throw "ffprobe did not return an exact video frame count for '$Path'."
    }
    return [int64]$streams[0].nb_read_frames
}

function Get-OptionalProperty {
    param(
        [Parameter(Mandatory)][object]$Object,
        [Parameter(Mandatory)][string]$Name
    )

    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) {
        return $null
    }
    return $property.Value
}

function Assert-Equal {
    param(
        [Parameter(Mandatory)][string]$Label,
        [AllowNull()][object]$SourceValue,
        [AllowNull()][object]$OutputValue
    )

    if ([string]$SourceValue -cne [string]$OutputValue) {
        throw "$Label differs: source='$SourceValue', output='$OutputValue'."
    }
}

function Get-AudioPayloadHash {
    param(
        [Parameter(Mandatory)][string]$Ffmpeg,
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][int]$AudioIndex
    )

    $hashText = Invoke-CapturedCommand -Command $Ffmpeg -Label "audio payload hash for '$Path' stream $AudioIndex" -Arguments @(
        "-hide_banner",
        "-loglevel", "error",
        "-i", $Path,
        "-map", "0:a:$AudioIndex",
        "-c", "copy",
        "-f", "hash",
        "-hash", "sha256",
        "-"
    )
    if ($hashText -notmatch "SHA256=([0-9a-fA-F]{64})") {
        throw "FFmpeg did not return an audio SHA-256 for '$Path' stream $AudioIndex."
    }
    return $Matches[1].ToUpperInvariant()
}

$resolvedSource = (Resolve-Path -LiteralPath $SourcePath).Path
$resolvedOutput = (Resolve-Path -LiteralPath $OutputPath).Path
if ($resolvedSource -eq $resolvedOutput) {
    throw "SourcePath and OutputPath resolve to the same file."
}

$ffmpeg = Resolve-NativeTool -Name "ffmpeg"
$ffprobe = Resolve-NativeTool -Name "ffprobe"
$sourceProbe = Get-Probe -Ffprobe $ffprobe -Path $resolvedSource
$outputProbe = Get-Probe -Ffprobe $ffprobe -Path $resolvedOutput

$sourceVideos = @($sourceProbe.streams | Where-Object { $_.codec_type -eq "video" })
$outputVideos = @($outputProbe.streams | Where-Object { $_.codec_type -eq "video" })
if ($sourceVideos.Count -lt 1 -or $outputVideos.Count -ne 1) {
    throw "Expected at least one source video stream and exactly one output video stream."
}

$sourceVideo = $sourceVideos[0]
$outputVideo = $outputVideos[0]
foreach ($propertyName in @("width", "height", "pix_fmt", "r_frame_rate")) {
    Assert-Equal -Label "Video $propertyName" -SourceValue (Get-OptionalProperty $sourceVideo $propertyName) -OutputValue (Get-OptionalProperty $outputVideo $propertyName)
}
foreach ($propertyName in @("color_range", "color_space", "color_transfer", "color_primaries", "chroma_location")) {
    $sourceValue = Get-OptionalProperty $sourceVideo $propertyName
    if ($sourceValue -and $sourceValue -ne "unknown") {
        Assert-Equal -Label "Video $propertyName" -SourceValue $sourceValue -OutputValue (Get-OptionalProperty $outputVideo $propertyName)
    }
}

Write-Host "Counting every source and output video frame..."
$sourceFrameCount = Get-FrameCount -Ffprobe $ffprobe -Path $resolvedSource
$outputFrameCount = Get-FrameCount -Ffprobe $ffprobe -Path $resolvedOutput
Assert-Equal -Label "Exact video frame count" -SourceValue $sourceFrameCount -OutputValue $outputFrameCount

$sourceAudio = @($sourceProbe.streams | Where-Object { $_.codec_type -eq "audio" })
$outputAudio = @($outputProbe.streams | Where-Object { $_.codec_type -eq "audio" })
Assert-Equal -Label "Audio stream count" -SourceValue $sourceAudio.Count -OutputValue $outputAudio.Count

$audioResults = @()
for ($audioIndex = 0; $audioIndex -lt $sourceAudio.Count; $audioIndex++) {
    foreach ($propertyName in @("codec_name", "sample_rate", "channels", "channel_layout")) {
        Assert-Equal -Label "Audio stream $audioIndex $propertyName" -SourceValue (Get-OptionalProperty $sourceAudio[$audioIndex] $propertyName) -OutputValue (Get-OptionalProperty $outputAudio[$audioIndex] $propertyName)
    }

    $sourceHash = $null
    $outputHash = $null
    if (-not $SkipAudioIdentity) {
        $sourceHash = Get-AudioPayloadHash -Ffmpeg $ffmpeg -Path $resolvedSource -AudioIndex $audioIndex
        $outputHash = Get-AudioPayloadHash -Ffmpeg $ffmpeg -Path $resolvedOutput -AudioIndex $audioIndex
        Assert-Equal -Label "Audio stream $audioIndex compressed payload SHA-256" -SourceValue $sourceHash -OutputValue $outputHash
    }

    $audioResults += [pscustomobject]@{
        index = $audioIndex
        codec = Get-OptionalProperty $sourceAudio[$audioIndex] "codec_name"
        payload_sha256 = $sourceHash
    }
}

$sourceChapters = @($sourceProbe.chapters)
$outputChapters = @($outputProbe.chapters)
Assert-Equal -Label "Chapter count" -SourceValue $sourceChapters.Count -OutputValue $outputChapters.Count

$ignoredFormatTags = @("major_brand", "minor_version", "compatible_brands", "encoder")
$sourceTags = Get-OptionalProperty $sourceProbe.format "tags"
$outputTags = Get-OptionalProperty $outputProbe.format "tags"
if ($sourceTags) {
    foreach ($sourceTag in $sourceTags.PSObject.Properties) {
        if ($sourceTag.Name -in $ignoredFormatTags) {
            continue
        }
        $outputValue = if ($outputTags) { Get-OptionalProperty $outputTags $sourceTag.Name } else { $null }
        Assert-Equal -Label "Format metadata '$($sourceTag.Name)'" -SourceValue $sourceTag.Value -OutputValue $outputValue
    }
}

Write-Host "Decoding the complete output video and every output audio stream..."
$null = Invoke-CapturedCommand -Command $ffmpeg -Label "full output decode" -Arguments @(
    "-hide_banner",
    "-loglevel", "error",
    "-xerror",
    "-i", $resolvedOutput,
    "-map", "0:v:0",
    "-map", "0:a?",
    "-f", "null",
    "NUL"
)

$result = [pscustomobject]@{
    status = "PASS"
    source = $resolvedSource
    output = $resolvedOutput
    video = [pscustomobject]@{
        source_codec = Get-OptionalProperty $sourceVideo "codec_name"
        output_codec = Get-OptionalProperty $outputVideo "codec_name"
        width = Get-OptionalProperty $outputVideo "width"
        height = Get-OptionalProperty $outputVideo "height"
        frame_rate = Get-OptionalProperty $outputVideo "r_frame_rate"
        exact_frames = $outputFrameCount
    }
    audio = $audioResults
    chapters = $outputChapters.Count
    output_bytes = (Get-Item -LiteralPath $resolvedOutput).Length
}

$result | ConvertTo-Json -Depth 6

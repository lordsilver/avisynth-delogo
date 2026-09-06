[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$toolchainRoot = $PSScriptRoot
$pluginRoot = Join-Path $toolchainRoot "Plugins"

if (-not (Test-Path -LiteralPath (Join-Path $toolchainRoot "AviSynth.dll") -PathType Leaf)) {
    throw "AviSynth.dll is missing from the toolchain root: $toolchainRoot"
}

if (-not (Test-Path -LiteralPath $pluginRoot -PathType Container)) {
    throw "Plugin directory is missing: $pluginRoot"
}

$registryPath = "HKCU:\Software\AviSynth"
New-Item -Path $registryPath -Force | Out-Null
Set-ItemProperty -Path $registryPath -Name "PluginDir+" -Value $pluginRoot

$pathEntries = [Collections.Generic.List[string]]::new()
$pathEntries.Add($toolchainRoot)

foreach ($commandName in @("ffmpeg", "ffprobe")) {
    if (-not (Test-Path -LiteralPath (Join-Path $toolchainRoot "$commandName.exe") -PathType Leaf)) {
        throw "$commandName.exe is missing from the toolchain root: $toolchainRoot"
    }
}

$avsPmodRoot = Join-Path $toolchainRoot "AvsPmod"
if (Test-Path -LiteralPath (Join-Path $avsPmodRoot "AvsPmod.exe") -PathType Leaf) {
    $pathEntries.Add($avsPmodRoot)
}

$env:AVISYNTH_DELOGO_ROOT = $toolchainRoot
$env:PATH = (($pathEntries + $env:PATH.Split([IO.Path]::PathSeparator)) | Select-Object -Unique) -join [IO.Path]::PathSeparator

Write-Host "Activated AviSynth delogo toolchain: $toolchainRoot"
Write-Host "AviSynth+ plugin autoload directory: $pluginRoot"
Write-Host "If Microsoft Visual C++ runtime DLLs are unavailable, install the official x64 package: https://aka.ms/vc14/vc_redist.x64.exe"

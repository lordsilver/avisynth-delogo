[CmdletBinding()]
param([string]$OutputFile = (Join-Path $PSScriptRoot "..\update-report.json"))

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$headers = @{ "User-Agent" = "avisynth-delogo-update-check" }
if ($env:GITHUB_TOKEN) {
    $headers.Authorization = "Bearer $($env:GITHUB_TOKEN)"
}

$releaseChecks = @(
    @{ component = "AviSynth+"; repository = "AviSynth/AviSynthPlus"; current = "v3.7.5" },
    @{ component = "AvsPmod GPo"; repository = "gispos/AvsPmod"; current = "2.7.9.7" },
    @{ component = "AvsInpaint"; repository = "pinterf/AvsInpaint"; current = "v1.3" },
    @{ component = "FFT3DFilter"; repository = "pinterf/fft3dfilter"; current = "v2.12" },
    @{ component = "MaskTools2"; repository = "pinterf/masktools"; current = "2.2.30" },
    @{ component = "FFMS2"; repository = "FFMS/ffms2"; current = "5.0" },
    @{ component = "GRunT"; repository = "pinterf/GRunT"; current = "v1.0.2" },
    @{ component = "L-SMASH-Works"; repository = "HomeOfAviSynthPlusEvolution/L-SMASH-Works"; current = "1310.0.0.0" },
    @{ component = "Neo FFT3D"; repository = "HomeOfAviSynthPlusEvolution/neo_FFT3D"; current = "r14" }
)

$commitChecks = @(
    @{ component = "InpaintDelogo"; repository = "Purfview/InpaintDelogo"; branch = "main"; current = "a6cc5d7bf1fd559b02d162b6e32d0b4f4a79a9b5" },
    @{ component = "DoomDelogo"; repository = "Purfview/DoomDelogo"; branch = "main"; current = "cfed253bb3e77668606e09de6fe363a6e9867873" }
)

$results = [Collections.Generic.List[object]]::new()
foreach ($check in $releaseChecks) {
    $release = Invoke-RestMethod -Headers $headers -Uri "https://api.github.com/repos/$($check.repository)/releases/latest"
    $results.Add([pscustomobject]@{
        component = $check.component
        current = $check.current
        latest = $release.tag_name
        update_available = $release.tag_name -ne $check.current
        url = $release.html_url
    })
}

foreach ($check in $commitChecks) {
    $commit = Invoke-RestMethod -Headers $headers -Uri "https://api.github.com/repos/$($check.repository)/commits/$($check.branch)"
    $results.Add([pscustomobject]@{
        component = $check.component
        current = $check.current
        latest = $commit.sha
        update_available = $commit.sha -ne $check.current
        url = $commit.html_url
    })
}

$report = [pscustomobject]@{
    checked_at = (Get-Date).ToUniversalTime().ToString("o")
    updates = @($results | Where-Object update_available)
    components = $results
}
$report | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $OutputFile -Encoding utf8

if ($env:GITHUB_STEP_SUMMARY) {
    Add-Content -LiteralPath $env:GITHUB_STEP_SUMMARY -Value "## Toolchain upstream check"
    foreach ($result in $results) {
        $status = if ($result.update_available) { "UPDATE" } else { "current" }
        Add-Content -LiteralPath $env:GITHUB_STEP_SUMMARY -Value "- $($result.component): $($result.current) -> $($result.latest) ($status)"
    }
}

Write-Host "Update report: $OutputFile"

# Runs every tool for real on a Windows machine (used by CI on windows-latest).
# Read-only or preview-only: nothing on the machine is changed.
$ErrorActionPreference = 'Stop'
$ok = $true
function Check($name, $cond) { if ($cond) { "PASS $name" } else { "FAIL $name"; $script:ok = $false } }

Import-Module "$PSScriptRoot/../tools/aio-certs/AioCerts.psm1" -Force
Import-Module "$PSScriptRoot/../tools/passforge/PassForge.psm1" -Force
Import-Module "$PSScriptRoot/../tools/pc-health/PcHealth.psm1" -Force

# AIO Certs - read-only expiry scan
$certs = @(Get-AioExpiringCertificate -Days 36500 -StoreLocation CurrentUser, LocalMachine)
Check "AIO Certs expiry scan ran ($($certs.Count) certs)" $true

# PassForge on Windows PowerShell's runtime too
$pw = New-PassForgePassword -Length 24
Check 'PassForge password' ($pw.Password.Length -eq 24)

# PC Health - full report + HTML
$html = Join-Path $env:RUNNER_TEMP 'pc-health.html'
$report = Get-PcHealthReport -HtmlPath $html
Check "PC Health report: score $($report.Score), status $($report.Status), $(@($report.Issues).Count) finding(s)" ($report.Score -ge 0 -and $report.Score -le 100)
Check 'PC Health found drives' (@($report.Disks).Count -ge 1)
Check 'PC Health wrote HTML' ((Test-Path $html) -and (Get-Item $html).Length -gt 1000)
$report.Issues | ForEach-Object { "    $($_.Severity): $($_.Message)" }

# PC Health cleanup - preview only
$preview = @(Invoke-PcCleanup -Target UserTemp, WindowsTemp, RecycleBin -WhatIf)
Check "Cleanup preview returned $($preview.Count) target(s)" ($preview.Count -ge 1 -and @($preview | Where-Object { -not $_.Preview }).Count -eq 0)
$preview | ForEach-Object { "    $($_.Target): $($_.FreedMB) MB could be freed" }

if ($ok) { 'ALL SMOKE TESTS PASSED' } else { 'SOME SMOKE TESTS FAILED'; exit 1 }

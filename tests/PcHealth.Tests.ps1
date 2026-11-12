$m = Import-Module $PSScriptRoot/../tools/pc-health/PcHealth.psm1 -Force -PassThru
$ok = $true
function Check($name, $cond) { if ($cond) { "PASS $name" } else { "FAIL $name"; $script:ok = $false } }

$healthy = [pscustomobject]@{
  Disks = @([pscustomobject]@{Drive='C:';SizeGB=500;FreeGB=200;FreePercent=40})
  PhysicalDisks = @([pscustomobject]@{Name='Disk0';Media='SSD';HealthStatus='Healthy'})
  Memory = [pscustomobject]@{TotalGB=16;UsedPercent=50}; UptimeDays=3; PendingReboot=$false
  DaysSinceLastUpdate=10; Antivirus=[pscustomobject]@{RealTimeProtection=$true;SignatureAgeDays=1}
  FailedServices=@(); CriticalEvents24h=0; TempGB=0.3
}
$i = & $m { param($d) Get-PcHealthIssue -Data $d } $healthy
$s = & $m { param($x) Get-PcHealthScore -Issues $x } $i
Check "healthy machine: no issues (got $(@($i).Count))" (@($i).Count -eq 0)
Check "healthy score 100 / Healthy" ($s.Score -eq 100 -and $s.Status -eq 'Healthy')

$sick = [pscustomobject]@{
  Disks = @([pscustomobject]@{Drive='C:';SizeGB=250;FreeGB=12;FreePercent=4.8},[pscustomobject]@{Drive='D:';SizeGB=1000;FreeGB=150;FreePercent=15})
  PhysicalDisks = @([pscustomobject]@{Name='Disk0';Media='HDD';HealthStatus='Warning'})
  Memory = [pscustomobject]@{TotalGB=8;UsedPercent=93}; UptimeDays=41; PendingReboot=$true
  DaysSinceLastUpdate=70; Antivirus=[pscustomobject]@{RealTimeProtection=$false;SignatureAgeDays=12}
  FailedServices=@([pscustomobject]@{Name='Spooler';DisplayName='Print Spooler';ExitCode=1067})
  CriticalEvents24h=9; TempGB=3.4
}
$i = & $m { param($d) Get-PcHealthIssue -Data $d } $sick
$s = & $m { param($x) Get-PcHealthScore -Issues $x } $i
$i | ForEach-Object { "  {0,-8} {1,-9} {2}" -f $_.Severity,$_.Area,$_.Message }
Check "sick machine: 12 findings (got $(@($i).Count))" (@($i).Count -eq 12)
Check "critical count 3" (@($i | Where-Object Severity -eq 'Critical').Count -eq 3)
Check "status Critical, score $($s.Score)" ($s.Status -eq 'Critical' -and $s.Score -eq 0)

$warnOnly = $healthy.PSObject.Copy(); $warnOnly.UptimeDays = 35; $warnOnly.PendingReboot = $true
$i = & $m { param($d) Get-PcHealthIssue -Data $d } $warnOnly
$s = & $m { param($x) Get-PcHealthScore -Issues $x } $i
Check "two warnings -> 80 Needs attention (got $($s.Score) $($s.Status))" ($s.Score -eq 80 -and $s.Status -eq 'Needs attention')

$null_av = $healthy.PSObject.Copy(); $null_av.Antivirus = $null; $null_av.PhysicalDisks = $null; $null_av.DaysSinceLastUpdate = $null
$null_av.FailedServices = $null; $null_av.Disks = @($healthy.Disks[0], $null)
$i = & $m { param($d) Get-PcHealthIssue -Data $d } $null_av
Check "missing probes do not crash or flag" (@($i).Count -eq 0)

$report = [pscustomobject]@{ ComputerName='TEST-PC <script>'; Generated='2026-11-12 07:30'; Status='Critical'; Score=0
  OS='Windows 11 Pro (build 26100)'; CPU='Example CPU'; UptimeDays=41; Memory=$sick.Memory; Disks=$sick.Disks
  Issues = (& $m { param($d) Get-PcHealthIssue -Data $d } $sick) }
$html = & $m { param($r) ConvertTo-PcHealthHtml -Report $r } $report
$null = $html
Check "html encodes input" ($html -notmatch '<script>' -and $html -match '&lt;script&gt;')
Check "html has findings" ($html -match 'Print Spooler' -and $html -match "class='pill crit'")

if ((Test-Path Variable:IsWindows) -and -not $IsWindows) { try { Get-PcHealthReport | Out-Null; Check "non-windows guard" $false } catch { Check "non-windows guard" ($_.Exception.Message -match "Windows") } }
if ($ok) { 'ALL TESTS PASSED' } else { 'SOME TESTS FAILED'; exit 1 }

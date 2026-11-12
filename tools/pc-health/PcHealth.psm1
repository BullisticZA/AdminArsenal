#Requires -Version 5.1
<#
.SYNOPSIS
    PC Health - one-command Windows health check with a scored HTML report,
    plus a safe, preview-first cleanup.
.DESCRIPTION
    Get-PcHealthReport only reads; it never changes anything.
    Invoke-PcCleanup supports -WhatIf and -Confirm and only touches temporary data.
    Part of AdminArsenal - https://github.com/BullisticZA/AdminArsenal
.NOTES
    Author : Charl Britz
    License: MIT
#>

Set-StrictMode -Version Latest

#region Helpers

function Test-PcIsWindows {
    # $IsWindows does not exist in Windows PowerShell 5.1, which only runs on Windows.
    if (Test-Path Variable:IsWindows) { return [bool]$IsWindows }
    $true
}

function Test-PcIsAdmin {
    if (-not (Test-PcIsWindows)) { return $false }
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    ([Security.Principal.WindowsPrincipal]$id).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-PcFolderSize {
    param([string]$Path)
    if (-not $Path -or -not (Test-Path -LiteralPath $Path)) { return [int64]0 }
    $sum = (Get-ChildItem -LiteralPath $Path -Recurse -Force -File -ErrorAction SilentlyContinue |
        Measure-Object -Property Length -Sum).Sum
    if ($sum) { [int64]$sum } else { [int64]0 }
}

function Invoke-PcSafely {
    # Runs a probe; a failed probe becomes $null instead of breaking the whole report.
    param([scriptblock]$Probe)
    try { & $Probe } catch { Write-Verbose "Probe failed: $($_.Exception.Message)"; $null }
}

function Get-PcHealthIssue {
    <#
        Turns raw report data into a list of findings. Pure function: no system calls,
        so the rules can be unit tested on any machine.
    #>
    param([Parameter(Mandatory)]$Data)

    $issues = New-Object System.Collections.Generic.List[object]
    function Add-Issue($Severity, $Area, $Message, $Fix) {
        $issues.Add([pscustomobject]@{ Severity = $Severity; Area = $Area; Message = $Message; Fix = $Fix })
    }

    foreach ($d in @($Data.Disks | Where-Object { $_ })) {
        if ($d.FreePercent -lt 10) {
            Add-Issue 'Critical' 'Storage' "Drive $($d.Drive) has only $($d.FreePercent)% free ($($d.FreeGB) GB)." 'Run Invoke-PcCleanup and remove unused apps or large files.'
        } elseif ($d.FreePercent -lt 20) {
            Add-Issue 'Warning' 'Storage' "Drive $($d.Drive) is getting full: $($d.FreePercent)% free." 'Run Invoke-PcCleanup -WhatIf to see what can be cleared.'
        }
    }
    foreach ($p in @($Data.PhysicalDisks)) {
        if ($p -and $p.HealthStatus -and $p.HealthStatus -ne 'Healthy') {
            Add-Issue 'Critical' 'Storage' "Physical disk '$($p.Name)' reports health: $($p.HealthStatus)." 'Back up now and plan to replace the disk.'
        }
    }
    if ($Data.Memory -and $Data.Memory.UsedPercent -ge 90) {
        Add-Issue 'Warning' 'Memory' "Memory is $($Data.Memory.UsedPercent)% used." 'Close heavy apps or check Task Manager for memory leaks.'
    }
    if ($Data.UptimeDays -ge 30) {
        Add-Issue 'Warning' 'System' "No restart for $($Data.UptimeDays) days." 'Restart to apply updates and clear memory.'
    }
    if ($Data.PendingReboot) {
        Add-Issue 'Warning' 'Updates' 'A restart is pending to finish installing updates.' 'Restart when convenient.'
    }
    if ($null -ne $Data.DaysSinceLastUpdate -and $Data.DaysSinceLastUpdate -ge 45) {
        Add-Issue 'Warning' 'Updates' "Last update was installed $($Data.DaysSinceLastUpdate) days ago." 'Open Windows Update and check for updates.'
    }
    if ($Data.Antivirus) {
        if (-not $Data.Antivirus.RealTimeProtection) {
            Add-Issue 'Critical' 'Security' 'Real-time antivirus protection is off.' 'Turn it on in Windows Security.'
        }
        if ($null -ne $Data.Antivirus.SignatureAgeDays -and $Data.Antivirus.SignatureAgeDays -gt 7) {
            Add-Issue 'Warning' 'Security' "Antivirus definitions are $($Data.Antivirus.SignatureAgeDays) days old." 'Update definitions in Windows Security.'
        }
    }
    # @() around an empty probe result would give one $null item, so filter nulls out.
    $failed = @($Data.FailedServices | Where-Object { $_ })
    if ($failed.Count -gt 0) {
        Add-Issue 'Warning' 'Services' "$($failed.Count) automatic service(s) stopped with an error: $(($failed | Select-Object -First 5 -ExpandProperty DisplayName) -join ', ')." 'Check them in services.msc or the System event log.'
    }
    if ($Data.CriticalEvents24h -ge 5) {
        Add-Issue 'Warning' 'Events' "$($Data.CriticalEvents24h) critical/error events in the System log in the last 24 hours." 'Review Event Viewer > Windows Logs > System.'
    }
    if ($Data.TempGB -ge 2) {
        Add-Issue 'Info' 'Storage' "$($Data.TempGB) GB of temporary files can likely be cleared." 'Run Invoke-PcCleanup.'
    }

    , $issues.ToArray()
}

function Get-PcHealthScore {
    param([object[]]$Issues)
    $score = 100
    foreach ($i in @($Issues)) {
        switch ($i.Severity) { 'Critical' { $score -= 25 } 'Warning' { $score -= 10 } 'Info' { $score -= 2 } }
    }
    $score = [math]::Max($score, 0)
    $status = if (@($Issues | Where-Object Severity -eq 'Critical').Count) { 'Critical' }
              elseif ($score -lt 85) { 'Needs attention' }
              else { 'Healthy' }
    [pscustomobject]@{ Score = $score; Status = $status }
}

function ConvertTo-PcHealthHtml {
    param([Parameter(Mandatory)]$Report)
    Add-Type -AssemblyName System.Web -ErrorAction SilentlyContinue
    function E($s) { [System.Net.WebUtility]::HtmlEncode([string]$s) }

    $color = switch ($Report.Status) { 'Healthy' { '#22c55e' } 'Needs attention' { '#f59e0b' } default { '#ef4444' } }
    $issueRows = if (@($Report.Issues).Count) {
        ($Report.Issues | ForEach-Object {
            $c = switch ($_.Severity) { 'Critical' { 'crit' } 'Warning' { 'warn' } default { 'info' } }
            "<tr><td><span class='pill $c'>$(E $_.Severity)</span></td><td>$(E $_.Area)</td><td>$(E $_.Message)</td><td>$(E $_.Fix)</td></tr>"
        }) -join "`n"
    } else { "<tr><td colspan='4'>No issues found. Nice.</td></tr>" }
    $diskRows = ($Report.Disks | ForEach-Object {
        $bar = [math]::Min([math]::Max(100 - $_.FreePercent, 0), 100)
        "<tr><td>$(E $_.Drive)</td><td>$(E $_.SizeGB) GB</td><td>$(E $_.FreeGB) GB</td><td><div class='bar'><i style='width:$bar%'></i></div></td></tr>"
    }) -join "`n"

    @"
<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>PC Health - $(E $Report.ComputerName)</title>
<style>
:root{--bg:#0a1222;--card:#13213d;--text:#e6edf7;--muted:#93a4c3;--accent:#5ee7ff}
*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--text);font:15px/1.5 system-ui,Segoe UI,sans-serif;padding:24px}
.wrap{max-width:960px;margin:auto}h1{margin:0 0 4px}h2{color:var(--accent);font-size:16px;margin:28px 0 10px}
.muted{color:var(--muted)}.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(200px,1fr));gap:12px}
.card{background:var(--card);border-radius:12px;padding:16px}.big{font-size:44px;font-weight:800;color:$color}
table{width:100%;border-collapse:collapse;background:var(--card);border-radius:12px;overflow:hidden}
td,th{padding:10px 12px;text-align:left;border-bottom:1px solid #1f3157;vertical-align:top}th{color:var(--muted);font-weight:600}
.pill{padding:2px 10px;border-radius:99px;font-size:12px;font-weight:700}.crit{background:#ef444433;color:#fca5a5}
.warn{background:#f59e0b33;color:#fcd34d}.info{background:#3b82f633;color:#93c5fd}
.bar{height:10px;background:#0a1222;border-radius:99px;overflow:hidden;min-width:120px}.bar i{display:block;height:100%;background:linear-gradient(90deg,#5ee7ff,#8b5cf6)}
</style></head><body><div class="wrap">
<h1>PC Health report</h1><div class="muted">$(E $Report.ComputerName) &middot; $(E $Report.Generated)</div>
<div class="grid" style="margin-top:16px">
<div class="card"><div class="muted">Health score</div><div class="big">$(E $Report.Score)</div><div>$(E $Report.Status)</div></div>
<div class="card"><div class="muted">System</div><div>$(E $Report.OS)</div><div class="muted">Up $(E $Report.UptimeDays) days</div></div>
<div class="card"><div class="muted">CPU</div><div>$(E $Report.CPU)</div></div>
<div class="card"><div class="muted">Memory</div><div>$(E $Report.Memory.UsedPercent)% of $(E $Report.Memory.TotalGB) GB used</div></div>
</div>
<h2>Findings</h2><table><tr><th>Severity</th><th>Area</th><th>Finding</th><th>Suggested fix</th></tr>
$issueRows
</table>
<h2>Drives</h2><table><tr><th>Drive</th><th>Size</th><th>Free</th><th>Used</th></tr>
$diskRows
</table>
<p class="muted" style="margin-top:28px">Generated by PC Health &middot; AdminArsenal</p>
</div></body></html>
"@
}

#endregion

function Get-PcHealthReport {
    <#
    .SYNOPSIS
        Runs a read-only health check and returns a scored report. Optionally saves an HTML report.
    .EXAMPLE
        Get-PcHealthReport
    .EXAMPLE
        Get-PcHealthReport -HtmlPath "$env:USERPROFILE\Desktop\pc-health.html" -Open
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [string]$HtmlPath,
        [switch]$Open
    )

    if (-not (Test-PcIsWindows)) { throw 'PC Health checks Windows machines only.' }
    if (-not (Test-PcIsAdmin)) { Write-Warning 'Not elevated: some checks (disk health, failed services, event log) may be incomplete.' }

    $now = Get-Date
    $os  = Get-CimInstance -ClassName Win32_OperatingSystem
    $cpu = Get-CimInstance -ClassName Win32_Processor | Select-Object -First 1

    $disks = @(Get-CimInstance -ClassName Win32_LogicalDisk -Filter 'DriveType=3' | Where-Object Size | ForEach-Object {
        [pscustomobject]@{
            Drive       = $_.DeviceID
            SizeGB      = [math]::Round($_.Size / 1GB, 1)
            FreeGB      = [math]::Round($_.FreeSpace / 1GB, 1)
            FreePercent = [math]::Round(100 * $_.FreeSpace / $_.Size, 1)
        }
    })

    $physical = Invoke-PcSafely {
        @(Get-PhysicalDisk | ForEach-Object {
            [pscustomobject]@{ Name = $_.FriendlyName; Media = [string]$_.MediaType; HealthStatus = [string]$_.HealthStatus }
        })
    }

    $pendingReboot = (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') -or
                     (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired')

    $lastUpdate = Invoke-PcSafely {
        Get-HotFix | Where-Object InstalledOn | Sort-Object InstalledOn -Descending | Select-Object -First 1 -ExpandProperty InstalledOn
    }

    $av = Invoke-PcSafely {
        $mp = Get-MpComputerStatus
        [pscustomobject]@{
            RealTimeProtection = [bool]$mp.RealTimeProtectionEnabled
            SignatureAgeDays   = [int]($now - $mp.AntivirusSignatureLastUpdated).TotalDays
        }
    }

    # Automatic services that are stopped AND exited with an error. Trigger-start services
    # that stop cleanly (exit code 0) are normal and are not reported.
    $failedServices = Invoke-PcSafely {
        @(Get-CimInstance -ClassName Win32_Service -Filter "StartMode='Auto' AND State<>'Running'" |
            Where-Object { $_.ExitCode -ne 0 } | Select-Object Name, DisplayName, ExitCode)
    }

    $events = Invoke-PcSafely {
        @(Get-WinEvent -FilterHashtable @{ LogName = 'System'; Level = 1, 2; StartTime = $now.AddHours(-24) } -ErrorAction Stop).Count
    }

    $tempBytes = (Get-PcFolderSize $env:TEMP) + (Get-PcFolderSize (Join-Path $env:windir 'Temp'))

    $data = [pscustomobject]@{
        Disks               = $disks
        PhysicalDisks       = $physical
        Memory              = [pscustomobject]@{
            TotalGB     = [math]::Round($os.TotalVisibleMemorySize / 1MB, 1)
            UsedPercent = [math]::Round(100 * (1 - $os.FreePhysicalMemory / $os.TotalVisibleMemorySize), 1)
        }
        UptimeDays          = [int]($now - $os.LastBootUpTime).TotalDays
        PendingReboot       = [bool]$pendingReboot
        DaysSinceLastUpdate = if ($lastUpdate) { [int]($now - $lastUpdate).TotalDays } else { $null }
        Antivirus           = $av
        FailedServices      = $failedServices
        CriticalEvents24h   = if ($null -ne $events) { $events } else { 0 }
        TempGB              = [math]::Round($tempBytes / 1GB, 2)
    }

    $issues = Get-PcHealthIssue -Data $data
    $score  = Get-PcHealthScore -Issues $issues

    $report = [pscustomobject]@{
        ComputerName  = $env:COMPUTERNAME
        Generated     = $now.ToString('yyyy-MM-dd HH:mm')
        Status        = $score.Status
        Score         = $score.Score
        OS            = "$($os.Caption) (build $($os.BuildNumber))"
        CPU           = $cpu.Name.Trim()
        UptimeDays    = $data.UptimeDays
        Memory        = $data.Memory
        Disks         = $data.Disks
        PhysicalDisks = $data.PhysicalDisks
        PendingReboot = $data.PendingReboot
        Antivirus     = $data.Antivirus
        Issues        = $issues
    }

    if ($HtmlPath) {
        ConvertTo-PcHealthHtml -Report $report | Set-Content -Path $HtmlPath -Encoding UTF8
        Write-Verbose "HTML report saved to $HtmlPath"
        if ($Open) { Invoke-Item $HtmlPath }
    }
    $report
}

function Invoke-PcCleanup {
    <#
    .SYNOPSIS
        Clears temporary data to free disk space. Preview first with -WhatIf.
    .DESCRIPTION
        Targets:
          UserTemp             - your %TEMP% folder
          WindowsTemp          - C:\Windows\Temp (admin)
          RecycleBin           - empties the Recycle Bin on all drives
          DeliveryOptimization - cached update downloads shared between PCs (admin)
          ComponentStore       - removes superseded Windows update components with DISM (admin, slow)
        Files in use are skipped automatically. By default only files older than 2 days are removed.
    .EXAMPLE
        Invoke-PcCleanup -WhatIf
    .EXAMPLE
        Invoke-PcCleanup -Target UserTemp, WindowsTemp, RecycleBin -Confirm:$false
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    [OutputType([pscustomobject])]
    param(
        [ValidateSet('UserTemp', 'WindowsTemp', 'RecycleBin', 'DeliveryOptimization', 'ComponentStore')]
        [string[]]$Target = @('UserTemp', 'WindowsTemp', 'RecycleBin'),
        [ValidateRange(0, 365)][int]$OlderThanDays = 2
    )

    if (-not (Test-PcIsWindows)) { throw 'PC Health cleans Windows machines only.' }
    $isAdmin = Test-PcIsAdmin
    $cutoff  = (Get-Date).AddDays(-$OlderThanDays)

    function Clear-PcFolder([string]$Name, [string]$Path) {
        $files = @(Get-ChildItem -LiteralPath $Path -Recurse -Force -File -ErrorAction SilentlyContinue |
            Where-Object LastWriteTime -lt $cutoff)
        $bytes = [int64](($files | Measure-Object Length -Sum).Sum)
        $removed = 0; $skipped = 0; $freed = [int64]0
        if ($PSCmdlet.ShouldProcess($Path, "Delete $($files.Count) file(s), $([math]::Round($bytes / 1MB, 1)) MB")) {
            foreach ($f in $files) {
                try { $len = $f.Length; Remove-Item -LiteralPath $f.FullName -Force -ErrorAction Stop; $removed++; $freed += $len }
                catch { $skipped++ }
            }
            # Remove folders left empty, deepest first.
            Get-ChildItem -LiteralPath $Path -Recurse -Force -Directory -ErrorAction SilentlyContinue |
                Sort-Object { $_.FullName.Length } -Descending | ForEach-Object {
                    if (-not (Get-ChildItem -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue)) {
                        Remove-Item -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue
                    }
                }
        } else { $freed = $bytes }
        [pscustomobject]@{ Target = $Name; Files = if ($WhatIfPreference) { $files.Count } else { $removed }; Skipped = $skipped; FreedMB = [math]::Round($freed / 1MB, 1); Preview = [bool]$WhatIfPreference }
    }

    foreach ($t in $Target) {
        $needsAdmin = $t -in 'WindowsTemp', 'DeliveryOptimization', 'ComponentStore'
        if ($needsAdmin -and -not $isAdmin) { Write-Warning "$t needs an elevated session - skipped."; continue }

        switch ($t) {
            'UserTemp'    { Clear-PcFolder $t $env:TEMP }
            'WindowsTemp' { Clear-PcFolder $t (Join-Path $env:windir 'Temp') }
            'RecycleBin' {
                $size = Invoke-PcSafely { [int64](((New-Object -ComObject Shell.Application).Namespace(10).Items() | Measure-Object Size -Sum).Sum) }
                if ($null -eq $size) { $size = 0 }
                if ($PSCmdlet.ShouldProcess('Recycle Bin (all drives)', "Empty $([math]::Round($size / 1MB, 1)) MB")) {
                    Clear-RecycleBin -Force -ErrorAction SilentlyContinue
                }
                [pscustomobject]@{ Target = $t; Files = $null; Skipped = 0; FreedMB = [math]::Round($size / 1MB, 1); Preview = [bool]$WhatIfPreference }
            }
            'DeliveryOptimization' {
                if (-not (Get-Command Delete-DeliveryOptimizationCache -ErrorAction SilentlyContinue)) { Write-Warning 'Delivery Optimization cmdlets not available on this OS - skipped.'; continue }
                $size = Invoke-PcSafely { [int64]((Get-DeliveryOptimizationStatus | Measure-Object FileSize -Sum).Sum) }
                if ($null -eq $size) { $size = 0 }
                if ($PSCmdlet.ShouldProcess('Delivery Optimization cache', "Clear $([math]::Round($size / 1MB, 1)) MB")) {
                    Delete-DeliveryOptimizationCache -Force
                }
                [pscustomobject]@{ Target = $t; Files = $null; Skipped = 0; FreedMB = [math]::Round($size / 1MB, 1); Preview = [bool]$WhatIfPreference }
            }
            'ComponentStore' {
                if ($PSCmdlet.ShouldProcess('Windows component store', 'DISM /StartComponentCleanup (can take 10+ minutes)')) {
                    & dism.exe /Online /Cleanup-Image /StartComponentCleanup /Quiet | Out-Null
                    if ($LASTEXITCODE -ne 0) { Write-Warning "DISM finished with exit code $LASTEXITCODE." }
                }
                [pscustomobject]@{ Target = $t; Files = $null; Skipped = 0; FreedMB = $null; Preview = [bool]$WhatIfPreference }
            }
        }
    }
}

Export-ModuleMember -Function Get-PcHealthReport, Invoke-PcCleanup

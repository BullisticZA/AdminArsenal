# 🩺 PC Health

A one-command **Windows health check** with a scored HTML report, and a **safe cleanup** that always lets you preview first.

Part of [AdminArsenal](../../README.md).

## ✨ Features

| Command | What it does |
|---|---|
| `Get-PcHealthReport` | Checks storage, disk health, memory, uptime, updates, antivirus, failing services and event log errors, then gives a **0–100 health score** with plain-English fixes. **Read-only.** |
| `Invoke-PcCleanup` | Frees disk space from temp folders, the Recycle Bin, update caches and old Windows components. Supports `-WhatIf` and asks before deleting. |

## 🔍 What gets checked

| Area | Check | Flags when |
|---|---|---|
| Storage | Free space per drive | Below 20% (warning) or 10% (critical) |
| Storage | Physical disk health (SMART via Windows) | Anything other than Healthy |
| Memory | RAM in use | 90% or more |
| System | Time since last restart | 30 days or more |
| Updates | Pending restart, last installed update | Restart pending; no update in 45+ days |
| Security | Real-time antivirus, definition age | Protection off; definitions 7+ days old |
| Services | Automatic services that crashed | Stopped with a non-zero exit code |
| Events | System log errors in the last 24 h | 5 or more |
| Storage | Temporary files | 2 GB or more |

Trigger-start services that stop normally are **not** reported, which avoids the usual flood of false alarms.

## 📋 Requirements

- Windows 10 / 11 or Windows Server 2016+
- Windows PowerShell 5.1 or PowerShell 7+
- Run as administrator for the full picture (disk health, `C:\Windows\Temp`, update caches)

## 🚀 Usage

```powershell
Import-Module .\tools\pc-health\PcHealth.psm1
```

### Health report

```powershell
Get-PcHealthReport                                   # score + findings in the console
Get-PcHealthReport | Select-Object -ExpandProperty Issues | Format-Table
Get-PcHealthReport -HtmlPath "$env:USERPROFILE\Desktop\pc-health.html" -Open
```

```
Severity Area     Message
-------- ----     -------
Critical Storage  Drive C: has only 4.8% free (12 GB).
Warning  Updates  A restart is pending to finish installing updates.
Info     Storage  3.4 GB of temporary files can likely be cleared.
```

### Cleanup: preview first, then run

```powershell
Invoke-PcCleanup -WhatIf                     # shows what would be removed, deletes nothing
Invoke-PcCleanup                             # asks for confirmation, then cleans
Invoke-PcCleanup -Target UserTemp, WindowsTemp, RecycleBin, DeliveryOptimization -Confirm:$false
Invoke-PcCleanup -Target ComponentStore      # DISM component cleanup (slow)
```

| Target | What it removes | Admin |
|---|---|---|
| `UserTemp` | Your `%TEMP%` folder | No |
| `WindowsTemp` | `C:\Windows\Temp` | Yes |
| `RecycleBin` | Recycle Bin on all drives | No |
| `DeliveryOptimization` | Cached update downloads shared between PCs | Yes |
| `ComponentStore` | Superseded Windows update components (DISM) | Yes |

By default only files **older than 2 days** are removed (change with `-OlderThanDays`), and files that are in use are skipped.

## ✅ Tested

The scoring rules have unit tests, and on every push the full report and a cleanup preview run on a real Windows machine in CI, under both Windows PowerShell 5.1 and PowerShell 7.

## 📜 License

[MIT](../../LICENSE) © 2026 Charl Britz

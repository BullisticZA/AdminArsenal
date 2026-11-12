# 🔐 AIO Certs

All-in-one certificate lifecycle toolkit for Windows: **CSR → issued cert → PFX → silent install → expiry report**, without clicking through MMC.

Part of [AdminArsenal](../../README.md).

## ✨ Features

| Command | What it does |
|---|---|
| `New-AioCsr` | Generates a private key + CSR (SHA-256, SANs included, CN auto-added as a SAN) |
| `Complete-AioCsr` | Pairs the issued certificate with its private key and exports a password-protected PFX with the full chain |
| `Install-AioPfx` | Silently imports a PFX into any store, ideal for pushing from an RMM tool |
| `Install-AioCertificate` | Imports a root / intermediate CA certificate (.cer/.crt) |
| `Get-AioExpiringCertificate` | Reports certificates expiring within N days |

## 📋 Requirements

- Windows 10 / Server 2016 or newer
- Windows PowerShell 5.1 or PowerShell 7+ (Windows)
- An elevated session for anything in the `LocalMachine` store

## 🚀 Usage

```powershell
Import-Module .\tools\aio-certs\AioCerts.psm1
```

### 1. Create a CSR

```powershell
New-AioCsr -CommonName mail.contoso.com `
           -SubjectAltName autodiscover.contoso.com, owa.contoso.com `
           -Organization "Contoso Ltd" -Locality "Cape Town" -State "Western Cape" -Country ZA `
           -OutputPath C:\Certs
```

Send the `.csr` file to your certificate authority.

### 2. Complete it into a PFX

Run this **on the same machine** that created the CSR, since that is where the private key lives:

```powershell
Complete-AioCsr -CertificatePath C:\Certs\mail_contoso_com.cer -PfxPath C:\Certs\mail.contoso.com.pfx
```

### 3. Deploy silently (e.g. from an RMM script)

```powershell
$pw = ConvertTo-SecureString $env:PFX_PASSWORD -AsPlainText -Force
Install-AioPfx -PfxPath C:\Temp\mail.contoso.com.pfx -PfxPassword $pw -NonExportable
```

> Pass the password through your RMM's secure variables, never hard-coded in the script.

### 4. Find what's about to expire

```powershell
Get-AioExpiringCertificate -Days 60 | Sort-Object DaysLeft | Format-Table
Get-AioExpiringCertificate -Days 30 -IncludeExpired | Export-Csv .\expiring.csv -NoTypeInformation
```

## 🗺️ Roadmap

- [ ] GUI front-end (WinForms) for the full workflow
- [ ] PEM ↔ PFX conversion (for Linux / firewall appliances)
- [ ] Remote expiry scan across multiple servers
- [ ] Email / Teams alert for expiring certificates

## 📜 License

[MIT](../../LICENSE) © 2026 Charl Britz

<p align="center">
  <img src="assets/logo.png" alt="AdminArsenal logo" width="160">
</p>

<h1 align="center">AdminArsenal</h1>

<p align="center">
  <b>An all-in-one PowerShell arsenal for system administrators.</b><br>
  Practical, standalone tools that take the repetitive work out of IT.
</p>

<p align="center">
  <a href="https://github.com/BullisticZA/AdminArsenal/actions/workflows/lint.yml"><img src="https://github.com/BullisticZA/AdminArsenal/actions/workflows/lint.yml/badge.svg" alt="CI"></a>
  <img src="https://img.shields.io/badge/PowerShell-5.1%20%7C%207%2B-5391FE?logo=powershell&logoColor=white" alt="PowerShell">
  <img src="https://img.shields.io/badge/platform-Windows-0078D6?logo=windows&logoColor=white" alt="Windows">
  <img src="https://img.shields.io/badge/license-MIT-green" alt="MIT">
</p>

---

## 🧰 The Arsenal

| Tool | What it does | Status |
|---|---|---|
| [**AIO Certs**](tools/aio-certs) | Generate CSRs, complete them into PFX files, silently install certificates and report on expiring ones | ✅ v0.1 |
| [**PassForge**](tools/passforge) | Crypto-secure passwords and passphrases, an honest strength meter and private breach checks | ✅ v1.0 |
| [**PC Health**](tools/pc-health) | Scored Windows health check with an HTML report, plus a preview-first cleanup | ✅ v1.0 |

More tools are on the way. Every tool is standalone: grab the one you need, read its README, and run it.

---

## 🚀 Quick start

```powershell
git clone https://github.com/BullisticZA/AdminArsenal.git
cd AdminArsenal

# Load a tool, then see what it can do
Import-Module .\tools\pc-health\PcHealth.psm1
Get-PcHealthReport -HtmlPath .\pc-health.html -Open

Import-Module .\tools\passforge\PassForge.psm1
New-PassForgePassphrase
```

> Scripts downloaded from the internet may be blocked by your execution policy.
> Review the code, then run `Unblock-File` on the files or use `Set-ExecutionPolicy -Scope Process RemoteSigned`.

## 📁 Repository layout

```
AdminArsenal/
├── assets/               # Logo and images
├── tests/                # Unit and Windows smoke tests (run in CI)
├── tools/
│   ├── aio-certs/        # Certificate lifecycle toolkit
│   ├── passforge/        # Passwords, passphrases, strength and breach checks
│   └── pc-health/        # Health report and safe cleanup
├── CHANGELOG.md
├── PSScriptAnalyzerSettings.psd1
├── LICENSE
└── README.md
```

## ✅ Quality

Every push is checked automatically on Windows:
- all scripts must parse cleanly and pass [PSScriptAnalyzer](https://github.com/PowerShell/PSScriptAnalyzer) with no warnings
- unit tests and a real Windows smoke test run under **both** Windows PowerShell 5.1 and PowerShell 7

## 🤝 Contributing

Issues and pull requests are welcome. If a tool saved you time, a ⭐ helps other engineers find it.

## 📜 License

[MIT](LICENSE) © 2026 Charl Britz

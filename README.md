# 🛡️ AdminArsenal

**All-in-one PowerShell arsenal for sysadmins and MSPs**: certificates, Microsoft 365, backups and infrastructure automation in one place.

![PowerShell](https://img.shields.io/badge/PowerShell-5.1%20%7C%207%2B-5391FE?logo=powershell&logoColor=white)
![Platform](https://img.shields.io/badge/platform-Windows-0078D6?logo=windows&logoColor=white)
![License](https://img.shields.io/badge/license-MIT-green)

AdminArsenal is a growing collection of practical tools built from real-world IT and MSP work. Every tool is standalone: grab the one you need, read its README, and run it.

---

## 🧰 The Arsenal

| Tool | What it does | Status |
|---|---|---|
| [**AIO Certs**](tools/aio-certs) | Generate CSRs, complete them into PFX files, silently install certificates and report on expiring ones | ✅ v0.1 |
| **M365 Tenant Explorer** | Export SharePoint sites, users, licences and more from any Microsoft 365 tenant | 🛠️ Planned |
| **Cove Deploy Kit** | Push and configure Cove Data Protection across many machines at once | 🛠️ Planned |
| **Backup Health Check** | One-shot report of backup job status across Veeam / Cove | 🛠️ Planned |

---

## 🚀 Quick start

```powershell
# Clone the arsenal
git clone https://github.com/BullisticZA/AdminArsenal.git
cd AdminArsenal

# Load a tool (example: AIO Certs)
Import-Module .\tools\aio-certs\AioCerts.psm1

# See what it can do
Get-Command -Module AioCerts
```

> Scripts downloaded from the internet may be blocked by your execution policy.
> Review the code, then run `Unblock-File` on the files or use `Set-ExecutionPolicy -Scope Process RemoteSigned`.

---

## 📁 Repository layout

```
AdminArsenal/
├── tools/
│   └── aio-certs/        # Certificate lifecycle toolkit
├── LICENSE
└── README.md
```

## 🤝 Contributing

Issues and pull requests are welcome. If a tool saved you time, a ⭐ helps other engineers find it.

## 📜 License

[MIT](LICENSE) © 2026 Charl Britz

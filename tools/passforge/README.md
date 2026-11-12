# 🔑 PassForge

Cryptographically secure **passwords and passphrases**, an honest **strength meter**, and a **private breach check**, all in one small PowerShell module.

Part of [AdminArsenal](../../README.md).

## ✨ Features

| Command | What it does |
|---|---|
| `New-PassForgePassword` | Random passwords that always include every character type you allow, with optional removal of look-alike characters (`I l 1 O 0`) |
| `New-PassForgePassphrase` | Memorable Diceware-style passphrases from the EFF's 7,776-word list |
| `Measure-PassForgeStrength` | Scores an existing password, penalising common passwords, repeats, sequences and dictionary words |
| `Test-PassForgePwned` | Checks if a password appears in known data breaches, without ever sending the password |

Every result shows its **entropy in bits**, a **rating** (Weak / Fair / Strong / Excellent) and an estimated **time to crack** at 10 billion guesses per second.

## 🔒 Why it's trustworthy

- **Crypto-grade randomness:** every pick uses the operating system's cryptographic random number generator, never `Get-Random`.
- **No modulo bias:** random numbers use rejection sampling, so every character and word is exactly equally likely.
- **Private breach checks:** only the first 5 characters of the password's SHA-1 hash are sent ([k-anonymity](https://haveibeenpwned.com/API/v3#PwnedPasswords)), with response padding enabled.
- **Secrets stay secret:** the strength and breach commands take a `SecureString`, so passwords don't end up in your command history.
- **Tested:** class coverage, look-alike removal, word-list membership and random number distribution are all checked.

## 📋 Requirements

Windows PowerShell 5.1 or PowerShell 7+ on Windows, macOS or Linux. `-CopyToClipboard` needs a clipboard (Windows or PowerShell 7 with a desktop session).

## 🚀 Usage

```powershell
Import-Module .\tools\passforge\PassForge.psm1
```

### Generate a password

```powershell
New-PassForgePassword                         # 20 characters, all types
New-PassForgePassword -Length 32 -CopyToClipboard
New-PassForgePassword -Length 16 -NoSymbols -NoAmbiguous -Count 10
```

```
Password             EntropyBits Strength  CrackTime
--------             ----------- --------  ---------
wXXaDq-*vh2m7ego89V-       129.5 Excellent millions of centuries+
```

### Generate a passphrase

```powershell
New-PassForgePassphrase                                         # 6 words, ~77 bits
New-PassForgePassphrase -Words 7 -Separator ' ' -Capitalize -AddNumber
```

```
Passphrase                                     EntropyBits Strength
----------                                     ----------- --------
canal-detract-glider-deceptive-liqueur-smooth         77.5 Strong
```

### Check an existing password

```powershell
Read-Host -AsSecureString 'Password' | Measure-PassForgeStrength
Read-Host -AsSecureString 'Password' | Test-PassForgePwned
```

## 📏 How strength is rated

| Bits | Rating | Rough meaning |
|---|---|---|
| < 40 | Weak | Crackable in seconds to hours |
| 40–59 | Fair | Hours to years, fine for low-value accounts only |
| 60–79 | Strong | Good for most accounts |
| 80+ | Excellent | Good for master passwords and admin accounts |

## 🙏 Credits

- Word list: [EFF Large Wordlist for Passphrases](https://www.eff.org/deeplinks/2016/07/new-wordlists-random-passphrases) by the Electronic Frontier Foundation, licensed under [CC BY 3.0 US](https://creativecommons.org/licenses/by/3.0/us/).
- Breach data: [Pwned Passwords](https://haveibeenpwned.com/Passwords) by Troy Hunt.

## 📜 License

Code: [MIT](../../LICENSE) © 2026 Charl Britz. Word list: CC BY 3.0 US (see Credits).

#Requires -Version 5.1
<#
.SYNOPSIS
    PassForge - cryptographically secure passwords and passphrases, strength scoring
    and private breach checks.
.DESCRIPTION
    Every random choice uses the OS cryptographic random number generator with
    rejection sampling, so there is no modulo bias. Works on Windows PowerShell 5.1
    and PowerShell 7+ on any platform.
    Part of AdminArsenal - https://github.com/BullisticZA/AdminArsenal
.NOTES
    Author : Charl Britz
    License: MIT. Word list: EFF Large Wordlist, CC BY 3.0 US (see README).
#>

Set-StrictMode -Version Latest

$script:Rng       = [Security.Cryptography.RandomNumberGenerator]::Create()
$script:WordList  = $null
$script:Lower     = 'abcdefghijklmnopqrstuvwxyz'
$script:Upper     = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ'
$script:Digits    = '0123456789'
$script:Symbols   = '!@#$%^&*()-_=+[]{};:,.<>?/~'
$script:Ambiguous = 'Il1O0o|`''"'
$script:Common    = @(
    'password', '123456', '12345678', 'qwerty', 'abc123', 'letmein', 'welcome', 'admin',
    'iloveyou', 'monkey', 'dragon', 'football', 'baseball', 'master', 'sunshine', 'princess',
    'passw0rd', 'p@ssw0rd', 'p@ssword', 'trustno1', 'starwars', 'whatever', 'shadow', 'login'
)

#region Helpers

function Get-PfRandomInt {
    # Uniform integer in [0, Max) from the crypto RNG, using rejection sampling.
    param([Parameter(Mandatory)][ValidateRange(1, [int]::MaxValue)][int]$Max)
    $range = [uint64]4294967296
    $limit = $range - ($range % [uint64]$Max)
    $bytes = New-Object byte[] 4
    do {
        $script:Rng.GetBytes($bytes)
        $value = [uint64][BitConverter]::ToUInt32($bytes, 0)
    } while ($value -ge $limit)
    [int]($value % [uint64]$Max)
}

function Get-PfShuffled {
    param([char[]]$Chars)
    for ($i = $Chars.Length - 1; $i -gt 0; $i--) {
        $j = Get-PfRandomInt -Max ($i + 1)
        $tmp = $Chars[$i]; $Chars[$i] = $Chars[$j]; $Chars[$j] = $tmp
    }
    -join $Chars
}

function Get-PfRating {
    param([double]$Bits)
    if ($Bits -lt 40)     { 'Weak' }
    elseif ($Bits -lt 60) { 'Fair' }
    elseif ($Bits -lt 80) { 'Strong' }
    else                  { 'Excellent' }
}

function Get-PfCrackTime {
    # Average time to guess, offline attack at 10 billion guesses per second.
    param([double]$Bits)
    $seconds = [math]::Pow(2, $Bits - 1) / 1e10
    $units = @(
        @{ Name = 'centuries'; Size = 3.15576e9 }, @{ Name = 'years'; Size = 3.15576e7 },
        @{ Name = 'days'; Size = 86400 }, @{ Name = 'hours'; Size = 3600 },
        @{ Name = 'minutes'; Size = 60 }, @{ Name = 'seconds'; Size = 1 }
    )
    if ($seconds -lt 1) { return 'instantly' }
    foreach ($u in $units) {
        if ($seconds -ge $u.Size) {
            $n = $seconds / $u.Size
            if ($n -ge 1e6) { return "millions of $($u.Name)+" }
            return '{0:N0} {1}' -f $n, $u.Name
        }
    }
}

function Get-PfWordList {
    if (-not $script:WordList) {
        $path = Join-Path $PSScriptRoot 'eff_large_wordlist.txt'
        if (-not (Test-Path $path)) { throw "Word list not found: $path" }
        $script:WordList = [string[]](Get-Content -Path $path | Where-Object { $_ })
    }
    , $script:WordList
}

function ConvertFrom-PfSecureString {
    param([securestring]$Secure)
    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Secure)
    try { [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr) }
    finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
}

#endregion

function New-PassForgePassword {
    <#
    .SYNOPSIS
        Generates random passwords that always contain every selected character type.
    .EXAMPLE
        New-PassForgePassword -Length 24
    .EXAMPLE
        New-PassForgePassword -Length 16 -NoSymbols -NoAmbiguous -Count 5
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Only generates values; changes no system state.')]
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [ValidateRange(8, 256)][int]$Length = 20,
        [ValidateRange(1, 1000)][int]$Count = 1,
        [switch]$NoUpper,
        [switch]$NoDigits,
        [switch]$NoSymbols,
        [switch]$NoAmbiguous,
        [switch]$CopyToClipboard
    )

    $sets = @($script:Lower)
    if (-not $NoUpper)   { $sets += $script:Upper }
    if (-not $NoDigits)  { $sets += $script:Digits }
    if (-not $NoSymbols) { $sets += $script:Symbols }
    if ($NoAmbiguous) {
        $sets = foreach ($s in $sets) { -join ($s.ToCharArray() | Where-Object { $script:Ambiguous.IndexOf($_) -lt 0 }) }
    }
    $pool = -join $sets
    $bits = [math]::Round($Length * [math]::Log($pool.Length, 2), 1)

    $results = for ($n = 0; $n -lt $Count; $n++) {
        # One guaranteed character from each set, the rest from the full pool, then shuffle.
        $chars = foreach ($s in $sets) { $s[(Get-PfRandomInt -Max $s.Length)] }
        $chars = @($chars) + @(for ($i = $sets.Count; $i -lt $Length; $i++) { $pool[(Get-PfRandomInt -Max $pool.Length)] })
        [pscustomobject]@{
            Password    = Get-PfShuffled -Chars ([char[]]$chars)
            EntropyBits = $bits
            Strength    = Get-PfRating -Bits $bits
            CrackTime   = Get-PfCrackTime -Bits $bits
        }
    }

    if ($CopyToClipboard) { Set-Clipboard -Value $results[0].Password; Write-Verbose 'First password copied to clipboard.' }
    $results
}

function New-PassForgePassphrase {
    <#
    .SYNOPSIS
        Generates memorable Diceware-style passphrases from the EFF large word list.
    .EXAMPLE
        New-PassForgePassphrase
    .EXAMPLE
        New-PassForgePassphrase -Words 7 -Separator ' ' -Capitalize -AddNumber
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Only generates values; changes no system state.')]
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [ValidateRange(4, 20)][int]$Words = 6,
        [ValidateLength(0, 3)][string]$Separator = '-',
        [ValidateRange(1, 1000)][int]$Count = 1,
        [switch]$Capitalize,
        [switch]$AddNumber,
        [switch]$CopyToClipboard
    )

    $list = Get-PfWordList
    $bits = $Words * [math]::Log($list.Count, 2)
    if ($AddNumber) { $bits += [math]::Log(100, 2) + [math]::Log($Words, 2) }
    $bits = [math]::Round($bits, 1)

    $results = for ($n = 0; $n -lt $Count; $n++) {
        $picked = @(for ($i = 0; $i -lt $Words; $i++) {
            $w = $list[(Get-PfRandomInt -Max $list.Count)]
            if ($Capitalize) { $w = $w.Substring(0, 1).ToUpper() + $w.Substring(1) }
            $w
        })
        if ($AddNumber) {
            $slot = Get-PfRandomInt -Max $Words
            $picked[$slot] = $picked[$slot] + (Get-PfRandomInt -Max 100)
        }
        [pscustomobject]@{
            Passphrase  = $picked -join $Separator
            EntropyBits = $bits
            Strength    = Get-PfRating -Bits $bits
            CrackTime   = Get-PfCrackTime -Bits $bits
        }
    }

    if ($CopyToClipboard) { Set-Clipboard -Value $results[0].Passphrase; Write-Verbose 'First passphrase copied to clipboard.' }
    $results
}

function Measure-PassForgeStrength {
    <#
    .SYNOPSIS
        Estimates the strength of an existing password, with penalties for common
        passwords, repeats and keyboard/number sequences.
    .EXAMPLE
        Read-Host -AsSecureString | Measure-PassForgeStrength
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory, ValueFromPipeline)][securestring]$Secret
    )
    process {
        $plain = ConvertFrom-PfSecureString -Secure $Secret
        $notes = New-Object System.Collections.Generic.List[string]

        if ([string]::IsNullOrEmpty($plain)) {
            return [pscustomobject]@{ Length = 0; EntropyBits = 0; Strength = 'Weak'; CrackTime = 'instantly'; Notes = 'Empty' }
        }

        $poolSize = 0
        if ($plain -cmatch '[a-z]')        { $poolSize += 26 }
        if ($plain -cmatch '[A-Z]')        { $poolSize += 26 }
        if ($plain -match '[0-9]')         { $poolSize += 10 }
        if ($plain -match '[^a-zA-Z0-9]')  { $poolSize += 33 }

        # Count characters that add new information: ignore runs and +1/-1 sequences.
        $effective = 1
        for ($i = 1; $i -lt $plain.Length; $i++) {
            $diff = [int]$plain[$i] - [int]$plain[$i - 1]
            if ($diff -ne 0 -and [math]::Abs($diff) -ne 1) { $effective++ }
        }
        if (($plain.Length - $effective) -ge 3 -or ($plain.Length - $effective) / $plain.Length -gt 0.25) {
            $notes.Add('Contains repeated or sequential characters')
        }

        $bits = $effective * [math]::Log([math]::Max($poolSize, 2), 2)

        # Passwords made of dictionary words are scored per word, not per character.
        $tokens = @(($plain.ToLower() -split '[^a-z]+') | Where-Object { $_.Length -ge 3 })
        if ($tokens.Count -ge 2) {
            $list  = Get-PfWordList
            $found = @($tokens | Where-Object { [Array]::BinarySearch($list, $_, [StringComparer]::Ordinal) -ge 0 })
            if ($found.Count * 2 -ge $tokens.Count) {
                $wordBits = 0
                foreach ($t in $tokens) {
                    if ($found -contains $t) { $wordBits += [math]::Log($list.Count, 2) }
                    else                     { $wordBits += $t.Length * [math]::Log(26, 2) }
                }
                # Digits add ~3.3 bits each; a repeated separator only adds its one-time choice.
                $extra = ($plain -replace '[^0-9]', '').Length * 3.3 +
                         @(($plain -replace '[a-zA-Z0-9]', '').ToCharArray() | Select-Object -Unique).Count * 5
                $bits  = [math]::Min($bits, $wordBits + $extra)
                $notes.Add("Mostly dictionary words ($($found.Count) of $($tokens.Count)) - scored per word")
            }
        }

        $lowerPlain = $plain.ToLower()
        $stripped = ($lowerPlain -replace '[^a-z@0]', '')
        foreach ($c in $script:Common) {
            if ($lowerPlain -eq $c -or $stripped -eq $c) { $bits = [math]::Min($bits, 10); $notes.Add('Matches a very common password'); break }
            if ($lowerPlain.Contains($c)) { $bits -= 15; $notes.Add("Contains the common word '$c'"); break }
        }
        if ($plain.Length -lt 12) { $notes.Add('Shorter than 12 characters') }

        $bits = [math]::Round([math]::Max($bits, 0), 1)
        [pscustomobject]@{
            Length      = $plain.Length
            EntropyBits = $bits
            Strength    = Get-PfRating -Bits $bits
            CrackTime   = Get-PfCrackTime -Bits $bits
            Notes       = if ($notes.Count) { $notes -join '; ' } else { 'No obvious weaknesses' }
        }
    }
}

function Test-PassForgePwned {
    <#
    .SYNOPSIS
        Checks whether a password appears in known data breaches using the
        Pwned Passwords k-anonymity API.
    .DESCRIPTION
        Only the first 5 characters of the password's SHA-1 hash leave your machine.
        The password itself is never sent anywhere.
    .EXAMPLE
        Read-Host -AsSecureString | Test-PassForgePwned
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory, ValueFromPipeline)][securestring]$Secret
    )
    process {
        $plain = ConvertFrom-PfSecureString -Secure $Secret
        $sha1  = [Security.Cryptography.SHA1]::Create()
        try {
            $hash = -join ($sha1.ComputeHash([Text.Encoding]::UTF8.GetBytes($plain)) | ForEach-Object { $_.ToString('X2') })
        } finally { $sha1.Dispose() }
        $prefix = $hash.Substring(0, 5)
        $suffix = $hash.Substring(5)

        # Windows PowerShell 5.1 may not offer TLS 1.2 by default; the API requires it.
        if ($PSVersionTable.PSVersion.Major -lt 6) {
            [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
        }

        $response = Invoke-RestMethod -Uri "https://api.pwnedpasswords.com/range/$prefix" `
            -Headers @{ 'Add-Padding' = 'true' } -UserAgent 'AdminArsenal-PassForge' -ErrorAction Stop

        $count = 0
        foreach ($line in ($response -split "`r?`n")) {
            $parts = $line.Split(':')
            if ($parts.Count -eq 2 -and $parts[0] -eq $suffix) { $count = [int]$parts[1]; break }
        }

        [pscustomobject]@{
            Pwned       = $count -gt 0
            TimesSeen   = $count
            Advice      = if ($count -gt 0) { 'Found in breaches - do not use this password.' } else { 'Not found in known breaches.' }
        }
    }
}

Export-ModuleMember -Function New-PassForgePassword, New-PassForgePassphrase, Measure-PassForgeStrength, Test-PassForgePwned

#Requires -Version 5.1
<#
.SYNOPSIS
    AIO Certs - all-in-one certificate lifecycle toolkit for Windows.
.DESCRIPTION
    Generate CSRs, complete issued certificates into PFX files, silently install
    certificates into the right store, and report on certificates that are expiring.
    Part of AdminArsenal - https://github.com/BullisticZA/AdminArsenal
.NOTES
    Author : Charl Britz
    License: MIT
#>

Set-StrictMode -Version Latest

function Test-AioAdmin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    ([Security.Principal.WindowsPrincipal]$id).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Assert-AioAdmin {
    param([string]$Location)
    if ($Location -eq 'LocalMachine' -and -not (Test-AioAdmin)) {
        throw "Working with the LocalMachine store needs an elevated (Run as administrator) PowerShell session."
    }
}

function Format-AioRdnValue {
    param([string]$Value)
    # Values containing commas must be quoted inside the subject string; INF doubles the quotes.
    if ($Value -match '[,+=]') { return '""' + ($Value -replace '"', '') + '""' }
    return $Value
}

function New-AioCsr {
    <#
    .SYNOPSIS
        Generates a private key and a Certificate Signing Request (CSR) using certreq.
    .EXAMPLE
        New-AioCsr -CommonName mail.example.com -SubjectAltName autodiscover.example.com -Organization "Example Org" -Country ZA
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string]$CommonName,
        [string[]]$SubjectAltName,
        [string]$Organization,
        [string]$OrganizationalUnit,
        [string]$Locality,
        [string]$State,
        [ValidatePattern('^[A-Za-z]{2}$')][string]$Country,
        [ValidateSet(2048, 3072, 4096)][int]$KeyLength = 2048,
        [ValidateSet('LocalMachine', 'CurrentUser')][string]$KeyLocation = 'LocalMachine',
        [string]$OutputPath = (Get-Location).Path
    )

    Assert-AioAdmin -Location $KeyLocation
    if (-not (Test-Path $OutputPath)) { New-Item -ItemType Directory -Path $OutputPath | Out-Null }

    $parts = @("CN=$(Format-AioRdnValue $CommonName)")
    if ($OrganizationalUnit) { $parts += "OU=$(Format-AioRdnValue $OrganizationalUnit)" }
    if ($Organization)       { $parts += "O=$(Format-AioRdnValue $Organization)" }
    if ($Locality)           { $parts += "L=$(Format-AioRdnValue $Locality)" }
    if ($State)              { $parts += "S=$(Format-AioRdnValue $State)" }
    if ($Country)            { $parts += "C=$($Country.ToUpper())" }
    $subject = $parts -join ', '

    # The CN is always included as a SAN - modern browsers ignore the CN on its own.
    $sans = @($CommonName) + @($SubjectAltName | Where-Object { $_ }) | Select-Object -Unique

    $safeName = $CommonName -replace '[^\w\.-]', '_'
    $infPath  = Join-Path $OutputPath "$safeName.inf"
    $csrPath  = Join-Path $OutputPath "$safeName.csr"

    $sanLines = foreach ($s in $sans) { "_continue_ = ""dns=$s&""" }
    $inf = @"
[Version]
Signature="`$Windows NT`$"

[NewRequest]
Subject = "$subject"
KeySpec = 1
KeyLength = $KeyLength
HashAlgorithm = sha256
Exportable = TRUE
MachineKeySet = $(if ($KeyLocation -eq 'LocalMachine') { 'TRUE' } else { 'FALSE' })
SMIME = FALSE
PrivateKeyArchive = FALSE
UserProtected = FALSE
UseExistingKeySet = FALSE
ProviderName = "Microsoft RSA SChannel Cryptographic Provider"
ProviderType = 12
RequestType = PKCS10
KeyUsage = 0xa0

[EnhancedKeyUsageExtension]
OID = 1.3.6.1.5.5.7.3.1

[Extensions]
2.5.29.17 = "{text}"
$($sanLines -join "`r`n")
"@

    if ($PSCmdlet.ShouldProcess($CommonName, 'Generate private key and CSR')) {
        Set-Content -Path $infPath -Value $inf -Encoding ASCII
        $out = & certreq.exe -new -q $infPath $csrPath 2>&1
        if ($LASTEXITCODE -ne 0) { throw "certreq failed: $($out -join ' ')" }

        [pscustomobject]@{
            CommonName  = $CommonName
            SANs        = $sans -join ', '
            CsrPath     = $csrPath
            InfPath     = $infPath
            KeyLocation = $KeyLocation
            NextStep    = "Send the CSR to your CA, then run Complete-AioCsr with the issued certificate on THIS machine."
        }
    }
}

function Complete-AioCsr {
    <#
    .SYNOPSIS
        Accepts an issued certificate (pairs it with the pending private key) and exports a PFX.
    .EXAMPLE
        Complete-AioCsr -CertificatePath .\mail_example_com.cer -PfxPath .\mail.pfx
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateScript({ Test-Path $_ })][string]$CertificatePath,
        [Parameter(Mandatory)][string]$PfxPath,
        [securestring]$PfxPassword = (Read-Host -AsSecureString 'PFX password'),
        [ValidateSet('LocalMachine', 'CurrentUser')][string]$KeyLocation = 'LocalMachine'
    )

    Assert-AioAdmin -Location $KeyLocation
    $certFile = (Resolve-Path $CertificatePath).Path

    $acceptArgs = @('-accept', '-q')
    if ($KeyLocation -eq 'LocalMachine') { $acceptArgs += '-machine' } else { $acceptArgs += '-user' }
    $out = & certreq.exe @acceptArgs $certFile 2>&1
    if ($LASTEXITCODE -ne 0) { throw "certreq -accept failed (was the CSR created on this machine?): $($out -join ' ')" }

    $thumb = (New-Object Security.Cryptography.X509Certificates.X509Certificate2 $certFile).Thumbprint
    $cert  = Get-Item "Cert:\$KeyLocation\My\$thumb" -ErrorAction Stop
    if (-not $cert.HasPrivateKey) { throw "Certificate $thumb was installed but has no private key attached." }

    Export-PfxCertificate -Cert $cert -FilePath $PfxPath -Password $PfxPassword -ChainOption BuildChain | Out-Null

    [pscustomobject]@{
        Subject    = $cert.Subject
        Thumbprint = $thumb
        NotAfter   = $cert.NotAfter
        PfxPath    = (Resolve-Path $PfxPath).Path
    }
}

function Install-AioPfx {
    <#
    .SYNOPSIS
        Silently imports a PFX into a certificate store. Safe to run from an RMM tool.
    .EXAMPLE
        Install-AioPfx -PfxPath C:\Temp\wifi.pfx -PfxPassword $pw -StoreLocation LocalMachine -NonExportable
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][ValidateScript({ Test-Path $_ })][string]$PfxPath,
        [Parameter(Mandatory)][securestring]$PfxPassword,
        [ValidateSet('LocalMachine', 'CurrentUser')][string]$StoreLocation = 'LocalMachine',
        [ValidateSet('My', 'Root', 'CA', 'TrustedPeople', 'WebHosting')][string]$StoreName = 'My',
        [switch]$NonExportable
    )

    Assert-AioAdmin -Location $StoreLocation
    $params = @{
        FilePath          = (Resolve-Path $PfxPath).Path
        CertStoreLocation = "Cert:\$StoreLocation\$StoreName"
        Password          = $PfxPassword
    }
    if (-not $NonExportable) { $params.Exportable = $true }

    if ($PSCmdlet.ShouldProcess($params.CertStoreLocation, "Import $PfxPath")) {
        Import-PfxCertificate @params |
            Select-Object Subject, Thumbprint, NotAfter, @{ n = 'Store'; e = { $params.CertStoreLocation } }
    }
}

function Install-AioCertificate {
    <#
    .SYNOPSIS
        Imports a public certificate (.cer/.crt) - e.g. a root or intermediate CA - into a store.
    .EXAMPLE
        Install-AioCertificate -CertificatePath .\RootCA.cer -StoreName Root
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][ValidateScript({ Test-Path $_ })][string]$CertificatePath,
        [ValidateSet('LocalMachine', 'CurrentUser')][string]$StoreLocation = 'LocalMachine',
        [ValidateSet('Root', 'CA', 'My', 'TrustedPeople', 'TrustedPublisher')][string]$StoreName = 'Root'
    )

    Assert-AioAdmin -Location $StoreLocation
    $location = "Cert:\$StoreLocation\$StoreName"
    if ($PSCmdlet.ShouldProcess($location, "Import $CertificatePath")) {
        Import-Certificate -FilePath (Resolve-Path $CertificatePath).Path -CertStoreLocation $location |
            Select-Object Subject, Thumbprint, NotAfter, @{ n = 'Store'; e = { $location } }
    }
}

function Get-AioExpiringCertificate {
    <#
    .SYNOPSIS
        Lists certificates that expire within the given number of days.
    .EXAMPLE
        Get-AioExpiringCertificate -Days 60 | Export-Csv .\expiring.csv -NoTypeInformation
    #>
    [CmdletBinding()]
    param(
        [int]$Days = 30,
        [ValidateSet('LocalMachine', 'CurrentUser')][string[]]$StoreLocation = @('LocalMachine', 'CurrentUser'),
        [string[]]$StoreName = @('My', 'WebHosting'),
        [switch]$IncludeExpired
    )

    $now    = Get-Date
    $cutoff = $now.AddDays($Days)

    foreach ($loc in $StoreLocation) {
        foreach ($store in $StoreName) {
            $path = "Cert:\$loc\$store"
            if (-not (Test-Path $path)) { continue }
            Get-ChildItem $path | Where-Object {
                $_.NotAfter -le $cutoff -and ($IncludeExpired -or $_.NotAfter -ge $now)
            } | ForEach-Object {
                [pscustomobject]@{
                    Subject       = $_.Subject
                    DaysLeft      = [int][math]::Floor(($_.NotAfter - $now).TotalDays)
                    NotAfter      = $_.NotAfter
                    Thumbprint    = $_.Thumbprint
                    HasPrivateKey = $_.HasPrivateKey
                    Store         = $path
                }
            }
        }
    }
}

Export-ModuleMember -Function New-AioCsr, Complete-AioCsr, Install-AioPfx, Install-AioCertificate, Get-AioExpiringCertificate

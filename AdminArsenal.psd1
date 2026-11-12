@{
    RootModule           = ''
    ModuleVersion        = '1.0.0'
    GUID                 = 'e10f6b3d-5235-40a6-b5c3-b02f4a0477d3'
    Author               = 'Charl Britz'
    CompanyName          = 'Charl Britz'
    Copyright            = '(c) 2026 Charl Britz. MIT License.'
    Description          = 'An all-in-one PowerShell arsenal for system administrators: certificate lifecycle (AIO Certs), secure passwords and breach checks (PassForge), and Windows health reports with safe cleanup (PC Health).'
    PowerShellVersion    = '5.1'
    CompatiblePSEditions = @('Desktop', 'Core')

    NestedModules        = @(
        'tools/aio-certs/AioCerts.psm1',
        'tools/passforge/PassForge.psm1',
        'tools/pc-health/PcHealth.psm1'
    )

    FunctionsToExport    = @(
        # AIO Certs
        'New-AioCsr', 'Complete-AioCsr', 'Install-AioPfx', 'Install-AioCertificate', 'Get-AioExpiringCertificate',
        # PassForge
        'New-PassForgePassword', 'New-PassForgePassphrase', 'Measure-PassForgeStrength', 'Test-PassForgePwned',
        # PC Health
        'Get-PcHealthReport', 'Invoke-PcCleanup'
    )
    CmdletsToExport      = @()
    VariablesToExport    = @()
    AliasesToExport      = @()

    FileList             = @(
        'AdminArsenal.psd1', 'LICENSE', 'README.md',
        'tools/aio-certs/AioCerts.psm1', 'tools/aio-certs/README.md',
        'tools/passforge/PassForge.psm1', 'tools/passforge/README.md', 'tools/passforge/eff_large_wordlist.txt',
        'tools/pc-health/PcHealth.psm1', 'tools/pc-health/README.md'
    )

    PrivateData          = @{
        PSData = @{
            Tags         = @('sysadmin', 'certificates', 'pfx', 'csr', 'password', 'passphrase', 'security', 'health-check', 'cleanup', 'windows', 'automation', 'PSEdition_Desktop', 'PSEdition_Core', 'Windows')
            LicenseUri   = 'https://github.com/BullisticZA/AdminArsenal/blob/main/LICENSE'
            ProjectUri   = 'https://github.com/BullisticZA/AdminArsenal'
            IconUri      = 'https://raw.githubusercontent.com/BullisticZA/AdminArsenal/main/assets/logo.png'
            ReleaseNotes = 'https://github.com/BullisticZA/AdminArsenal/blob/main/CHANGELOG.md'
        }
    }
}

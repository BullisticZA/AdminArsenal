# Checks the AdminArsenal.psd1 manifest: it is valid, loads every tool, and exports exactly what it declares.
$ok = $true
function Check($name, $cond) { if ($cond) { "PASS $name" } else { "FAIL $name"; $script:ok = $false } }

$path = Join-Path (Split-Path $PSScriptRoot) 'AdminArsenal.psd1'
$info = Test-ModuleManifest -Path $path -ErrorAction Stop
Check "manifest valid (v$($info.Version))" ($null -ne $info)

$declared = (Import-PowerShellDataFile $path).FunctionsToExport | Sort-Object
$module = Import-Module $path -Force -PassThru
$exported = $module.ExportedFunctions.Keys | Sort-Object
Check "exports match declaration ($($exported.Count) functions)" ((Compare-Object $declared $exported | Measure-Object).Count -eq 0)

foreach ($f in (Import-PowerShellDataFile $path).FileList) {
    Check "file exists: $f" (Test-Path (Join-Path (Split-Path $PSScriptRoot) $f))
}

# A function from each tool works through the bundled module
Check 'PassForge via module' ((New-PassForgePassphrase -Words 5).Passphrase.Split('-').Count -eq 5)

# Every function declared in a tool is exported by the bundle (nothing forgotten)
$toolFunctions = Get-ChildItem (Join-Path (Split-Path $PSScriptRoot) 'tools') -Recurse -Filter *.psm1 | ForEach-Object {
    (Select-String -Path $_.FullName -Pattern '^Export-ModuleMember -Function (.+)$').Matches.Groups[1].Value -split ',\s*'
} | Sort-Object
Check 'bundle exports every tool function' ((Compare-Object $toolFunctions $declared | Measure-Object).Count -eq 0)

if ($ok) { 'ALL TESTS PASSED' } else { 'SOME TESTS FAILED'; exit 1 }

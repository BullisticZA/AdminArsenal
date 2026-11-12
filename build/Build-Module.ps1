<#
.SYNOPSIS
    Assembles a clean, publishable copy of the AdminArsenal module in ./out/AdminArsenal.
.EXAMPLE
    ./build/Build-Module.ps1
    Publish-Module -Path ./out/AdminArsenal -NuGetApiKey $key
#>
[CmdletBinding()]
param([string]$OutputRoot = (Join-Path (Split-Path $PSScriptRoot) 'out'))

$ErrorActionPreference = 'Stop'
$root     = Split-Path $PSScriptRoot
$manifest = Import-PowerShellDataFile (Join-Path $root 'AdminArsenal.psd1')
$target   = Join-Path $OutputRoot 'AdminArsenal'

if (Test-Path $target) { Remove-Item $target -Recurse -Force }
New-Item -ItemType Directory -Path $target -Force | Out-Null

# Copy exactly the files the manifest declares - nothing else ships.
foreach ($file in $manifest.FileList) {
    $source = Join-Path $root $file
    if (-not (Test-Path $source)) { throw "FileList entry missing: $file" }
    $dest = Join-Path $target $file
    New-Item -ItemType Directory -Path (Split-Path $dest) -Force | Out-Null
    Copy-Item $source $dest
}

$info = Test-ModuleManifest -Path (Join-Path $target 'AdminArsenal.psd1')
Write-Host "Built AdminArsenal $($info.Version) -> $target"
Write-Host "Exports: $(($info.ExportedFunctions.Keys | Sort-Object) -join ', ')"

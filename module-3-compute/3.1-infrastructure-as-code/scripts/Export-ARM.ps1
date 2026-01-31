<#
.SYNOPSIS
    Exports an Azure Resource Group to an ARM template.

.DESCRIPTION
    Used in Lab 3.1 to demonstrate exporting existing resources to ARM JSON.

.PARAMETER ResourceGroup
    The name of the resource group to export. Default: 'dev-skycraft-swc-rg'

.PARAMETER OutputFile
    Path to save the JSON file. Default: 'exported-template.json'
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$ResourceGroup = 'dev-skycraft-swc-rg',

    [Parameter(Mandatory = $false)]
    [string]$OutputFile = 'exported-template.json'
)

Write-Host "=== Lab 3.1 - Export ARM Template ===" -ForegroundColor Cyan

# 1. Verify Connection
$context = Get-AzContext
if (-not $context) { Write-Host "Not logged in." -ForegroundColor Red; exit 1 }

# 2. Check RG existence
$rg = Get-AzResourceGroup -Name $ResourceGroup -ErrorAction SilentlyContinue
if (-not $rg) {
    Write-Host "Resource Group '$ResourceGroup' not found." -ForegroundColor Yellow
    Write-Host "Have you deployed the prerequisites?" -ForegroundColor Gray
    exit 1
}

# 3. Export
Write-Host "Exporting '$ResourceGroup' to '$OutputFile'..." -ForegroundColor Yellow

try {
    Export-AzResourceGroup -ResourceGroupName $ResourceGroup -Path $OutputFile -Force -ErrorAction Stop
    Write-Host "[SUCCESS] Template saved to $OutputFile" -ForegroundColor Green
}
catch {
    Write-Host "[ERROR] Export failed." -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    exit 1
}

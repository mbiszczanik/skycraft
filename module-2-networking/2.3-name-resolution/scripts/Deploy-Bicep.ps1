[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$Location = 'swedencentral',

    [Parameter(Mandatory = $false)]
    [string]$TemplateFile = '..\bicep\main.bicep'
)

$deploymentName = "Lab-2.3-DNS-$(Get-Date -Format 'yyyyMMdd-HHmm')"

Write-Host "=== Lab 2.3 - Deploy Bicep (DNS) ===" -ForegroundColor Cyan -BackgroundColor Black

# Verify Bicep File
if (-not (Test-Path $TemplateFile)) {
    Write-Host "Error: Template file not found at $TemplateFile" -ForegroundColor Red
    exit 1
}

Write-Host "Starting deployment: $deploymentName..." -ForegroundColor Yellow

try {
    New-AzDeployment `
        -Name $deploymentName `
        -Location $Location `
        -TemplateFile $TemplateFile `
        -Verbose
    
    Write-Host "`n[OK] Deployment completed successfully!" -ForegroundColor Green
}
catch {
    Write-Host "`n[ERROR] Deployment failed: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

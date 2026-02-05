<#
.SYNOPSIS
    Validates Lab 4.1 - Storage Accounts deployment.

.DESCRIPTION
    Verifies storage accounts exist with correct configuration:
    - Naming conventions
    - Redundancy settings (LRS/GRS/GZRS)
    - Security settings (TLS 1.2, HTTPS only, no public access)
    - Required tags (Project, Environment, CostCenter)
    - Encryption settings

.PARAMETER Environment
    Validate specific environment only. If not specified, validates all.

.EXAMPLE
    .\Test-Lab.ps1
    Validates all SkyCraft storage accounts.

.EXAMPLE
    .\Test-Lab.ps1 -Environment prod
    Validates only production storage account.

.NOTES
    Project: SkyCraft
    Lab: 4.1 - Storage Accounts
    Version: 1.0.0
    Date: 2026-02-05
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [ValidateSet('dev', 'prod', 'platform', 'all')]
    [string]$Environment = 'all'
)

Write-Host "=== Lab 4.1: Validate Storage Accounts ===" -ForegroundColor Cyan
Write-Host ""

# Test counters
$script:testsPassed = 0
$script:testsFailed = 0
$script:testsWarning = 0

function Test-Condition {
    param(
        [string]$Description,
        [bool]$Condition,
        [string]$FailMessage = ""
    )
    
    if ($Condition) {
        Write-Host "  [PASS] $Description" -ForegroundColor Green
        $script:testsPassed++
        return $true
    }
    else {
        Write-Host "  [FAIL] $Description" -ForegroundColor Red
        if ($FailMessage) {
            Write-Host "         $FailMessage" -ForegroundColor Red
        }
        $script:testsFailed++
        return $false
    }
}

function Test-Warning {
    param(
        [string]$Description,
        [string]$Message
    )
    Write-Host "  [WARN] $Description" -ForegroundColor Yellow
    Write-Host "         $Message" -ForegroundColor Yellow
    $script:testsWarning++
}

# Storage account configurations to validate
$storageConfigs = @{
    platform = @{
        Name                   = 'platformskycraftswcsa'
        ResourceGroup          = 'platform-skycraft-swc-rg'
        ExpectedSku            = 'Standard_GRS'
        ExpectedEnvironmentTag = 'Platform'
    }
    dev      = @{
        Name                   = 'devskycraftswcsa'
        ResourceGroup          = 'dev-skycraft-swc-rg'
        ExpectedSku            = 'Standard_LRS'
        ExpectedEnvironmentTag = 'Development'
    }
    prod     = @{
        Name                   = 'prodskycraftswcsa'
        ResourceGroup          = 'prod-skycraft-swc-rg'
        ExpectedSku            = 'Standard_GZRS'
        ExpectedEnvironmentTag = 'Production'
    }
}

# Filter environments to test
$envsToTest = if ($Environment -eq 'all') {
    @('platform', 'dev', 'prod')
}
else {
    @($Environment)
}

foreach ($env in $envsToTest) {
    $config = $storageConfigs[$env]
    
    Write-Host ""
    Write-Host "--- Testing $($config.ExpectedEnvironmentTag) Storage Account ---" -ForegroundColor Yellow
    Write-Host "    Name: $($config.Name)"
    Write-Host "    Resource Group: $($config.ResourceGroup)"
    Write-Host ""
    
    # Check if storage account exists
    try {
        $sa = Get-AzStorageAccount -ResourceGroupName $config.ResourceGroup -Name $config.Name -ErrorAction Stop
        Test-Condition -Description "Storage account exists" -Condition $true | Out-Null
    }
    catch {
        Test-Condition -Description "Storage account exists" -Condition $false -FailMessage "Not found: $($config.Name)" | Out-Null
        continue
    }
    
    # Test redundancy/SKU
    Test-Condition `
        -Description "Redundancy is $($config.ExpectedSku)" `
        -Condition ($sa.Sku.Name -eq $config.ExpectedSku) `
        -FailMessage "Actual: $($sa.Sku.Name)" | Out-Null
    
    # Test location
    Test-Condition `
        -Description "Location is swedencentral" `
        -Condition ($sa.PrimaryLocation -eq 'swedencentral') `
        -FailMessage "Actual: $($sa.PrimaryLocation)" | Out-Null
    
    # Test security settings
    Test-Condition `
        -Description "TLS version is TLS1_2" `
        -Condition ($sa.MinimumTlsVersion -eq 'TLS1_2') `
        -FailMessage "Actual: $($sa.MinimumTlsVersion)" | Out-Null
    
    Test-Condition `
        -Description "HTTPS only enabled" `
        -Condition ($sa.EnableHttpsTrafficOnly -eq $true) `
        -FailMessage "HTTPS only is disabled" | Out-Null
    
    Test-Condition `
        -Description "Public blob access disabled" `
        -Condition ($sa.AllowBlobPublicAccess -eq $false) `
        -FailMessage "Public access is enabled" | Out-Null
    
    # Test encryption
    Test-Condition `
        -Description "Blob encryption enabled" `
        -Condition ($sa.Encryption.Services.Blob.Enabled -eq $true) | Out-Null
    
    Test-Condition `
        -Description "File encryption enabled" `
        -Condition ($sa.Encryption.Services.File.Enabled -eq $true) | Out-Null
    
    # Test tags
    $tags = $sa.Tags
    
    Test-Condition `
        -Description "Tag 'Project' = 'SkyCraft'" `
        -Condition ($tags['Project'] -eq 'SkyCraft') `
        -FailMessage "Actual: $($tags['Project'])" | Out-Null
    
    Test-Condition `
        -Description "Tag 'Environment' = '$($config.ExpectedEnvironmentTag)'" `
        -Condition ($tags['Environment'] -eq $config.ExpectedEnvironmentTag) `
        -FailMessage "Actual: $($tags['Environment'])" | Out-Null
    
    Test-Condition `
        -Description "Tag 'CostCenter' = 'MSDN'" `
        -Condition ($tags['CostCenter'] -eq 'MSDN') `
        -FailMessage "Actual: $($tags['CostCenter'])" | Out-Null
    
    # Test blob service properties (soft delete)
    try {
        $blobProps = Get-AzStorageBlobServiceProperty -StorageAccountName $config.Name -ResourceGroupName $config.ResourceGroup -ErrorAction Stop
        
        Test-Condition `
            -Description "Blob soft delete enabled" `
            -Condition ($blobProps.DeleteRetentionPolicy.Enabled -eq $true) | Out-Null
        
        if ($blobProps.ContainerDeleteRetentionPolicy) {
            Test-Condition `
                -Description "Container soft delete enabled" `
                -Condition ($blobProps.ContainerDeleteRetentionPolicy.Enabled -eq $true) | Out-Null
        }
    }
    catch {
        Test-Warning -Description "Could not check blob service properties" -Message $_.Exception.Message
    }
}

# Summary
Write-Host ""
Write-Host "=== Validation Summary ===" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Tests Passed:  $script:testsPassed" -ForegroundColor Green
Write-Host "  Tests Failed:  $script:testsFailed" -ForegroundColor $(if ($script:testsFailed -gt 0) { 'Red' } else { 'Green' })
Write-Host "  Warnings:      $script:testsWarning" -ForegroundColor $(if ($script:testsWarning -gt 0) { 'Yellow' } else { 'Green' })
Write-Host ""

if ($script:testsFailed -eq 0) {
    Write-Host "All tests passed! Lab 4.1 completed successfully." -ForegroundColor Green
    exit 0
}
else {
    Write-Host "Some tests failed. Review the errors above." -ForegroundColor Red
    exit 1
}

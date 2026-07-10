<#
.SYNOPSIS
    Creates the three SkyCraft resource groups (dev / prod / platform) in Sweden Central.

.DESCRIPTION
    Idempotently creates the resource groups required by Lab 1.2 and stamps each one
    with the mandatory governance tags (Project, Environment, CostCenter). Skips
    groups that already exist. Use -WhatIf to print planned actions without making changes.

.PARAMETER SubscriptionId
    The target Azure Subscription ID. Mandatory — the script switches context to it before
    creating any resource groups.

.PARAMETER Location
    Azure region for all three resource groups. Defaults to 'Sweden Central'.

.PARAMETER WhatIf
    If specified, prints the resource groups that would be created without actually creating them.

.EXAMPLE
    .\New-LabResourceGroup.ps1 -SubscriptionId '00000000-0000-0000-0000-000000000000'
    Creates dev/prod/platform resource groups in Sweden Central.

.EXAMPLE
    .\New-LabResourceGroup.ps1 -SubscriptionId $subId -WhatIf
    Prints the planned resource groups without creating anything.

.NOTES
    Project: SkyCraft
    Lab: 1.2 - RBAC
    Author: Marcin Biszczanik
    Date: 2026-01-11
#>

#Requires -Version 7.0
#Requires -Modules Az.Accounts, Az.Resources

[CmdletBinding(SupportsShouldProcess = $false)]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$SubscriptionId,

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$Location = "Sweden Central",

    [Parameter(Mandatory = $false)]
    [switch]$WhatIf
)

$ErrorActionPreference = "Stop"
$ProgressPreference = 'SilentlyContinue'

# Color functions
function Write-Success {
    param([string]$Message)
    Write-Host "$Message" -ForegroundColor Green
}

function Write-Info {
    param([string]$Message)
    Write-Host "$Message" -ForegroundColor Cyan
}

function Write-Error-Custom {
    param([string]$Message)
    Write-Host "$Message" -ForegroundColor Red
}

# Check if logged in to Azure
Write-Info "Checking Azure connection..."

try {
    $context = Get-AzContext
    if (-not $context) {
        Write-Info "Not logged in. Please log in to Azure."
        $context = Connect-AzAccount
    }

    Write-Success "Connected to Azure - Tenant: $($context.Tenant.Id)"
}
catch {
    Write-Error-Custom "Error: $($_.Exception.Message)"
    exit 1
}

Write-Info "Setting subscription context..."
Set-AzContext -SubscriptionId $SubscriptionId | Out-Null
Write-Success "Using subscription: $SubscriptionId"

# Define resource groups
$resourceGroups = @(
    @{
        Name     = "dev-skycraft-swc-rg"
        Location = $Location
        Tags     = @{
            Environment = "Development"
            Project     = "Skycraft"
            CostCenter  = "MSDN"
        }
    }
    @{
        Name     = "prod-skycraft-swc-rg"
        Location = $Location
        Tags     = @{
            Environment = "Production"
            Project     = "Skycraft"
            CostCenter  = "MSDN"
        }
    }
    @{
        Name     = "platform-skycraft-swc-rg"
        Location = $Location
        Tags     = @{
            Environment = "Platform"
            Project     = "Skycraft"
            CostCenter  = "MSDN"
        }
    }
)

# Create Resource Groups
Write-Info "Creating resource groups..."
foreach ($rg in $resourceGroups) {
    if ($WhatIf) {
        Write-Host "WhatIf: Would create resource group: $($rg.Name)" -ForegroundColor Yellow
    }
    else {
        $exisitingRg = Get-AzResourceGroup -Name $rg.Name -ErrorAction SilentlyContinue
        if (-not $exisitingRg) {
            New-AzResourceGroup -Name $rg.Name -Location $rg.Location -Tag $rg.Tags | Out-Null
            Write-Success "Created resource group: $($rg.Name)"
        }
        else {
            Write-Info "Resource group $($rg.Name) already exists. Skipping creation."
        }
    }
}

Write-Success "Resource Group creation script complete!"

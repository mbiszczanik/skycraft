# Lab 1.2 - Resource Groups Creation Script
# This script creates resource groups

param(
    [Parameter(Mandatory = $true)]
    [string]$SubscriptionId,

    [string]$Location = "Sweden Central",

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

# Lab 1.2 - RBAC Role Assignment Automation Script
# This script creates resource groups and assigns RBAC roles

param(
    [Parameter(Mandatory = $true)]
    [string]$SubscriptionId,

    [string]$Location = "Sweden Central",

    [switch]$WhatIf
)

$ErrorActionPreference = "Stop"

# Color functions
function Write-Success {
    param([string]$Message)
    Write-Host "✓ $Message" -ForegroundColor Green
}

function Write-Info {
    param([string]$Message)
    Write-Host "ℹ $Message" -ForegroundColor Cyan
}

function Write-Error-Custom {
    param([string]$Message)
    Write-Host "✗ $Message" -ForegroundColor Red
}

# Check if logged in to Azure
Write-Info "Checking Azure connection..."
try {
    $context = Get-AzContext
    if (-not $context) {
        throw "Not logged in"
    }
    Write-Success "Connected to Azure - Tenant: $($context.Tenant.Id)"
}
catch {
    Write-Error-Custom "Not logged in to Azure. Please run: Connect-AzAccount"
    exit 1
}

Write-Info "Setting subscription context..."
Set-AzContext -SubscriptionId $SubscriptionId | Out-Null
Write-Success "Using subscription: $SubscriptionId"

# Define resource groups
$resourceGroups = @(
    @{
        Name = "dev-skycraft-swc-rg"
        Location = $Location
        Tags = @{
            Environment = "Development"
            Project     = "Skycraft"
        }
    }
    @{
        Name = "prod-skycraft-swc-rg"
        Location = $Location
        Tags = @{
            Environment = "Production"
            Project     = "Skycraft"
        }
    }
    @{
        Name = "platform-skycraft-swc-rg"
        Location = $Location
        Tags = @{
            Environment = "Platform"
            Project     = "Skycraft"
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

# Define role assignments
$roleAssignments = @()
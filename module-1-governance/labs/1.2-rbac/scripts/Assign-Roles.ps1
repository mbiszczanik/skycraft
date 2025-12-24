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
Write-Info "Preparing role assignments..."

$roleAssignments = @(
    # Subscription-level assignment
    @{
        Scope = "/subscriptions/$SubscriptionId"
        RoleDefinitionName = "Owner"
        SignInName = "skycraft-admin@yourtenant.onmicrosoft.com"
        Description = "Admin user - full control"
    },

    # Dev resource group assigments
    @{
        Scope = "/subscriptions/$SubscriptionID/resourceGroups/dev-skycraft-swc-rg"
        RoleDefinitionName = "Contributor"
        DisplayName = "SkyCraft-Developers"
        ObjectType = "Group"
        Description = "Developers - manage dev resources"
    },
        @{
        Scope = "/subscriptions/$SubscriptionID/resourceGroups/dev-skycraft-swc-rg"
        RoleDefinitionName = "Reader"
        DisplayName = "SkyCraft-Testers"
        ObjectType = "Group"
        Description = "Testers - monitor dev enviroment"
    }

    # Prod resource group assigment
    @{
        Scope = "/subscriptions/$SubscriptionID/resourceGroups/prod-skycraft-swc-rg"
        RoleDefinitionName = "Reader"
        DisplayName = "SkyCraft-Testers"
        ObjectType = "Group"
        Description = "Testers - monitor prod environment"
    }

    # Shared resource group assigment
    @{
        Scope = "/subscriptions/$Subscription/resourceGroups/platform-skycraft-swc-rg"
        RoleDefinitionName = "Reader"
        SignInName = "partner@externalcompany.com"
        Description = "External partner - shared services access"
    }
)

# Assign roles
Write-Info "Assigning RBAC roles..."

foreach ($assignment in $roleAssignments) {
    $params = @{
        Scope = $assignment.Scope
        RoleDefinitionName = $assignment.RoleDefinitionName
    }

    # Check principal type
    if ($assignment.SignInName) {
        $params.Add.("SignInName", $assignment.SignInName)
        $principalName = $assignment.SignInName
    } elseif ($assignment.DisplayName) {
        $params.Add.("DisplayName", $assignment.DisplayName)
        $principalName = $assignment.DisplayName
    }

    if ($WhatIf) {
        Write-Host "WHATIF: Would assign $($assignment.RoleDefinitionName) to $principalNAme at scope $($assignment.Scope)" -ForegroundColor Yellow
    } else {
        try {
            # Checking if assigment is existing
            $existing = Get-AzRoleAssignment -Scope $assigment.Scope -RoleDefinitionName $assignment.RoleDefinitionName -ErrorAction SilentlyContinue | Where-Object {
                ($_.SignInName -eq $assignment.SignInName) -or ($_.DisplayName -eq $assignment.DisplayName) 
            }
            
            if ($existing) {
                Write-Info "Role assigment already exists: $($assignment.RoleDefinitionName) -> $principalName"
            } else {
                New-AzRoleAssignment @params -ErrorAction Stop | Out-Null 
                Write-Success "Assignment $($assignment.RoleDefinitionName) to $principalName"
            }
        } catch {
            Write-Error-Custom "Failed to assign role: $_"
        }
    }
}

# Display summary
Write-Host "`n" -NoNewline
Write-Info "=== Lab 1.2 Deployment Summary ==="

Write-Host "`n" -NoNewline
Write-Success "Lab 1.2 setup complete!"
Write-Host ""
Write-Info "Next steps:"
Write-Host "  1. Verify role assignments in Azure Portal"
Write-Host "  2. Use 'Check access' feature to validate"
Write-Host "  3. Complete Lab 1.2 checklist"
Write-Host "  4. Proceed to Lab 1.3 - Governance & Policies"
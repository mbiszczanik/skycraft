# Lab 1.3 - Governance and Policy Deployment Script
# This script applies tags, policies, locks, and budgets

param(
    [Parameter(Mandatory = $true)]
    [string]$SubscriptionId,
    
    [Parameter(Mandatory = $true)]
    [string]$AdminEmail,
    
    [int]$MonthlyBudget = 200,
    
    [switch]$WhatIf
)

# Color output functions
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

# Apply Tags
Write-Info "Applying tags to Resource Groups..."

$tagConfigurations = @(
    @{
        ResourceGroup = "dev-skycraft-swc-rg"
        Tags          = @{
            Environment = "Development"
            Project     = "SkyCraft"
            ConstCenter = "MSDN"
            Owner       = $AdminEmail

        }
    },
    @{
        ResourceGroup = "prod-skycraft-swc-rg"
        Tags          = @{
            Environment = "Production"
            Project     = "SkyCraft"
            ConstCenter = "MSDN"
            Owner       = $AdminEmail

        }
    },
    @{
        ResourceGroup = "platform-skycraft-swc-rg"
        Tags          = @{
            Environment = "Platform"
            Project     = "SkyCraft"
            ConstCenter = 'MSDN'
            Owner       = $AdminEmail
        }
    }
)

foreach ($config in $tagConfigurations) {
    if ($WhatIf) {
        Write-Host "WHATIF: Would apply tags to $(config.ResourceGroup)" -ForegroundColor -Yellow
    }
    else {
        try {
            $rg = Get-AzResourceGroup -Name $config.ResourceGroup -ErrorAction Stop
            Update-AzTag -ResourceId $rg.ResourceId -Tag $config.Tags -Operation Merge | Out-Null
            Write-Success "Applied tags to $($config.ResourceGroup)"
        }
        catch {
            Write-Error-Custom "Failed to tag $(config.ResourceGroup): $_"
        }
    }

}

# Assign Azure Policies
Write-Info "Assigning Azure Policies..."

# Policy 1: Require Environment tag on resource groups

$policy1 = @{
    Name                 = "Require-Environment-Tag-RG"
    DisplayName          = "Require Environment Tag on Resource Groups"
    PolicyDefiniton      = Get-AzPolicyDefinition | Where-Object { $_.Properties.DisplayName -eq "Require a tag on resource groups" }
    Scope                = "/subscriptions/$SubscriptionId"
    Parameters           = @{
        tagName = "Environment"
    }
    NonComplianceMessage = "Resource Group must have an Environment tag (Development, Production, Platform)"
}

if ($WhatIf) {
    Write-Host "WHATIF: Would assign policy : $($policy1.DisplayName)" -ForegroundColor Yellow
}
else {
    try {
        New-AzPolicyAssignment `
            -Name $policy1.Name `
            -DisplayName $policy1.DisplayName `
            -Scope $policy1.Scope `
            -PolicyDefinition $policy1.PolicyDefiniton `
            -PolicyParameterObject $policy1.Parameters `
            -NonComplianceMessage $policy1.NonComplianceMessage `
            -ErrorAction Stop | Out-Null 
        Write-Success "Assigned policy $($policy1.DisplayName)"
    }
    catch {
        if ($_.Exception.Message -like "*already exists*") {
            Write-Info "Policy already assigmend: $($policy1.DisplayName)"
        }
        else {
            Write-Error-Custom "Failed to assign policy: $_"
        }
    }
}

# Policy 2: Require Project tag with value
$policy2 = Get-AzPolicyDefinition | Where-Object { $_.Properties.DisplayName -eq "Require a tag and its value on resources" }

if ($WhatIf) {
    Write-Host "WHATIF: Would assign policy: Enforce Project Tag" -ForegroundColor Yellow
}
else {
    try {
        New-AzPolicyAssignment `
            -Name "Enforce-Project-Tag" `
            -DisplayName "Enforce Project Tag Value" `
            -Scope "/subscription/$SubscriptionId" `
            -PolicyDefinition $policy2 `
            -PolicyParameterObject @{
            tagName  = "Project"
            tagValue = "SkyCraft"
        } `
            -NonComplianceMessage "All resources must be tagged with Project=Skycraft" `
            -ErrorAction Stop | Out-Null 
        Write-Success "Assigned policy: Enforce Project Tag"
    }
    catch {
        Write-Error-Custom "Failed to assign policy: $_"
    }
}

# Policy 3: Allowed locations
$policy3 = Get-AzPolicyDefinition | Where-Object { $_.Properties.DisplayName -eq "Allowed locations" }

if ($WhatIf) {
    Write-Host "WHATIF: Would assign policy: Restrict Azure Regions" -ForegroundColor Yellow
}
else {
    try {
        New-AzPolicyAssignment `
            -Name "Restrict-Azure-Regions" `
            -DisplayName "Restrict to Allowed Regions" `
            -Scope "/subscription/$SubscriptionId" `
            -PolicyDefinition $policy3 `
            -PolicyParameterObject @{
            listOfAllowedLocations = @("swedencentral", "northeurope")
        } `
            -NonComplianceMessage "Resources must be deployed to Sweden Central or North Europe regions only" `
            -ErrorAction Stop | Out-Null 
        Write-Success "Assigned policy: Restrict Azure Regions"
    }
    catch {
        if ($_.Exception.Message -like "*already exists*") {
            Write-Info "Policy already assigned: Restrict Azure Regions"
        }
        else {
            Write-Error-Custom "Failed to assign policy: $_"
        }
    }
}

# Apply Resource Locks
Write-Info "Applying resource locks..."

$locks = @(
    @{
        ResourceGroup = "prod-skycraft-swc-rg"
        LockName      = "lock-no-delete-prod"
        LockLevel     = "CanNotDelete"
        LockNotes     = "Prevents accidental deletion of production resources"
    }
    @{
        ResourceGroup = "platform-skycraft-swc-rg"
        LockName      = "lock-no-delete-platform"
        LockLevel     = "CanNotDelete"
        LockNotes     = "Protects shared monitoring and logging infrastructure"
    }
)

foreach ($lock in $locks) {
    if ($WhatIf) {
        Write-Host "WHATIF: Would create lock $($lock.LockName) on $($lock.ResourceGroup)" -ForegroundColor Yellow
    }
    else {
        try {
            $existingLock = Get-AzResourceLock -ResourceGroupName $lock.ResourceGroup -LockName $lock.LockName -ErrorAction SilentlyContinue

            if ($existingLock) {
                Write-Info "Lock already exists: $($lock.LockName)"
            }
            else {
                New-AzResourceLock `
                    -ResourceGroupName $lock.ResourceGroup `
                    -LockName $lock.LockName `
                    -LockLevel $lock.LockLevel `
                    -LockNotes $lock.LockNotes `
                    -Force | Out-Null
                Write-Success "Created lock: $($lock.LockName) on $($lock.ResourceGroup)"
            }
        }
        catch {
            Write-Error-Custom "Failed to create lock: $_"
        }
    }
}

# Summary
Write-Host "`n" -NoNewline
Write-Info "=== Lab 1.3 Governance Deployment Summary ==="

Write-Host "`n" -NoNewline
Write-Success "Lab 1.3 governance deployment complete!"
Write-Host ""
Write-Info "Next steps:"
Write-Host "  1. Create budgets in Azure Portal (Cost Management)"
Write-Host "  2. Configure Azure Advisor alerts"
Write-Host "  3. Review Policy Compliance dashboard"
Write-Host "  4. Complete Lab 1.3 checklist"
Write-Host "  5. Proceed to Module 2 - Virtual Networking"

<#
.SYNOPSIS
    Deploys Lab 1.3 Governance artifacts (Tags, Policies, Locks) using imperative PowerShell.

.DESCRIPTION
    This script demonstrates how to apply governance controls using Azure PowerShell cmdlets directly.
    It serves as a "PowerShell Showcase" alternative to the Bicep deployment.
    
    Actions performed:
    1. Applies Tags to Resource Groups (Update-AzTag)
    2. Assigns Azure Policies at Subscription Scope (New-AzPolicyAssignment)
    3. Creating Resource Locks (New-AzResourceLock)

.PARAMETER SubscriptionId
    Target Subscription ID. Defaults to current context.

.PARAMETER AdminEmail
    Email address for the Owner tag. Default: admin@skycraft.com.

.EXAMPLE
    .\Deploy-Governance.ps1

.NOTES
    Project: SkyCraft
    Lab: 1.3 - Governance
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$SubscriptionId,
    
    [Parameter(Mandatory = $false)]
    [string]$AdminEmail = "admin@skycraft.com",
    
    [switch]$WhatIf
)

$ErrorActionPreference = "Stop"

# Color output functions
function Write-Success { param([string]$Message) Write-Host "  -> [SUCCESS] $Message" -ForegroundColor Green }
function Write-Info { param([string]$Message) Write-Host "$Message" -ForegroundColor Yellow }
function Write-Header { param([string]$Message) Write-Host "$Message" -ForegroundColor Cyan }
function Write-Error-Custom { param([string]$Message) Write-Host "  -> [ERROR] $Message" -ForegroundColor Red }

Write-Host "=== Lab 1.3: Governance Deployment (Imperative) ===" -ForegroundColor Cyan -BackgroundColor Black

# 1. Connection & Context
try {
    Write-Info "Checking Azure connection..."
    $context = Get-AzContext
    if (-not $context) {
        Write-Host "Logging in..." -ForegroundColor Yellow
        $context = Connect-AzAccount -ErrorAction Stop
    }
    
    if ([string]::IsNullOrWhiteSpace($SubscriptionId)) {
        $SubscriptionId = $context.Subscription.Id
    }
    
    Set-AzContext -SubscriptionId $SubscriptionId -ErrorAction Stop | Out-Null
    Write-Host "Using Subscription: $($context.Subscription.Name) ($SubscriptionId)" -ForegroundColor Green
}
catch {
    Write-Error-Custom "Failed to connect: $_"
    exit 1
}

# 2. Apply Tags
Write-Header "`n=== 1. Applying Tags (Update-AzTag) ==="

$tagConfigurations = @(
    @{ Name = "dev-skycraft-swc-rg"; Tags = @{ Environment="Development"; Project="SkyCraft"; CostCenter="MSDN"; Owner=$AdminEmail } },
    @{ Name = "prod-skycraft-swc-rg"; Tags = @{ Environment="Production"; Project="SkyCraft"; CostCenter="MSDN"; Owner=$AdminEmail } },
    @{ Name = "platform-skycraft-swc-rg"; Tags = @{ Environment="Platform"; Project="SkyCraft"; CostCenter="MSDN"; Owner=$AdminEmail } }
)

foreach ($config in $tagConfigurations) {
    if ($WhatIf) {
        Write-Host "WHATIF: Would tag $($config.Name)" -ForegroundColor Yellow
    }
    else {
        try {
            $rg = Get-AzResourceGroup -Name $config.Name -ErrorAction Stop
            # Merge tags
            Update-AzTag -ResourceId $rg.ResourceId -Tag $config.Tags -Operation Merge -ErrorAction Stop | Out-Null
            Write-Success "Tagged $($config.Name)"
        }
        catch {
            Write-Host "  -> [WARN] Failed to tag $($config.Name) (RG might not exist?)" -ForegroundColor Yellow
        }
    }
}

# 3. Assign Policies
Write-Header "`n=== 2. Assigning Policies (New-AzPolicyAssignment) ==="

$policies = @(
    @{
        Name = "Require-Environment-Tag-RG"
        DisplayName = "Require Environment Tag on Resource Groups"
        Definition = "Require a tag on resource groups"
        Params = @{ tagName = "Environment" }
    },
    @{
        Name = "Enforce-Project-Tag"
        DisplayName = "Enforce Project Tag Value"
        Definition = "Require a tag and its value on resources"
        Params = @{ tagName = "Project"; tagValue = "SkyCraft" }
    },
    @{
        Name = "Restrict-Azure-Regions"
        DisplayName = "Restrict to Allowed Regions"
        Definition = "Allowed locations"
        Params = @{ listOfAllowedLocations = @("swedencentral", "northeurope") }
    }
)

foreach ($policy in $policies) {
    if ($WhatIf) {
         Write-Host "WHATIF: Would assign policy $($policy.Name)" -ForegroundColor Yellow
    }
    else {
        try {
            $def = Get-AzPolicyDefinition | Where-Object { $_.Properties.DisplayName -eq $policy.Definition } | Select-Object -First 1
            if ($def) {
                # Check existance first to avoid error spam
                if (Get-AzPolicyAssignment -Name $policy.Name -Scope "/subscriptions/$SubscriptionId" -ErrorAction SilentlyContinue) {
                     Write-Success "Policy $($policy.Name) already assigned."
                }
                else {
                    New-AzPolicyAssignment `
                        -Name $policy.Name `
                        -DisplayName $policy.DisplayName `
                        -Scope "/subscriptions/$SubscriptionId" `
                        -PolicyDefinition $def `
                        -PolicyParameterObject $policy.Params `
                        -ErrorAction Stop | Out-Null
                    Write-Success "Assigned policy $($policy.Name)"
                }
            } else {
                Write-Error-Custom "Definition '$($policy.Definition)' not found."
            }
        }
        catch {
            Write-Error-Custom "Failed to assign $($policy.Name): $_"
        }
    }
}

# 4. Apply Locks
Write-Header "`n=== 3. Applying Locks (New-AzResourceLock) ==="

$locks = @(
    @{ RG = "prod-skycraft-swc-rg"; Name = "lock-no-delete-prod"; Notes = "Production protection" },
    @{ RG = "platform-skycraft-swc-rg"; Name = "lock-no-delete-platform"; Notes = "Platform protection" }
)

foreach ($lock in $locks) {
    if ($WhatIf) {
        Write-Host "WHATIF: Would lock $($lock.RG)" -ForegroundColor Yellow
    }
    else {
        try {
            if (Get-AzResourceGroup -Name $lock.RG -ErrorAction SilentlyContinue) {
                if (Get-AzResourceLock -ResourceGroupName $lock.RG -LockName $lock.Name -ErrorAction SilentlyContinue) {
                    Write-Success "Lock $($lock.Name) already exists."
                }
                else {
                    New-AzResourceLock `
                        -ResourceGroupName $lock.RG `
                        -LockName $lock.Name `
                        -LockLevel CanNotDelete `
                        -LockNotes $lock.Notes `
                        -Force `
                        -ErrorAction Stop | Out-Null
                    Write-Success "Locked $($lock.RG)"
                }
            }
            else {
                Write-Host "  -> [WARN] RG $($lock.RG) not found, skipping lock." -ForegroundColor Yellow
            }
        }
        catch {
            Write-Error-Custom "Failed to lock $($lock.RG): $_"
        }
    }
}

Write-Host "`nImperative Deployment Complete." -ForegroundColor Green

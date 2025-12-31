# Lab 1.2 - RBAC Role Assignment Automation Script
# This script creates resource groups and assigns RBAC roles

param(
    [Parameter(Mandatory = $true)]
    [string]$SubscriptionId,

    [string]$Location = "Sweden Central",

    [switch]$WhatIf
)

$ErrorActionPreference = "Stop"
$ProgressPreference = 'SilentlyContinue'

if (-not (Get-Module -ListAvailable -Name Microsoft.Graph)) {
    Write-Host "Installing Microsoft.Graph module..."
    Install-Module -Name Microsoft.Graph -Scope CurrentUser -Force -AllowClobber
}

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

# Check if logged in to Microsoft Graph
Write-Info "Checking Microsoft Graph connection..."
$mgContext = Get-MgContext
if (-not $mgContext) {
    Write-Info "Not connected to Microsoft Graph. Attempting to connect..."
    Connect-MgGraph -Scopes "User.ReadWrite.All", "Group.ReadWrite.All", "Directory.ReadWrite.All", "Domain.Read.All", "User.Invite.All" -ErrorAction Stop
    $mgContext = Get-MgContext
}

if (-not $mgContext) {
    Write-Error-Custom "Failed to connect to Microsoft Graph. This script requires Graph permissions to verify users/groups."
    exit 1
}

Write-Success "Connected to Microsoft Entra ID - Tenant: $($mgContext.TenantId)"

# Get Primary Domain for UPN construction
try {
    Write-Info "Fetching default domain..."
    $mgDomain = Get-MgDomain | Where-Object { $_.IsDefault }
    if ($mgDomain) {
        $domain = $mgDomain.Id
        Write-Success "Detected default domain: $domain"
    }
    else {
        $domain = "onmicrosoft.com"
        Write-Warning "Could not detect default domain. Falling back to '$domain'."
    }
}
catch {
    $domain = "onmicrosoft.com"
    Write-Warning "Error detecting domain: $($_.Exception.Message). Falling back to '$domain'."
}


# Define role assignments
Write-Info "Preparing role assignments..."

$roleAssignments = @(
    # Subscription-level assignment
    @{
        Scope              = "/subscriptions/$SubscriptionId"
        RoleDefinitionName = "Owner"
        SignInName         = "skycraft-admin@$domain"
        Description        = "Admin user - full control"
    },

    # Dev resource group assigments
    @{
        Scope              = "/subscriptions/$SubscriptionId/resourceGroups/dev-skycraft-swc-rg"
        RoleDefinitionName = "Contributor"
        DisplayName        = "SkyCraft-Developers"
        ObjectType         = "Group"
        Description        = "Developers - manage dev resources"
    },
    @{
        Scope              = "/subscriptions/$SubscriptionId/resourceGroups/dev-skycraft-swc-rg"
        RoleDefinitionName = "Reader"
        DisplayName        = "SkyCraft-Testers"
        ObjectType         = "Group"
        Description        = "Testers - monitor dev enviroment"
    }

    # Prod resource group assigment
    @{
        Scope              = "/subscriptions/$SubscriptionId/resourceGroups/prod-skycraft-swc-rg"
        RoleDefinitionName = "Reader"
        DisplayName        = "SkyCraft-Testers"
        ObjectType         = "Group"
        Description        = "Testers - monitor prod environment"
    }

    # Shared resource group assigment
    @{
        Scope              = "/subscriptions/$SubscriptionId/resourceGroups/platform-skycraft-swc-rg"
        RoleDefinitionName = "Reader"
        SignInName         = "partner@externalcompany.com"
        Description        = "External partner - shared services access"
    }
)

# Assign roles
Write-Info "Assigning RBAC roles..."

foreach ($assignment in $roleAssignments) {
    $params = @{
        Scope              = $assignment.Scope
        RoleDefinitionName = $assignment.RoleDefinitionName
    }

    # Check principal type
    if ($assignment.SignInName) {
        $params.Add("SignInName", $assignment.SignInName)
        $principalName = $assignment.SignInName
    }
    elseif ($assignment.DisplayName) {
        $params.Add("DisplayName", $assignment.DisplayName)
        $principalName = $assignment.DisplayName
    }

    if ($WhatIf) {
        Write-Host "WHATIF: Would assign $($assignment.RoleDefinitionName) to $principalName at scope $($assignment.Scope)" -ForegroundColor Yellow
    }
    else {
        try {
            # Checking if assignment is existing
            $existing = Get-AzRoleAssignment -Scope $assignment.Scope -RoleDefinitionName $assignment.RoleDefinitionName -ErrorAction SilentlyContinue | Where-Object {
                ($_.SignInName -eq $assignment.SignInName) -or ($_.DisplayName -eq $assignment.DisplayName) 
            }
            
            if ($existing) {
                Write-Info "Role assignment already exists: $($assignment.RoleDefinitionName) -> $principalName"
            }
            else {
                New-AzRoleAssignment @params -ErrorAction Stop | Out-Null 
                Write-Success "Assignment $($assignment.RoleDefinitionName) to $principalName"
            }
        }
        catch {
            Write-Error-Custom "Failed to assign role: $_"
        }
    }
}

Write-Success "Role assignments completed"
# Lab 1.1 - Create Users and Groups - Automation Script
# This script automates user and group creation for Lab 1.1

param (
    [string]$TenantId = "<Your-Tenant-ID>",
    [string]$DemoMode = $false
)

$ErrorActionPreference = "Stop"
$ProgressPreference = 'SilentlyContinue'

function Write-Sucess {
    param ([string]$Message)
    Write-Host  "✓ $Message" -ForegroundColor Green
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

$tenantName = ($context | ConvertFrom-Json).tenantId
Write-Sucess "Connected to tenant: $tenantName"

Write-Info "Creating users..."

$users = @(
    @{
        UserPrincipalName = "skycraft-admin"
        DisplayName       = "Skycraft Admin"
        Password          = "TempPassword!2025"
        Departamen        = "IT Operations"
        JobTitle          = "Cloud Infrastructure Manager"
    },
    @{
        UserPrincipalName = "skycraft-dev"
        DisplayName       = "SkyCraft Developer"
        Password          = "TempPassword!2025"
        Department        = "Development"
        JobTitle          = "Cloud Developer"
    },
    @{
        UserPrincipalName = "skycraft-tester"
        DisplayName       = "SkyCraft Tester"
        Password          = "TempPassword!2025"
        Department        = "QA"
        JobTitle          = "Quality Assurance Lead"
    }
)

foreach ($user in $users) {
    Write-Info "Creating user: $($user.DisplayName)..."

    $upn = "$($user.UserPrincipalName)@yourtenant.onmicrosoft.com"

    # To be done: Add user creation logic here
}


Write-Info "Creating security groups..."

$groups = @(
    @{
        DisplayName = "SkyCraft-Admins"
        Description = "Administrative team for SkyCraft infrastructure"
    },
    @{
        DisplayName = "SkyCraft-Developers"
        Description = "Development team for SkyCraft deployment"
    },
    @{
        DisplayName = "SkyCraft-Testers"
        Description = "Testing and monitoring team"
    }
)

foreach ($group in $groups) {
    Write-Info "Creating group: $($group.DisplayName)"
    
    # To be done: Add group creation logic here
}

Write-Success "Script template complete. Follow manual steps in portal as prompted."

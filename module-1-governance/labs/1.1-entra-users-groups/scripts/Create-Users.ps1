<#
.SYNOPSIS
    Automates the creation of users and security groups for the SkyCraft lab.

.DESCRIPTION
    This script creates three internal users (Admin, Developer, Tester), invites one guest user, 
    and sets up security groups with the corresponding memberships. It automatically detects 
    the Tenant ID and default domain from the current Azure context.

.PARAMETER TenantId
    The Microsoft Entra Tenant ID to use. If omitted, it will be detected from the current Az context.

.PARAMETER DemoMode
    If specified, the script will simulate the creation process and output what would happen 
    without making any actual changes to the tenant.

.EXAMPLE
    .\Create-Users.ps1 -DemoMode
    Simulates the creation of all users and groups.

.EXAMPLE
    .\Create-Users.ps1
    Executes the creation process using the current Azure context.
#>

if (-not (Get-Module -ListAvailable -Name Microsoft.Graph)) {
    Write-Host "Installing Microsoft.Graph module..."
    Install-Module -Name Microsoft.Graph -Scope CurrentUser -Force -AllowClobber
}

param (
    [Parameter(HelpMessage = "The Tenant ID to use for creation. If not provided, it will be detected from the current context.")]
    [string]$TenantId,
    
    [Parameter(HelpMessage = "Enable demo mode (skips actual creation).")]
    [bool]$DemoMode = $false
)

$ErrorActionPreference = "Stop"
$ProgressPreference = 'SilentlyContinue'

function Write-Success {
    param ([string]$Message)
    Write-Host  "$Message" -ForegroundColor Green
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
        throw "Not logged in to Azure. Please run: Connect-AzAccount"
    }

    if ([string]::IsNullOrWhiteSpace($TenantId)) {
        $TenantId = $context.Tenant.Id
        Write-Success "Detected Tenant ID from context: $TenantId"
    }
    else {
        Write-Info "Using provided Tenant ID: $TenantId"
    }
    
    # Get Primary Domain for UPN construction
    $domain = (Get-MgDomain | Where-Object { $_.IsDefault }).Id
    if (-not $domain) {
        $domain = "onmicrosoft.com" # Fallback if domain detection fails
        Write-Warning "Could not detect default domain. Falling back to '$domain'."
    }
    Write-Success "Using domain: $domain"
}
catch {
    Write-Error-Custom "Error: $($_.Exception.Message)"
    exit 1
}

Write-Info "Creating users..."

$users = @(
    @{
        UserPrincipalName = "skycraft-admin"
        DisplayName       = "Skycraft Admin"
        Password          = "TempPassword!2025"
        Department        = "IT Operations"
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

    $upn = "$($user.UserPrincipalName)@$domain"

    try {
        if ($DemoMode) {
            Write-Info "[DEMO] Would create user: $upn"
        }
        else {
            $newUser = New-MgUser -UserPrincipalName $upn -DisplayName $user.DisplayName -PasswordProfile @{ Password = $user.Password } -AccountEnabled $true -MailNickname $user.UserPrincipalName -UsageLocation "US" -Department $user.Department -JobTitle $user.JobTitle
            Write-Success "User created: $($user.DisplayName) (ID: $($newUser.Id))"
        }
    }
    catch {
        Write-Error-Custom "Failed to create user: $($user.DisplayName). Error: $($_.Exception.Message)"
    }
}

Write-Info "Inviting guest users..."

$guestUsers = @(
    @{
        DisplayName = "External Partner Consultant"
        Email       = "partner@externalcompany.com"
        Message     = "Welcome to the SkyCraft deployment project. Please accept this invitation to collaborate on our infrastructure deployment."
    }
)

foreach ($guest in $guestUsers) {
    Write-Info "Inviting guest: $($guest.DisplayName)..."
    try {
        if ($DemoMode) {
            Write-Info "[DEMO] Would invite guest: $($guest.Email)"
        }
        else {
            New-MgInvitation -InvitedUserEmailAddress $guest.Email -InvitedUserDisplayName $guest.DisplayName -InviteRedirectUrl "https://myapplications.microsoft.com" -SendInvitationMessage -InvitedUserMessageInfo @{ CustomizedMessageBody = $guest.Message }
            Write-Success "Invitation sent to: $($guest.Email)"
        }
    }
    catch {
        Write-Error-Custom "Failed to invite guest: $($guest.DisplayName). Error: $($_.Exception.Message)"
    }
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
    
    try {
        if ($DemoMode) {
            Write-Info "[DEMO] Would create group: $($group.DisplayName)"
        }
        else {
            $newGroup = New-MgGroup -DisplayName $group.DisplayName -Description $group.Description -MailEnabled $false -SecurityEnabled $true -MailNickname ($group.DisplayName -replace " ", "")
            Write-Success "Group created: $($group.DisplayName) (ID: $($newGroup.Id))"
        }
    }
    catch {
        Write-Error-Custom "Failed to create group: $($group.DisplayName). Error: $($_.Exception.Message)"
    }
}

Write-Info "Assigning users to groups..."

$assignments = @(
    @{ GroupName = "SkyCraft-Admins"; UserUPN = "skycraft-admin@$domain" },
    @{ GroupName = "SkyCraft-Developers"; UserUPN = "skycraft-dev@$domain" },
    @{ GroupName = "SkyCraft-Testers"; UserUPN = "skycraft-tester@$domain" }
)

foreach ($assign in $assignments) {
    Write-Info "Adding $($assign.UserUPN) to $($assign.GroupName)..."
    try {
        if ($DemoMode) {
            Write-Info "[DEMO] Would add $($assign.UserUPN) to $($assign.GroupName)"
        }
        else {
            $targetGroup = Get-MgGroup -Filter "DisplayName eq '$($assign.GroupName)'"
            $targetUser = Get-MgUser -UserId $assign.UserUPN
            
            if ($targetGroup -and $targetUser) {
                New-MgGroupMember -GroupId $targetGroup.Id -DirectoryObjectId $targetUser.Id
                Write-Success "Successfully added $($assign.UserUPN) to $($assign.GroupName)"
            }
            else {
                throw "Could not find group or user"
            }
        }
    }
    catch {
        Write-Error-Custom "Failed to assign membership: $($assign.UserUPN) -> $($assign.GroupName). Error: $($_.Exception.Message)"
    }
}


Write-Success "Script template complete. Follow manual steps in portal as prompted."
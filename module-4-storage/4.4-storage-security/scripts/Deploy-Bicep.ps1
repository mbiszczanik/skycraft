<#
.SYNOPSIS
    Deploys Lab 4.4 Storage Security
.DESCRIPTION
    Deploys storage firewall rules, VNet integration, the dev-assets container and the
    Storage Blob Data Contributor assignment of guide Step 4.4.7.
    Requires existing storage account (Lab 4.1) and VNet (Lab 2.1) with the Microsoft.Storage
    service endpoint on WorldSubnet (Lab 2.2).

    The role goes to whoever runs the script - a user or a service principal - unless
    -DataPrincipalId names someone else. The object id is read from the oid claim of the
    Azure Resource Manager access token the session already holds, so no Microsoft Graph call is
    made. If that principal holds the role on the account already (from the Portal path, or from
    the optional Azure CLI commands of Lab 4.2), the template is given no assignment: ARM refuses
    a second assignment of the same role to the same principal at the same scope.

    Creating the assignment needs Owner or User Access Administrator. An identity with only
    Contributor, which is enough for the rest of the template, fails the whole deployment on
    Microsoft.Authorization/roleAssignments/write: run it with -SkipDataRoleAssignment, and have
    the role assigned as in guide Step 4.4.7.

    The script prints your public IP address when it detects it: do not paste its output into a
    public issue.
.PARAMETER Location
    Azure region for deployment. Default: swedencentral.
.PARAMETER Environment
    Target environment (prod or dev). Default: prod.
    platform is not supported: the hub VNet has no workload subnet to allow through
    the storage firewall.
.PARAMETER ClientIp
    Your client IP to allow through the firewall. Auto-detected if omitted.
.PARAMETER DataPrincipalId
    Object id of the user or service principal that gets Storage Blob Data Contributor on the
    account. Defaults to the signed-in identity.
.PARAMETER SkipDataRoleAssignment
    Sends no role assignment, for an identity that may not create one (Contributor only).
    Test-Lab.ps1 then fails its role check until the role is assigned as in guide Step 4.4.7.
.PARAMETER WhatIf
    Previews the deployment with the ARM what-if API and exits. Nothing is created or changed.
.EXAMPLE
    .\Deploy-Bicep.ps1 -Environment prod
.EXAMPLE
    .\Deploy-Bicep.ps1 -Environment prod -WhatIf
    Previews the storage firewall deployment without changing anything.
.EXAMPLE
    .\Deploy-Bicep.ps1 -Environment prod -SkipDataRoleAssignment
    Deploys with an identity that holds Contributor only; the role is assigned separately.
.NOTES
    Project: SkyCraft
    Author: SkyCraft
    Date: 2026-10-18
#>

#Requires -Version 7.0
#Requires -Modules Az.Accounts, Az.Resources

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [ValidateSet('swedencentral', 'northeurope')]
    [string]$Location = 'swedencentral',

    [Parameter(Mandatory = $false)]
    [ValidateSet('prod', 'dev')]
    [string]$Environment = 'prod',

    [Parameter(Mandatory = $false)]
    [string]$ClientIp = '',

    [Parameter(Mandatory = $false)]
    [string]$DataPrincipalId = '',

    [Parameter(Mandatory = $false)]
    [switch]$SkipDataRoleAssignment,

    [Parameter(Mandatory = $false)]
    [switch]$WhatIf
)

$ErrorActionPreference = 'Stop'
# Exit-Lab ends the script with exit code 0 or 1 and leaves an interactive session open (#257).
Import-Module (Join-Path $PSScriptRoot '../../../tools/LabCommon.psm1') -Force -Verbose:$false

$dataRoleName = 'Storage Blob Data Contributor'

# The object id (oid claim) of the identity the Az session is signed in as, read from an Azure
# Resource Manager access token: no Microsoft Graph call, so it works for a user, a service
# principal and a session started with Connect-AzAccount -AccessToken. Empty when it cannot be read.
function Get-LabSignedInObjectId {
    [CmdletBinding()]
    [OutputType([string])]
    param()

    try {
        $accessToken = Get-AzAccessToken -ResourceUrl 'https://management.azure.com/' -ErrorAction Stop -WarningAction SilentlyContinue
        $token = $accessToken.Token
        if ($token -is [securestring]) { $token = ConvertFrom-SecureString -SecureString $token -AsPlainText }
        $parts = "$token".Split('.')
        if ($parts.Count -lt 2) { return '' }
        # The payload is base64url: '-' and '_' instead of '+' and '/', and no padding.
        $payload = $parts[1].Replace('-', '+').Replace('_', '/')
        $payload = $payload.PadRight($payload.Length + ((4 - $payload.Length % 4) % 4), '=')
        $claims = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($payload)) | ConvertFrom-Json
        return [string]$claims.oid
    }
    catch {
        return ''
    }
}

# Whether the principal holds the data role on the account itself already. A lookup that fails
# answers $false with a warning, and the deployment then tries to create the assignment.
function Test-LabDataRoleAssigned {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Scope,

        [Parameter(Mandatory = $true)]
        [string]$PrincipalId
    )

    # The ARM API, not Get-AzRoleAssignment, which needs a Microsoft Graph token (#397).
    try {
        $existing = @(Get-LabArmRoleAssignment -Scope $Scope -PrincipalId $PrincipalId | Where-Object {
                $_.ObjectId -eq $PrincipalId -and $_.RoleDefinitionName -eq $dataRoleName -and $_.Scope -eq $Scope
            })
        return $existing.Count -gt 0
    }
    catch {
        Write-Host "  -> [WARNING] Could not read the role assignments on the account: $($_.Exception.Message)" -ForegroundColor Yellow
        Write-Host "     The deployment will try to create the assignment; it fails with RoleAssignmentExists if the role is there already." -ForegroundColor Yellow
        return $false
    }
}

# The object id the template assigns Storage Blob Data Contributor to (guide Step 4.4.7), or ''
# for no assignment: when -SkipDataRoleAssignment is set, when no identity can be read, or when
# that identity holds the role on the account already.
function Resolve-LabDataPrincipalId {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Scope,

        [Parameter(Mandatory = $false)]
        [string]$PrincipalId = '',

        [Parameter(Mandatory = $false)]
        [switch]$Skip
    )

    if ($Skip) {
        Write-Host "  -> -SkipDataRoleAssignment: the template assigns no role. Assign '$dataRoleName' as in guide Step 4.4.7; Test-Lab.ps1 fails its role check until then." -ForegroundColor Yellow
        return ''
    }
    if ([string]::IsNullOrWhiteSpace($PrincipalId)) {
        Write-Host "Reading the signed-in identity for the '$dataRoleName' assignment..." -ForegroundColor Yellow
        $PrincipalId = Get-LabSignedInObjectId
        if (-not $PrincipalId) {
            Write-Host "  -> [WARNING] Could not read the signed-in identity. No role assignment will be made; pass -DataPrincipalId, or assign the role as in Step 4.4.7." -ForegroundColor Yellow
            return ''
        }
    }
    if (Test-LabDataRoleAssigned -Scope $Scope -PrincipalId $PrincipalId) {
        Write-Host "  -> The identity holds '$dataRoleName' on the account already; the template leaves that assignment as it is." -ForegroundColor Green
        return ''
    }
    Write-Host "  -> The template assigns '$dataRoleName' on the account to the identity. That needs Owner or User Access Administrator; with Contributor only, run the script with -SkipDataRoleAssignment." -ForegroundColor Green
    return $PrincipalId
}

Write-Host "=== Lab 4.4: Deploying Storage Security ===" -ForegroundColor Cyan

# 1. Verify Connection
$context = Get-AzContext
if (-not $context) {
    Write-Host " [ERROR] Not logged in. Please run Connect-AzAccount." -ForegroundColor Red; Exit-Lab -FailureCount 1
}

# 2. Auto-detect client IP if not provided
if ([string]::IsNullOrWhiteSpace($ClientIp)) {
    try {
        Write-Host "Auto-detecting client IP..." -ForegroundColor Yellow
        $ClientIp = (Invoke-RestMethod -Uri 'https://api.ipify.org' -TimeoutSec 5).Trim()
        Write-Host "  -> Detected: $ClientIp" -ForegroundColor Green
    }
    catch {
        Write-Host "  -> [WARNING] Could not auto-detect IP. Firewall will not include client IP rule." -ForegroundColor Yellow
        $ClientIp = ''
    }
}

# 3. Who gets Storage Blob Data Contributor on the account (guide Step 4.4.7)
$accountScope = "/subscriptions/$($context.Subscription.Id)/resourceGroups/$Environment-skycraft-swc-rg/providers/Microsoft.Storage/storageAccounts/${Environment}skycraftswcsa"
$assignPrincipalId = Resolve-LabDataPrincipalId -Scope $accountScope -PrincipalId $DataPrincipalId -Skip:$SkipDataRoleAssignment

# 4. Deploy Bicep
try {
    Write-Host "Deploying main.bicep to subscription level..." -ForegroundColor Yellow

    $deployParams = @{
        Name                          = "lab-4.4-deploy-$(Get-Date -Format 'yyyyMMdd-HHmm')"
        Location                      = $Location
        TemplateFile                  = (Join-Path $PSScriptRoot "..\bicep\main.bicep")
        parLocation                   = $Location
        parEnvironment                = $Environment
        parClientIp                   = $ClientIp
        parDataContributorPrincipalId = $assignPrincipalId
        ErrorAction                   = 'Stop'
    }

    if ($WhatIf) {
        Write-Host "  Running in what-if mode (dry run)..." -ForegroundColor Cyan
        Get-AzSubscriptionDeploymentWhatIfResult @deployParams
        Write-Host "`n  What-if completed. Review the changes above - nothing was deployed." -ForegroundColor Cyan
        exit 0
    }

    $deployment = New-AzSubscriptionDeployment @deployParams

    if ($deployment.ProvisioningState -ne 'Succeeded') {
        Write-Host "`n [FAILED] Deployment failed with state: $($deployment.ProvisioningState)" -ForegroundColor Red
        Exit-Lab -FailureCount 1
    }

    Write-Host "`nSuccessfully deployed Lab 4.4 security configuration!" -ForegroundColor Green
    Write-Host "  -> Storage Account: $($deployment.Outputs.outStorageAccountId.Value)" -ForegroundColor Green
    Write-Host "  -> Container:       $($deployment.Outputs.outContainerName.Value)" -ForegroundColor Green
    Write-Host "  -> Firewall:        $($deployment.Outputs.outFirewallDefaultAction.Value)" -ForegroundColor Green
    if ($assignPrincipalId) {
        Write-Host "  -> Role:            '$dataRoleName' assigned on the account. It takes up to about five minutes to take effect." -ForegroundColor Green
    }
}
catch {
    Write-Host "`n [ERROR] Deployment failed!" -ForegroundColor Red
    Write-Host "  -> Cause: $($_.Exception.Message)" -ForegroundColor Red
    if ($assignPrincipalId -and "$($_.Exception.Message)" -match 'roleAssignments/write') {
        Write-Host "  -> The identity may not create role assignments. Run the script again with -SkipDataRoleAssignment, and have the role assigned as in guide Step 4.4.7." -ForegroundColor Yellow
    }
    Exit-Lab -FailureCount 1
}

<#
.SYNOPSIS
    Validates the configuration of Lab 3.3 Container resources.

.DESCRIPTION
    This script runs validation checks against the deployed SkyCraft Lab 3.3 resources:
    - Azure Container Registry (ACR) provisioning state, SKU, admin user and image existence.
    - Azure Container Instance (ACI) provisioning state, OS type, SKU, restart policy, size, public
      IP, DNS name label, and no container instance logs (the Portal's default creates a Log
      Analytics workspace in East US).
    - Azure Container Apps (ACA) provisioning state, ingress, scaling config, and the provisioning
      state, workload profile and logs destination of its environment, found through the app
      (docs/powershell-standards.md rule 7).
    - No Log Analytics workspace with the Portal's automatic name in the resource group: the
      Container Apps wizard's default creates one, and Module 5 wizards then offer it as their
      default workspace (#374).
    - The region and the Project, Environment and CostCenter tags of the four resources.
    A resource left in a Failed provisioning state fails its check (#371).

    It accepts the state each path of the lab guide leaves - the Portal steps, the Az PowerShell
    blocks and Deploy-Bicep.ps1 (#362).

.PARAMETER Environment
    The environment to validate: dev, prod or platform. Default: 'dev'. Every resource name
    below defaults to the prefix this selects (#121), matching what Deploy-Bicep.ps1 deploys.

.PARAMETER ResourceGroupName
    The resource group name. Default: '<Environment>-skycraft-swc-rg'

.PARAMETER AcrName
    The container registry name. Default: '<Environment>skycraftswcacr01'

.PARAMETER AciName
    The container instance name. Default: '<Environment>-skycraft-swc-aci-auth'

.PARAMETER CaeName
    The Container Apps environment name. Default: '<Environment>-skycraft-swc-cae-02'

.PARAMETER AcaName
    The container app name. Default: '<Environment>-skycraft-swc-aca-world'

.EXAMPLE
    .\Test-Lab.ps1
    Runs all validation checks against the dev resources and outputs results.

.EXAMPLE
    .\Test-Lab.ps1 -Environment prod
    Validates the prod resources in prod-skycraft-swc-rg.

.NOTES
    Project: SkyCraft
    Lab: 3.3 - Containers
    Author: Antigravity
    Date: 2026-01-31
#>

#Requires -Version 7.0
#Requires -Modules Az.Accounts, Az.ContainerRegistry, Az.ContainerInstance, Az.Resources

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [ValidateSet('dev', 'prod', 'platform')]
    [string]$Environment = 'dev',

    # Defaults below read $Environment, so it must be declared first.
    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$ResourceGroupName = "$Environment-skycraft-swc-rg",

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$AcrName = "${Environment}skycraftswcacr01",

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$AciName = "$Environment-skycraft-swc-aci-auth",

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$CaeName = "$Environment-skycraft-swc-cae-02",

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$AcaName = "$Environment-skycraft-swc-aca-world"
)

$ErrorActionPreference = 'Stop'
# Exit-Lab ends the script with exit code 0 or 1 and leaves an interactive session open (#257).
Import-Module (Join-Path $PSScriptRoot '../../../tools/LabCommon.psm1') -Force -Verbose:$false
$failCount = 0

Write-Host "=== Lab 3.3 Validation Script ===" -ForegroundColor Cyan -BackgroundColor Black

# Check Azure Connection
$context = Get-AzContext
if (-not $context) {
    Write-Host "Not logged in. Please run Connect-AzAccount" -ForegroundColor Red
    Exit-Lab -FailureCount 1
}
Write-Host "Connected to: $($context.Subscription.Name)" -ForegroundColor Green
Write-Host "Environment: $Environment (resource group $ResourceGroupName)" -ForegroundColor Gray

# 1. Validate ACR
Write-Host "`n=== 1. Validating Azure Container Registry ===" -ForegroundColor Cyan
$imageName = "skycraft-auth"
$imageTag = "v1"

$acr = Get-AzContainerRegistry -ResourceGroupName $ResourceGroupName -Name $AcrName -ErrorAction SilentlyContinue
if ($acr) {
    Write-Host "[OK] ACR found: $AcrName" -ForegroundColor Green

    # A registry whose create failed still shows up by name (#371).
    if ("$($acr.ProvisioningState)" -eq 'Succeeded') {
        Write-Host "  - Provisioning State: Succeeded" -ForegroundColor Green
    } else {
        Write-Host "  - [FAIL] Provisioning State is '$($acr.ProvisioningState)' (Expected: Succeeded)" -ForegroundColor Red
        $failCount++
    }

    if ($acr.SkuName -eq "Standard") {
        Write-Host "  - SKU Standard verified" -ForegroundColor Green
    } else {
        Write-Host "  - [FAIL] SKU is $($acr.SkuName) (Expected: Standard)" -ForegroundColor Red
        $failCount++
    }

    if ($acr.AdminUserEnabled) {
        Write-Host "  - Admin User Enabled" -ForegroundColor Green
    } else {
        Write-Host "  - [FAIL] Admin User Not Enabled" -ForegroundColor Red
        $failCount++
    }

    # Check Image
    $repos = Get-AzContainerRegistryRepository -RegistryName $AcrName -ErrorAction SilentlyContinue
    if ($repos -contains $imageName) {
        Write-Host "  - [OK] Repository '$imageName' found" -ForegroundColor Green
    } else {
        Write-Host "  - [FAIL] Repository '$imageName' not found" -ForegroundColor Red
        $failCount++
    }
} else {
    Write-Host "[FAIL] ACR $AcrName not found" -ForegroundColor Red
    $failCount++
}

# 2. Validate ACI
Write-Host "`n=== 2. Validating Azure Container Instance ===" -ForegroundColor Cyan

try {
    $aci = Get-AzContainerGroup -ResourceGroupName $ResourceGroupName -Name $AciName -ErrorAction Stop
    Write-Host "[OK] ACI found: $AciName" -ForegroundColor Green

    if ($aci.ProvisioningState -eq "Succeeded") {
        Write-Host "  - Provisioning State: Succeeded" -ForegroundColor Green
    } else {
        Write-Host "  - [FAIL] Provisioning State is $($aci.ProvisioningState) (Expected: Succeeded)" -ForegroundColor Red
        $failCount++
    }

    # The settings Step 3.3.4 chooses, as all three paths set them.
    $aciExpected = [ordered]@{ 'OS type' = @('Linux', $aci.OSType); 'SKU' = @('Standard', $aci.Sku); 'Restart policy' = @('Always', $aci.RestartPolicy) }
    foreach ($setting in $aciExpected.Keys) {
        $expected, $actual = $aciExpected[$setting]
        if ("$actual" -eq $expected) {
            Write-Host "  - $($setting): $expected" -ForegroundColor Green
        } else {
            Write-Host "  - [FAIL] $setting is '$actual' (Expected: $expected, Step 3.3.4)" -ForegroundColor Red
            $failCount++
        }
    }
    $aciContainer = @($aci.Container)[0]
    if ($aciContainer -and [double]"$($aciContainer.RequestCpu)" -eq 1 -and [double]"$($aciContainer.RequestMemoryInGb)" -eq 1) {
        Write-Host "  - Size: 1 CPU core, 1 GiB memory" -ForegroundColor Green
    } else {
        Write-Host "  - [FAIL] Size is '$($aciContainer.RequestCpu)' CPU cores and '$($aciContainer.RequestMemoryInGb)' GiB memory (Expected: 1 and 1, Step 3.3.4 Change size)" -ForegroundColor Red
        $failCount++
    }

    # Get-AzContainerGroup returns the IP settings flat (IPAddress*); there is no IpAddress object.
    if ($aci.IPAddressIP) {
        Write-Host "  - Public IP: $($aci.IPAddressIP)" -ForegroundColor Green
    } else {
        Write-Host "  - [FAIL] No Public IP assigned" -ForegroundColor Red
        $failCount++
    }

    # Step 3.3.5 opens the instance by its FQDN, which exists only with a DNS name label.
    if ($aci.IPAddressFqdn) {
        Write-Host "  - FQDN: $($aci.IPAddressFqdn)" -ForegroundColor Green
        # The guide, its PowerShell block and the Bicep leave the Unsecure scope (or no value, read
        # as Unsecure); the Portal switches to Tenant once a label is typed. Tenant works and is the
        # safer scope, so it is reported, not failed.
        $labelScope = "$($aci.IPAddressAutoGeneratedDomainNameLabelScope)"
        if ($labelScope -and $labelScope -ne 'Unsecure') {
            Write-Host "  - [INFO] DNS name label scope is $labelScope, not Any reuse (unsecure) as in Step 3.3.4: the FQDN carries a hash segment." -ForegroundColor Gray
        }
    } else {
        Write-Host "  - [FAIL] No DNS name label: Step 3.3.4 sets one, and Step 3.3.5 opens the FQDN it gives" -ForegroundColor Red
        $failCount++
    }

    # Step 3.3.4 unchecks "Enable container instance logs": checked, it sends the logs to a new
    # workspace in East US (#374).
    if ($aci.LogAnalyticWorkspaceId) {
        Write-Host "  - [FAIL] Container instance logs go to a Log Analytics workspace (workspace id $($aci.LogAnalyticWorkspaceId)). Step 3.3.4 unchecks 'Enable container instance logs'; recreate the instance without them. Remove-LabResource.ps1 deletes that workspace (Azure's default DefaultWorkspace-..., which no other lab uses) and its resource group if nothing else is in it, but finds it only while this instance sends its logs there: once you recreate the instance, delete the workspace yourself (guide, What This Lab Leaves Behind)." -ForegroundColor Red
        $failCount++
    } else {
        Write-Host "  - No container instance logs (no Log Analytics workspace)" -ForegroundColor Green
    }

} catch {
    Write-Host "[FAIL] ACI $AciName not found or could not be read: $_" -ForegroundColor Red
    $failCount++
}

# 3. Validate ACA
Write-Host "`n=== 3. Validating Azure Container Apps ===" -ForegroundColor Cyan

# Generic ARM lookup (no native Az cmdlet for Container Apps in base modules)
$aca = Get-AzResource -ResourceGroupName $ResourceGroupName -ResourceType 'Microsoft.App/containerApps' -Name $AcaName -ExpandProperties -ErrorAction SilentlyContinue
if ($aca) {
    Write-Host "[OK] ACA found: $AcaName" -ForegroundColor Green
    $props = $aca.Properties

    if ($props.provisioningState -eq "Succeeded") {
        Write-Host "  - Provisioning State: Succeeded" -ForegroundColor Green
    } else {
        Write-Host "  - [FAIL] Provisioning State: $($props.provisioningState)" -ForegroundColor Red
        $failCount++
    }

    if ($props.configuration.ingress.external) {
        Write-Host "  - Ingress: External (Enabled)" -ForegroundColor Green
        Write-Host "  - FQDN: https://$($props.configuration.ingress.fqdn)" -ForegroundColor Cyan
    } else {
        Write-Host "  - [FAIL] Ingress not configured correctly" -ForegroundColor Red
        $failCount++
    }

    if ("$($props.configuration.ingress.targetPort)" -eq '80') {
        Write-Host "  - Ingress target port 80 verified" -ForegroundColor Green
    } else {
        Write-Host "  - [FAIL] Ingress target port is '$($props.configuration.ingress.targetPort)' (Expected: 80, Step 3.3.8)" -ForegroundColor Red
        $failCount++
    }

    # Check Scaling (Step 3.3.9): the rule the guide names, and the replica range. The Portal adds
    # its own rule, http-scaler, which the guide deletes; another rule is reported, not failed.
    $scale = $props.template.scale
    $httpRule = @($scale.rules) | Where-Object { $_ -and $_.name -eq 'http-load' -and "$($_.http.metadata.concurrentRequests)" -eq '10' }
    if ($httpRule) {
        Write-Host "  - Scaling Rule 'http-load' (10 concurrent) verified" -ForegroundColor Green
    } else {
        Write-Host "  - [FAIL] Scaling rule 'http-load' with 10 concurrent requests not found (Step 3.3.9)" -ForegroundColor Red
        $failCount++
    }
    foreach ($otherRule in @(@($scale.rules) | Where-Object { $_ -and $_.name -ne 'http-load' })) {
        Write-Host "  - [INFO] Another scale rule: '$($otherRule.name)' (Step 3.3.9 deletes the Portal's http-scaler)" -ForegroundColor Gray
    }
    if ("$($scale.minReplicas)" -eq '1' -and "$($scale.maxReplicas)" -eq '3') {
        Write-Host "  - Replicas 1-3 verified" -ForegroundColor Green
    } else {
        Write-Host "  - [FAIL] Replicas are '$($scale.minReplicas)'-'$($scale.maxReplicas)' (Expected: 1-3, Step 3.3.9)" -ForegroundColor Red
        $failCount++
    }

    # Validate Image Tag
    # @() first: a template without containers would otherwise throw "Cannot index into a null
    # array" and end the script without its summary (#355).
    $containerImage = @($props.template.containers)[0].image
    if ($containerImage -match ":$imageTag$") {
        Write-Host "  - Image Tag '$imageTag' verified" -ForegroundColor Green
    } else {
        Write-Host "  - [FAIL] Image Tag mismatch. Found: $containerImage" -ForegroundColor Red
        $failCount++
    }

    # Validate Environment
    $envId = $props.managedEnvironmentId
    if ($envId -match $CaeName) {
        Write-Host "  - Managed Environment '$CaeName' verified" -ForegroundColor Green
    } else {
        Write-Host "  - [FAIL] Managed Environment mismatch. Found: $envId" -ForegroundColor Red
        $failCount++
    }

    # The environment's logs destination, read from the environment the app runs in (#374). Step
    # 3.3.6 and the Bicep choose Azure Monitor, which creates no workspace; 'Don't save logs' (no
    # destination) creates none either. The Portal's default, Azure Log Analytics, creates one.
    if ($envId) {
        try {
            $cae = Get-AzResource -ResourceId $envId -ExpandProperties -ErrorAction Stop
            # An environment whose create failed still shows up by id (#371).
            if ("$($cae.Properties.provisioningState)" -eq 'Succeeded') {
                Write-Host "  - Environment provisioning state: Succeeded" -ForegroundColor Green
            } else {
                Write-Host "  - [FAIL] Environment provisioning state is '$($cae.Properties.provisioningState)' (Expected: Succeeded)" -ForegroundColor Red
                $failCount++
            }
            # Step 3.3.6 leaves the Workload profiles tab with its Consumption profile; the
            # PowerShell block and the Bicep declare the same.
            if (@($cae.Properties.workloadProfiles) | Where-Object { $_ -and "$($_.workloadProfileType)" -eq 'Consumption' }) {
                Write-Host "  - Environment workload profile: Consumption" -ForegroundColor Green
            } else {
                Write-Host "  - [FAIL] The environment has no Consumption workload profile (a Consumption-only environment, or another profile). Step 3.3.6 creates a Workload profiles environment with the Consumption profile." -ForegroundColor Red
                $failCount++
            }
            $logs = $cae.Properties.appLogsConfiguration
            if ("$($logs.destination)" -eq 'log-analytics') {
                Write-Host "  - [FAIL] The environment sends its logs to a Log Analytics workspace (customer id $($logs.logAnalyticsConfiguration.customerId)). Step 3.3.6 chooses Azure Monitor: under Monitoring > Logging options, choose Azure Monitor, then run Remove-LabResource.ps1 or delete the workspace (#374)." -ForegroundColor Red
                $failCount++
            } else {
                $shownDestination = if ($logs.destination) { $logs.destination } else { 'none' }
                Write-Host "  - Environment logs destination: $shownDestination (no Log Analytics workspace)" -ForegroundColor Green
            }
        } catch {
            Write-Host "  - [FAIL] Could not read the environment $($envId): $_" -ForegroundColor Red
            $failCount++
        }
    }

} else {
    Write-Host "[FAIL] ACA $AcaName not found" -ForegroundColor Red
    $failCount++
}

# 4. No Log Analytics workspace left by the Portal (#374)
Write-Host "`n=== 4. Validating that no auto-created Log Analytics workspace is left ===" -ForegroundColor Cyan

# The Container Apps wizard's default names its new workspace 'workspace' followed by the resource
# group's name without dashes and a short suffix (workspacedevskycraftswcrg1a2b). No step of this
# lab creates a workspace, and Module 5 wizards offer one found here as their default.
$autoWorkspacePattern = '^workspace-?' + [regex]::Escape(($ResourceGroupName -replace '[^A-Za-z0-9]', '').ToLowerInvariant()) + '[0-9a-z]*$'
try {
    $autoWorkspaces = @(Get-AzResource -ResourceGroupName $ResourceGroupName -ResourceType 'Microsoft.OperationalInsights/workspaces' -ErrorAction Stop |
        Where-Object { $_.Name -match $autoWorkspacePattern })
    if ($autoWorkspaces.Count -eq 0) {
        Write-Host "[OK] No auto-created Log Analytics workspace in $ResourceGroupName" -ForegroundColor Green
    } else {
        foreach ($workspace in $autoWorkspaces) {
            Write-Host "[FAIL] Log Analytics workspace '$($workspace.Name)' in $ResourceGroupName was created by the Portal's default (Step 3.3.6 chooses Azure Monitor). Module 5 wizards would offer it as their default; run Remove-LabResource.ps1 or delete it." -ForegroundColor Red
            $failCount++
        }
    }
} catch {
    Write-Host "[FAIL] Could not list the Log Analytics workspaces in $($ResourceGroupName): $_" -ForegroundColor Red
    $failCount++
}

# 5. Region and tags of the four resources
Write-Host "`n=== 5. Validating region and tags ===" -ForegroundColor Cyan

# Every create step sets the region and the SkyCraft tags (Owner is the learner's own, so it is not
# compared). A resource that sections 1-3 did not find is not reported again here.
$expectedEnvironmentTag = @{ dev = 'Development'; prod = 'Production'; platform = 'Platform' }[$Environment]
$allowedRegions = @('swedencentral', 'northeurope')
$labResources = @(
    @{ Type = 'Microsoft.ContainerRegistry/registries';      Name = $AcrName }
    @{ Type = 'Microsoft.ContainerInstance/containerGroups'; Name = $AciName }
    @{ Type = 'Microsoft.App/managedEnvironments';           Name = $CaeName }
    @{ Type = 'Microsoft.App/containerApps';                 Name = $AcaName }
)
try {
    $inGroup = @(Get-AzResource -ResourceGroupName $ResourceGroupName -ErrorAction Stop)
    foreach ($expected in $labResources) {
        $resource = $inGroup | Where-Object { $_ -and $_.ResourceType -eq $expected.Type -and $_.Name -eq $expected.Name } | Select-Object -First 1
        if (-not $resource) { continue }

        if ("$($resource.Location)" -in $allowedRegions) {
            Write-Host "  - $($expected.Name): region $($resource.Location)" -ForegroundColor Green
        } else {
            Write-Host "  - [FAIL] $($expected.Name) is in '$($resource.Location)' (Expected: swedencentral, or northeurope as in Troubleshooting Issue 1)" -ForegroundColor Red
            $failCount++
        }

        $tags = if ($resource.Tags) { $resource.Tags } else { @{} }
        $expectedTags = [ordered]@{ Project = 'SkyCraft'; Environment = $expectedEnvironmentTag; CostCenter = 'MSDN' }
        $wrongTags = foreach ($tag in $expectedTags.GetEnumerator()) {
            if ("$($tags[$tag.Key])" -ne $tag.Value) { "$($tag.Key) is '$($tags[$tag.Key])' (Expected: $($tag.Value))" }
        }
        if (-not $wrongTags) {
            Write-Host "  - $($expected.Name): tags Project, Environment and CostCenter verified" -ForegroundColor Green
        } else {
            Write-Host "  - [FAIL] $($expected.Name): tag $($wrongTags -join '; tag '). Every create step sets the four SkyCraft tags on its Tags tab." -ForegroundColor Red
            $failCount++
        }
    }
} catch {
    Write-Host "[FAIL] Could not list the resources in $($ResourceGroupName): $_" -ForegroundColor Red
    $failCount++
}

Write-Host "`n=== Validation Summary ===" -ForegroundColor Cyan
if ($failCount -eq 0) {
    Write-Host "All Lab 3.3 checks passed." -ForegroundColor Green
} else {
    Write-Host "Lab 3.3 validation found $failCount issue(s)." -ForegroundColor Red
}

Exit-Lab -FailureCount $failCount

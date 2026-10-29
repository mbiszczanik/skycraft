<#
.SYNOPSIS
    Verifies Lab 4.2 Infrastructure (Blob Storage).

.DESCRIPTION
    Checks the production and development storage accounts against the end state the lab guide,
    its Az PowerShell blocks and its Bicep all reach (issue #362):

      - Production: anonymous access off, the four containers private, soft delete for blobs and
        for containers at 7 days, versioning on.
      - Both accounts in the provisioning state Succeeded: an account Azure left in Failed does
        not count as built (#371).
      - Production lifecycle policy: rules 'tier-game-logs' and 'archive-backups', each enabled
        and limited by a prefix filter to its own container ('game-logs/', 'player-backups/'). A
        rule without the filter applies to every block blob in the account, and tier-game-logs
        would then delete game assets and player backups after 365 days (#356); such a rule fails.
      - The base blob actions of each rule, by days since the last modification: tier-game-logs
        Cool 30, Cold 90, Archive 180, Delete 365; archive-backups Archive 7 and no delete. The
        Portal's first If/Then block starts at "Delete the blob", so a rule saved with that
        default deletes logs after 30 days or every player backup after 7; such a rule fails.
      - Development: anonymous access off, versioning off, container 'public-demo' private.

    A property the Portal never sets reads as $null and counts as its Portal default: dev
    versioning unset is "off" (#355). A blob service that could not be read is a failure, not a
    default. The blobs of guide Steps 4.2.11-4.2.13 are not checked.

    Ends through Exit-Lab (tools/LabCommon.psm1): exit 1 when any check failed, 0 otherwise; at a
    prompt the session stays open (#257).

.PARAMETER ProdRgName
    Resource group name for production. Default: prod-skycraft-swc-rg

.PARAMETER DevRgName
    Resource group name for development. Default: dev-skycraft-swc-rg

.PARAMETER ProdSaName
    Production storage account name. Default: prodskycraftswcsa

.PARAMETER DevSaName
    Development storage account name. Default: devskycraftswcsa

.EXAMPLE
    .\Test-Lab.ps1

.NOTES
    Project: SkyCraft
    Author: SkyCraft
#>

#Requires -Version 7.0
#Requires -Modules Az.Accounts, Az.Storage

[CmdletBinding()]
param(
    [ValidateNotNullOrEmpty()]
    [string]$ProdRgName = 'prod-skycraft-swc-rg',
    [ValidateNotNullOrEmpty()]
    [string]$DevRgName = 'dev-skycraft-swc-rg',
    [ValidatePattern('^[a-z0-9]{3,24}$')]
    [string]$ProdSaName = 'prodskycraftswcsa',
    [ValidatePattern('^[a-z0-9]{3,24}$')]
    [string]$DevSaName = 'devskycraftswcsa'
)

$ErrorActionPreference = 'Stop'
# Exit-Lab ends the script with exit code 0 or 1 and leaves an interactive session open (#257).
Import-Module (Join-Path $PSScriptRoot '../../../tools/LabCommon.psm1') -Force -Verbose:$false
$TestsPassed = 0
$TestsTotal = 0

function Assert-Check {
    param(
        [string]$Description,
        [bool]$Condition,
        [string]$SuccessMessage = "OK",
        [string]$FailureMessage = "FAIL"
    )
    $script:TestsTotal++
    Write-Host "  Checking: $Description ... " -NoNewline
    if ($Condition) {
        Write-Host "PASS ($SuccessMessage)" -ForegroundColor Green
        $script:TestsPassed++
    }
    else {
        Write-Host "FAIL ($FailureMessage)" -ForegroundColor Red
    }
}

# Reads a blob service's properties. Returns the properties, or $null with the reason in $Reason.
function Get-LabBlobServiceProperty {
    param(
        [string]$ResourceGroupName,
        [string]$StorageAccountName,
        [ref]$Reason
    )
    try {
        $properties = Get-AzStorageBlobServiceProperty -ResourceGroupName $ResourceGroupName -StorageAccountName $StorageAccountName -ErrorAction Stop
        if ($null -eq $properties) { $Reason.Value = 'Blob service properties not returned' }
        return $properties
    }
    catch {
        $Reason.Value = "Could not read the blob service: $($_.Exception.Message)"
        return $null
    }
}

# Checks that a lifecycle rule exists, is enabled and is limited by a prefix filter to $Prefix:
# at least one prefix, and every prefix starts with $Prefix (prefixes are case-sensitive). A rule
# without a prefix applies to every block blob in the account.
#
# $Actions lists the base blob actions the rule must have, in the order Get-LifecycleActionText
# reports them, each with its days since the last modification; any other base blob action, or
# other days, fails the check.
function Assert-LifecycleRule {
    param(
        [object[]]$Rules,
        [string]$Name,
        [string]$Prefix,
        [System.Collections.Specialized.OrderedDictionary]$Actions
    )
    $rule = @($Rules | Where-Object { $_.Name -eq $Name }) | Select-Object -First 1
    Assert-Check "PROD: '$Name' rule present" -Condition ($null -ne $rule)
    if (-not $rule) { return }

    Assert-Check "PROD: '$Name' rule enabled" `
        -Condition ($rule.Enabled -eq $true) `
        -SuccessMessage "Enabled" `
        -FailureMessage "Disabled"

    $prefixes = @($rule.Definition.Filters.PrefixMatch | Where-Object { -not [string]::IsNullOrEmpty($_) })
    $outside = @($prefixes | Where-Object { -not $_.StartsWith($Prefix, [System.StringComparison]::Ordinal) })
    $failure = if ($prefixes.Count -eq 0) {
        "No prefix filter: the rule applies to every blob in the account. Add the Blob prefix '$Prefix' (guide Step 4.2.8/4.2.9)"
    }
    else {
        "Prefix filter $($outside -join ', ') reaches outside '$Prefix'"
    }
    Assert-Check "PROD: '$Name' rule limited to '$Prefix'" `
        -Condition ($prefixes.Count -gt 0 -and $outside.Count -eq 0) `
        -SuccessMessage "Prefix $($prefixes -join ', ')" `
        -FailureMessage $failure

    $expected = (@($Actions.Keys | ForEach-Object { "$_ $($Actions[$_])" }) -join ', ')
    $actual = Get-LifecycleActionText -BaseBlob $rule.Definition.Actions.BaseBlob
    $deletes = $rule.Definition.Actions.BaseBlob.Delete
    $actionFailure = "Actions $actual, expected $expected"
    if ($deletes -and (-not $Actions.Contains('Delete') -or $deletes.DaysAfterModificationGreaterThan -ne $Actions['Delete'])) {
        $actionFailure += ". The rule deletes blobs the guide keeps: the Portal's first block starts at 'Delete the blob' (guide Step 4.2.8/4.2.9)"
    }
    Assert-Check "PROD: '$Name' rule actions" `
        -Condition ($actual -ceq $expected) `
        -SuccessMessage $actual `
        -FailureMessage $actionFailure
}

# The base blob actions of a lifecycle rule as text, in a fixed order: 'TierToCool 30, Delete 365'.
# The days are those since the last modification; an action on another condition shows it
# ('Delete created 30', 'TierToCool accessed 30'), so it never matches an expected action.
# An action with the Portal's "Skip blobs that have been rehydrated in the last" days adds them
# ('TierToArchive 180 rehydrated 7'), so a rule saved with that box unticked fails.
function Get-LifecycleActionText {
    param([object]$BaseBlob)
    if ($null -eq $BaseBlob) { return 'none' }
    $parts = foreach ($action in 'TierToHot', 'TierToCool', 'TierToCold', 'TierToArchive', 'Delete') {
        $when = $BaseBlob.$action
        if ($null -eq $when) { continue }
        $text = if ($null -ne $when.DaysAfterModificationGreaterThan) { "$action $($when.DaysAfterModificationGreaterThan)" }
        elseif ($null -ne $when.DaysAfterCreationGreaterThan) { "$action created $($when.DaysAfterCreationGreaterThan)" }
        elseif ($null -ne $when.DaysAfterLastAccessTimeGreaterThan) { "$action accessed $($when.DaysAfterLastAccessTimeGreaterThan)" }
        else { "$action (no days)" }
        if ($null -ne $when.DaysAfterLastTierChangeGreaterThan) { $text += " rehydrated $($when.DaysAfterLastTierChangeGreaterThan)" }
        $text
    }
    if (@($parts).Count -eq 0) { return 'none' }
    return (@($parts) -join ', ')
}

Write-Host "`n=== Lab 4.2: Verifying Blob Storage Configuration ===" -ForegroundColor Cyan

# 1. Environment Check
try {
    $prodSa = Get-AzStorageAccount -ResourceGroupName $ProdRgName -Name $ProdSaName -ErrorAction Stop
    $devSa = Get-AzStorageAccount -ResourceGroupName $DevRgName -Name $DevSaName -ErrorAction Stop
}
catch {
    Write-Host "FATAL: Could not retrieve storage accounts. Ensure deployment succeeded." -ForegroundColor Red
    Exit-Lab -FailureCount 1
}

# 2. Production Security Verification (Privacy & Versioning)
Write-Host "`n--- Production Verification (Secure) ---" -ForegroundColor Yellow

# An account Azure left in Failed is listed and readable, but the lab did not build it (#371).
Assert-Check "PROD: Storage account provisioned" `
    -Condition ("$($prodSa.ProvisioningState)" -eq 'Succeeded') `
    -SuccessMessage "Succeeded" `
    -FailureMessage "Provisioning state '$($prodSa.ProvisioningState)', expected Succeeded"

# AllowBlobPublicAccess MUST be False
Assert-Check "PROD: AllowBlobPublicAccess is disabled" `
    -Condition ($prodSa.AllowBlobPublicAccess -eq $false) `
    -SuccessMessage "Public Access Disabled" `
    -FailureMessage "Public Access Enabled (Security Risk!)"

# Data protection (guide Steps 4.2.5-4.2.7): versioning on, soft delete at 7 days for blobs and
# for containers. Lab 4.1's Portal wizard turns both soft delete settings on at 7 days.
$prodBlobServiceError = $null
$prodBlobService = Get-LabBlobServiceProperty -ResourceGroupName $ProdRgName -StorageAccountName $ProdSaName -Reason ([ref]$prodBlobServiceError)

Assert-Check "PROD: Versioning enabled" `
    -Condition ($null -ne $prodBlobService -and $prodBlobService.IsVersioningEnabled -eq $true) `
    -SuccessMessage "Versioning ON" `
    -FailureMessage $(if ($prodBlobServiceError) { $prodBlobServiceError } else { "Versioning OFF" })

foreach ($softDelete in @(
        @{ Label = 'blobs'; Policy = 'DeleteRetentionPolicy' }
        @{ Label = 'containers'; Policy = 'ContainerDeleteRetentionPolicy' }
    )) {
    $policy = if ($prodBlobService) { $prodBlobService.($softDelete.Policy) } else { $null }
    Assert-Check "PROD: Soft delete for $($softDelete.Label) on, 7 days" `
        -Condition ($null -ne $policy -and $policy.Enabled -eq $true -and $policy.Days -eq 7) `
        -SuccessMessage "On, $($policy.Days) days" `
        -FailureMessage $(if ($prodBlobServiceError) { $prodBlobServiceError } elseif ($policy.Enabled -ne $true) { "Off" } else { "On, $($policy.Days) days, expected 7" })
}

# Containers Verification (guide Steps 4.2.2-4.2.3)
$prodCtx = $prodSa.Context
$prodContainers = Get-AzStorageContainer -Context $prodCtx -ErrorAction SilentlyContinue

foreach ($containerName in 'game-assets', 'player-backups', 'server-config', 'game-logs') {
    $container = $prodContainers | Where-Object Name -eq $containerName
    Assert-Check "PROD: '$containerName' container exists" `
        -Condition ($null -ne $container)

    if ($container) {
        Assert-Check "PROD: '$containerName' is PRIVATE" `
            -Condition ($container.PublicAccess -eq 'Off') `
            -SuccessMessage "Private Access" `
            -FailureMessage "Public Access detected! Should be Private."
    }
}

# Lifecycle Management Verification (guide Steps 4.2.8-4.2.9, #356)
$prodPolicy = Get-AzStorageAccountManagementPolicy -ResourceGroupName $ProdRgName -StorageAccountName $ProdSaName -ErrorAction SilentlyContinue
Assert-Check "PROD: Lifecycle Policy exists" `
    -Condition ($null -ne $prodPolicy)

if ($prodPolicy) {
    $rules = @($prodPolicy.Rules)
    Assert-LifecycleRule -Rules $rules -Name 'tier-game-logs' -Prefix 'game-logs/' `
        -Actions ([ordered]@{ TierToCool = 30; TierToCold = 90; TierToArchive = '180 rehydrated 7'; Delete = 365 })
    Assert-LifecycleRule -Rules $rules -Name 'archive-backups' -Prefix 'player-backups/' `
        -Actions ([ordered]@{ TierToArchive = '7 rehydrated 7' })
}

# 3. Development Verification
Write-Host "`n--- Development Verification ---" -ForegroundColor Yellow

Assert-Check "DEV: Storage account provisioned" `
    -Condition ("$($devSa.ProvisioningState)" -eq 'Succeeded') `
    -SuccessMessage "Succeeded" `
    -FailureMessage "Provisioning state '$($devSa.ProvisioningState)', expected Succeeded"

# AllowBlobPublicAccess MUST be False (guide Step 4.2.12)
Assert-Check "DEV: AllowBlobPublicAccess is disabled" `
    -Condition ($devSa.AllowBlobPublicAccess -eq $false) `
    -SuccessMessage "Public Access Disabled" `
    -FailureMessage "Public Access Enabled (unexpected)"

# Versioning should be Disabled (default). A dev account created in the Portal never sets the
# property, so it reads $null; the Bicep writes $false. Both are the default, off (#355). A blob
# service that could not be read is a failure, not an "off".
$devBlobServiceError = $null
$devBlobService = Get-LabBlobServiceProperty -ResourceGroupName $DevRgName -StorageAccountName $DevSaName -Reason ([ref]$devBlobServiceError)
Assert-Check "DEV: Versioning disabled (scope check)" `
    -Condition ($null -ne $devBlobService -and -not $devBlobService.IsVersioningEnabled) `
    -SuccessMessage $(if ($null -eq $devBlobService.IsVersioningEnabled) { "Versioning not set (Portal default: off)" } else { "Versioning OFF" }) `
    -FailureMessage $(if ($devBlobServiceError) { $devBlobServiceError } else { "Versioning ON" })

# Container Verification - public-demo exists as private container
$devCtx = $devSa.Context
$devContainer = Get-AzStorageContainer -Context $devCtx -Name 'public-demo' -ErrorAction SilentlyContinue

Assert-Check "DEV: 'public-demo' container exists" `
    -Condition ($null -ne $devContainer)

if ($devContainer) {
    Assert-Check "DEV: 'public-demo' is private" `
        -Condition ($devContainer.PublicAccess -eq 'Off') `
        -SuccessMessage "Private Access OK" `
        -FailureMessage "Access is $($devContainer.PublicAccess), expected Off"
}

# Summary
$failedCount = $TestsTotal - $TestsPassed
Write-Host "`n=== Test Summary ===" -ForegroundColor Cyan
Write-Host "Tests Passed: $TestsPassed / $TestsTotal"
if ($failedCount -eq 0) {
    Write-Host "SUCCESS: Lab 4.2 compliant!" -ForegroundColor Green
}
else {
    Write-Host "FAILURE: Some checks failed." -ForegroundColor Red
}
Exit-Lab -FailureCount $failedCount

<#
.SYNOPSIS
    Pester 5 tests for the Lab 1.3 cleanup: what it removes, and when it exits 1.

.DESCRIPTION
    Regression cover for issue #252. The cleanup removed only the two locks and the three policy
    assignments, so the two budgets, the Advisor alert and its action group stayed behind, and it
    looked everything up with -ErrorAction SilentlyContinue and exited 0 even when a removal
    failed. These tests run the real Remove-LabResource.ps1 in a child pwsh process against a
    generated stub of the Az commands it calls, and assert the observable contract:

      1. Every object the guide creates is removed when it is present: the locks, the policy
         assignments, the subscription and resource group budgets, the Advisor alert, and its
         action group (under the current name, and the one used before #225). An unrelated
         action group in the same resource group is left alone. The budgets are listed and
         deleted through the Consumption API at 2023-05-01 (Get-LabArmBudget,
         Remove-LabArmBudget; issue #411), served by the shared ARM fake, never through Az.Billing.
      2. An object that is absent - an empty listing, a policy assignment reported as not
         found, or a resource group that is gone - is not a failure: the run exits 0.
      3. A lookup that fails with an error is an [ERROR], counted, and the run exits 1 without
         touching the object it could not see. The stub reports the failure with Write-Error, as
         the Az getters do, so a script that passes -ErrorAction SilentlyContinue swallows it.
         A failed budget read prints its HTTP status and the service's message, and names no
         cause the message does not give (no offer without Cost Management, issue #411).
      4. A removal that fails is an [ERROR], counted, and the later steps still run: exit 1.
      5. -WhatIf removes nothing and does not wait for lock propagation.
      6. Which errors mean "not found" is pinned by lifting Test-LabNotFoundError out of the
         script with the parser and running it on one error per shape.
      7. The policy assignments are found whichever path made them (issue #330): by the fixed
         name the Bicep path sets, or by the display name a learner types into the Portal next
         to a generated resource name. They are removed by id, from the subscription only. An
         assignment made twice is removed neither time: an [ERROR], counted, exit 1.
      8. The Modify assignment Inherit-Project-Tag (issue #350) is removed too, and the role
         assignments its identity holds in the subscription go first, found by principal id in
         one listing of the ARM role assignments API (never through the Az role cmdlets, which
         call Microsoft Graph, issue #397); a role assignment of another principal, or one
         inherited from a management group, is left alone. When that listing or a removal
         fails, the assignment is kept for a second run: an [ERROR], counted, exit 1. The Bicep
         path's Deny assignments made before main.bicep set managedIdentities to {} carry an
         identity with no role: they are removed as usual, and kept with the rest when the
         listing fails.

    Scope limit, as in the Lab 5.2 suite: the child is launched with -Command, so these tests
    prove the failure counter reaches `exit`, not that `pwsh -File` carries the code out of the
    process. That half is Exit-Lab's (tools/LabCommon.psm1, issues #104 and #257), proven with
    real pwsh processes by tests/Exit-Code-Propagation.Tests.ps1.

    No subscription is needed, and none is used. The script runs through
    tests/Support/LabScriptStub.psm1 (issue #112), which imports the real modules first, the stub
    module last, and aborts the child with exit 99 unless every stubbed command resolves to the
    stub. Start-Sleep is stubbed too, so the 45-second lock propagation wait costs nothing.

.EXAMPLE
    Invoke-Pester -Path .\Remove-LabResource.Tests.ps1

.NOTES
    Project: SkyCraft
    Lab: 1.3 - Governance
#>

#Requires -Version 7.0
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..' '..' '..' 'tests' 'Support' 'LabScriptStub.psm1') -Force

    $script:ScriptPath     = (Resolve-Path (Join-Path $PSScriptRoot '..' 'scripts' 'Remove-LabResource.ps1')).Path
    $script:StubModuleName = 'SkyCraftLab13CleanupStub'
    # Exactly the script's '#Requires -Modules' line: these are imported for real before the stub.
    $script:RequiredModules = @('Az.Accounts', 'Az.Resources', 'Az.Monitor')

    $script:StubCommands = @(
        'Get-AzContext'
        'Get-AzResourceLock'
        'Remove-AzResourceLock'
        'Get-AzPolicyAssignment'
        'Remove-AzPolicyAssignment'
        'Invoke-AzRestMethod'
        'Get-AzActivityLogAlert'
        'Remove-AzActivityLogAlert'
        'Get-AzActionGroup'
        'Remove-AzActionGroup'
        'Start-Sleep'
    )

    # Every command the script calls, recording its own invocation. By default the subscription
    # holds everything the guide creates, plus an unrelated action group in prod-skycraft-swc-rg.
    # Environment variables change that, so one generated module serves every scenario:
    #   SKYCRAFT_STUB_EMPTY   '1' leaves nothing to find: every listing comes back empty
    #   SKYCRAFT_STUB_POLICYSET  who made the four policy assignments: 'bicep' (the default:
    #                         fixed names), 'portal' (generated names, the guide's names as
    #                         display names) or 'both' (two of each)
    #   SKYCRAFT_STUB_LOOKUP  '<lookup>=<kind>,...' makes one lookup fail (denied, throttled,
    #                         unprocessable: the 422 current subscriptions gave Az.Billing) or
    #                         report its resource group gone (rgnotfound)
    #   SKYCRAFT_STUB_FAIL    '<Remove-command>:<name>,...' makes one removal throw
    #   SKYCRAFT_STUB_LOCKELSEWHERE  resource groups whose own lock is missing, while a lock with
    #                         the same name sits on one of their resources and on the
    #                         subscription - both returned by the group's lock listing, as the
    #                         real cmdlet returns them
    # A lookup is named after its command and what it reads: 'Get-AzResourceLock:<rg>',
    # 'Get-AzPolicyAssignment:subscription', 'Get-RoleAssignment:subscription',
    # 'Get-Budget:<rg or subscription>',
    # 'Get-AzActivityLogAlert:<rg>', 'Get-AzActionGroup:<rg>'. A removal is logged both bare and
    # with the object's name, so the assertions can be generic or precise.
    $script:StubBody = @'
$script:LogPath = $env:SKYCRAFT_STUB_LOG

function Write-StubCall {
    param([string]$Name)
    if ($script:LogPath) { Add-Content -LiteralPath $script:LogPath -Value $Name }
}

function Test-StubEmpty { return $env:SKYCRAFT_STUB_EMPTY -eq '1' }

function Invoke-StubRemoval {
    param([string]$Command, [string]$Name)
    Write-StubCall -Name $Command
    Write-StubCall -Name "${Command}:$Name"
    if (@($env:SKYCRAFT_STUB_FAIL -split ',') -contains "${Command}:$Name") { throw "stub failure: ${Command} $Name" }
}

# How the lookup named here fails, if at all. The failure is reported with Write-Error, as the
# Az getters do, so the caller's -ErrorAction decides what happens to it. Returns $true when the
# lookup failed, so the stub returns nothing after it.
function Invoke-StubLookup {
    param([string]$Name)
    Write-StubCall -Name $Name
    $kind = foreach ($entry in @($env:SKYCRAFT_STUB_LOOKUP -split ',')) {
        $key, $value = $entry -split '=', 2
        if ($key -eq $Name) { $value }
    }
    switch ($kind) {
        'denied' {
            Write-Error -ErrorId 'AuthorizationFailed' -Message "The client 'stub' does not have authorization to perform action 'read' over scope '$Name' or the scope is invalid."
            return $true
        }
        'throttled' {
            Write-Error -ErrorId 'TooManyRequests' -Message "Number of 'read' requests exceeded the limit for $Name. Please try again after '17' seconds."
            return $true
        }
        'rgnotfound' {
            Write-Error -ErrorId 'ResourceGroupNotFound' -Message "Resource group 'prod-skycraft-swc-rg' could not be found."
            return $true
        }
        'unprocessable' {
            Write-Error -ErrorId '422' -Message 'This operation is not supported in the version specified in the request. Please use version 2018-12-01-preview or later.'
            return $true
        }
    }
    return $false
}

function Get-AzContext {
    [CmdletBinding()]
    param()
    [pscustomobject]@{
        Subscription = [pscustomobject]@{ Id = '00000000-0000-0000-0000-000000000000'; Name = 'stub-subscription' }
    }
}

function Get-AzResourceLock {
    [CmdletBinding()]
    param([string]$ResourceGroupName, [Parameter(ValueFromRemainingArguments)]$Rest)
    if (Invoke-StubLookup -Name "Get-AzResourceLock:$ResourceGroupName") { return }
    if (Test-StubEmpty) { return }
    $name = "lock-no-delete-$(($ResourceGroupName -split '-')[0])"
    $subscription = '/subscriptions/00000000-0000-0000-0000-000000000000'
    if (@($env:SKYCRAFT_STUB_LOCKELSEWHERE -split ',') -contains $ResourceGroupName) {
        $resourceLock = "$subscription/resourceGroups/$ResourceGroupName/providers/Microsoft.Storage/storageAccounts/stubsa/providers/Microsoft.Authorization/locks/$name"
        $subscriptionLock = "$subscription/providers/Microsoft.Authorization/locks/$name"
        foreach ($lockId in $resourceLock, $subscriptionLock) {
            [pscustomobject]@{ Name = $name; LockId = $lockId; ResourceId = $lockId }
        }
        return
    }
    # ARM does not keep the casing of ids stable ('resourcegroups' turns up as often as
    # 'resourceGroups'), so the prod lock comes back lower-cased: the match must not care.
    $lockId = if ($ResourceGroupName -like 'prod-*') {
        "$subscription/resourcegroups/$ResourceGroupName/providers/microsoft.authorization/locks/$name"
    } else {
        "$subscription/resourceGroups/$ResourceGroupName/providers/Microsoft.Authorization/locks/$name"
    }
    [pscustomobject]@{ Name = $name; LockId = $lockId; ResourceId = $lockId; ResourceGroupName = $ResourceGroupName }
}

function Remove-AzResourceLock {
    [CmdletBinding()]
    param([string]$ResourceGroupName, [string]$LockName, [switch]$Force)
    Invoke-StubRemoval -Command 'Remove-AzResourceLock' -Name $LockName
}

$script:PrincipalId = '11111111-1111-1111-1111-111111111111'

# Shaped like Get-AzPolicyAssignment's output in Az.Resources 7 and later; -Identity adds a
# system-assigned identity at the top level, as the real cmdlet returns it.
function New-StubAssignment {
    param([string]$Name, [string]$DisplayName, [string]$Definition, [string]$Scope, [switch]$Identity)
    $assignment = [pscustomobject]@{
        Name               = $Name
        DisplayName        = $DisplayName
        PolicyDefinitionId = "/providers/Microsoft.Authorization/policyDefinitions/$Definition"
        Scope              = $Scope
        Id                 = "$Scope/providers/Microsoft.Authorization/policyAssignments/$Name"
    }
    if ($Identity) {
        $assignment | Add-Member -NotePropertyName IdentityType -NotePropertyValue 'SystemAssigned'
        $assignment | Add-Member -NotePropertyName IdentityPrincipalId -NotePropertyValue $script:PrincipalId
    }
    $assignment
}

# Lists the assignments that apply to the subscription, as the real cmdlet does for -Scope with
# no -Name: the lab's four, made by the Bicep path, the Portal or both, plus one inherited from a
# management group under the guide's name and an unrelated one under a guide display name, which
# must both be left alone. Inherit-Project-Tag carries a system-assigned identity.
function Get-AzPolicyAssignment {
    [CmdletBinding()]
    param([string]$Name, [string]$Scope, [Parameter(ValueFromRemainingArguments)]$Rest)
    if (Invoke-StubLookup -Name 'Get-AzPolicyAssignment:subscription') { return }
    if ($Name) { throw "stub: the lab looks assignments up by listing the scope, not by name ($Name)" }
    if (Test-StubEmpty) { return }

    $lab = @(
        @{ Name = 'Require-Environment-Tag-RG'; Bicep = 'Require Environment Tag on Resource Groups'; Definition = '96670d01-0a4d-4649-9c89-2d3abc0a5025'; Portal = 'aaaaaaaaaaaaaaaaaaaaaaa1' }
        @{ Name = 'Enforce-Project-Tag'; Bicep = 'Enforce Project Tag Value'; Definition = '1e30110a-5ceb-460c-a204-c1c3969c6d62'; Portal = 'aaaaaaaaaaaaaaaaaaaaaaa2' }
        @{ Name = 'Inherit-Project-Tag'; Bicep = 'Inherit Project Tag from Resource Group'; Definition = 'ea3f2387-9b95-492a-a190-fcdc54f7b070'; Portal = 'aaaaaaaaaaaaaaaaaaaaaaa4'; Identity = $true }
        @{ Name = 'Restrict-Azure-Regions'; Bicep = 'Restrict to Allowed Regions'; Definition = 'e56962a6-4747-49cd-b67b-bf8b01975c4c'; Portal = 'aaaaaaaaaaaaaaaaaaaaaaa3' }
    )
    $set = if ($env:SKYCRAFT_STUB_POLICYSET) { $env:SKYCRAFT_STUB_POLICYSET } else { 'bicep' }
    foreach ($assignment in $lab) {
        $identity = [bool]$assignment.Identity
        if ($set -in 'bicep', 'both') {
            # Before main.bicep set managedIdentities to {} on them, the AVM default gave the
            # Bicep path's Deny assignments an identity too, each with its own principal and no role.
            if (-not $identity -and $env:SKYCRAFT_STUB_DENYIDENTITY -eq '1') {
                $old = New-StubAssignment -Name $assignment.Name -DisplayName $assignment.Bicep -Definition $assignment.Definition -Scope $Scope
                $old | Add-Member -NotePropertyName IdentityType -NotePropertyValue 'SystemAssigned'
                $old | Add-Member -NotePropertyName IdentityPrincipalId -NotePropertyValue "33333333-3333-3333-3333-00000000000$([array]::IndexOf($lab, $assignment))"
                $old
                continue
            }
            New-StubAssignment -Name $assignment.Name -DisplayName $assignment.Bicep -Definition $assignment.Definition -Scope $Scope -Identity:$identity
        }
        if ($set -in 'portal', 'both') {
            New-StubAssignment -Name $assignment.Portal -DisplayName $assignment.Name -Definition $assignment.Definition -Scope $Scope -Identity:$identity
        }
        # The Bicep and script paths since issue #406: fixed names, the guide's names as display names.
        if ($set -eq 'scripted') {
            New-StubAssignment -Name $assignment.Name -DisplayName $assignment.Name -Definition $assignment.Definition -Scope $Scope -Identity:$identity
        }
    }
    New-StubAssignment -Name 'Enforce-Project-Tag' -DisplayName 'Enforce Project Tag Value' -Definition '1e30110a-5ceb-460c-a204-c1c3969c6d62' `
        -Scope '/providers/Microsoft.Management/managementGroups/stub-mg'
    New-StubAssignment -Name 'bbbbbbbbbbbbbbbbbbbbbbb1' -DisplayName 'Restrict-Azure-Regions' -Definition '00000000-0000-0000-0000-00000000beef' -Scope $Scope
}

# Removes by full id, the one handle that names a Portal-made assignment and nothing else. The
# call is logged with the id's last segment (the resource name) and with its scope.
function Remove-AzPolicyAssignment {
    [CmdletBinding()]
    param([string]$Id, [string]$Name, [string]$Scope)
    if (-not $Id) { throw "stub: the lab removes an assignment by its id, not by name ($Name)" }
    $assignmentScope = $Id -replace '/providers/Microsoft\.Authorization/policyAssignments/[^/]+$', ''
    Write-StubCall -Name "Remove-AzPolicyAssignment@$assignmentScope"
    Invoke-StubRemoval -Command 'Remove-AzPolicyAssignment' -Name ($Id -split '/')[-1]
}

# Role assignments on the subscription: Inherit-Project-Tag's identity holds Contributor on the
# subscription (what the Portal grants it); another principal holds one too, and the identity
# holds one inherited from a management group - both must be left alone.
# Served through the ARM role assignments API fake appended to this body (issue #397). The cleanup
# lists the subscription's assignments once, unfiltered, so a principal filter here is a change
# of design the suite should hear about.
function Get-StubRoleAssignment {
    [CmdletBinding()]
    param([string]$Scope, [string]$PrincipalId)
    if ($PrincipalId) { throw "stub: the cleanup lists the subscription's role assignments once, not per principal ($PrincipalId)" }
    if (Invoke-StubLookup -Name 'Get-RoleAssignment:subscription') { return }
    if (Test-StubEmpty) { return }
    [pscustomobject]@{ Name = 'ra-identity-sub'; PrincipalId = $script:PrincipalId; Scope = $Scope; RoleDefinitionId = 'b24988ac-6180-42a0-ab88-20f7382dd24c'; PrincipalType = 'ServicePrincipal' }
    [pscustomobject]@{ Name = 'ra-other-sub'; PrincipalId = '22222222-2222-2222-2222-222222222222'; Scope = $Scope; RoleDefinitionId = 'b24988ac-6180-42a0-ab88-20f7382dd24c' }
    [pscustomobject]@{ Name = 'ra-identity-mg'; PrincipalId = $script:PrincipalId; Scope = '/providers/Microsoft.Management/managementGroups/stub-mg'; RoleDefinitionId = 'b24988ac-6180-42a0-ab88-20f7382dd24c'; PrincipalType = 'ServicePrincipal' }
}

# Removes the role assignment by the id the script listed, logged by its name (the id's last segment).
function Remove-StubRoleAssignment {
    [CmdletBinding()]
    param([string]$Id, [string]$Scope, [string]$Name)
    Invoke-StubRemoval -Command 'Remove-RoleAssignment' -Name $Name
}

# Budgets, served through the Consumption API fake appended to this body (issue #411). The ARM
# scope is logged as 'subscription' or the resource group's name; one under another subscription
# is a script bug.
function Get-StubBudgetScopeLabel {
    param([string]$Scope)
    if ($Scope -notlike '/subscriptions/00000000-0000-0000-0000-000000000000*') { throw "stub: budget scope outside the context's subscription ($Scope)" }
    if ($Scope -match '/resourceGroups/(?<rg>[^/]+)$') { return $Matches['rg'] }
    return 'subscription'
}

function Get-StubBudget {
    [CmdletBinding()]
    param([string]$Scope)
    $label = Get-StubBudgetScopeLabel -Scope $Scope
    if (Invoke-StubLookup -Name "Get-Budget:$label") { return }
    if (Test-StubEmpty) { return }
    if ($label -ne 'subscription') {
        [pscustomobject]@{ Name = 'SkyCraft-Prod-Monthly' }
    } else {
        # A subscription listing can hold budgets this lab did not create.
        [pscustomobject]@{ Name = 'SkyCraft-Monthly-Budget' }
        [pscustomobject]@{ Name = 'Someone-Elses-Budget' }
    }
}

function Remove-StubBudget {
    [CmdletBinding()]
    param([string]$Scope, [string]$Name)
    $label = Get-StubBudgetScopeLabel -Scope $Scope
    Write-StubCall -Name "Remove-Budget@${label}:$Name"
    Invoke-StubRemoval -Command 'Remove-Budget' -Name $Name
}

function Get-AzActivityLogAlert {
    [CmdletBinding()]
    param([string]$ResourceGroupName)
    if (Invoke-StubLookup -Name "Get-AzActivityLogAlert:$ResourceGroupName") { return }
    if (Test-StubEmpty) { return }
    [pscustomobject]@{ Name = 'Advisor-Cost-Recommendations' }
}

function Remove-AzActivityLogAlert {
    [CmdletBinding()]
    param([string]$ResourceGroupName, [string]$Name)
    Invoke-StubRemoval -Command 'Remove-AzActivityLogAlert' -Name $Name
}

function Get-AzActionGroup {
    [CmdletBinding()]
    param([string]$ResourceGroupName)
    if (Invoke-StubLookup -Name "Get-AzActionGroup:$ResourceGroupName") { return }
    if (Test-StubEmpty) { return }
    [pscustomobject]@{ Name = 'skycraft-advisor-ag' }
    # The name step 1.3.7 gave the action group before #225.
    [pscustomobject]@{ Name = 'prod-skycraft-swc-rg' }
    [pscustomobject]@{ Name = 'unrelated-ag' }
}

function Remove-AzActionGroup {
    [CmdletBinding()]
    param([string]$ResourceGroupName, [string]$Name)
    Invoke-StubRemoval -Command 'Remove-AzActionGroup' -Name $Name
}

function Start-Sleep {
    [CmdletBinding()]
    param([int]$Seconds)
    Write-StubCall -Name "Start-Sleep:$Seconds"
}
'@

    # Runs the real script in a child process with the stubs shadowing the Az commands, and
    # returns the exit code it hands back together with the stub's call log.
    function Invoke-CleanupScript {
        param(
            [pscustomobject]$Stub,
            [string[]]$Fail = @(),
            [string[]]$Lookup = @(),
            [string[]]$ArgumentList = @('-Force'),
            [string[]]$LockElsewhere = @(),
            [ValidateSet('bicep', 'portal', 'scripted', 'both')]
            [string]$PolicySet = 'bicep',
            [switch]$DenyIdentity,
            [switch]$Empty
        )

        $logPath = Join-Path $Stub.Directory 'calls.log'
        Remove-Item -LiteralPath $logPath -Force -ErrorAction SilentlyContinue

        $run = Invoke-LabScriptWithStub -Stub $Stub -ScriptPath $script:ScriptPath -ArgumentList $ArgumentList -Environment @{
            SKYCRAFT_STUB_FAIL   = $Fail -join ','
            SKYCRAFT_STUB_LOOKUP = $Lookup -join ','
            SKYCRAFT_STUB_EMPTY  = if ($Empty) { '1' } else { '0' }
            SKYCRAFT_STUB_LOCKELSEWHERE = $LockElsewhere -join ','
            SKYCRAFT_STUB_POLICYSET = $PolicySet
            SKYCRAFT_STUB_DENYIDENTITY = if ($DenyIdentity) { '1' } else { '0' }
            SKYCRAFT_STUB_LOG    = $logPath
        }

        $calls = if (Test-Path -LiteralPath $logPath) { @(Get-Content -LiteralPath $logPath) } else { @() }
        return [pscustomobject]@{
            ExitCode = $run.ExitCode
            Refused  = $run.Refused
            Output   = $run.Output
            Calls    = $calls
        }
    }

    $script:Stub    = Initialize-LabScriptStub -Name $script:StubModuleName -Command $script:StubCommands `
        -Body ($script:StubBody + (Get-LabArmStub -Api RoleAssignment, Budget)) -RequiredModule $script:RequiredModules
    $script:StubDir = $script:Stub.Directory

    # One invocation per scenario, reused by the assertions below - each child process costs
    # several seconds.
    $script:Clean   = Invoke-CleanupScript -Stub $script:Stub
    $script:Nothing = Invoke-CleanupScript -Stub $script:Stub -Empty
    $script:WhatIf  = Invoke-CleanupScript -Stub $script:Stub -ArgumentList '-WhatIf'
    # prod-skycraft-swc-rg is gone (a later lab's cleanup deleted it); the rest is in place.
    $script:ProdGone = Invoke-CleanupScript -Stub $script:Stub -Lookup @(
        'Get-AzResourceLock:prod-skycraft-swc-rg=rgnotfound'
        'Get-Budget:prod-skycraft-swc-rg=rgnotfound'
        'Get-AzActivityLogAlert:prod-skycraft-swc-rg=rgnotfound'
        'Get-AzActionGroup:prod-skycraft-swc-rg=rgnotfound'
    )
    $script:NewLookupsFail = Invoke-CleanupScript -Stub $script:Stub -Lookup @(
        'Get-Budget:subscription=denied'
        'Get-Budget:prod-skycraft-swc-rg=throttled'
        'Get-AzActivityLogAlert:prod-skycraft-swc-rg=denied'
        'Get-AzActionGroup:prod-skycraft-swc-rg=throttled'
    )
    # The service refuses both budget reads with the 422 Az.Billing met (#411).
    $script:BudgetReadsRefused = Invoke-CleanupScript -Stub $script:Stub -Lookup @(
        'Get-Budget:subscription=unprocessable'
        'Get-Budget:prod-skycraft-swc-rg=unprocessable'
    )
    $script:OldLookupsFail = Invoke-CleanupScript -Stub $script:Stub -Lookup @(
        'Get-AzResourceLock:prod-skycraft-swc-rg=denied'
        'Get-AzPolicyAssignment:subscription=throttled'
    )
    $script:NewRemovalsFail = Invoke-CleanupScript -Stub $script:Stub -Fail @(
        'Remove-Budget:SkyCraft-Monthly-Budget'
        'Remove-AzActivityLogAlert:Advisor-Cost-Recommendations'
        'Remove-AzActionGroup:skycraft-advisor-ag'
    )
    $script:OldRemovalsFail = Invoke-CleanupScript -Stub $script:Stub -Fail @(
        'Remove-AzResourceLock:lock-no-delete-prod'
        'Remove-AzPolicyAssignment:Restrict-Azure-Regions'
    )
    # The group's own lock is gone, but its listing still returns same-named locks on a resource
    # in it and on the subscription.
    $script:LockElsewhere = Invoke-CleanupScript -Stub $script:Stub -LockElsewhere 'platform-skycraft-swc-rg'
    # The learner made the three assignments in the Portal (#330), or in the Portal and again with
    # the Bicep path or Invoke-LabGovernance.ps1.
    $script:PortalMade = Invoke-CleanupScript -Stub $script:Stub -PolicySet 'portal'
    $script:TwoSets    = Invoke-CleanupScript -Stub $script:Stub -PolicySet 'both'
    $script:ScriptMade = Invoke-CleanupScript -Stub $script:Stub -PolicySet 'scripted'
    # The identity's role assignments cannot be listed, or one cannot be removed (#350).
    $script:RoleLookupFails  = Invoke-CleanupScript -Stub $script:Stub -Lookup 'Get-RoleAssignment:subscription=throttled'
    $script:RoleRemovalFails = Invoke-CleanupScript -Stub $script:Stub -PolicySet 'portal' -Fail 'Remove-RoleAssignment:ra-identity-sub'
    # The Bicep path's Deny assignments from before main.bicep set managedIdentities to {} carry
    # identities with no role: removed like the others, or kept with the rest when the role
    # assignments cannot be listed.
    $script:DenyIdentity           = Invoke-CleanupScript -Stub $script:Stub -DenyIdentity
    $script:DenyIdentityRoleFails  = Invoke-CleanupScript -Stub $script:Stub -DenyIdentity -Lookup 'Get-RoleAssignment:subscription=throttled'

    $script:AllRuns = @(
        $script:Clean, $script:Nothing, $script:WhatIf, $script:ProdGone, $script:NewLookupsFail,
        $script:BudgetReadsRefused, $script:OldLookupsFail, $script:NewRemovalsFail, $script:OldRemovalsFail, $script:LockElsewhere,
        $script:PortalMade, $script:ScriptMade, $script:TwoSets, $script:RoleLookupFails, $script:RoleRemovalFails,
        $script:DenyIdentity, $script:DenyIdentityRoleFails
    )
}

AfterAll {
    if ($script:StubDir) { Remove-Item -LiteralPath $script:StubDir -Recurse -Force -ErrorAction SilentlyContinue }
}

Describe 'Lab 1.3 Remove-LabResource.ps1 - test harness' {

    It 'shadows the real Az commands instead of touching a subscription' {
        # Refused is the child exiting 99 before the script ran. Asserted on every scenario: a
        # refusal in one of them is a half-stubbed session, not a scenario-specific failure.
        foreach ($run in $script:AllRuns) {
            $run.Refused | Should -BeFalse -Because "the harness must never fall through to the real Az commands (exit $($run.ExitCode)): $($run.Output)"
        }
    }
}

Describe 'Lab 1.3 Remove-LabResource.ps1 - removes everything the guide creates (#252)' {

    It 'exits 0 when every object is found and removed' {
        $script:Clean.ExitCode | Should -Be 0 -Because "a clean teardown must report success; output was:`n$($script:Clean.Output)"
        $script:Clean.Output   | Should -Match 'Cleanup complete'
        $script:Clean.Output   | Should -Not -Match '\[ERROR\]'
    }

    It 'still removes both locks and all four policy assignments' {
        foreach ($call in 'Remove-AzResourceLock:lock-no-delete-prod', 'Remove-AzResourceLock:lock-no-delete-platform',
                'Remove-AzPolicyAssignment:Require-Environment-Tag-RG', 'Remove-AzPolicyAssignment:Enforce-Project-Tag',
                'Remove-AzPolicyAssignment:Inherit-Project-Tag', 'Remove-AzPolicyAssignment:Restrict-Azure-Regions') {
            $script:Clean.Calls | Should -Contain $call
        }
    }

    It 'removes the subscription budget from the subscription (step 1.3.15)' {
        $script:Clean.Calls  | Should -Contain 'Remove-Budget@subscription:SkyCraft-Monthly-Budget'
        $script:Clean.Output | Should -Match '\[SUCCESS\] Removed budget: SkyCraft-Monthly-Budget'
    }

    It 'removes the resource group budget from prod-skycraft-swc-rg (step 1.3.17)' {
        $script:Clean.Calls  | Should -Contain 'Remove-Budget@prod-skycraft-swc-rg:SkyCraft-Prod-Monthly'
        $script:Clean.Output | Should -Match '\[SUCCESS\] Removed budget: SkyCraft-Prod-Monthly'
    }

    It 'leaves a budget the lab did not create alone' {
        $script:Clean.Calls | Should -Not -Contain 'Remove-Budget:Someone-Elses-Budget'
    }

    It 'removes the Advisor alert (step 1.3.7)' {
        $script:Clean.Calls  | Should -Contain 'Remove-AzActivityLogAlert:Advisor-Cost-Recommendations'
        $script:Clean.Output | Should -Match '\[SUCCESS\] Removed Advisor alert: Advisor-Cost-Recommendations'
    }

    It 'removes the action group, under its current name and the one used before #225' {
        $script:Clean.Calls  | Should -Contain 'Remove-AzActionGroup:skycraft-advisor-ag'
        $script:Clean.Calls  | Should -Contain 'Remove-AzActionGroup:prod-skycraft-swc-rg'
        $script:Clean.Output | Should -Match '\[SUCCESS\] Removed action group: skycraft-advisor-ag'
    }

    It 'leaves an unrelated action group in the same resource group alone' {
        $script:Clean.Calls | Should -Not -Contain 'Remove-AzActionGroup:unrelated-ag'
    }

    It 'removes the Advisor alert before its action group, and both after the locks' {
        $calls = $script:Clean.Calls
        $lock  = [array]::LastIndexOf($calls, 'Remove-AzResourceLock:lock-no-delete-prod')
        $sleep = [array]::IndexOf($calls, 'Start-Sleep:45')
        $alert = [array]::IndexOf($calls, 'Remove-AzActivityLogAlert:Advisor-Cost-Recommendations')
        $group = [array]::IndexOf($calls, 'Remove-AzActionGroup:skycraft-advisor-ag')
        $rgBudget = [array]::IndexOf($calls, 'Remove-Budget:SkyCraft-Prod-Monthly')
        $sleep    | Should -BeGreaterThan $lock
        $rgBudget | Should -BeGreaterThan $sleep
        $alert    | Should -BeGreaterThan $sleep
        $group    | Should -BeGreaterThan $alert
    }
}

Describe 'Lab 1.3 Remove-LabResource.ps1 - removes the policy assignments whichever path made them (#330)' {

    It 'removes the Portal-made assignments, found by the display names the learner typed' {
        # The Portal's Assignment name sets only the display name; the resource name is generated,
        # so a lookup by name reported them absent and left two deny policies on the subscription.
        $run = $script:PortalMade
        $run.ExitCode | Should -Be 0 -Because "output was:`n$($run.Output)"
        foreach ($name in 'aaaaaaaaaaaaaaaaaaaaaaa1', 'aaaaaaaaaaaaaaaaaaaaaaa2', 'aaaaaaaaaaaaaaaaaaaaaaa3', 'aaaaaaaaaaaaaaaaaaaaaaa4') {
            $run.Calls | Should -Contain "Remove-AzPolicyAssignment:$name"
        }
        $run.Output | Should -Match "\[SUCCESS\] Removed policy: Enforce-Project-Tag 'Enforce-Project-Tag' \(name aaaaaaaaaaaaaaaaaaaaaaa2\)"
        $run.Output | Should -Not -Match 'Policy [^ ]+ not found'
    }

    It 'removes the assignments the Bicep and script paths make since #406: fixed names, the guide''s display names' {
        $run = $script:ScriptMade
        $run.ExitCode | Should -Be 0 -Because "output was:`n$($run.Output)"
        foreach ($name in 'Require-Environment-Tag-RG', 'Enforce-Project-Tag', 'Inherit-Project-Tag', 'Restrict-Azure-Regions') {
            $run.Calls | Should -Contain "Remove-AzPolicyAssignment:$name"
        }
        $run.Output | Should -Not -Match 'Policy [^ ]+ not found'
    }

    It 'removes from the subscription only, and leaves an inherited or unrelated assignment alone' {
        foreach ($run in $script:Clean, $script:PortalMade) {
            @($run.Calls | Where-Object { $_ -like 'Remove-AzPolicyAssignment@*' }) |
                Should -Be (@('Remove-AzPolicyAssignment@/subscriptions/00000000-0000-0000-0000-000000000000') * 4)
            $run.Calls | Should -Not -Contain 'Remove-AzPolicyAssignment:bbbbbbbbbbbbbbbbbbbbbbb1'
        }
    }

    It 'lists the subscription''s assignments once, rather than reading each by name' {
        @($script:Clean.Calls | Where-Object { $_ -eq 'Get-AzPolicyAssignment:subscription' }).Count | Should -Be 1
    }

    It 'refuses to remove an assignment made twice, names both, and exits 1' {
        # Which of the two the learner meant cannot be told; removing one and reporting success
        # would leave the other in force.
        $run = $script:TwoSets
        $run.ExitCode | Should -Be 1 -Because "output was:`n$($run.Output)"
        $run.Calls | Should -Not -Contain 'Remove-AzPolicyAssignment'
        $run.Output | Should -Match "\[ERROR\] 2 assignments match Enforce-Project-Tag: 'Enforce Project Tag Value' \(name Enforce-Project-Tag\), 'Enforce-Project-Tag' \(name aaaaaaaaaaaaaaaaaaaaaaa2\)\. Removing none of them"
        $run.Output | Should -Match 'Cleanup finished with 4 failure\(s\)'
        $run.Calls | Should -Contain 'Remove-Budget:SkyCraft-Monthly-Budget'
        # Neither Inherit-Project-Tag is removed, so neither identity's role is either.
        $run.Calls | Should -Not -Contain 'Remove-RoleAssignment'
    }
}

Describe 'Lab 1.3 Remove-LabResource.ps1 - removes Inherit-Project-Tag after its identity''s role (#350)' {

    It 'removes the identity''s role assignment on the subscription before the assignment' {
        foreach ($run in $script:Clean, $script:PortalMade) {
            $run.ExitCode | Should -Be 0 -Because "output was:`n$($run.Output)"
            $role = [array]::IndexOf($run.Calls, 'Remove-RoleAssignment:ra-identity-sub')
            $policy = [array]::IndexOf($run.Calls, $(if ($run -eq $script:Clean) { 'Remove-AzPolicyAssignment:Inherit-Project-Tag' } else { 'Remove-AzPolicyAssignment:aaaaaaaaaaaaaaaaaaaaaaa4' }))
            $role | Should -BeGreaterThan -1
            $policy | Should -BeGreaterThan $role -Because 'removed after the assignment, the role assignment would stay behind for an unknown identity'
        }
        $script:Clean.Output | Should -Match '\[SUCCESS\] Removed role assignment: Contributor at /subscriptions/00000000-0000-0000-0000-000000000000 for the identity of Inherit-Project-Tag'
    }

    It 'leaves another principal''s role assignment and one inherited from a management group alone' {
        @($script:Clean.Calls | Where-Object { $_ -like 'Remove-RoleAssignment:*' }) | Should -Be @('Remove-RoleAssignment:ra-identity-sub')
    }

    It 'lists the role assignments once, by scope, through the ARM API (#397)' {
        @($script:Clean.Calls | Where-Object { $_ -eq 'Get-RoleAssignment:subscription' }).Count | Should -Be 1
    }

    It 'keeps Inherit-Project-Tag when its identity''s role assignments cannot be listed, and exits 1' {
        $run = $script:RoleLookupFails
        $run.ExitCode | Should -Be 1 -Because "output was:`n$($run.Output)"
        $run.Output | Should -Match '\[ERROR\] Could not look up the role assignments on the subscription'
        $run.Output | Should -Match 'Keeping policy Inherit-Project-Tag'
        $run.Calls  | Should -Not -Contain 'Remove-AzPolicyAssignment:Inherit-Project-Tag'
        $run.Calls  | Should -Contain 'Remove-AzPolicyAssignment:Enforce-Project-Tag'
        $run.Output | Should -Match 'Cleanup finished with 1 failure\(s\)'
    }

    It 'keeps Inherit-Project-Tag when its identity''s role assignment cannot be removed, and exits 1' {
        $run = $script:RoleRemovalFails
        $run.ExitCode | Should -Be 1 -Because "output was:`n$($run.Output)"
        $run.Output | Should -Match '\[ERROR\] Failed to remove role assignment Contributor at /subscriptions/00000000-0000-0000-0000-000000000000 for the identity of Inherit-Project-Tag'
        $run.Calls  | Should -Not -Contain 'Remove-AzPolicyAssignment:aaaaaaaaaaaaaaaaaaaaaaa4'
        $run.Calls  | Should -Contain 'Remove-AzPolicyAssignment:aaaaaaaaaaaaaaaaaaaaaaa2'
        $run.Output | Should -Match 'Cleanup finished with 1 failure\(s\)'
    }

    It 'removes the older Bicep path''s Deny assignments that carry an identity with no role' {
        $run = $script:DenyIdentity
        $run.ExitCode | Should -Be 0 -Because "output was:`n$($run.Output)"
        foreach ($name in 'Require-Environment-Tag-RG', 'Enforce-Project-Tag', 'Inherit-Project-Tag', 'Restrict-Azure-Regions') {
            $run.Calls | Should -Contain "Remove-AzPolicyAssignment:$name"
        }
        @($run.Calls | Where-Object { $_ -like 'Remove-RoleAssignment:*' }) | Should -Be @('Remove-RoleAssignment:ra-identity-sub')
        @($run.Calls | Where-Object { $_ -eq 'Get-RoleAssignment:subscription' }).Count | Should -Be 1
    }

    It 'keeps every assignment with an identity, the older Bicep path''s Deny ones included, when the role assignments cannot be listed, and exits 1' {
        $run = $script:DenyIdentityRoleFails
        $run.ExitCode | Should -Be 1 -Because "output was:`n$($run.Output)"
        foreach ($name in 'Require-Environment-Tag-RG', 'Enforce-Project-Tag', 'Inherit-Project-Tag', 'Restrict-Azure-Regions') {
            $run.Calls  | Should -Not -Contain "Remove-AzPolicyAssignment:$name"
            $run.Output | Should -Match "Keeping policy $name"
        }
        # One failed listing, counted once, however many assignments it keeps.
        $run.Output | Should -Match 'Cleanup finished with 1 failure\(s\)'
    }
}

Describe 'Lab 1.3 Remove-LabResource.ps1 - only the lock on the group itself is the guide lock' {

    It 'matches the lock id at the group scope regardless of its casing' {
        # The stub returns the prod lock with a lower-cased id ('resourcegroups').
        $script:Clean.Calls | Should -Contain 'Remove-AzResourceLock:lock-no-delete-prod'
    }

    It 'does not take a same-named lock on a resource or on the subscription for the group lock' {
        $run = $script:LockElsewhere
        $run.ExitCode | Should -Be 0 -Because "a lock elsewhere is not the guide's lock; output was:`n$($run.Output)"
        $run.Output | Should -Match 'Lock lock-no-delete-platform not found'
        $run.Output | Should -Not -Match '\[ERROR\]'
        $run.Calls  | Should -Not -Contain 'Remove-AzResourceLock:lock-no-delete-platform'
        $run.Calls  | Should -Contain 'Remove-AzResourceLock:lock-no-delete-prod'
    }
}

Describe 'Lab 1.3 Remove-LabResource.ps1 - an absent object is not a failure (#252)' {

    It 'exits 0 and removes nothing when nothing is there' {
        $run = $script:Nothing
        $run.ExitCode | Should -Be 0 -Because "nothing to remove is a clean teardown; output was:`n$($run.Output)"
        $run.Output | Should -Not -Match '\[ERROR\]'
        $run.Output | Should -Match 'Cleanup complete'
        @($run.Calls | Where-Object { $_ -match '^Remove-' }) | Should -BeNullOrEmpty
    }

    It 'reports each absent object as not found' {
        $run = $script:Nothing
        $run.Output | Should -Match 'Lock lock-no-delete-prod not found'
        $run.Output | Should -Match 'Policy Enforce-Project-Tag not found'
        $run.Output | Should -Match 'Budget SkyCraft-Monthly-Budget not found'
        $run.Output | Should -Match 'Budget SkyCraft-Prod-Monthly not found'
        $run.Output | Should -Match 'Advisor alert Advisor-Cost-Recommendations not found'
        $run.Output | Should -Match 'Action group skycraft-advisor-ag not found'
    }

    It 'does not wait for lock propagation when no lock was removed' {
        $script:Nothing.Calls | Should -Not -Contain 'Start-Sleep:45'
        $script:Clean.Calls   | Should -Contain 'Start-Sleep:45'
    }

    It 'exits 0 when prod-skycraft-swc-rg is already gone, and still cleans up the rest' {
        $run = $script:ProdGone
        $run.ExitCode | Should -Be 0 -Because "a group that is gone holds nothing to remove; output was:`n$($run.Output)"
        $run.Output | Should -Not -Match '\[ERROR\]'
        $run.Calls  | Should -Not -Contain 'Remove-AzResourceLock:lock-no-delete-prod'
        $run.Calls  | Should -Not -Contain 'Remove-Budget:SkyCraft-Prod-Monthly'
        $run.Calls  | Should -Not -Contain 'Remove-AzActivityLogAlert'
        $run.Calls  | Should -Not -Contain 'Remove-AzActionGroup'
        $run.Calls  | Should -Contain 'Remove-AzResourceLock:lock-no-delete-platform'
        $run.Calls  | Should -Contain 'Remove-Budget:SkyCraft-Monthly-Budget'
    }
}

Describe 'Lab 1.3 Remove-LabResource.ps1 - a failed lookup is not "absent" (#252)' {

    It 'exits 1 and counts each budget, alert and action group lookup that failed' {
        $run = $script:NewLookupsFail
        $run.ExitCode | Should -Be 1 -Because "an object that may still exist must not look like a clean cleanup; output was:`n$($run.Output)"
        $run.Output | Should -Match '\[ERROR\] Could not look up budget SkyCraft-Monthly-Budget on the subscription[^\r\n]*does not have authorization'
        $run.Output | Should -Match '\[ERROR\] Could not look up budget SkyCraft-Prod-Monthly on prod-skycraft-swc-rg[^\r\n]*requests exceeded the limit'
        $run.Output | Should -Match '\[ERROR\] Could not look up Advisor alert Advisor-Cost-Recommendations in prod-skycraft-swc-rg'
        $run.Output | Should -Match '\[ERROR\] Could not look up the action groups in prod-skycraft-swc-rg'
        $run.Output | Should -Match 'Cleanup finished with 4 failure\(s\)'
        $run.Output | Should -Not -Match 'Cleanup complete'
        $run.Output | Should -Not -Match 'Budget SkyCraft-Monthly-Budget not found'
    }

    It 'prints the HTTP status and the service''s message of each failed budget read (#411)' {
        $run = $script:NewLookupsFail
        $run.Output | Should -Match '\[ERROR\] Could not look up budget SkyCraft-Monthly-Budget on the subscription: ARM GET /subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft\.Consumption/budgets returned HTTP 403 \(AuthorizationFailed\)'
        $run.Output | Should -Match '\[ERROR\] Could not look up budget SkyCraft-Prod-Monthly on prod-skycraft-swc-rg: ARM GET /subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/prod-skycraft-swc-rg/providers/Microsoft\.Consumption/budgets returned HTTP 429 \(TooManyRequests\)'
    }

    It 'points each failed budget read to the Portal, and nothing else' {
        $hints = [regex]::Matches($script:NewLookupsFail.Output, 'Check Cost Management > Budgets in the Portal')
        $hints.Count | Should -Be 2 -Because 'each failed budget read carries the pointer, and nothing else does'
        $script:OldLookupsFail.Output | Should -Not -Match 'Cost Management'
    }

    It 'counts a 422 on both budget reads, with the service''s message, and guesses no cause it does not give (#411)' {
        $run = $script:BudgetReadsRefused
        $run.ExitCode | Should -Be 1 -Because "output was:`n$($run.Output)"
        $run.Output | Should -Match 'Could not look up budget SkyCraft-Monthly-Budget on the subscription: [^\r\n]*HTTP 422 \(422\): This operation is not supported in the version specified in the request\. Please use version 2018-12-01-preview or later\.'
        $run.Output | Should -Match 'Could not look up budget SkyCraft-Prod-Monthly on prod-skycraft-swc-rg: [^\r\n]*HTTP 422'
        $run.Output | Should -Match 'Cleanup finished with 2 failure\(s\)'
        $run.Output | Should -Not -Match 'Budget SkyCraft-[A-Za-z-]+ not found'
        $run.Output | Should -Not -Match 'Azure for Students|Sponsorship|without Cost Management|Cost Management is unavailable' -Because 'the message names the API version, not the offer (R5)'
        $run.Calls  | Should -Not -Contain 'Remove-Budget'
    }

    It 'removes nothing it could not look up, and still runs every other step' {
        $run = $script:NewLookupsFail
        $run.Calls | Should -Not -Contain 'Remove-Budget'
        $run.Calls | Should -Not -Contain 'Remove-AzActivityLogAlert'
        $run.Calls | Should -Not -Contain 'Remove-AzActionGroup'
        $run.Calls | Should -Contain 'Remove-AzResourceLock:lock-no-delete-prod'
        $run.Calls | Should -Contain 'Remove-AzPolicyAssignment:Restrict-Azure-Regions'
    }

    It 'counts a lock or policy lookup that failed, which it used to read as "not found"' {
        $run = $script:OldLookupsFail
        $run.ExitCode | Should -Be 1 -Because "output was:`n$($run.Output)"
        $run.Output | Should -Match '\[ERROR\] Could not look up lock lock-no-delete-prod on prod-skycraft-swc-rg'
        $run.Output | Should -Match '\[ERROR\] Could not look up the policy assignments on the subscription'
        $run.Output | Should -Not -Match 'Lock lock-no-delete-prod not found'
        $run.Output | Should -Not -Match 'Policy [^ ]+ not found'
        $run.Output | Should -Match 'Cleanup finished with 2 failure\(s\)'
        $run.Calls  | Should -Not -Contain 'Remove-AzResourceLock:lock-no-delete-prod'
        $run.Calls  | Should -Not -Contain 'Remove-AzPolicyAssignment'
        $run.Calls  | Should -Contain 'Remove-AzActionGroup:skycraft-advisor-ag'
    }
}

Describe 'Lab 1.3 Remove-LabResource.ps1 - a failed removal is counted (#252)' {

    It 'exits 1 and counts each budget, alert and action group it could not remove' {
        $run = $script:NewRemovalsFail
        $run.ExitCode | Should -Be 1 -Because "a stuck object must not look like a clean cleanup; output was:`n$($run.Output)"
        $run.Output | Should -Match '\[ERROR\] Failed to remove budget SkyCraft-Monthly-Budget'
        $run.Output | Should -Match '\[ERROR\] Failed to remove Advisor alert Advisor-Cost-Recommendations'
        $run.Output | Should -Match '\[ERROR\] Failed to remove action group skycraft-advisor-ag'
        $run.Output | Should -Match 'Cleanup finished with 3 failure\(s\)'
        $run.Output | Should -Not -Match 'Cleanup complete'
    }

    It 'keeps going after a failed removal' {
        $run = $script:NewRemovalsFail
        $run.Calls | Should -Contain 'Remove-Budget:SkyCraft-Prod-Monthly'
        $run.Calls | Should -Contain 'Remove-AzActionGroup:skycraft-advisor-ag'
        $run.Calls | Should -Contain 'Remove-AzActionGroup:prod-skycraft-swc-rg'
    }

    It 'exits 1 when a lock or a policy assignment cannot be removed, which it used to report as success' {
        $run = $script:OldRemovalsFail
        $run.ExitCode | Should -Be 1 -Because "output was:`n$($run.Output)"
        $run.Output | Should -Match '\[ERROR\] Failed to remove lock lock-no-delete-prod'
        $run.Output | Should -Match '\[ERROR\] Failed to remove policy Restrict-Azure-Regions'
        $run.Output | Should -Match 'Cleanup finished with 2 failure\(s\)'
        $run.Calls  | Should -Contain 'Remove-AzActivityLogAlert:Advisor-Cost-Recommendations'
    }
}

Describe 'Lab 1.3 Remove-LabResource.ps1 - -WhatIf' {

    It 'looks everything up, removes nothing and does not wait' {
        $run = $script:WhatIf
        $run.ExitCode | Should -Be 0 -Because "output was:`n$($run.Output)"
        @($run.Calls | Where-Object { $_ -match '^(Remove-|Start-Sleep)' }) | Should -BeNullOrEmpty
        $run.Calls  | Should -Contain 'Get-Budget:subscription'
        $run.Calls  | Should -Contain 'Get-AzActionGroup:prod-skycraft-swc-rg'
        $run.Output | Should -Match 'What if: .*SkyCraft-Monthly-Budget'
        $run.Output | Should -Match 'What if: .*Advisor-Cost-Recommendations'
    }
}

Describe 'Lab 1.3 Remove-LabResource.ps1 - which lookup errors mean "not found"' {

    BeforeAll {
        # Lift the helpers with the parser: the script body never runs, so nothing is looked up.
        $parseError = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($script:ScriptPath, [ref]$null, [ref]$parseError)
        if ($parseError) { throw "Remove-LabResource.ps1 does not parse: $($parseError[0].Message)" }
        $script:LiftedName = @()
        foreach ($function in $ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $false)) {
            . ([scriptblock]::Create($function.Extent.Text))
            $script:LiftedName += $function.Name
        }

        # The errors the LabCommon budget helper raises (#411), made by the helper itself from a
        # canned ARM reply, so a change to their wording is seen here.
        $script:LabCommon = Import-Module (Join-Path $PSScriptRoot '..' '..' '..' 'tools' 'LabCommon.psm1') -Force -PassThru
        function global:Invoke-AzRestMethod {
            [CmdletBinding()]
            param([string]$Path, [string]$Method = 'GET', [string]$Payload)
            $global:SkyCraftLab13ArmReply
        }
        function Get-HelperErrorFixture {
            param([int]$StatusCode, [string]$Code, [string]$Message)
            $global:SkyCraftLab13ArmReply = [pscustomobject]@{
                StatusCode = $StatusCode
                Content    = @{ error = @{ code = $Code; message = $Message } } | ConvertTo-Json -Compress
            }
            try { Get-LabArmBudget -Scope '/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/prod-skycraft-swc-rg' | Out-Null }
            catch { return $_ }
            throw 'Get-LabArmBudget did not throw on an error reply'
        }

        # The shape of the SDK exceptions the Az getters raise: the ARM error code in Body and the
        # status in Response (older Az SDK exceptions), ResponseStatusCode (generated cmdlets) or
        # HttpStatus (Get-AzResourceLock).
        if (-not ('SkyCraftLab13StubAzureException' -as [type])) {
            Add-Type -TypeDefinition @'
public class SkyCraftLab13StubAzureException : System.Exception
{
    public SkyCraftLab13StubAzureException(string message) : base(message) { }
    public object Body { get; set; }
    public object Response { get; set; }
    public object ResponseStatusCode { get; set; }
    public object HttpStatus { get; set; }
}
'@
        }

        function Get-LookupErrorFixture {
            param(
                [string]$Message = 'Operation failed.',
                [string]$ErrorId = 'StubError',
                [string]$Code,
                [object]$StatusCode,
                [object]$ResponseStatusCode,
                [object]$HttpStatus
            )
            $exception = [SkyCraftLab13StubAzureException]::new($Message)
            if ($Code) { $exception.Body = [pscustomobject]@{ Code = $Code } }
            if ($null -ne $StatusCode) { $exception.Response = [pscustomobject]@{ StatusCode = $StatusCode } }
            if ($null -ne $ResponseStatusCode) { $exception.ResponseStatusCode = $ResponseStatusCode }
            if ($null -ne $HttpStatus) { $exception.HttpStatus = $HttpStatus }
            [System.Management.Automation.ErrorRecord]::new($exception, $ErrorId, 'InvalidOperation', $null)
        }
    }

    AfterAll {
        Remove-Item -Path Function:\Invoke-AzRestMethod -ErrorAction SilentlyContinue
        Remove-Variable -Name SkyCraftLab13ArmReply -Scope Global -ErrorAction SilentlyContinue
        if ($script:LabCommon) { Remove-Module -ModuleInfo $script:LabCommon -Force -ErrorAction SilentlyContinue }
    }

    It 'lifts Test-LabNotFoundError and Invoke-LabLookup out of the script' {
        $script:LiftedName | Should -Contain 'Test-LabNotFoundError'
        $script:LiftedName | Should -Contain 'Invoke-LabLookup'
    }

    It 'reads <Shape> as not found' -ForEach @(
        @{ Shape  = 'a policy assignment that is not assigned (PolicyAssignmentNotFound)'
           Record = { Get-LookupErrorFixture -ErrorId 'PolicyAssignmentNotFound,Get-AzPolicyAssignment' -Message "The policy assignment 'Enforce-Project-Tag' is not found." } }
        @{ Shape  = 'the PolicyAssignmentNotFound code in the message only'
           Record = { Get-LookupErrorFixture -Message "PolicyAssignmentNotFound : The policy assignment 'Enforce-Project-Tag' is not found." } }
        @{ Shape  = 'a resource group that is gone (ResourceGroupNotFound message)'
           Record = { Get-LookupErrorFixture -Message "Resource group 'prod-skycraft-swc-rg' could not be found." } }
        @{ Shape  = 'a 404 HttpStatus (Get-AzResourceLock)'
           Record = { Get-LookupErrorFixture -HttpStatus ([System.Net.HttpStatusCode]::NotFound) } }
        @{ Shape  = 'a 404 on the response with no error body (older Az SDK exceptions)'
           Record = { Get-LookupErrorFixture -StatusCode ([System.Net.HttpStatusCode]::NotFound) -Message "Operation returned an invalid status code 'NotFound'" } }
        @{ Shape  = 'a 404 on a generated cmdlet RestException (Get-AzActionGroup)'
           Record = { Get-LookupErrorFixture -ResponseStatusCode ([System.Net.HttpStatusCode]::NotFound) } }
        @{ Shape  = 'a budget read on a resource group that is gone (Get-LabArmBudget, HTTP 404 ResourceGroupNotFound)'
           Record = { Get-HelperErrorFixture -StatusCode 404 -Code 'ResourceGroupNotFound' -Message "Resource group 'prod-skycraft-swc-rg' could not be found." } }
    ) {
        Test-LabNotFoundError -ErrorRecord (& $Record) | Should -BeTrue
    }

    It 'reads <Shape> as a failed lookup' -ForEach @(
        @{ Shape  = 'a 403 AuthorizationFailed'
           Record = { Get-LookupErrorFixture -ErrorId 'AuthorizationFailed' -Code 'AuthorizationFailed' -StatusCode ([System.Net.HttpStatusCode]::Forbidden) -Message "The client 'stub' does not have authorization to perform action 'Microsoft.Consumption/budgets/read' over scope '/subscriptions/0' or the scope is invalid." } }
        @{ Shape  = 'a 403 HttpStatus (Get-AzResourceLock)'
           Record = { Get-LookupErrorFixture -HttpStatus ([System.Net.HttpStatusCode]::Forbidden) } }
        @{ Shape  = 'a 429 throttling response'
           Record = { Get-LookupErrorFixture -ErrorId 'TooManyRequests' -ResponseStatusCode 429 -Message "Number of 'read' requests exceeded. Please try again after '17' seconds." } }
        @{ Shape  = 'a transient transport error'
           Record = { Get-LookupErrorFixture -Message 'An error occurred while sending the request.' } }
        @{ Shape  = 'a missing subscription, although ARM answers it with 404'
           Record = { Get-LookupErrorFixture -Code 'SubscriptionNotFound' -StatusCode ([System.Net.HttpStatusCode]::NotFound) -Message "The subscription '00000000-0000-0000-0000-000000000000' could not be found." } }
        @{ Shape  = 'a budget read the service refuses for its API version (Get-LabArmBudget, HTTP 422)'
           Record = { Get-HelperErrorFixture -StatusCode 422 -Code '422' -Message 'This operation is not supported in the version specified in the request. Please use version 2018-12-01-preview or later.' } }
        @{ Shape  = 'a budget read without permission (Get-LabArmBudget, HTTP 403)'
           Record = { Get-HelperErrorFixture -StatusCode 403 -Code 'AuthorizationFailed' -Message "The client 'stub' does not have authorization to perform action 'Microsoft.Consumption/budgets/read'." } }
        @{ Shape  = 'a budget read on a missing subscription (Get-LabArmBudget, HTTP 404 SubscriptionNotFound)'
           Record = { Get-HelperErrorFixture -StatusCode 404 -Code 'SubscriptionNotFound' -Message "The subscription '00000000-0000-0000-0000-000000000000' could not be found." } }
    ) {
        Test-LabNotFoundError -ErrorRecord (& $Record) | Should -BeFalse
    }
}

<#
.SYNOPSIS
    Pester 5 tests for the Lab 1.3 imperative deployment's policy assignment step.

.DESCRIPTION
    Regression cover for issue #330. Invoke-LabGovernance.ps1 checked whether each policy
    assignment existed by its resource name. A learner who made the assignments in the Portal has
    them under generated names, so a run after the Portal pass created a second set next to the
    first, and Remove-LabResource.ps1 could then tell neither apart. These tests run the real
    script in a child pwsh process against a generated stub of the Az commands it calls, and
    assert the contract of the policy step:

      1. With no assignment on the subscription, it creates the four, under the fixed names and
         display names the Bicep path uses, from the built-in definitions read by id; the Modify
         assignment Inherit-Project-Tag (issue #350) with a system-assigned identity in
         swedencentral.
      2. With the four already made - by the Bicep path, or in the Portal under generated names
         - it creates nothing and says each one is already assigned.
      3. With an assignment made twice, it creates nothing for it and reports an [ERROR] that
         names both.
      4. When the listing fails, it creates nothing: an assignment it could not see may exist.
      5. The identity of Inherit-Project-Tag gets Contributor on the subscription, as the Portal
         gives it, unless it holds it there already; an existing Inherit-Project-Tag without an
         identity is an [ERROR]. Role assignments are listed by scope, never with -ObjectId.

    The tags and locks steps are left to their own behaviour; their stubs only make them run.

    No subscription is needed, and none is used. The script runs through
    tests/Support/LabScriptStub.psm1 (issue #112), which imports the real modules first, the stub
    module last, and aborts the child with exit 99 unless every stubbed command resolves to the
    stub.

.EXAMPLE
    Invoke-Pester -Path .\Invoke-LabGovernance.Tests.ps1

.NOTES
    Project: SkyCraft
    Lab: 1.3 - Governance
#>

#Requires -Version 7.0
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..' '..' '..' 'tests' 'Support' 'LabScriptStub.psm1') -Force

    $script:ScriptPath     = (Resolve-Path (Join-Path $PSScriptRoot '..' 'scripts' 'Invoke-LabGovernance.ps1')).Path
    $script:StubModuleName = 'SkyCraftLab13GovernanceStub'
    # Exactly the script's '#Requires -Modules' line: these are imported for real before the stub.
    $script:RequiredModules = @('Az.Accounts', 'Az.Resources')

    $script:StubCommands = @(
        'Get-AzContext'
        'Connect-AzAccount'
        'Set-AzContext'
        'Get-AzResourceGroup'
        'Update-AzTag'
        'Get-AzPolicyDefinition'
        'Get-AzPolicyAssignment'
        'New-AzPolicyAssignment'
        'Get-AzRoleAssignment'
        'New-AzRoleAssignment'
        'Get-AzResourceLock'
        'New-AzResourceLock'
    )

    # Every Az command the script calls, recording its own invocation. Environment variables pick
    # what the subscription already holds:
    #   SKYCRAFT_STUB_POLICYSET   'none' (the default), 'bicep' (fixed names), 'portal' (generated
    #                             names, the guide's names as display names) or 'both'
    #   SKYCRAFT_STUB_LOOKUPFAIL  '1' makes the policy assignment listing fail
    #   SKYCRAFT_STUB_ROLEHELD    '1' makes Inherit-Project-Tag's identity hold Contributor on the
    #                             subscription already
    #   SKYCRAFT_STUB_NOIDENTITY  '1' lists Inherit-Project-Tag without a managed identity
    $script:StubBody = @'
$script:LogPath = $env:SKYCRAFT_STUB_LOG

function Write-StubCall {
    param([string]$Name)
    if ($script:LogPath) { Add-Content -LiteralPath $script:LogPath -Value $Name }
}

function Get-AzContext {
    [CmdletBinding()]
    param()
    [pscustomobject]@{
        Subscription = [pscustomobject]@{ Id = '00000000-0000-0000-0000-000000000000'; Name = 'stub-subscription' }
    }
}

function Connect-AzAccount { [CmdletBinding()] param() throw 'stub: the script must not sign in when a context exists' }

function Set-AzContext { [CmdletBinding()] param([string]$SubscriptionId) }

function Get-AzResourceGroup {
    [CmdletBinding()]
    param([string]$Name, [Parameter(ValueFromRemainingArguments)]$Rest)
    [pscustomobject]@{ ResourceGroupName = $Name; ResourceId = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/$Name" }
}

function Update-AzTag { [CmdletBinding()] param([Parameter(ValueFromRemainingArguments)]$Rest) }

function Get-AzPolicyDefinition {
    [CmdletBinding()]
    param([string]$Id, [Parameter(ValueFromRemainingArguments)]$Rest)
    if (-not $Id) { throw 'stub: the script reads each built-in definition by its id' }
    Write-StubCall -Name "Get-AzPolicyDefinition:$(($Id -split '/')[-1])"
    [pscustomobject]@{ Id = $Id; Name = ($Id -split '/')[-1] }
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

function Get-AzPolicyAssignment {
    [CmdletBinding()]
    param([string]$Name, [string]$Scope, [Parameter(ValueFromRemainingArguments)]$Rest)
    Write-StubCall -Name 'Get-AzPolicyAssignment'
    if ($env:SKYCRAFT_STUB_LOOKUPFAIL -eq '1') { Write-Error 'stub lookup failure: Get-AzPolicyAssignment'; return }
    if ($Name) { throw "stub: the lab looks assignments up by listing the scope, not by name ($Name)" }

    $lab = @(
        @{ Name = 'Require-Environment-Tag-RG'; Bicep = 'Require Environment Tag on Resource Groups'; Definition = '96670d01-0a4d-4649-9c89-2d3abc0a5025'; Portal = 'aaaaaaaaaaaaaaaaaaaaaaa1' }
        @{ Name = 'Enforce-Project-Tag'; Bicep = 'Enforce Project Tag Value'; Definition = '1e30110a-5ceb-460c-a204-c1c3969c6d62'; Portal = 'aaaaaaaaaaaaaaaaaaaaaaa2' }
        @{ Name = 'Inherit-Project-Tag'; Bicep = 'Inherit Project Tag from Resource Group'; Definition = 'ea3f2387-9b95-492a-a190-fcdc54f7b070'; Portal = 'aaaaaaaaaaaaaaaaaaaaaaa4'; Identity = $true }
        @{ Name = 'Restrict-Azure-Regions'; Bicep = 'Restrict to Allowed Regions'; Definition = 'e56962a6-4747-49cd-b67b-bf8b01975c4c'; Portal = 'aaaaaaaaaaaaaaaaaaaaaaa3' }
    )
    $set = $env:SKYCRAFT_STUB_POLICYSET
    foreach ($assignment in $lab) {
        $identity = [bool]$assignment.Identity -and $env:SKYCRAFT_STUB_NOIDENTITY -ne '1'
        if ($set -in 'bicep', 'both') {
            New-StubAssignment -Name $assignment.Name -DisplayName $assignment.Bicep -Definition $assignment.Definition -Scope $Scope -Identity:$identity
        }
        if ($set -in 'portal', 'both') {
            New-StubAssignment -Name $assignment.Portal -DisplayName $assignment.Name -Definition $assignment.Definition -Scope $Scope -Identity:$identity
        }
    }
    # Inherited from a management group under the guide's name: not the lab's assignment.
    New-StubAssignment -Name 'Enforce-Project-Tag' -DisplayName 'Enforce Project Tag Value' -Definition '1e30110a-5ceb-460c-a204-c1c3969c6d62' `
        -Scope '/providers/Microsoft.Management/managementGroups/stub-mg'
}

function New-AzPolicyAssignment {
    [CmdletBinding()]
    param([string]$Name, [string]$DisplayName, [string]$Scope, [object]$PolicyDefinition, [object]$PolicyParameterObject,
        [string]$IdentityType, [string]$Location)
    $parameters = ($PolicyParameterObject.GetEnumerator() | Sort-Object Key | ForEach-Object { "$($_.Key)=$(@($_.Value) -join ',')" }) -join ';'
    Write-StubCall -Name "New-AzPolicyAssignment:$Name|$DisplayName|$Scope|$($PolicyDefinition.Name)|$parameters|$IdentityType|$Location"
    New-StubAssignment -Name $Name -DisplayName $DisplayName -Definition $PolicyDefinition.Name -Scope $Scope -Identity:($IdentityType -eq 'SystemAssigned')
}

# Role assignments on the subscription: one held by someone else, one inherited from a
# management group by the identity, and - with SKYCRAFT_STUB_ROLEHELD - the identity's Contributor.
function Get-AzRoleAssignment {
    [CmdletBinding()]
    param([string]$Scope, [string]$ObjectId, [Parameter(ValueFromRemainingArguments)]$Rest)
    if ($ObjectId) { throw 'stub: the lab lists role assignments by scope, not by -ObjectId (a Microsoft Graph lookup)' }
    Write-StubCall -Name "Get-AzRoleAssignment:$Scope"
    [pscustomobject]@{ ObjectId = '22222222-2222-2222-2222-222222222222'; Scope = $Scope; RoleDefinitionId = 'b24988ac-6180-42a0-ab88-20f7382dd24c'; RoleDefinitionName = 'Contributor' }
    [pscustomobject]@{ ObjectId = $script:PrincipalId; Scope = '/providers/Microsoft.Management/managementGroups/stub-mg'; RoleDefinitionId = 'b24988ac-6180-42a0-ab88-20f7382dd24c'; RoleDefinitionName = 'Contributor' }
    if ($env:SKYCRAFT_STUB_ROLEHELD -eq '1') {
        [pscustomobject]@{ ObjectId = $script:PrincipalId; Scope = $Scope; RoleDefinitionId = 'b24988ac-6180-42a0-ab88-20f7382dd24c'; RoleDefinitionName = 'Contributor' }
    }
}

function New-AzRoleAssignment {
    [CmdletBinding()]
    param([string]$ObjectId, [string]$ObjectType, [string]$RoleDefinitionId, [string]$Scope)
    Write-StubCall -Name "New-AzRoleAssignment:$ObjectId|$ObjectType|$RoleDefinitionId|$Scope"
}

function Get-AzResourceLock { [CmdletBinding()] param([Parameter(ValueFromRemainingArguments)]$Rest) }

function New-AzResourceLock { [CmdletBinding()] param([Parameter(ValueFromRemainingArguments)]$Rest) }
'@

    function Invoke-GovernanceScript {
        param(
            [pscustomobject]$Stub,
            [ValidateSet('none', 'bicep', 'portal', 'both')]
            [string]$PolicySet = 'none',
            [switch]$LookupFail,
            [switch]$RoleHeld,
            [switch]$NoIdentity
        )

        $logPath = Join-Path $Stub.Directory 'calls.log'
        Remove-Item -LiteralPath $logPath -Force -ErrorAction SilentlyContinue

        $run = Invoke-LabScriptWithStub -Stub $Stub -ScriptPath $script:ScriptPath -Environment @{
            SKYCRAFT_STUB_POLICYSET  = $PolicySet
            SKYCRAFT_STUB_LOOKUPFAIL = if ($LookupFail) { '1' } else { '0' }
            SKYCRAFT_STUB_ROLEHELD   = if ($RoleHeld) { '1' } else { '0' }
            SKYCRAFT_STUB_NOIDENTITY = if ($NoIdentity) { '1' } else { '0' }
            SKYCRAFT_STUB_LOG        = $logPath
        }

        $calls = if (Test-Path -LiteralPath $logPath) { @(Get-Content -LiteralPath $logPath) } else { @() }
        return [pscustomobject]@{
            ExitCode = $run.ExitCode
            Refused  = $run.Refused
            Output   = $run.Output
            Calls    = $calls
            Created  = @($calls | Where-Object { $_ -like 'New-AzPolicyAssignment:*' })
            Granted  = @($calls | Where-Object { $_ -like 'New-AzRoleAssignment:*' })
        }
    }

    $script:Stub    = Initialize-LabScriptStub -Name $script:StubModuleName -Command $script:StubCommands `
        -Body $script:StubBody -RequiredModule $script:RequiredModules
    $script:StubDir = $script:Stub.Directory

    $script:Fresh      = Invoke-GovernanceScript -Stub $script:Stub
    $script:BicepMade  = Invoke-GovernanceScript -Stub $script:Stub -PolicySet 'bicep'
    $script:PortalMade = Invoke-GovernanceScript -Stub $script:Stub -PolicySet 'portal'
    $script:TwoSets    = Invoke-GovernanceScript -Stub $script:Stub -PolicySet 'both'
    $script:ListFails  = Invoke-GovernanceScript -Stub $script:Stub -LookupFail
    $script:RoleHeld   = Invoke-GovernanceScript -Stub $script:Stub -PolicySet 'portal' -RoleHeld
    $script:NoIdentity = Invoke-GovernanceScript -Stub $script:Stub -PolicySet 'portal' -NoIdentity

    $script:AllRuns = @($script:Fresh, $script:BicepMade, $script:PortalMade, $script:TwoSets, $script:ListFails,
        $script:RoleHeld, $script:NoIdentity)
}

AfterAll {
    if ($script:StubDir) { Remove-Item -LiteralPath $script:StubDir -Recurse -Force -ErrorAction SilentlyContinue }
}

Describe 'Lab 1.3 Invoke-LabGovernance.ps1 - test harness' {

    It 'shadows the real Az commands instead of touching a subscription' {
        foreach ($run in $script:AllRuns) {
            $run.Refused | Should -BeFalse -Because "the harness must never fall through to the real Az commands (exit $($run.ExitCode)): $($run.Output)"
        }
    }
}

Describe 'Lab 1.3 Invoke-LabGovernance.ps1 - never creates a second set of policy assignments (#330)' {

    It 'creates the four assignments under the Bicep path''s names when none exists' {
        $subscription = '/subscriptions/00000000-0000-0000-0000-000000000000'
        $script:Fresh.Created | Should -Be @(
            "New-AzPolicyAssignment:Require-Environment-Tag-RG|Require Environment Tag on Resource Groups|$subscription|96670d01-0a4d-4649-9c89-2d3abc0a5025|tagName=Environment||"
            "New-AzPolicyAssignment:Enforce-Project-Tag|Enforce Project Tag Value|$subscription|1e30110a-5ceb-460c-a204-c1c3969c6d62|tagName=Project;tagValue=SkyCraft||"
            "New-AzPolicyAssignment:Inherit-Project-Tag|Inherit Project Tag from Resource Group|$subscription|ea3f2387-9b95-492a-a190-fcdc54f7b070|tagName=Project|SystemAssigned|swedencentral"
            "New-AzPolicyAssignment:Restrict-Azure-Regions|Restrict to Allowed Regions|$subscription|e56962a6-4747-49cd-b67b-bf8b01975c4c|listOfAllowedLocations=swedencentral,northeurope||"
        ) -Because "an assignment inherited from a management group is not the lab's; output was:`n$($script:Fresh.Output)"
        $script:Fresh.Output | Should -Not -Match '\[ERROR\]'
    }

    It 'creates nothing next to the Bicep-made assignments' {
        $script:BicepMade.Created | Should -BeNullOrEmpty
        $script:BicepMade.Output | Should -Match "Policy Enforce-Project-Tag already assigned: 'Enforce Project Tag Value' \(name Enforce-Project-Tag\)"
    }

    It 'creates nothing next to the Portal-made assignments, found by the display names the learner typed' {
        $run = $script:PortalMade
        $run.Created | Should -BeNullOrEmpty -Because "a second set would leave the cleanup two of each; output was:`n$($run.Output)"
        $run.Output | Should -Match "Policy Require-Environment-Tag-RG already assigned: 'Require-Environment-Tag-RG' \(name aaaaaaaaaaaaaaaaaaaaaaa1\)"
        $run.Output | Should -Match "Policy Enforce-Project-Tag already assigned: 'Enforce-Project-Tag' \(name aaaaaaaaaaaaaaaaaaaaaaa2\)"
        $run.Output | Should -Match "Policy Restrict-Azure-Regions already assigned: 'Restrict-Azure-Regions' \(name aaaaaaaaaaaaaaaaaaaaaaa3\)"
        $run.Output | Should -Not -Match '\[ERROR\]'
    }

    It 'creates nothing for an assignment made twice, and names both in an [ERROR]' {
        $run = $script:TwoSets
        $run.Created | Should -BeNullOrEmpty
        $run.Output | Should -Match "\[ERROR\] 2 assignments match Enforce-Project-Tag: 'Enforce Project Tag Value' \(name Enforce-Project-Tag\), 'Enforce-Project-Tag' \(name aaaaaaaaaaaaaaaaaaaaaaa2\)\. Not creating another"
    }

    It 'creates nothing when the listing fails, because an assignment it could not see may exist' {
        $run = $script:ListFails
        $run.Created | Should -BeNullOrEmpty
        $run.Output | Should -Match '\[ERROR\] Could not list the policy assignments on the subscription[^\r\n]*stub lookup failure'
        @($run.Calls | Where-Object { $_ -like 'Get-AzPolicyDefinition:*' }) | Should -BeNullOrEmpty
    }

    It 'lists the subscription''s assignments once, rather than reading each by name' {
        @($script:Fresh.Calls | Where-Object { $_ -eq 'Get-AzPolicyAssignment' }).Count | Should -Be 1
    }
}

Describe 'Lab 1.3 Invoke-LabGovernance.ps1 - the identity of Inherit-Project-Tag gets the Portal''s role (#350)' {

    It 'grants Contributor on the subscription to the new assignment''s identity, as the Portal does' {
        $script:Fresh.Granted | Should -Be @(
            'New-AzRoleAssignment:11111111-1111-1111-1111-111111111111|ServicePrincipal|b24988ac-6180-42a0-ab88-20f7382dd24c|/subscriptions/00000000-0000-0000-0000-000000000000'
        ) -Because "a role inherited from a management group or held by someone else is not the identity's on the subscription; output was:`n$($script:Fresh.Output)"
        $script:Fresh.Output | Should -Match '\[SUCCESS\] Granted role b24988ac-6180-42a0-ab88-20f7382dd24c on the subscription to the identity of Inherit-Project-Tag'
    }

    It 'grants the role to an existing assignment''s identity that does not hold it yet' {
        # The Bicep-made set: the assignment exists, its identity holds no role on the subscription.
        $script:BicepMade.Granted.Count | Should -Be 1
    }

    It 'grants nothing when the identity holds the role already' {
        $run = $script:RoleHeld
        $run.Granted | Should -BeNullOrEmpty
        $run.Output | Should -Match 'Identity of Inherit-Project-Tag already holds role b24988ac-6180-42a0-ab88-20f7382dd24c on the subscription'
        $run.Output | Should -Not -Match '\[ERROR\]'
    }

    It 'reports an existing Inherit-Project-Tag without a managed identity as an [ERROR], and grants nothing' {
        $run = $script:NoIdentity
        $run.Granted | Should -BeNullOrEmpty
        $run.Created | Should -BeNullOrEmpty
        $run.Output | Should -Match "\[ERROR\] Inherit-Project-Tag 'Inherit-Project-Tag' \(name aaaaaaaaaaaaaaaaaaaaaaa4\) has no managed identity"
    }

    It 'lists role assignments by scope, never with -ObjectId (a Microsoft Graph lookup)' {
        @($script:Fresh.Calls | Where-Object { $_ -like 'Get-AzRoleAssignment:*' }) |
            Should -Be @('Get-AzRoleAssignment:/subscriptions/00000000-0000-0000-0000-000000000000')
    }
}

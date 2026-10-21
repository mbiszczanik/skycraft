<#
.SYNOPSIS
    Pester 5 tests for Lab 1.3's Bicep deployment over a lab built in the Portal.

.DESCRIPTION
    Regression cover for issue #406. The live pass of 2026-10-20 ran Deploy-Bicep.ps1 -WhatIf
    over a Lab 1.3 built in the Portal and got "5 to create": the four policy assignments again
    (the template names them itself, the Portal with generated ids) and a role assignment for the
    identity of Inherit-Project-Tag. These tests run the real script in a child pwsh process
    against a generated stub of the Az commands it calls, record the parameters it hands the
    template, and evaluate the compiled template's conditions with them:

      1. Over a Portal-built lab (generated names, the guide's display names and values, the
         identity holding Contributor), the script keeps all four assignments, the template
         deploys no policy assignment and no role assignment, and the run prints
         "Existing assignments: 4 of 4".
      2. With no assignment, the template creates all four and grants the role.
      3. Over a Bicep-made lab (fixed names), the template deploys over the assignments and
         grants the role only when the identity lacks it.
      4. A Portal-made Inherit-Project-Tag whose identity lacks the role (a learner with
         Contributor alone) gets the role from the template's own role-assignment module.
      5. An assignment whose parameters or enforcement mode differ from the lab's, two
         assignments for one of the guide's, one with the guide's definition under the
         wizard's default name or the guide's name on another definition, an identity with no
         principal id, an adopted identity in another region than -Location, or a listing that
         fails: the script names the problem, calls neither the what-if nor the deployment, and
         exits 1.
      6. An identity holding another role than Contributor still gets Contributor.

    No subscription is needed, and none is used. The script runs through
    tests/Support/LabScriptStub.psm1 (issue #112), which aborts the child with exit 99 unless
    every stubbed command resolves to the stub. The template is compiled with the Bicep CLI that
    tools/BicepCli.psm1 finds.

.EXAMPLE
    Invoke-Pester -Path .\Deploy-Bicep.Tests.ps1

.NOTES
    Project: SkyCraft
    Lab: 1.3 - Governance
#>

#Requires -Version 7.0
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..' '..')).Path
    Import-Module (Join-Path $script:RepoRoot 'tests' 'Support' 'LabScriptStub.psm1') -Force
    Import-Module (Join-Path $script:RepoRoot 'tools' 'BicepCli.psm1') -Force

    $script:ScriptPath     = (Resolve-Path (Join-Path $PSScriptRoot '..' 'scripts' 'Deploy-Bicep.ps1')).Path
    $script:TemplatePath   = (Resolve-Path (Join-Path $PSScriptRoot '..' 'bicep' 'main.bicep')).Path
    $script:StubModuleName = 'SkyCraftLab13DeployBicepStub'
    $script:RequiredModules = @('Az.Accounts', 'Az.Resources')
    $script:GuideNames = @('Require-Environment-Tag-RG', 'Enforce-Project-Tag', 'Inherit-Project-Tag', 'Restrict-Azure-Regions')

    $script:StubCommands = @(
        'Get-AzContext'
        'Connect-AzAccount'
        'Get-AzPolicyAssignment'
        'Get-AzRoleAssignment'
        'Get-AzSubscriptionDeploymentWhatIfResult'
        'New-AzSubscriptionDeployment'
        'Get-AzSubscriptionDeploymentOperation'
    )

    # Environment variables pick what the subscription already holds:
    #   SKYCRAFT_STUB_POLICYSET   'none', 'portal' (generated names, the guide's display names),
    #                             'bicep' (fixed names, the pre-#406 Bicep display names), 'both',
    #                             'portal-default-name' (the Portal set, Require-Environment-Tag-RG
    #                             under the wizard's prefill) or 'wrong-definition' (the Portal
    #                             set, Inherit-Project-Tag on "Inherit a tag from the resource group")
    #   SKYCRAFT_STUB_ROLEHELD    '1' makes Inherit-Project-Tag's identity hold Contributor
    #   SKYCRAFT_STUB_OTHERROLE   '1' makes the identity hold Reader on the subscription
    #   SKYCRAFT_STUB_NOPRINCIPAL '1' lists the identity without a principal id
    #   SKYCRAFT_STUB_DRIFT       '1' gives Enforce-Project-Tag tagValue 'Contoso' and
    #                             Restrict-Azure-Regions enforcement mode DoNotEnforce
    #   SKYCRAFT_STUB_LOOKUPFAIL  '1' makes the policy assignment listing fail
    #   SKYCRAFT_STUB_ROLEFAIL    '1' makes the role assignment listing fail
    $script:StubBody = @'
$script:LogPath = $env:SKYCRAFT_STUB_LOG
$script:PrincipalId = '11111111-1111-1111-1111-111111111111'

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

function New-StubAssignment {
    param([string]$Name, [string]$DisplayName, [string]$Definition, [string]$Scope, [switch]$Identity,
        [System.Collections.IDictionary]$Parameter, [string]$EnforcementMode)
    $bag = [ordered]@{}
    foreach ($key in $Parameter.Keys) { $bag[$key] = [pscustomobject]@{ value = $Parameter[$key] } }
    $assignment = [pscustomobject]@{
        Name               = $Name
        DisplayName        = $DisplayName
        PolicyDefinitionId = "/providers/Microsoft.Authorization/policyDefinitions/$Definition"
        Scope              = $Scope
        Id                 = "$Scope/providers/Microsoft.Authorization/policyAssignments/$Name"
        Parameter          = [pscustomobject]$bag
        EnforcementMode    = $EnforcementMode
    }
    if ($Identity) {
        $assignment | Add-Member -NotePropertyName IdentityType -NotePropertyValue 'SystemAssigned'
        $assignment | Add-Member -NotePropertyName IdentityPrincipalId -NotePropertyValue $(if ($env:SKYCRAFT_STUB_NOPRINCIPAL -eq '1') { '' } else { $script:PrincipalId })
        # The guide's region.
        $assignment | Add-Member -NotePropertyName Location -NotePropertyValue 'swedencentral'
    }
    $assignment
}

function Get-AzPolicyAssignment {
    [CmdletBinding()]
    param([string]$Scope, [Parameter(ValueFromRemainingArguments)]$Rest)
    Write-StubCall -Name 'Get-AzPolicyAssignment'
    if ($env:SKYCRAFT_STUB_LOOKUPFAIL -eq '1') { Write-Error 'stub lookup failure: Get-AzPolicyAssignment'; return }

    $drift = $env:SKYCRAFT_STUB_DRIFT -eq '1'
    $lab = @(
        @{ Name = 'Require-Environment-Tag-RG'; Bicep = 'Require Environment Tag on Resource Groups'; Definition = '96670d01-0a4d-4649-9c89-2d3abc0a5025'; Portal = 'aaaaaaaaaaaaaaaaaaaaaaa1'
            Parameter = @{ tagName = 'Environment' } }
        @{ Name = 'Enforce-Project-Tag'; Bicep = 'Enforce Project Tag Value'; Definition = '1e30110a-5ceb-460c-a204-c1c3969c6d62'; Portal = 'aaaaaaaaaaaaaaaaaaaaaaa2'
            Parameter = @{ tagName = 'Project'; tagValue = $(if ($drift) { 'Contoso' } else { 'SkyCraft' }) } }
        @{ Name = 'Inherit-Project-Tag'; Bicep = 'Inherit Project Tag from Resource Group'; Definition = 'ea3f2387-9b95-492a-a190-fcdc54f7b070'; Portal = 'aaaaaaaaaaaaaaaaaaaaaaa4'; Identity = $true
            Parameter = @{ tagName = 'Project' } }
        @{ Name = 'Restrict-Azure-Regions'; Bicep = 'Restrict to Allowed Regions'; Definition = 'e56962a6-4747-49cd-b67b-bf8b01975c4c'; Portal = 'aaaaaaaaaaaaaaaaaaaaaaa3'
            Parameter = @{ listOfAllowedLocations = @('northeurope', 'swedencentral') }; EnforcementMode = $(if ($drift) { 'DoNotEnforce' } else { 'Default' }) }
    )
    $set = $env:SKYCRAFT_STUB_POLICYSET
    foreach ($a in $lab) {
        $mode = if ($a.EnforcementMode) { $a.EnforcementMode } else { 'Default' }
        if ($set -in 'bicep', 'both') {
            New-StubAssignment -Name $a.Name -DisplayName $a.Bicep -Definition $a.Definition -Scope $Scope -Identity:([bool]$a.Identity) -Parameter $a.Parameter -EnforcementMode $mode
        }
        if ($set -in 'portal', 'both', 'portal-default-name', 'wrong-definition') {
            $display = $a.Name
            $definition = $a.Definition
            if ($set -eq 'portal-default-name' -and $a.Name -eq 'Require-Environment-Tag-RG') { $display = 'Require a tag on resource groups' }
            if ($set -eq 'wrong-definition' -and $a.Name -eq 'Inherit-Project-Tag') { $definition = 'cd3aa116-8754-49c9-a813-ad46512ece54' }
            New-StubAssignment -Name $a.Portal -DisplayName $display -Definition $definition -Scope $Scope -Identity:([bool]$a.Identity) -Parameter $a.Parameter -EnforcementMode $mode
        }
    }
    # Inherited from a management group under the guide's name: not the lab's.
    New-StubAssignment -Name 'Enforce-Project-Tag' -DisplayName 'Enforce-Project-Tag' -Definition '1e30110a-5ceb-460c-a204-c1c3969c6d62' `
        -Scope '/providers/Microsoft.Management/managementGroups/stub-mg' -Parameter @{ tagName = 'Project'; tagValue = 'SkyCraft' } -EnforcementMode 'Default'
}

function Get-AzRoleAssignment {
    [CmdletBinding()]
    param([string]$Scope, [string]$ObjectId, [Parameter(ValueFromRemainingArguments)]$Rest)
    if ($ObjectId) { throw 'stub: the lab lists role assignments by scope, not by -ObjectId (a Microsoft Graph lookup)' }
    Write-StubCall -Name "Get-AzRoleAssignment:$Scope"
    if ($env:SKYCRAFT_STUB_ROLEFAIL -eq '1') { throw 'stub lookup failure: Get-AzRoleAssignment' }
    [pscustomobject]@{ ObjectId = '22222222-2222-2222-2222-222222222222'; Scope = $Scope; RoleDefinitionId = 'b24988ac-6180-42a0-ab88-20f7382dd24c' }
    # Inherited from a management group: not the identity's role on the subscription.
    [pscustomobject]@{ ObjectId = $script:PrincipalId; Scope = '/providers/Microsoft.Management/managementGroups/stub-mg'; RoleDefinitionId = 'b24988ac-6180-42a0-ab88-20f7382dd24c' }
    if ($env:SKYCRAFT_STUB_ROLEHELD -eq '1') {
        [pscustomobject]@{ ObjectId = $script:PrincipalId; Scope = $Scope; RoleDefinitionId = 'b24988ac-6180-42a0-ab88-20f7382dd24c' }
    }
    if ($env:SKYCRAFT_STUB_OTHERROLE -eq '1') {
        [pscustomobject]@{ ObjectId = $script:PrincipalId; Scope = $Scope; RoleDefinitionId = 'acdd72a7-3385-48ef-bd42-f606fba81ae7' }
    }
}

function Get-AzSubscriptionDeploymentWhatIfResult {
    [CmdletBinding()]
    param([string]$Name, [string]$Location, [string]$TemplateFile, [hashtable]$TemplateParameterObject)
    Write-StubCall -Name "WhatIf:$($TemplateParameterObject | ConvertTo-Json -Compress -Depth 5)"
}

function New-AzSubscriptionDeployment {
    [CmdletBinding()]
    param([string]$Name, [string]$Location, [string]$TemplateFile, [hashtable]$TemplateParameterObject)
    Write-StubCall -Name "Deploy:$($TemplateParameterObject | ConvertTo-Json -Compress -Depth 5)"
    [pscustomobject]@{ ProvisioningState = 'Succeeded'; Outputs = @{} }
}

function Get-AzSubscriptionDeploymentOperation { [CmdletBinding()] param([Parameter(ValueFromRemainingArguments)]$Rest) }
'@

    function Invoke-DeployScript {
        param(
            [pscustomobject]$Stub,
            [ValidateSet('none', 'bicep', 'portal', 'both', 'portal-default-name', 'wrong-definition')]
            [string]$PolicySet = 'none',
            [switch]$RoleHeld,
            [switch]$OtherRole,
            [switch]$NoPrincipal,
            [string]$Location,
            [switch]$Drift,
            [switch]$LookupFail,
            [switch]$RoleFail,
            [switch]$Deploy
        )

        $logPath = Join-Path $Stub.Directory 'calls.log'
        Remove-Item -LiteralPath $logPath -Force -ErrorAction SilentlyContinue

        $arguments = @(@(if (-not $Deploy) { '-WhatIf' }) + @(if ($Location) { '-Location', $Location }))
        $run = Invoke-LabScriptWithStub -Stub $Stub -ScriptPath $script:ScriptPath `
            -ArgumentList $arguments -Environment @{
            SKYCRAFT_STUB_POLICYSET   = $PolicySet
            SKYCRAFT_STUB_ROLEHELD    = if ($RoleHeld) { '1' } else { '0' }
            SKYCRAFT_STUB_OTHERROLE   = if ($OtherRole) { '1' } else { '0' }
            SKYCRAFT_STUB_NOPRINCIPAL = if ($NoPrincipal) { '1' } else { '0' }
            SKYCRAFT_STUB_DRIFT      = if ($Drift) { '1' } else { '0' }
            SKYCRAFT_STUB_LOOKUPFAIL = if ($LookupFail) { '1' } else { '0' }
            SKYCRAFT_STUB_ROLEFAIL   = if ($RoleFail) { '1' } else { '0' }
            SKYCRAFT_STUB_LOG        = $logPath
        }

        $calls = if (Test-Path -LiteralPath $logPath) { @(Get-Content -LiteralPath $logPath) } else { @() }
        $handed = @($calls | Where-Object { $_ -like 'WhatIf:*' -or $_ -like 'Deploy:*' })
        return [pscustomobject]@{
            ExitCode   = $run.ExitCode
            Refused    = $run.Refused
            Output     = $run.Output
            Calls      = $calls
            Handed     = $handed
            Parameters = if ($handed.Count -eq 1) { ($handed[0] -replace '^(WhatIf|Deploy):', '') | ConvertFrom-Json -AsHashtable } else { $null }
        }
    }

    # Which policy assignments and role assignments the compiled template deploys with the
    # parameters the script handed it: each module's condition is evaluated for the patterns the
    # template uses, and an unknown condition fails the test rather than counting as deployed.
    function Get-DeployedByTemplate {
        param([hashtable]$Parameters)
        $policies = [System.Collections.Generic.List[string]]::new()
        $roles = [System.Collections.Generic.List[string]]::new()
        foreach ($module in $script:Compiled) {
            $isPolicy = $module.properties.template.resources.policyAssignment.type -eq 'Microsoft.Authorization/policyAssignments'
            $isRole = $module.properties.template.resources.roleAssignment.type -eq 'Microsoft.Authorization/roleAssignments'
            if (-not ($isPolicy -or $isRole)) { continue }

            $condition = $module.condition
            $deployed = if ($null -eq $condition) { $true }
            elseif ($condition -match "^\[not\(contains\(parameters\('parExistingPolicyAssignments'\), '([^']+)'\)\)\]$") {
                $Matches[1] -notin @($Parameters.parExistingPolicyAssignments)
            }
            elseif ($condition -eq "[not(empty(parameters('parInheritProjectTagPrincipalId')))]") {
                -not [string]::IsNullOrEmpty($Parameters.parInheritProjectTagPrincipalId)
            }
            else { throw "unknown condition on module $($module.name): $condition" }
            if (-not $deployed) { continue }

            if ($isRole) { $roles.Add($module.name); continue }
            $policies.Add($module.name)
            # A policy module grants roles through its roleDefinitionIds.
            $roleExpression = $module.properties.parameters.roleDefinitionIds
            if ($roleExpression) {
                $grants = if ($roleExpression -is [string]) {
                    if ($roleExpression -ne "[if(parameters('parGrantInheritProjectTagRole'), createObject('value', createArray(variables('varContributorRoleId'))), createObject('value', createArray()))]") {
                        throw "unknown roleDefinitionIds on module $($module.name): $roleExpression"
                    }
                    [bool]$Parameters.parGrantInheritProjectTagRole
                }
                else { @($roleExpression.value).Count -gt 0 }
                if ($grants) { $roles.Add("$($module.name) (module role)") }
            }
        }
        [pscustomobject]@{ Policies = @($policies); Roles = @($roles) }
    }

    $script:WorkDir = Join-Path ([System.IO.Path]::GetTempPath()) ('skycraft-406-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $script:WorkDir -Force | Out-Null
    # --outfile rather than --stdout: --stdout crashes on a non-UTF-8 Windows console with AVM modules.
    $compiledPath = Join-Path $script:WorkDir 'main.json'
    $null = & (Get-BicepCliPath) build $script:TemplatePath --outfile $compiledPath 2>&1
    if ($LASTEXITCODE -ne 0) { throw "bicep build failed for $script:TemplatePath" }
    $resources = (Get-Content -Raw -LiteralPath $compiledPath | ConvertFrom-Json -AsHashtable).resources
    $script:Compiled = @(if ($resources -is [System.Collections.IDictionary]) { $resources.Values } else { $resources })

    $script:Stub    = Initialize-LabScriptStub -Name $script:StubModuleName -Command $script:StubCommands `
        -Body $script:StubBody -RequiredModule $script:RequiredModules
    $script:StubDir = $script:Stub.Directory

    $script:Fresh          = Invoke-DeployScript -Stub $script:Stub
    $script:Portal         = Invoke-DeployScript -Stub $script:Stub -PolicySet 'portal' -RoleHeld
    $script:PortalDeploy   = Invoke-DeployScript -Stub $script:Stub -PolicySet 'portal' -RoleHeld -Deploy
    $script:PortalNoRole   = Invoke-DeployScript -Stub $script:Stub -PolicySet 'portal'
    $script:Bicep          = Invoke-DeployScript -Stub $script:Stub -PolicySet 'bicep' -RoleHeld
    $script:BicepNoRole    = Invoke-DeployScript -Stub $script:Stub -PolicySet 'bicep'
    $script:Drifted        = Invoke-DeployScript -Stub $script:Stub -PolicySet 'portal' -RoleHeld -Drift
    $script:DriftedDeploy  = Invoke-DeployScript -Stub $script:Stub -PolicySet 'portal' -RoleHeld -Drift -Deploy
    $script:TwoSets        = Invoke-DeployScript -Stub $script:Stub -PolicySet 'both' -RoleHeld
    $script:ListFails      = Invoke-DeployScript -Stub $script:Stub -LookupFail
    $script:RoleListFails  = Invoke-DeployScript -Stub $script:Stub -PolicySet 'portal' -RoleFail
    $script:DefaultName    = Invoke-DeployScript -Stub $script:Stub -PolicySet 'portal-default-name' -RoleHeld
    $script:WrongDef       = Invoke-DeployScript -Stub $script:Stub -PolicySet 'wrong-definition' -RoleHeld
    $script:OtherRole      = Invoke-DeployScript -Stub $script:Stub -PolicySet 'portal' -OtherRole
    $script:NoPrincipal    = Invoke-DeployScript -Stub $script:Stub -PolicySet 'portal' -NoPrincipal
    $script:BicepAway      = Invoke-DeployScript -Stub $script:Stub -PolicySet 'bicep' -RoleHeld -Location 'northeurope'
    $script:PortalAway     = Invoke-DeployScript -Stub $script:Stub -PolicySet 'portal' -RoleHeld -Location 'northeurope'

    $script:AllRuns = @($script:Fresh, $script:Portal, $script:PortalDeploy, $script:PortalNoRole, $script:Bicep,
        $script:BicepNoRole, $script:Drifted, $script:DriftedDeploy, $script:TwoSets, $script:ListFails, $script:RoleListFails,
        $script:DefaultName, $script:WrongDef, $script:OtherRole, $script:NoPrincipal, $script:BicepAway, $script:PortalAway)
}

AfterAll {
    if ($script:StubDir) { Remove-Item -LiteralPath $script:StubDir -Recurse -Force -ErrorAction SilentlyContinue }
    if ($script:WorkDir) { Remove-Item -LiteralPath $script:WorkDir -Recurse -Force -ErrorAction SilentlyContinue }
}

Describe 'Lab 1.3 Deploy-Bicep.ps1 - test harness' {

    It 'shadows the real Az commands instead of touching a subscription' {
        foreach ($run in $script:AllRuns) {
            $run.Refused | Should -BeFalse -Because "the harness must never fall through to the real Az commands (exit $($run.ExitCode)): $($run.Output)"
        }
    }

    It 'finds the four policy assignment modules and the role module in the compiled template' {
        $all = Get-DeployedByTemplate -Parameters @{ parExistingPolicyAssignments = @(); parGrantInheritProjectTagRole = $true; parInheritProjectTagPrincipalId = 'x' }
        $all.Policies | Should -Be $script:GuideNames
        $all.Roles | Should -Be @('Inherit-Project-Tag (module role)', 'Inherit-Project-Tag-Role')
    }
}

Describe 'Lab 1.3 Deploy-Bicep.ps1 - a lab built in the Portal gets no second assignment (#406)' {

    It 'keeps the four Portal-made assignments, found by definition and the guide''s display names' {
        $run = $script:Portal
        $run.ExitCode | Should -Be 0 -Because "output was:`n$($run.Output)"
        $run.Output | Should -Match "\[KEEP\]   Require-Environment-Tag-RG: 'Require-Environment-Tag-RG' \(name aaaaaaaaaaaaaaaaaaaaaaa1\), made outside the template; left as it is\."
        $run.Output | Should -Match "\[KEEP\]   Enforce-Project-Tag: 'Enforce-Project-Tag' \(name aaaaaaaaaaaaaaaaaaaaaaa2\)"
        $run.Output | Should -Match "\[KEEP\]   Inherit-Project-Tag: 'Inherit-Project-Tag' \(name aaaaaaaaaaaaaaaaaaaaaaa4\)"
        $run.Output | Should -Match "\[KEEP\]   Restrict-Azure-Regions: 'Restrict-Azure-Regions' \(name aaaaaaaaaaaaaaaaaaaaaaa3\)"
        $run.Output | Should -Match 'Existing assignments: 4 of 4'
        $run.Output | Should -Match '\[KEEP\]   Role b24988ac-6180-42a0-ab88-20f7382dd24c of the identity of Inherit-Project-Tag: held on the subscription already'
    }

    It 'hands the what-if parameters under which the template deploys no policy assignment and no role assignment' {
        $run = $script:Portal
        $run.Handed.Count | Should -Be 1
        $run.Handed[0] | Should -BeLike 'WhatIf:*'
        @($run.Parameters.parExistingPolicyAssignments) | Should -Be $script:GuideNames
        $run.Parameters.parGrantInheritProjectTagRole | Should -BeFalse
        $run.Parameters.parInheritProjectTagPrincipalId | Should -BeNullOrEmpty
        $deployed = Get-DeployedByTemplate -Parameters $run.Parameters
        $deployed.Policies | Should -BeNullOrEmpty
        $deployed.Roles | Should -BeNullOrEmpty
    }

    It 'hands the deployment the same parameters' {
        $run = $script:PortalDeploy
        $run.ExitCode | Should -Be 0 -Because "output was:`n$($run.Output)"
        $run.Handed[0] | Should -BeLike 'Deploy:*'
        @($run.Parameters.parExistingPolicyAssignments) | Should -Be $script:GuideNames
        (Get-DeployedByTemplate -Parameters $run.Parameters).Policies | Should -BeNullOrEmpty
    }

    It 'grants the role through the template when a Portal-made identity lacks it (a learner with Contributor alone)' {
        $run = $script:PortalNoRole
        $run.ExitCode | Should -Be 0 -Because "output was:`n$($run.Output)"
        $run.Output | Should -Match '\[GRANT\]  Role b24988ac-6180-42a0-ab88-20f7382dd24c of the identity of Inherit-Project-Tag: not held on the subscription; the template grants it\.'
        $run.Parameters.parInheritProjectTagPrincipalId | Should -Be '11111111-1111-1111-1111-111111111111'
        $deployed = Get-DeployedByTemplate -Parameters $run.Parameters
        $deployed.Policies | Should -BeNullOrEmpty
        $deployed.Roles | Should -Be @('Inherit-Project-Tag-Role')
    }

    It 'grants Contributor when the identity holds another role on the subscription' {
        $run = $script:OtherRole
        $run.ExitCode | Should -Be 0 -Because "output was:`n$($run.Output)"
        $run.Output | Should -Match '\[GRANT\]  Role b24988ac-6180-42a0-ab88-20f7382dd24c of the identity of Inherit-Project-Tag'
        $run.Parameters.parInheritProjectTagPrincipalId | Should -Be '11111111-1111-1111-1111-111111111111'
        (Get-DeployedByTemplate -Parameters $run.Parameters).Roles | Should -Be @('Inherit-Project-Tag-Role')
    }

    It 'keeps a Portal-made identity in another region than -Location: the template does not redeploy it' {
        $run = $script:PortalAway
        $run.ExitCode | Should -Be 0 -Because "output was:`n$($run.Output)"
        (Get-DeployedByTemplate -Parameters $run.Parameters).Policies | Should -BeNullOrEmpty
    }

    It 'reads the role assignments by scope, never with -ObjectId (a Microsoft Graph lookup)' {
        @($script:Portal.Calls | Where-Object { $_ -like 'Get-AzRoleAssignment:*' }) |
            Should -Be @('Get-AzRoleAssignment:/subscriptions/00000000-0000-0000-0000-000000000000')
    }
}

Describe 'Lab 1.3 Deploy-Bicep.ps1 - an empty or Bicep-made lab (#406)' {

    It 'creates all four assignments and grants the role when none exists' {
        $run = $script:Fresh
        $run.ExitCode | Should -Be 0 -Because "output was:`n$($run.Output)"
        $run.Output | Should -Match 'Existing assignments: 0 of 4'
        $run.Output | Should -Match '\[CREATE\] Enforce-Project-Tag: none on the subscription; the template creates it\.'
        $deployed = Get-DeployedByTemplate -Parameters $run.Parameters
        $deployed.Policies | Should -Be $script:GuideNames -Because 'an assignment inherited from a management group is not the lab''s'
        $deployed.Roles | Should -Be @('Inherit-Project-Tag (module role)')
        @($run.Calls | Where-Object { $_ -like 'Get-AzRoleAssignment:*' }) | Should -BeNullOrEmpty
    }

    It 'deploys over Bicep-made assignments and grants no second role when the identity holds it' {
        $run = $script:Bicep
        $run.ExitCode | Should -Be 0 -Because "output was:`n$($run.Output)"
        $run.Output | Should -Match "\[ADOPT\]  Enforce-Project-Tag: 'Enforce Project Tag Value' \(name Enforce-Project-Tag\); the template deploys over it\."
        $run.Output | Should -Match 'Existing assignments: 4 of 4'
        $deployed = Get-DeployedByTemplate -Parameters $run.Parameters
        $deployed.Policies | Should -Be $script:GuideNames
        $deployed.Roles | Should -BeNullOrEmpty
    }

    It 'grants the role with the module when a Bicep-made identity lacks it' {
        $deployed = Get-DeployedByTemplate -Parameters $script:BicepNoRole.Parameters
        $deployed.Roles | Should -Be @('Inherit-Project-Tag (module role)')
        $script:BicepNoRole.Parameters.parInheritProjectTagPrincipalId | Should -BeNullOrEmpty
    }
}

Describe 'Lab 1.3 Deploy-Bicep.ps1 - deploys nothing it cannot account for (#406)' {

    It 'names each difference of a mismatched assignment and calls neither the what-if nor the deployment' {
        foreach ($run in $script:Drifted, $script:DriftedDeploy) {
            $run.ExitCode | Should -Be 1 -Because "output was:`n$($run.Output)"
            $run.Handed | Should -BeNullOrEmpty
            $run.Output | Should -Match "\[ERROR\] Enforce-Project-Tag 'Enforce-Project-Tag' \(name aaaaaaaaaaaaaaaaaaaaaaa2\) differs from the lab's: parameter tagValue is 'Contoso', the lab's is 'SkyCraft'\. Set it as step 1\.3\.8 does"
            $run.Output | Should -Match "\[ERROR\] Restrict-Azure-Regions 'Restrict-Azure-Regions' \(name aaaaaaaaaaaaaaaaaaaaaaa3\) differs from the lab's: enforcement mode is 'DoNotEnforce', the lab's is 'Default'"
            $run.Output | Should -Match 'Nothing deployed: 2 problem\(s\) above'
        }
    }

    It 'stops when two assignments match one of the guide''s' {
        $run = $script:TwoSets
        $run.ExitCode | Should -Be 1
        $run.Handed | Should -BeNullOrEmpty
        $run.Output | Should -Match "\[ERROR\] 2 assignments match Enforce-Project-Tag: 'Enforce Project Tag Value' \(name Enforce-Project-Tag\), 'Enforce-Project-Tag' \(name aaaaaaaaaaaaaaaaaaaaaaa2\)"
    }

    It 'stops on an assignment of the guide''s definition under the wizard''s default name, rather than create a second one' {
        $run = $script:DefaultName
        $run.ExitCode | Should -Be 1 -Because "output was:`n$($run.Output)"
        $run.Handed | Should -BeNullOrEmpty
        $run.Output | Should -Match "\[ERROR\] Require-Environment-Tag-RG: none matches, and the template would create it next to: 'Require a tag on resource groups' \(name aaaaaaaaaaaaaaaaaaaaaaa1\) assigns 'Require a tag on resource groups' under another name than the guide's; rename it to 'Require-Environment-Tag-RG' \(Edit assignment > Assignment name\) or delete it"
        $run.Output | Should -Match 'Nothing deployed: 1 problem\(s\) above'
    }

    It 'stops on an assignment under the guide''s name with another definition, rather than create the lab''s next to it' {
        $run = $script:WrongDef
        $run.ExitCode | Should -Be 1 -Because "output was:`n$($run.Output)"
        $run.Handed | Should -BeNullOrEmpty
        $run.Output | Should -Match "\[ERROR\] Inherit-Project-Tag: none matches, and the template would create it next to: 'Inherit-Project-Tag' \(name aaaaaaaaaaaaaaaaaaaaaaa4\) assigns another definition than 'Inherit a tag from the resource group if missing'; delete it"
    }

    It 'stops when a found identity reports no principal id, rather than claim a grant it cannot make' {
        $run = $script:NoPrincipal
        $run.ExitCode | Should -Be 1 -Because "output was:`n$($run.Output)"
        $run.Handed | Should -BeNullOrEmpty
        $run.Output | Should -Match "\[ERROR\] Inherit-Project-Tag 'Inherit-Project-Tag' \(name aaaaaaaaaaaaaaaaaaaaaaa4\) reports no principal id for its identity"
        $run.Output | Should -Not -Match '\[GRANT\]'
    }

    It 'stops before deploying over an identity in another region than -Location' {
        $run = $script:BicepAway
        $run.ExitCode | Should -Be 1 -Because "output was:`n$($run.Output)"
        $run.Handed | Should -BeNullOrEmpty
        $run.Output | Should -Match "\[ERROR\] Inherit-Project-Tag 'Inherit Project Tag from Resource Group' \(name Inherit-Project-Tag\) has its identity in 'swedencentral', and this run deploys it to 'northeurope'[^\r\n]*Run this script with -Location swedencentral"
        $run.Output | Should -Match 'Nothing deployed: 1 problem\(s\) above'
    }

    It 'stops when the policy assignments cannot be listed' {
        $run = $script:ListFails
        $run.ExitCode | Should -Be 1
        $run.Handed | Should -BeNullOrEmpty
        $run.Output | Should -Match '\[ERROR\] Could not list the policy assignments on the subscription, so nothing is deployed[^\r\n]*stub lookup failure'
    }

    It 'stops when the role assignments cannot be listed' {
        $run = $script:RoleListFails
        $run.ExitCode | Should -Be 1
        $run.Handed | Should -BeNullOrEmpty
        $run.Output | Should -Match '\[ERROR\] Could not list the role assignments on the subscription[^\r\n]*stub lookup failure'
    }
}

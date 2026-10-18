<#
.SYNOPSIS
    Pester 5 tests for the Lab 1.3 policy assignment lookup shared by the lab's three scripts.

.DESCRIPTION
    Regression cover for issue #330. The Portal's Assign policy wizard sets only the display name
    from what the learner types into Assignment name; the assignment's resource name is a
    generated id. Test-Lab.ps1, Remove-LabResource.ps1 and Invoke-LabGovernance.ps1 looked the
    three assignments up by resource name, so they missed every assignment a learner made in the
    Portal. They now share one lookup, scripts/LabPolicyAssignment.ps1, which these tests pin:

      1. An assignment is the guide's when it sits on the subscription itself, assigns the
         expected built-in policy definition, and carries the guide's name either as its
         resource name or as its display name - or the display name the Bicep path and
         Invoke-LabGovernance.ps1 give it.
      2. A Portal-made assignment (generated name, display name typed by the learner) and a
         Bicep-made one (fixed name, Bicep display name) are both found.
      3. Nothing is found when no assignment matches, and every matching assignment is
         returned, so a caller can refuse to act on more than one.
      4. An assignment of another definition under the guide's name, and one inherited from a
         management group, are not the guide's.
      5. The Modify assignment Inherit-Project-Tag (issue #350) is found by its own definition,
         never counts as Enforce-Project-Tag, and its tagName and managed identity are compared
         with the spec in both Az.Resources shapes; its identity's role assignments are picked
         from a listing by principal id and subscription scope.

    The helper is dot-sourced: it only defines functions, so nothing is looked up.

.EXAMPLE
    Invoke-Pester -Path .\LabPolicyAssignment.Tests.ps1

.NOTES
    Project: SkyCraft
    Lab: 1.3 - Governance
#>

#Requires -Version 7.0
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    . (Join-Path $PSScriptRoot '..' 'scripts' 'LabPolicyAssignment.ps1')

    $script:SubscriptionId = '00000000-0000-0000-0000-000000000000'
    $script:SubscriptionScope = "/subscriptions/$script:SubscriptionId"
    $script:Specs = @(Get-LabPolicyAssignmentSpec)
    $script:Tag = $script:Specs | Where-Object { $_.Name -eq 'Enforce-Project-Tag' }

    # Shaped like Get-AzPolicyAssignment's output in Az.Resources 7 and later.
    function Get-AssignmentFixture {
        param(
            [string]$Name,
            [string]$DisplayName,
            [string]$PolicyDefinitionId = $script:Tag.PolicyDefinitionId,
            [string]$Scope = $script:SubscriptionScope
        )
        [pscustomobject]@{
            Name               = $Name
            DisplayName        = $DisplayName
            PolicyDefinitionId = $PolicyDefinitionId
            Scope              = $Scope
            Id                 = "$Scope/providers/Microsoft.Authorization/policyAssignments/$Name"
        }
    }

    function Select-Tag {
        param([object[]]$Assignment)
        @(Select-LabPolicyAssignment -Assignment $Assignment -SubscriptionId $script:SubscriptionId -Spec $script:Tag)
    }
}

Describe 'Lab 1.3 policy assignment lookup - the guide''s four assignments' {

    It 'names the four assignments the guide, the Bicep path and Invoke-LabGovernance.ps1 create' {
        $script:Specs.Name | Should -Be @('Require-Environment-Tag-RG', 'Enforce-Project-Tag', 'Inherit-Project-Tag', 'Restrict-Azure-Regions')
        $script:Specs.DisplayName | Should -Be @('Require Environment Tag on Resource Groups', 'Enforce Project Tag Value', 'Inherit Project Tag from Resource Group', 'Restrict to Allowed Regions')
        $script:Specs.Step | Should -Be @('1.3.5', '1.3.8', '1.3.8', '1.3.9')
    }

    It 'gives each assignment its own definition, so one never counts as another' {
        @($script:Specs.PolicyDefinitionId | Sort-Object -Unique).Count | Should -Be 4
    }

    It 'asks a managed identity, tagName Project and the definition''s role of the Modify assignment only (#350)' {
        $inherit = $script:Specs | Where-Object { $_.Name -eq 'Inherit-Project-Tag' }
        $inherit.PolicyDefinitionId | Should -Be '/providers/Microsoft.Authorization/policyDefinitions/ea3f2387-9b95-492a-a190-fcdc54f7b070'
        $inherit.DefinitionDisplayName | Should -Be 'Inherit a tag from the resource group if missing'
        $inherit.ExpectedParameter['tagName'] | Should -Be 'Project'
        $inherit.ManagedIdentity | Should -BeTrue
        # Contributor: the built-in definition's roleDefinitionIds, which the Portal grants itself.
        $inherit.RoleDefinitionId | Should -Be '/providers/Microsoft.Authorization/roleDefinitions/b24988ac-6180-42a0-ab88-20f7382dd24c'
        foreach ($deny in @($script:Specs | Where-Object { $_.Name -ne 'Inherit-Project-Tag' })) {
            $deny.ManagedIdentity | Should -BeFalse -Because $deny.Name
            $deny.RoleDefinitionId | Should -BeNullOrEmpty -Because $deny.Name
        }
    }

    It 'matches bicep/main.bicep''s identity, parameter and role for Inherit-Project-Tag' {
        $bicep = Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot '..' 'bicep' 'main.bicep')
        $module = [regex]::Match($bicep, "(?s)module modInheritProjectTagPolicy .*?\r?\n}\r?\n").Value
        $module | Should -Not -BeNullOrEmpty
        $module | Should -Match "tagName:\s*\{\s*value: 'Project'"
        $module | Should -Match 'systemAssigned: true'
        $module | Should -Match ([regex]::Escape("'/providers/Microsoft.Authorization/roleDefinitions/b24988ac-6180-42a0-ab88-20f7382dd24c'"))
        $module | Should -Match 'location: parLocation'
    }

    It 'gives the three Deny assignments in bicep/main.bicep no managed identity, as the Portal and the script do' {
        # AVM policy-assignment/sub-scope defaults managedIdentities to { systemAssigned: true }:
        # left out, every Deny assignment of the Bicep path got an identity the other paths do not
        # create, and the paths ended in different states.
        $bicep = Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot '..' 'bicep' 'main.bicep')
        $modules = @([regex]::Matches($bicep, "(?s)module \w+ 'br/public:avm/res/authorization/policy-assignment/sub-scope:[^']+' = \{.*?\r?\n}\r?\n") |
            ForEach-Object { $_.Value })
        $modules.Count | Should -Be 4
        foreach ($deny in @($script:Specs | Where-Object { -not $_.ManagedIdentity })) {
            $module = @($modules | Where-Object { $_ -match [regex]::Escape("policyDefinitionId: '$($deny.PolicyDefinitionId)'") })
            $module.Count | Should -Be 1 -Because $deny.Name
            $module[0] | Should -Match 'managedIdentities: \{\}' -Because "$($deny.Name) is a Deny assignment"
            $module[0] | Should -Not -Match 'roleDefinitionIds' -Because $deny.Name
        }
    }

    It 'holds the same definition ids and display names as bicep/main.bicep' {
        # The Bicep path sets the names itself; a drift between the two would make the scripts
        # miss every Bicep-made assignment.
        $bicep = Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot '..' 'bicep' 'main.bicep')
        foreach ($spec in $script:Specs) {
            $bicep | Should -Match ([regex]::Escape("name: '$($spec.Name)'"))
            $bicep | Should -Match ([regex]::Escape("policyDefinitionId: '$($spec.PolicyDefinitionId)'"))
            $bicep | Should -Match ([regex]::Escape("displayName: '$($spec.DisplayName)'"))
        }
    }
}

Describe 'Lab 1.3 policy assignment lookup - which assignment is the guide''s (#330)' {

    It 'finds a Portal-made assignment: generated name, the guide''s name as display name' {
        $portal = Get-AssignmentFixture -Name 'aaaaaaaaaaaaaaaaaaaaaaa2' -DisplayName 'Enforce-Project-Tag'
        $found = Select-Tag -Assignment @($portal)
        $found.Count | Should -Be 1
        $found[0].Name | Should -Be 'aaaaaaaaaaaaaaaaaaaaaaa2'
    }

    It 'finds a Bicep-made assignment: fixed name, the Bicep display name' {
        $bicep = Get-AssignmentFixture -Name 'Enforce-Project-Tag' -DisplayName 'Enforce Project Tag Value'
        $found = Select-Tag -Assignment @($bicep)
        $found.Count | Should -Be 1
        $found[0].Name | Should -Be 'Enforce-Project-Tag'
    }

    It 'finds an assignment that carries the Bicep display name under a generated name' {
        $typed = Get-AssignmentFixture -Name 'aaaaaaaaaaaaaaaaaaaaaaa2' -DisplayName 'Enforce Project Tag Value'
        (Select-Tag -Assignment @($typed)).Count | Should -Be 1
    }

    It 'finds nothing when there is no assignment' {
        (Select-Tag -Assignment @()).Count | Should -Be 0
    }

    It 'returns both assignments when two match, so the caller can refuse to act' {
        $portal = Get-AssignmentFixture -Name 'aaaaaaaaaaaaaaaaaaaaaaa2' -DisplayName 'Enforce-Project-Tag'
        $bicep = Get-AssignmentFixture -Name 'Enforce-Project-Tag' -DisplayName 'Enforce Project Tag Value'
        $found = Select-Tag -Assignment @($portal, $bicep)
        $found.Count | Should -Be 2
    }

    It 'does not take an assignment of another definition under the guide''s name' {
        $other = Get-AssignmentFixture -Name 'Enforce-Project-Tag' -DisplayName 'Enforce-Project-Tag' `
            -PolicyDefinitionId '/providers/Microsoft.Authorization/policyDefinitions/00000000-0000-0000-0000-00000000beef'
        (Select-Tag -Assignment @($other)).Count | Should -Be 0
    }

    It 'does not take an assignment under the definition''s own name (the wizard''s prefill)' {
        # The wizard prefills Assignment name with the definition's display name; the guide has
        # the learner replace it, and only the guide's names are accepted.
        $prefill = Get-AssignmentFixture -Name 'aaaaaaaaaaaaaaaaaaaaaaa2' -DisplayName 'Require a tag and its value on resources'
        (Select-Tag -Assignment @($prefill)).Count | Should -Be 0
    }

    It 'does not take an assignment inherited from a management group' {
        # Get-AzPolicyAssignment -Scope also lists the assignments that apply from above.
        $inherited = Get-AssignmentFixture -Name 'Enforce-Project-Tag' -DisplayName 'Enforce Project Tag Value' `
            -Scope '/providers/Microsoft.Management/managementGroups/stub-mg'
        (Select-Tag -Assignment @($inherited)).Count | Should -Be 0
    }

    It 'does not take an assignment on a resource group of the subscription' {
        $onGroup = Get-AssignmentFixture -Name 'Enforce-Project-Tag' -DisplayName 'Enforce Project Tag Value' `
            -Scope "$script:SubscriptionScope/resourceGroups/prod-skycraft-swc-rg"
        (Select-Tag -Assignment @($onGroup)).Count | Should -Be 0
    }

    It 'compares ids, scopes and names without regard to case, as ARM does' {
        $mixed = Get-AssignmentFixture -Name 'aaaaaaaaaaaaaaaaaaaaaaa2' -DisplayName 'enforce-project-tag' `
            -PolicyDefinitionId $script:Tag.PolicyDefinitionId.ToLowerInvariant() -Scope $script:SubscriptionScope.ToUpperInvariant()
        (Select-Tag -Assignment @($mixed)).Count | Should -Be 1
    }

    It 'reads the older Az.Resources shape, whose fields sit under Properties' {
        $old = [pscustomobject]@{
            Name       = 'aaaaaaaaaaaaaaaaaaaaaaa2'
            ResourceId = "$script:SubscriptionScope/providers/Microsoft.Authorization/policyAssignments/aaaaaaaaaaaaaaaaaaaaaaa2"
            Properties = [pscustomobject]@{
                DisplayName        = 'Enforce-Project-Tag'
                PolicyDefinitionId = $script:Tag.PolicyDefinitionId
                Scope              = $script:SubscriptionScope
            }
        }
        $found = Select-Tag -Assignment @($old)
        $found.Count | Should -Be 1
        Get-LabPolicyAssignmentId -Assignment $found[0] | Should -Be $old.ResourceId
    }

    It 'describes an assignment by display name and resource name' {
        $portal = Get-AssignmentFixture -Name 'aaaaaaaaaaaaaaaaaaaaaaa2' -DisplayName 'Enforce-Project-Tag'
        Format-LabPolicyAssignment -Assignment $portal | Should -Be "'Enforce-Project-Tag' (name aaaaaaaaaaaaaaaaaaaaaaa2)"
    }
}

Describe 'Lab 1.3 policy assignment lookup - the Modify assignment Inherit-Project-Tag (#350)' {

    BeforeAll {
        $script:Inherit = $script:Specs | Where-Object { $_.Name -eq 'Inherit-Project-Tag' }
        $script:PrincipalId = '11111111-1111-1111-1111-111111111111'

        # Shaped like Get-AzPolicyAssignment's output in Az.Resources 7 and later: parameters
        # under Parameter.<name>.value, the identity at the top level.
        function Get-InheritFixture {
            param(
                [string]$Name = 'aaaaaaaaaaaaaaaaaaaaaaa4',
                [string]$DisplayName = 'Inherit-Project-Tag',
                [string]$TagName = 'Project',
                [string]$IdentityType = 'SystemAssigned'
            )
            $fixture = Get-AssignmentFixture -Name $Name -DisplayName $DisplayName -PolicyDefinitionId $script:Inherit.PolicyDefinitionId
            $parameter = if ($TagName) { [pscustomobject]@{ tagName = [pscustomobject]@{ value = $TagName } } } else { $null }
            $fixture | Add-Member -NotePropertyName Parameter -NotePropertyValue $parameter
            $fixture | Add-Member -NotePropertyName IdentityType -NotePropertyValue $IdentityType
            $fixture | Add-Member -NotePropertyName IdentityPrincipalId -NotePropertyValue $(if ($IdentityType -eq 'SystemAssigned') { $script:PrincipalId } else { $null })
            $fixture
        }
    }

    It 'finds a Portal-made Inherit-Project-Tag by its definition and display name' {
        $found = @(Select-LabPolicyAssignment -Assignment @(Get-InheritFixture) -SubscriptionId $script:SubscriptionId -Spec $script:Inherit)
        $found.Count | Should -Be 1
    }

    It 'does not count Inherit-Project-Tag as a second Enforce-Project-Tag' {
        # Both carry the Project tag in their names; only the definition tells them apart.
        $inherit = Get-InheritFixture -DisplayName 'Enforce-Project-Tag'
        (Select-Tag -Assignment @($inherit)).Count | Should -Be 0
        $enforce = Get-AssignmentFixture -Name 'Enforce-Project-Tag' -DisplayName 'Enforce Project Tag Value'
        @(Select-LabPolicyAssignment -Assignment @($enforce) -SubscriptionId $script:SubscriptionId -Spec $script:Inherit).Count | Should -Be 0
    }

    It 'reports nothing for tagName Project and a system-assigned identity' {
        @(Get-LabPolicyAssignmentProblem -Assignment (Get-InheritFixture) -Spec $script:Inherit) | Should -BeNullOrEmpty
    }

    It 'reports a wrong tag name' {
        $problems = @(Get-LabPolicyAssignmentProblem -Assignment (Get-InheritFixture -TagName 'Environment') -Spec $script:Inherit)
        $problems | Should -Be @("parameter tagName is 'Environment', expected 'Project'")
    }

    It 'reports a tag name that is not set' {
        $problems = @(Get-LabPolicyAssignmentProblem -Assignment (Get-InheritFixture -TagName '') -Spec $script:Inherit)
        $problems | Should -Be @("parameter tagName is not set, expected 'Project'")
    }

    It 'reports an assignment without a managed identity' {
        $problems = @(Get-LabPolicyAssignmentProblem -Assignment (Get-InheritFixture -IdentityType 'None') -Spec $script:Inherit)
        $problems | Should -Be @('it has no managed identity, expected a system-assigned managed identity (a Modify policy needs one)')
    }

    It 'reads the older Az.Resources shape: Properties.Parameters and an Identity object' {
        $old = [pscustomobject]@{
            Name       = 'Inherit-Project-Tag'
            ResourceId = "$script:SubscriptionScope/providers/Microsoft.Authorization/policyAssignments/Inherit-Project-Tag"
            Identity   = [pscustomobject]@{ Type = 'SystemAssigned'; PrincipalId = $script:PrincipalId }
            Properties = [pscustomobject]@{
                DisplayName        = 'Inherit Project Tag from Resource Group'
                PolicyDefinitionId = $script:Inherit.PolicyDefinitionId
                Scope              = $script:SubscriptionScope
                Parameters         = [pscustomobject]@{ tagName = [pscustomobject]@{ value = 'Project' } }
            }
        }
        @(Select-LabPolicyAssignment -Assignment @($old) -SubscriptionId $script:SubscriptionId -Spec $script:Inherit).Count | Should -Be 1
        Get-LabPolicyAssignmentParameterValue -Assignment $old -Name 'tagName' | Should -Be 'Project'
        (Get-LabPolicyAssignmentIdentity -Assignment $old).PrincipalId | Should -Be $script:PrincipalId
        @(Get-LabPolicyAssignmentProblem -Assignment $old -Spec $script:Inherit) | Should -BeNullOrEmpty
    }

    It 'checks no parameter or identity on the three Deny assignments' {
        $enforce = Get-AssignmentFixture -Name 'Enforce-Project-Tag' -DisplayName 'Enforce Project Tag Value'
        @(Get-LabPolicyAssignmentProblem -Assignment $enforce -Spec $script:Tag) | Should -BeNullOrEmpty
    }

    It 'picks the identity''s role assignments in the subscription, and no one else''s' {
        $roles = @(
            [pscustomobject]@{ Name = 'own-sub';   ObjectId = $script:PrincipalId; Scope = $script:SubscriptionScope }
            [pscustomobject]@{ Name = 'own-rg';    ObjectId = $script:PrincipalId.ToUpperInvariant(); Scope = "$script:SubscriptionScope/resourceGroups/dev-skycraft-swc-rg" }
            [pscustomobject]@{ Name = 'own-mg';    ObjectId = $script:PrincipalId; Scope = '/providers/Microsoft.Management/managementGroups/stub-mg' }
            [pscustomobject]@{ Name = 'other-sub'; ObjectId = '22222222-2222-2222-2222-222222222222'; Scope = $script:SubscriptionScope }
            [pscustomobject]@{ Name = 'own-other'; ObjectId = $script:PrincipalId; Scope = '/subscriptions/99999999-9999-9999-9999-999999999999' }
        )
        $picked = @(Select-LabPolicyIdentityRoleAssignment -RoleAssignment $roles -PrincipalId $script:PrincipalId -SubscriptionId $script:SubscriptionId)
        $picked.Name | Should -Be @('own-sub', 'own-rg')
    }
}

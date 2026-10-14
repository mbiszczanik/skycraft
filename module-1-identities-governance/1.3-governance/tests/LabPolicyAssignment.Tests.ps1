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

Describe 'Lab 1.3 policy assignment lookup - the guide''s three assignments' {

    It 'names the three assignments the guide, the Bicep path and Invoke-LabGovernance.ps1 create' {
        $script:Specs.Name | Should -Be @('Require-Environment-Tag-RG', 'Enforce-Project-Tag', 'Restrict-Azure-Regions')
        $script:Specs.DisplayName | Should -Be @('Require Environment Tag on Resource Groups', 'Enforce Project Tag Value', 'Restrict to Allowed Regions')
        $script:Specs.Step | Should -Be @('1.3.5', '1.3.7', '1.3.8')
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

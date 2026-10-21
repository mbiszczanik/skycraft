<#
.SYNOPSIS
    Finds the Lab 1.3 policy assignments, whichever path created them. Dot-sourced by the lab's
    other scripts; running it on its own does nothing.

.DESCRIPTION
    Test-Lab.ps1, Remove-LabResource.ps1 and Invoke-LabGovernance.ps1 all need to find the three
    assignments of steps 1.3.5, 1.3.8 and 1.3.9. They dot-source this file so that the three
    share one answer to "which assignment is the guide's" (issue #330). It lives in the lab's own
    scripts/ folder, so the lab still reads on its own, and it ends nothing: the script that
    dot-sources it calls Exit-Lab (docs/powershell-standards.md, sections 7.3 and 7.5).

    The two paths name an assignment differently:
    - bicep/main.bicep and Invoke-LabGovernance.ps1 set the resource name (Enforce-Project-Tag)
      and a display name of their own (Enforce Project Tag Value).
    - In the Portal's Assign policy wizard, what the learner types into Assignment name becomes
      the display name only (Enforce-Project-Tag); the resource name is a generated id.

    An assignment is therefore the guide's when it is applied to the subscription itself (not
    inherited from a management group, not on a resource group), assigns the expected built-in
    policy definition, and carries the guide's name as its resource name or as its display name,
    or the Bicep display name as its display name. Ids, scopes and names compare without regard
    to case, as ARM's do.

    The lookup returns every match. A caller that would act on the assignment (remove it, or
    create one when none exists) refuses when there is more than one: it cannot tell which one
    the learner meant, and acting on the wrong one leaves a deny policy behind.

    Functions:
    - Get-LabPolicyAssignmentSpec   the three assignments, with their definition ids and steps
    - Select-LabPolicyAssignment    the assignments in a listing that are one of them
    - Get-LabPolicyAssignmentId     an assignment's full id, to remove it by
    - Format-LabPolicyAssignment    an assignment's display name and resource name, for messages

.EXAMPLE
    . (Join-Path $PSScriptRoot 'LabPolicyAssignment.ps1')
    $assignments = @(Get-AzPolicyAssignment -Scope "/subscriptions/$subscriptionId" -ErrorAction Stop)
    foreach ($spec in Get-LabPolicyAssignmentSpec) {
        $found = @(Select-LabPolicyAssignment -Assignment $assignments -SubscriptionId $subscriptionId -Spec $spec)
    }

.NOTES
    Project: SkyCraft
    Lab: 1.3 - Governance
#>

#Requires -Version 7.0

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

# The three assignments, in the order the guide creates them. Name, DisplayName and
# PolicyDefinitionId are the values bicep/main.bicep sets (tests/LabPolicyAssignment.Tests.ps1
# holds the two files together); DefinitionDisplayName is what the learner searches for in the
# wizard.
function Get-LabPolicyAssignmentSpec {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()

    [pscustomobject]@{
        Name                  = 'Require-Environment-Tag-RG'
        DisplayName           = 'Require Environment Tag on Resource Groups'
        PolicyDefinitionId    = '/providers/Microsoft.Authorization/policyDefinitions/96670d01-0a4d-4649-9c89-2d3abc0a5025'
        DefinitionDisplayName = 'Require a tag on resource groups'
        Step                  = '1.3.5'
    }
    [pscustomobject]@{
        Name                  = 'Enforce-Project-Tag'
        DisplayName           = 'Enforce Project Tag Value'
        PolicyDefinitionId    = '/providers/Microsoft.Authorization/policyDefinitions/1e30110a-5ceb-460c-a204-c1c3969c6d62'
        DefinitionDisplayName = 'Require a tag and its value on resources'
        Step                  = '1.3.8'
    }
    [pscustomobject]@{
        Name                  = 'Restrict-Azure-Regions'
        DisplayName           = 'Restrict to Allowed Regions'
        PolicyDefinitionId    = '/providers/Microsoft.Authorization/policyDefinitions/e56962a6-4747-49cd-b67b-bf8b01975c4c'
        DefinitionDisplayName = 'Allowed locations'
        Step                  = '1.3.9'
    }
}

# One field of an assignment. Az.Resources 7 and later return the fields at the top level; older
# versions kept them under Properties, and the id in ResourceId rather than Id.
function Get-LabPolicyAssignmentField {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Assignment,

        [Parameter(Mandatory = $true)]
        [string]$Field
    )

    $value = $Assignment.$Field
    if (-not $value -and $Assignment.Properties) { $value = $Assignment.Properties.$Field }
    return [string]$value
}

function Get-LabPolicyAssignmentId {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Assignment
    )

    $id = Get-LabPolicyAssignmentField -Assignment $Assignment -Field 'Id'
    if (-not $id) { $id = Get-LabPolicyAssignmentField -Assignment $Assignment -Field 'ResourceId' }
    return $id
}

# Returns the assignments in $Assignment that are the guide's $Spec assignment on the
# subscription: none, one, or - when the Portal and the Bicep path both ran - more.
function Select-LabPolicyAssignment {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]]$Assignment,

        [Parameter(Mandatory = $true)]
        [string]$SubscriptionId,

        [Parameter(Mandatory = $true)]
        [pscustomobject]$Spec
    )

    $subscriptionScope = "/subscriptions/$SubscriptionId"
    foreach ($item in $Assignment) {
        if (-not $item) { continue }

        # Where the assignment is applied: its Scope, or else its id up to the provider segment.
        $scope = Get-LabPolicyAssignmentField -Assignment $item -Field 'Scope'
        if (-not $scope) {
            $scope = (Get-LabPolicyAssignmentId -Assignment $item) -replace '/providers/Microsoft\.Authorization/policyAssignments/[^/]+$', ''
        }
        if ($scope.TrimEnd('/') -ne $subscriptionScope) { continue }

        $definitionId = Get-LabPolicyAssignmentField -Assignment $item -Field 'PolicyDefinitionId'
        if ($definitionId -ne $Spec.PolicyDefinitionId) { continue }

        $displayName = Get-LabPolicyAssignmentField -Assignment $item -Field 'DisplayName'
        if ($item.Name -eq $Spec.Name -or $displayName -in @($Spec.Name, $Spec.DisplayName)) {
            $item
        }
    }
}

function Format-LabPolicyAssignment {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Assignment
    )

    $displayName = Get-LabPolicyAssignmentField -Assignment $Assignment -Field 'DisplayName'
    return "'$displayName' (name $($Assignment.Name))"
}

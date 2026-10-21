<#
.SYNOPSIS
    Finds the Lab 1.3 policy assignments, whichever path created them. Dot-sourced by the lab's
    other scripts; running it on its own does nothing.

.DESCRIPTION
    Test-Lab.ps1, Remove-LabResource.ps1 and Invoke-LabGovernance.ps1 all need to find the four
    assignments of steps 1.3.5, 1.3.8 (two: Enforce-Project-Tag and Inherit-Project-Tag) and
    1.3.9. They dot-source this file so that the scripts share one answer to "which assignment is
    the guide's" (issue #330). It lives in the lab's own scripts/ folder, so the lab still reads
    on its own, and it ends nothing: the script that dot-sources it calls Exit-Lab
    (docs/powershell-standards.md, sections 7.3 and 7.5).

    Inherit-Project-Tag (issue #350) is a Modify assignment: it adds the resource group's Project
    tag to a resource created without one, before Enforce-Project-Tag's Deny evaluates the
    request. It carries a system-assigned managed identity, which the Portal gives the role its
    definition names (Contributor) on the subscription; the Bicep path and
    Invoke-LabGovernance.ps1 grant the same role, so all three paths end in the same state when
    the learner may assign roles (Owner). The role is used only by a remediation task: a
    request-time Modify needs none. The three Deny assignments carry no identity in any path:
    bicep/main.bicep sets managedIdentities to {} on them, because the AVM module would otherwise
    give each one a system-assigned identity. A Deny assignment made by the Bicep path before
    that change still has one, with no role; Remove-LabResource.ps1 handles it like any other
    assignment with an identity.

    The paths name an assignment differently:
    - bicep/main.bicep and Invoke-LabGovernance.ps1 set the resource name (Enforce-Project-Tag)
      and, since issue #406, the guide's name as the display name too.
    - In the Portal's Assign policy wizard, what the learner types into Assignment name becomes
      the display name only (Enforce-Project-Tag); the resource name is a generated id.

    An assignment is therefore the guide's when it is applied to the subscription itself (not
    inherited from a management group, not on a resource group), assigns the expected built-in
    policy definition, and carries the guide's name as its resource name or as its display name,
    or the display name the scripted paths used before issue #406. Ids, scopes and names compare
    without regard to case, as ARM's do. One on the subscription that has the definition but not
    the name, or the name but not the definition, is not the guide's either; the deploy scripts
    stop on it rather than create the guide's next to it (Get-LabPolicyAssignmentNearMiss).

    Every path gives an assignment the guide's display name, description, non-compliance message
    and parameters (issue #406), so a lab built in the Portal and one built by a script end in
    the same state, and the deploy scripts can tell a learner's assignment that differs in effect
    from the lab's (Get-LabPolicyAssignmentDrift).

    The lookup returns every match. A caller that would act on the assignment (remove it, or
    create one when none exists) refuses when there is more than one: it cannot tell which one
    the learner meant, and acting on the wrong one leaves a deny policy behind.

    The four specs differ in their definitions, and an assignment is matched by its definition
    first, so the Modify assignment never counts as a second Enforce-Project-Tag.

    Functions:
    - Get-LabPolicyAssignmentSpec            the four assignments, with their definition ids,
                                             steps, checked parameters and identity
    - Select-LabPolicyAssignment             the assignments in a listing that are one of them
    - Get-LabPolicyAssignmentId              an assignment's full id, to remove it by
    - Format-LabPolicyAssignment             an assignment's display name and resource name
    - Get-LabPolicyAssignmentParameterValue  the value an assignment gives one parameter
    - Get-LabPolicyAssignmentIdentity        an assignment's managed identity: type, principal id
    - Get-LabPolicyAssignmentProblem         what in an assignment differs from its spec
                                             (Test-Lab.ps1's checks)
    - Get-LabPolicyAssignmentDrift           what in an assignment would change its effect
                                             compared with the lab's (the deploy scripts)
    - Get-LabPolicyAssignmentNearMiss        assignments with the definition but not the name,
                                             or the name but not the definition
    - Get-LabPolicyAssignmentPlan            what a deploy does with each assignment: create,
                                             adopt, keep a Portal-made one, or stop
    - Select-LabPolicyIdentityRoleAssignment the role assignments an assignment's identity holds
                                             in the subscription

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

# The four assignments, in the order the guide creates them. Name, DisplayName, Description,
# NonComplianceMessage and Parameter are what the guide has the learner type and pick in the Assign
# policy wizard; bicep/main.bicep and Invoke-LabGovernance.ps1 set the same values, so every path
# ends in the same state (issue #406; tests/LabPolicyAssignment.Tests.ps1 holds the guide, this
# file and the template together). DefinitionDisplayName is what the learner searches for.
#   LegacyDisplayName  the display name the Bicep path and Invoke-LabGovernance.ps1 gave before
#                      issue #406, still matched so the cleanup finds older assignments
#   Parameter          the lab's parameter values; a found assignment with other values is drift
#   ExpectedParameter  parameter values Test-Lab.ps1 checks on the assignment it finds
#   ManagedIdentity    the assignment must carry a system-assigned identity (a Modify needs one)
#   RoleDefinitionId   the role the identity gets on the subscription: the one the built-in
#                      definition lists in roleDefinitionIds, which the Portal grants itself
function Get-LabPolicyAssignmentSpec {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()

    [pscustomobject]@{
        Name                  = 'Require-Environment-Tag-RG'
        DisplayName           = 'Require-Environment-Tag-RG'
        LegacyDisplayName     = 'Require Environment Tag on Resource Groups'
        Description           = 'All resource groups must have an Environment tag'
        NonComplianceMessage  = 'Resource group must have an Environment tag (Development, Production, or Platform)'
        PolicyDefinitionId    = '/providers/Microsoft.Authorization/policyDefinitions/96670d01-0a4d-4649-9c89-2d3abc0a5025'
        DefinitionDisplayName = 'Require a tag on resource groups'
        Step                  = '1.3.5'
        Parameter             = [ordered]@{ tagName = 'Environment' }
        ExpectedParameter     = @{}
        ManagedIdentity       = $false
        RoleDefinitionId      = $null
    }
    [pscustomobject]@{
        Name                  = 'Enforce-Project-Tag'
        DisplayName           = 'Enforce-Project-Tag'
        LegacyDisplayName     = 'Enforce Project Tag Value'
        Description           = 'All resources must have Project tag set to SkyCraft'
        NonComplianceMessage  = 'All resources must be tagged with Project=SkyCraft'
        PolicyDefinitionId    = '/providers/Microsoft.Authorization/policyDefinitions/1e30110a-5ceb-460c-a204-c1c3969c6d62'
        DefinitionDisplayName = 'Require a tag and its value on resources'
        Step                  = '1.3.8'
        Parameter             = [ordered]@{ tagName = 'Project'; tagValue = 'SkyCraft' }
        ExpectedParameter     = @{}
        ManagedIdentity       = $false
        RoleDefinitionId      = $null
    }
    [pscustomobject]@{
        Name                  = 'Inherit-Project-Tag'
        DisplayName           = 'Inherit-Project-Tag'
        LegacyDisplayName     = 'Inherit Project Tag from Resource Group'
        Description           = 'Resources get the Project tag of their resource group when they are created without it'
        # The guide's Modify assignment has no non-compliance message.
        NonComplianceMessage  = $null
        PolicyDefinitionId    = '/providers/Microsoft.Authorization/policyDefinitions/ea3f2387-9b95-492a-a190-fcdc54f7b070'
        DefinitionDisplayName = 'Inherit a tag from the resource group if missing'
        Step                  = '1.3.8'
        Parameter             = [ordered]@{ tagName = 'Project' }
        ExpectedParameter     = @{ tagName = 'Project' }
        ManagedIdentity       = $true
        # Contributor, the definition's roleDefinitionIds.
        RoleDefinitionId      = '/providers/Microsoft.Authorization/roleDefinitions/b24988ac-6180-42a0-ab88-20f7382dd24c'
    }
    [pscustomobject]@{
        Name                  = 'Restrict-Azure-Regions'
        DisplayName           = 'Restrict-Azure-Regions'
        LegacyDisplayName     = 'Restrict to Allowed Regions'
        Description           = 'Resources can only be created in Sweden Central and North Europe'
        NonComplianceMessage  = 'Resources must be deployed to Sweden Central or North Europe regions only'
        PolicyDefinitionId    = '/providers/Microsoft.Authorization/policyDefinitions/e56962a6-4747-49cd-b67b-bf8b01975c4c'
        DefinitionDisplayName = 'Allowed locations'
        Step                  = '1.3.9'
        Parameter             = [ordered]@{ listOfAllowedLocations = @('swedencentral', 'northeurope') }
        ExpectedParameter     = @{}
        ManagedIdentity       = $false
        RoleDefinitionId      = $null
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

# Where an assignment is applied: its Scope, or else its id up to the provider segment.
function Get-LabPolicyAssignmentScope {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Assignment
    )

    $scope = Get-LabPolicyAssignmentField -Assignment $Assignment -Field 'Scope'
    if (-not $scope) {
        $scope = (Get-LabPolicyAssignmentId -Assignment $Assignment) -replace '/providers/Microsoft\.Authorization/policyAssignments/[^/]+$', ''
    }
    return $scope.TrimEnd('/')
}

# Whether an assignment carries one of $Spec's names: the guide's as resource or display name, or
# the display name the scripted paths used before issue #406.
function Test-LabPolicyAssignmentName {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Assignment,

        [Parameter(Mandatory = $true)]
        [pscustomobject]$Spec
    )

    $displayName = Get-LabPolicyAssignmentField -Assignment $Assignment -Field 'DisplayName'
    return ($Assignment.Name -eq $Spec.Name -or $displayName -in @($Spec.Name, $Spec.DisplayName, $Spec.LegacyDisplayName))
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
        if ((Get-LabPolicyAssignmentScope -Assignment $item) -ne $subscriptionScope) { continue }

        $definitionId = Get-LabPolicyAssignmentField -Assignment $item -Field 'PolicyDefinitionId'
        if ($definitionId -ne $Spec.PolicyDefinitionId) { continue }

        if (Test-LabPolicyAssignmentName -Assignment $item -Spec $Spec) { $item }
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

# The value an assignment gives one parameter, or $null when it gives none. Az.Resources 7 and
# later return the parameters as Parameter.<name>.value; older versions kept them under
# Properties.Parameters. Property names compare without regard to case, so 'value' and 'Value'
# both read.
function Get-LabPolicyAssignmentParameterValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Assignment,

        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    foreach ($bag in @($Assignment.Parameter, $Assignment.Properties.Parameters)) {
        if ($null -eq $bag) { continue }
        $entry = if ($bag -is [System.Collections.IDictionary]) { $bag[$Name] } else { $bag.$Name }
        if ($null -eq $entry) { continue }
        $value = if ($entry -is [System.Collections.IDictionary]) { $entry['value'] } else { $entry.value }
        if ($null -ne $value) { return $value }
    }
    return $null
}

# An assignment's managed identity: its type ('SystemAssigned', 'UserAssigned' or empty) and the
# principal id of a system-assigned one. Az.Resources 7 and later return IdentityType and
# IdentityPrincipalId at the top level; older versions, and the -BackwardCompatible shape, an
# Identity object with Type (or IdentityType) and PrincipalId.
function Get-LabPolicyAssignmentIdentity {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Assignment
    )

    $type = [string]$Assignment.IdentityType
    $principalId = [string]$Assignment.IdentityPrincipalId
    if ($Assignment.Identity) {
        if (-not $type) { $type = [string]$Assignment.Identity.Type }
        if (-not $type) { $type = [string]$Assignment.Identity.IdentityType }
        if (-not $principalId) { $principalId = [string]$Assignment.Identity.PrincipalId }
    }
    if ($type -eq 'None') { $type = '' }
    [pscustomobject]@{ Type = $type; PrincipalId = $principalId }
}

# What in a found assignment differs from its spec, one line each; nothing when it matches. Only
# the spec's ExpectedParameter values and its managed identity are compared: the three Deny
# assignments are matched by definition and name alone, as before issue #350.
function Get-LabPolicyAssignmentProblem {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Assignment,

        [Parameter(Mandatory = $true)]
        [pscustomobject]$Spec
    )

    if ($Spec.ExpectedParameter) {
        foreach ($name in @($Spec.ExpectedParameter.Keys | Sort-Object)) {
            $expected = [string]$Spec.ExpectedParameter[$name]
            $actual = Get-LabPolicyAssignmentParameterValue -Assignment $Assignment -Name $name
            if ($null -eq $actual) {
                "parameter $name is not set, expected '$expected'"
            }
            elseif ([string]$actual -ne $expected) {
                "parameter $name is '$actual', expected '$expected'"
            }
        }
    }

    if ($Spec.ManagedIdentity) {
        $identity = Get-LabPolicyAssignmentIdentity -Assignment $Assignment
        if ($identity.Type -notmatch 'SystemAssigned') {
            $found = if ($identity.Type) { "a $($identity.Type) identity" } else { 'no managed identity' }
            "it has $found, expected a system-assigned managed identity (a Modify policy needs one)"
        }
    }
}

# What in a found assignment would change its effect compared with the lab's, one line each;
# nothing when it has the lab's parameters, enforcement mode, exclusions and identity (issue #406).
# The deploy scripts refuse to accept an assignment that differs rather than leave a learner's assignment
# with other values in place, or overwrite it, without a word. Lists compare as sets, values
# without regard to case. Texts (display name, description, message) do not change the effect
# and are not compared. An assignment that leaves enforcement mode unset enforces (ARM's default).
function Get-LabPolicyAssignmentDrift {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Assignment,

        [Parameter(Mandatory = $true)]
        [pscustomobject]$Spec
    )

    foreach ($name in @($Spec.Parameter.Keys)) {
        $expected = @($Spec.Parameter[$name] | ForEach-Object { ([string]$_).ToLowerInvariant() } | Sort-Object)
        $actualValue = Get-LabPolicyAssignmentParameterValue -Assignment $Assignment -Name $name
        $expectedText = @($Spec.Parameter[$name]) -join ', '
        if ($null -eq $actualValue) {
            "parameter $name is not set, the lab's is '$expectedText'"
            continue
        }
        $actual = @($actualValue | ForEach-Object { ([string]$_).ToLowerInvariant() } | Sort-Object)
        if (($actual -join "`n") -ne ($expected -join "`n")) {
            "parameter $name is '$(@($actualValue) -join ', ')', the lab's is '$expectedText'"
        }
    }

    $mode = Get-LabPolicyAssignmentField -Assignment $Assignment -Field 'EnforcementMode'
    if ($mode -and $mode -ne 'Default') {
        "enforcement mode is '$mode', the lab's is 'Default'"
    }

    # Basics > Exclusions: an excluded scope escapes the policy.
    $notScopes = @(@($Assignment.NotScope) + @($Assignment.Properties.NotScopes) | Where-Object { $_ })
    if ($notScopes.Count -gt 0) {
        "it excludes $($notScopes -join ', '), the lab's excludes nothing"
    }

    if ($Spec.ManagedIdentity) {
        $identity = Get-LabPolicyAssignmentIdentity -Assignment $Assignment
        if ($identity.Type -notmatch 'SystemAssigned') {
            $found = if ($identity.Type) { "a $($identity.Type) identity" } else { 'no managed identity' }
            "it has $found, the lab's has a system-assigned managed identity"
        }
    }
}

# What a deploy script does with each of the four assignments, given the subscription's listing
# (issue #406). Action is one of:
#   Create     none exists; the deploy creates it
#   Adopt      one exists under the fixed resource name (an earlier Bicep or script run); the
#              deploy writes the lab's values over it
#   Keep       one exists under another resource name (the Portal's generated id); the deploy
#              leaves it as it is and creates no second one
#   Duplicate  more than one matches; the deploy must stop, it cannot tell which is the lab's
#   Unmatched  none matches, but one has the definition without the guide's name, or the name
#              without the definition; the deploy must stop, a new one would sit next to it
# Drift lists what in the one found assignment differs in effect from the lab's, or, for
# Unmatched, each near miss; a deploy must stop then too.
function Get-LabPolicyAssignmentPlan {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]]$Assignment,

        [Parameter(Mandatory = $true)]
        [string]$SubscriptionId
    )

    foreach ($spec in Get-LabPolicyAssignmentSpec) {
        $found = @(Select-LabPolicyAssignment -Assignment $Assignment -SubscriptionId $SubscriptionId -Spec $spec)
        $nearMiss = if ($found.Count -eq 0) { @(Get-LabPolicyAssignmentNearMiss -Assignment $Assignment -SubscriptionId $SubscriptionId -Spec $spec) } else { @() }
        $action = if ($nearMiss.Count -gt 0) { 'Unmatched' }
        elseif ($found.Count -eq 0) { 'Create' }
        elseif ($found.Count -gt 1) { 'Duplicate' }
        elseif ($found[0].Name -eq $spec.Name) { 'Adopt' }
        else { 'Keep' }
        $drift = if ($found.Count -eq 1) { @(Get-LabPolicyAssignmentDrift -Assignment $found[0] -Spec $spec) } else { @($nearMiss) }
        [pscustomobject]@{
            Spec   = $spec
            Found  = $found
            Action = $action
            Drift  = $drift
        }
    }
}

# The assignments on the subscription that are almost the guide's $Spec one, one line each with
# what to do: its definition under another name (the learner kept the wizard's prefill), or its
# name on another definition (a look-alike such as "Inherit a tag from the resource group", which
# overwrites the tag). A deploy that created the lab's assignment next to one would leave two
# (issue #406).
function Get-LabPolicyAssignmentNearMiss {
    [CmdletBinding()]
    [OutputType([string])]
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
        if ((Get-LabPolicyAssignmentScope -Assignment $item) -ne $subscriptionScope) { continue }

        $sameDefinition = (Get-LabPolicyAssignmentField -Assignment $item -Field 'PolicyDefinitionId') -eq $Spec.PolicyDefinitionId
        $sameName = Test-LabPolicyAssignmentName -Assignment $item -Spec $Spec
        $label = Format-LabPolicyAssignment -Assignment $item
        if ($sameDefinition -and -not $sameName) {
            "$label assigns '$($Spec.DefinitionDisplayName)' under another name than the guide's; rename it to '$($Spec.DisplayName)' (Edit assignment > Assignment name) or delete it"
        }
        elseif ($sameName -and -not $sameDefinition) {
            "$label assigns another definition than '$($Spec.DefinitionDisplayName)'; delete it"
        }
    }
}

# The role assignments that the principal $PrincipalId holds in the subscription: on the
# subscription itself or on a scope below it. Get-AzRoleAssignment -Scope also lists assignments
# inherited from a management group; those are not the lab's. Read from a listing rather than
# with Get-AzRoleAssignment -ObjectId, which looks the principal up in Microsoft Graph first and
# fails where the Az context cannot reach Graph.
function Select-LabPolicyIdentityRoleAssignment {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]]$RoleAssignment,

        [Parameter(Mandatory = $true)]
        [string]$PrincipalId,

        [Parameter(Mandatory = $true)]
        [string]$SubscriptionId
    )

    $subscriptionScope = "/subscriptions/$SubscriptionId"
    foreach ($item in $RoleAssignment) {
        if (-not $item -or [string]$item.ObjectId -ne $PrincipalId) { continue }
        $scope = ([string]$item.Scope).TrimEnd('/')
        if ($scope -eq $subscriptionScope -or $scope -like "$subscriptionScope/*") {
            $item
        }
    }
}

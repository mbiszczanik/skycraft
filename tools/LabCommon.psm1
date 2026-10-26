<#
.SYNOPSIS
    Shared helpers for the lab scripts. Today: Exit-Lab, which ends a lab script with the right
    exit code without closing the learner's PowerShell session, the role assignment helpers,
    which read, create and remove Azure role assignments without Microsoft Graph, and the budget
    helpers, which list and delete Cost Management budgets without Az.Billing, and Import-LabModule, which
    imports the modules a script needs, the Microsoft Graph ones at one version, or tells the
    learner what to install.

.DESCRIPTION
    Every lab script serves two callers at once (issue #301):

      - the learner, who runs it at an interactive prompt (`.\scripts\Test-Lab.ps1`) on their own
        machine or in Cloud Shell, and keeps working in that session afterwards;
      - the automated callers, which start it as a process: tools/Invoke-LabCycle.ps1 through
        tools/Invoke-LabScript.ps1, CI, or anyone running `pwsh -File <script>`.

    PowerShell 7 drops the exit code of a script run as `pwsh -File` when the script declares
    `#Requires -Modules` for a module it has to auto-import - every Az.* module qualifies - so the
    process reports 0 for a failed run (issue #104). `$Host.SetShouldExit(<code>)` carries the code
    out, but it asks the host to end the whole process, not just the script: called from a script
    the learner ran at the prompt, it closes their PowerShell window, even with code 0 (issue #257).

    Exit-Lab settles both. It exits 1 when the failure count is above zero and 0 otherwise, and it
    calls `$Host.SetShouldExit` only when the calling script is the process entry point:

      - the process was started with `-File` (or a script path in its place) and without
        `-NoExit`, read from [Environment]::GetCommandLineArgs(); and
      - the outermost frame of the call stack is the script that called Exit-Lab, so the script
        was not called by another script (the lab cycle's launcher shim), by a typed command line
        (an interactive prompt, `-Command`) or by a test runner.

    In every other case it is a plain `exit`, which ends the script, sets $LASTEXITCODE for the
    caller and leaves the session open. A plain `exit` already reaches the caller in all of those
    cases: under `-Command` the process takes $LASTEXITCODE, and the launcher shim re-exits with it.

    Never `exit $failCount`: an exit code is one byte on Linux, so 256 failures would read as 0.

    `exit` inside a module function ends the script that called the function, not just the
    function, and sets $LASTEXITCODE - measured on PowerShell 7.6. So a lab script ends with
    `Exit-Lab -FailureCount $failCount` where it used to end with `exit`.

    Import it from a lab script by a path relative to the script, which holds in any clone of the
    repository, Cloud Shell included:

        Import-Module (Join-Path $PSScriptRoot '../../../tools/LabCommon.psm1') -Force -Verbose:$false

    Role assignments (issue #397). Every form of Get-AzRoleAssignment, -Scope alone included,
    and New-AzRoleAssignment / Remove-AzRoleAssignment call Microsoft Graph to resolve the
    principals. Where the Az sign-in cannot get a Graph token without interaction (a tenant whose
    Conditional Access asks for it), they fail with "Authentication failed against resource
    MicrosoftGraphEndpointResourceId", although the Azure Resource Manager token works. Lab
    scripts therefore go to the ARM role assignments API through Invoke-AzRestMethod, which needs
    only the ARM token:

        Get-LabArmRoleAssignment     lists the assignments at a scope, optionally for one principal
        New-LabArmRoleAssignment     creates one for a principal whose object id the script has
        Remove-LabArmRoleAssignment  deletes one by its id
        Get-LabBuiltInRoleId         the fixed id of a built-in role the labs use, by name

    A request that ARM answers with a status outside 2xx throws, with the status, the error code
    and the message: a failed read is never an empty list. What these helpers cannot do is name
    a principal: finding a user or a group by name still needs Microsoft Graph, and a script that
    does so says which sign-in provides it (Get-LabGraphSignInHint).

    Budgets (issue #411). Az.Billing 2.3.0 sends every Consumption request, Get-AzConsumptionBudget
    and Remove-AzConsumptionBudget included, at api-version 2018-01-31, which current
    subscriptions refuse with 422 ("Please use version 2018-12-01-preview or later"). Lab scripts
    therefore go to the Consumption budgets API through Invoke-AzRestMethod, at 2023-05-01 (the
    version az consumption uses):

        Get-LabArmBudget     lists the budgets at a subscription or resource group scope
        Remove-LabArmBudget  deletes one by name at such a scope

    They follow the same rule as the role assignment helpers: a status outside 2xx throws with
    the status, the error code and the service's message, so a failed read is never "no budget".

    Import-LabModule (issue #375) imports the modules a script needs where `#Requires -Modules`
    cannot help the learner: Azure Cloud Shell ships the Az modules and a basic set of Microsoft
    Graph modules, but not Microsoft.Graph.Users, and `#Requires` stops the script with
    PowerShell's own error, which names no install command. It imports the Graph modules at one
    version, since a session loads only one Microsoft.Graph.Authentication; when a module is
    missing or not installed at that version, it prints the `Install-Module` line for it and
    returns $false, and the script ends itself with `Exit-Lab -FailureCount 1`:

        $labModule = @('Microsoft.Graph.Authentication', 'Microsoft.Graph.Users')
        if (-not (Import-LabModule -Name $labModule)) { Exit-Lab -FailureCount 1 }

    The rest of #301 (Invoke-LabCheck, Get-LabResourceOrFail, Assert-LabSubscription) is not here
    yet. tests/Exit-Code-Propagation.Tests.ps1 requires every lab script, except a helper that
    lab scripts dot-source, to import this module and call Exit-Lab, forbids a direct
    $Host.SetShouldExit and any non-zero `exit`, and proves both callers with real pwsh processes.

.EXAMPLE
    Import-Module (Join-Path $PSScriptRoot '../../../tools/LabCommon.psm1') -Force -Verbose:$false
    Exit-Lab -FailureCount $failCount

.NOTES
    Project: SkyCraft
    Issues: #257, #301, #375, #397, #411
#>

#Requires -Version 7.0

$ErrorActionPreference = 'Stop'

function Test-LabProcessEntryPoint {
    <#
    .SYNOPSIS
        Tells whether a script is the entry point of a `pwsh -File` process that ends with it.

    .DESCRIPTION
        True only when both hold:

          - the command line starts the process with -File (any prefix of it, with -, -- or /),
            or with a bare .ps1 path in its place, and carries no -NoExit before it. Arguments
            after the script path belong to the script and are not read. -Command,
            -CommandWithArgs and -EncodedCommand make it false: the process then runs typed
            text, not the script.
          - the outermost frame of the call stack is the calling script itself.

        A pure function of its inputs so the suite can test every shape of command line without
        starting a process for each.

    .PARAMETER CommandLineArgs
        The process command line, as [Environment]::GetCommandLineArgs() returns it: element 0 is
        the executable and is skipped.

    .PARAMETER OutermostScript
        The ScriptName of the outermost call-stack frame; empty for a typed command line.

    .PARAMETER CallerScript
        The path of the script that called Exit-Lab.

    .NOTES
        Project: SkyCraft
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter()]
        [AllowEmptyCollection()]
        [string[]]$CommandLineArgs = @(),

        [Parameter()]
        [AllowEmptyString()]
        [string]$OutermostScript = '',

        [Parameter()]
        [AllowEmptyString()]
        [string]$CallerScript = ''
    )

    if (-not $CallerScript -or -not $OutermostScript) { return $false }

    $comparison = if ($IsWindows) { [System.StringComparison]::OrdinalIgnoreCase } else { [System.StringComparison]::Ordinal }
    if (-not [string]::Equals($OutermostScript, $CallerScript, $comparison)) { return $false }

    $fileMode = $false
    $noExit   = $false
    foreach ($argument in @($CommandLineArgs | Select-Object -Skip 1)) {
        if ($argument -match '^(--|-|/)(?<name>[A-Za-z]+)(:.*)?$') {
            $name = $Matches['name'].ToLowerInvariant()
            if ('file'.StartsWith($name)) { $fileMode = $true; break }
            if ($name.Length -ge 3 -and 'noexit'.StartsWith($name)) { $noExit = $true; continue }
            # -CommandWithArgs (-cwa, pwsh 7.4+) is not a prefix of -Command, so it is named.
            if ('command'.StartsWith($name) -or $name -in 'e', 'ec', 'cwa', 'commandwithargs' -or
                ($name.Length -ge 2 -and 'encodedcommand'.StartsWith($name))) {
                return $false
            }
            continue
        }
        # A bare argument is a switch's value (-ExecutionPolicy Bypass) or, when it names a
        # script, the script pwsh runs as if after -File.
        if ($argument -match '\.ps1$') { $fileMode = $true; break }
    }

    return ($fileMode -and -not $noExit)
}

function Exit-Lab {
    <#
    .SYNOPSIS
        Ends the calling lab script: exit 1 when anything failed, 0 otherwise.

    .DESCRIPTION
        Exits 1 when -FailureCount is above zero and 0 when it is zero. Calls
        $Host.SetShouldExit with the same code only when the calling script is the entry point of
        a `pwsh -File` process (see Test-LabProcessEntryPoint), where `#Requires -Modules` would
        otherwise drop the code (#104). At an interactive prompt, under -Command and when another
        script called the lab script, it is a plain `exit`: the session stays open and
        $LASTEXITCODE holds the code (#257).

        Call it from the lab script itself or from a function defined in it, not from a file the
        script dot-sources: the entry-point check compares the caller's file with the script the
        process started.

        Typed at the prompt, outside any script, it does nothing but warn. A lab script imports
        the module into the session it runs in, so Exit-Lab stays available there afterwards, and
        an `exit` from the prompt would close the learner's session (#257).

        With -Verbose it says which way it ends - "SetShouldExit(<code>)" as the entry point,
        "plain exit <code>" otherwise - so the suite can prove the entry-point decision in a real
        `pwsh -File` process on a machine without Az.Accounts, where the #104 fault itself does
        not reproduce.

    .PARAMETER FailureCount
        How many checks, steps or preconditions failed. Above zero exits 1, zero exits 0. The count
        is never the exit code itself, which would wrap at 256.

    .EXAMPLE
        Exit-Lab -FailureCount $failCount

    .EXAMPLE
        Write-Host "Not logged in." -ForegroundColor Red; Exit-Lab -FailureCount 1

    .NOTES
        Project: SkyCraft
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateRange(0, [int]::MaxValue)]
        [int]$FailureCount
    )

    $code   = if ($FailureCount -gt 0) { 1 } else { 0 }
    $caller = [string]$MyInvocation.PSCommandPath

    if (-not $caller) {
        Write-Warning "Exit-Lab ends a lab script; typed at the prompt it does nothing (it would have exited $code)."
        return
    }

    $stack     = @(Get-PSCallStack)
    $outermost = if ($stack.Count -gt 0) { [string]$stack[-1].ScriptName } else { '' }

    $entryPoint = Test-LabProcessEntryPoint `
        -CommandLineArgs ([Environment]::GetCommandLineArgs()) `
        -OutermostScript $outermost `
        -CallerScript $caller

    if ($entryPoint) {
        Write-Verbose "Exit-Lab: entry point of a pwsh -File process, SetShouldExit($code)"
        $Host.SetShouldExit($code)
    }
    else {
        Write-Verbose "Exit-Lab: not the process entry point, plain exit $code"
    }

    exit $code
}

# --- Role assignments through the Azure Resource Manager API (issue #397) ---------------------

$script:LabRoleAssignmentApiVersion = '2022-04-01'

# The built-in roles the lab scripts assign or look for. A built-in role has the same id in every
# tenant, so no lookup is needed to turn its name into the id ARM stores.
$script:LabBuiltInRoles = [ordered]@{
    'Owner'                              = '8e3af657-a8ff-443c-a75c-2fe8c4bcb635'
    'Contributor'                        = 'b24988ac-6180-42a0-ab88-20f7382dd24c'
    'Reader'                             = 'acdd72a7-3385-48ef-bd42-f606fba81ae7'
    'Storage Blob Data Contributor'      = 'ba92f5b4-2d11-453d-a403-e96b0029c9fe'
    'Storage Blob Data Owner'            = 'b7e6dc6d-f1e8-4753-8033-0f276bb0955b'
    'Storage Account Backup Contributor' = 'e5e2a7ff-d759-4cd2-bb51-3152d37e2eb1'
}

function Get-LabBuiltInRoleId {
    <#
    .SYNOPSIS
        Returns the id (a GUID) of a built-in role the labs use, by its name.

    .DESCRIPTION
        Owner, Contributor, Reader, Storage Blob Data Contributor, Storage Blob Data Owner and
        Storage Account Backup Contributor. A built-in role has the same id in every tenant, so
        this reads no directory and no subscription. A name not in the list throws: add it here
        with its id from the Azure built-in roles reference rather than look it up at run time.

    .PARAMETER Name
        The role's name, as the Portal shows it.

    .EXAMPLE
        Get-LabBuiltInRoleId -Name 'Owner'

    .NOTES
        Project: SkyCraft
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Name
    )

    foreach ($key in $script:LabBuiltInRoles.Keys) {
        if ($key -eq $Name) { return $script:LabBuiltInRoles[$key] }
    }
    throw "Get-LabBuiltInRoleId: '$Name' is not one of the built-in roles the labs use ($(@($script:LabBuiltInRoles.Keys) -join ', '))."
}

function Get-LabGraphSignInHint {
    <#
    .SYNOPSIS
        Names the sign-in that gives a script Microsoft Graph, for its failure message.

    .DESCRIPTION
        A lab script that finds a user or a group by name needs Microsoft Graph. Az PowerShell
        (Get-AzADUser, Get-AzADGroup) uses the Graph token of the Az sign-in, which a tenant's
        Conditional Access can refuse to issue without interaction; Microsoft Graph PowerShell
        (Get-MgUser, Get-MgGroup) has its own sign-in. The text is the same everywhere, so a
        learner who meets it in one lab recognises it in the next.

    .PARAMETER Client
        Az for a script that reads the directory through Az PowerShell, MgGraph for one that uses
        Microsoft Graph PowerShell.

    .EXAMPLE
        Write-Host "[ERROR] Could not read Entra ID: $_ $(Get-LabGraphSignInHint -Client Az)"

    .NOTES
        Project: SkyCraft
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Az', 'MgGraph')]
        [string]$Client
    )

    if ($Client -eq 'Az') {
        return "Finding users and groups by name needs Microsoft Graph; sign in again with 'Connect-AzAccount -AuthScope MicrosoftGraphEndpointResourceId' and run the script again."
    }
    return "Finding users and groups by name needs Microsoft Graph; sign in with 'Connect-MgGraph -Scopes User.ReadWrite.All,Group.ReadWrite.All,Directory.ReadWrite.All' (Lab 1.1's scopes) and run the script again."
}

# Sends one ARM request (role assignments, budgets) and returns the parsed body ($null when there
# is none). A status outside 2xx throws with the status, ARM's error code and its message, so no
# caller can read a refused or failed request as an empty answer. Invoke-AzRestMethod itself throws
# when it cannot get a token or reach ARM.
function Invoke-LabArmRequest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('GET', 'PUT', 'DELETE')]
        [string]$Method,

        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter()]
        [string]$Payload
    )

    $request = @{ Path = $Path; Method = $Method; ErrorAction = 'Stop' }
    if ($Payload) { $request.Payload = $Payload }
    $response = Invoke-AzRestMethod @request

    $status = [int]$response.StatusCode
    $target = ($Path -split '\?')[0]
    $success = $status -ge 200 -and $status -le 299
    $body = $null
    if ($response.Content) {
        try {
            $body = $response.Content | ConvertFrom-Json -Depth 20
        }
        catch {
            # An error body may be plain text; a success body that is not JSON is not an answer.
            if ($success) { throw "ARM $Method $target returned HTTP $status with a body that is not JSON: $($response.Content)" }
        }
    }

    if (-not $success) {
        $code = if ($body -and $body.error -and $body.error.code) { [string]$body.error.code } else { "HTTP$status" }
        $message = if ($body -and $body.error -and $body.error.message) { [string]$body.error.message } else { [string]$response.Content }
        $exception = [System.InvalidOperationException]::new("ARM $Method $target returned HTTP $status ($code): $message")
        $exception.Data['StatusCode'] = $status
        $exception.Data['ErrorCode'] = $code
        throw [System.Management.Automation.ErrorRecord]::new($exception, $code, [System.Management.Automation.ErrorCategory]::InvalidResult, $target)
    }

    return $body
}

# GETs a list and follows nextLink to the last page, returning every item of 'value'. A 2xx
# answer without 'value', or a nextLink already followed, throws under the caller's name.
function Invoke-LabArmList {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [string]$Caller
    )

    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    while ($Path) {
        if (-not $seen.Add($Path)) { throw "${Caller}: ARM returned the same nextLink twice ($Path)." }
        $body = Invoke-LabArmRequest -Method GET -Path $Path
        if ($null -eq $body -or $body.PSObject.Properties.Name -notcontains 'value') {
            throw "${Caller}: ARM answered GET $(($Path -split '\?')[0]) without a 'value' list."
        }
        foreach ($item in @($body.value)) {
            if ($item) { $item }
        }
        # nextLink is an absolute URL on the ARM endpoint; Invoke-AzRestMethod -Path takes the
        # part after the host.
        $Path = if ($body.nextLink) { ([uri][string]$body.nextLink).PathAndQuery } else { $null }
    }
}

# One role assignment as ARM returns it, in the shape the lab scripts read: the field names of
# Get-AzRoleAssignment's output where it has one (ObjectId, RoleDefinitionId as a bare GUID,
# RoleAssignmentId), and the ARM names beside them. RoleDefinitionName is filled only for the
# built-in roles Get-LabBuiltInRoleId knows; compare RoleDefinitionId, not the name.
function ConvertTo-LabArmRoleAssignment {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Item
    )

    $properties = $Item.properties
    $definitionId = [string]$properties.roleDefinitionId
    $definitionGuid = ($definitionId -split '/')[-1]
    $definitionName = ''
    foreach ($key in $script:LabBuiltInRoles.Keys) {
        if ($script:LabBuiltInRoles[$key] -eq $definitionGuid) { $definitionName = $key }
    }

    [pscustomobject]@{
        PSTypeName               = 'SkyCraft.LabRoleAssignment'
        RoleAssignmentId         = [string]$Item.id
        RoleAssignmentName       = [string]$Item.name
        Scope                    = [string]$properties.scope
        ObjectId                 = [string]$properties.principalId
        PrincipalId              = [string]$properties.principalId
        ObjectType               = [string]$properties.principalType
        PrincipalType            = [string]$properties.principalType
        RoleDefinitionId         = $definitionGuid
        RoleDefinitionResourceId = $definitionId
        RoleDefinitionName       = $definitionName
        Condition                = [string]$properties.condition
    }
}

function Get-LabArmRoleAssignment {
    <#
    .SYNOPSIS
        Lists the role assignments at a scope from the ARM role assignments API, without
        Microsoft Graph.

    .DESCRIPTION
        GET <scope>/providers/Microsoft.Authorization/roleAssignments (api-version 2022-04-01)
        through Invoke-AzRestMethod, following nextLink until the last page. What ARM returns:

          - with no filter: the assignments at the scope, above it (inherited from a resource
            group, the subscription or a management group) and below it;
          - with -PrincipalId: the same, for that principal only ($filter=principalId eq '<id>');
          - with -AtScope: the assignments at the scope and above it ($filter=atScope()).

        So a caller that wants the assignments made at the scope itself compares Scope. A status
        outside 2xx throws (with the status, ARM's error code and message): a failed read is never
        an empty list. Get-AzRoleAssignment is not used, because every form of it calls Microsoft
        Graph to resolve the principals (issue #397).

    .PARAMETER Scope
        The scope, such as /subscriptions/<id> or a resource id.

    .PARAMETER PrincipalId
        The object id of one principal (a GUID).

    .PARAMETER AtScope
        Only the assignments at the scope and above it.

    .OUTPUTS
        SkyCraft.LabRoleAssignment objects: RoleAssignmentId, RoleAssignmentName, Scope, ObjectId,
        PrincipalId, ObjectType, PrincipalType, RoleDefinitionId (the role's GUID),
        RoleDefinitionResourceId, RoleDefinitionName (built-in roles the labs use only) and
        Condition (empty when the assignment has none).

    .EXAMPLE
        Get-LabArmRoleAssignment -Scope "/subscriptions/$subId" -PrincipalId $principalId

    .NOTES
        Project: SkyCraft
    #>
    [CmdletBinding(DefaultParameterSetName = 'All')]
    param(
        [Parameter(Mandatory)]
        [ValidatePattern('^/')]
        [string]$Scope,

        [Parameter(Mandatory, ParameterSetName = 'Principal')]
        [ValidateScript({ $parsed = [guid]::Empty; [guid]::TryParse($_, [ref]$parsed) })]
        [string]$PrincipalId,

        [Parameter(Mandatory, ParameterSetName = 'AtScope')]
        [switch]$AtScope
    )

    $query = "api-version=$script:LabRoleAssignmentApiVersion"
    if ($PrincipalId) {
        $query += '&$filter=' + [uri]::EscapeDataString("principalId eq '$PrincipalId'")
    }
    elseif ($AtScope) {
        $query += '&$filter=' + [uri]::EscapeDataString('atScope()')
    }

    $path = "$($Scope.TrimEnd('/'))/providers/Microsoft.Authorization/roleAssignments?$query"
    foreach ($item in Invoke-LabArmList -Path $path -Caller 'Get-LabArmRoleAssignment') {
        ConvertTo-LabArmRoleAssignment -Item $item
    }
}

function New-LabArmRoleAssignment {
    <#
    .SYNOPSIS
        Creates a role assignment through the ARM role assignments API, without Microsoft Graph.

    .DESCRIPTION
        PUT <scope>/providers/Microsoft.Authorization/roleAssignments/<new GUID> (api-version
        2022-04-01) through Invoke-AzRestMethod, with roleDefinitionId, principalId and, when the
        caller knows it, principalType. Pass -PrincipalType ServicePrincipal for a managed
        identity: ARM then skips its directory check of the principal, which fails for an
        identity created seconds before (PrincipalNotFound while it replicates). New-AzRoleAssignment
        is not used, because it calls Microsoft Graph to resolve the principal (issue #397).

        A status outside 2xx throws with the status, ARM's error code (RoleAssignmentExists,
        AuthorizationFailed, PrincipalNotFound...) and its message.

    .PARAMETER Scope
        The scope, such as /subscriptions/<id> or a resource id.

    .PARAMETER RoleDefinitionId
        The role's GUID, or its full id (/subscriptions/<id>/providers/Microsoft.Authorization/
        roleDefinitions/<GUID>). A GUID is turned into the full id under the scope's subscription.

    .PARAMETER PrincipalId
        The object id of the user, group or service principal.

    .PARAMETER PrincipalType
        User, Group or ServicePrincipal (also ForeignGroup, Device). Leave it out when unknown.

    .OUTPUTS
        The new assignment, as Get-LabArmRoleAssignment returns one.

    .EXAMPLE
        New-LabArmRoleAssignment -Scope "/subscriptions/$subId" -RoleDefinitionId (Get-LabBuiltInRoleId -Name Contributor) -PrincipalId $id -PrincipalType ServicePrincipal

    .NOTES
        Project: SkyCraft
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [ValidatePattern('^/')]
        [string]$Scope,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$RoleDefinitionId,

        [Parameter(Mandatory)]
        [ValidateScript({ $parsed = [guid]::Empty; [guid]::TryParse($_, [ref]$parsed) })]
        [string]$PrincipalId,

        [Parameter()]
        [ValidateSet('User', 'Group', 'ServicePrincipal', 'ForeignGroup', 'Device')]
        [string]$PrincipalType
    )

    $scopePath = $Scope.TrimEnd('/')
    $definition = $RoleDefinitionId
    if ($definition -notmatch '/') {
        $subscriptionPrefix = if ($scopePath -match '^(/subscriptions/[^/]+)') { $Matches[1] } else { '' }
        $definition = "$subscriptionPrefix/providers/Microsoft.Authorization/roleDefinitions/$definition"
    }

    $properties = [ordered]@{ roleDefinitionId = $definition; principalId = $PrincipalId }
    if ($PrincipalType) { $properties.principalType = $PrincipalType }
    $payload = @{ properties = $properties } | ConvertTo-Json -Depth 5 -Compress

    $name = [guid]::NewGuid().ToString()
    $path = "$scopePath/providers/Microsoft.Authorization/roleAssignments/$($name)?api-version=$script:LabRoleAssignmentApiVersion"
    if (-not $PSCmdlet.ShouldProcess("$PrincipalId on $scopePath", "Assign role $definition")) { return }
    $body = Invoke-LabArmRequest -Method PUT -Path $path -Payload $payload
    if ($body -and $body.properties) { ConvertTo-LabArmRoleAssignment -Item $body }
}

function Remove-LabArmRoleAssignment {
    <#
    .SYNOPSIS
        Deletes a role assignment by its id through the ARM role assignments API, without
        Microsoft Graph.

    .DESCRIPTION
        DELETE <id> (api-version 2022-04-01) through Invoke-AzRestMethod. ARM answers 200 with the
        deleted assignment, or 204 when there was none to delete; both are success. Any other
        status throws with the status, ARM's error code and its message. Remove-AzRoleAssignment
        is not used, because it calls Microsoft Graph to resolve the principal (issue #397).

    .PARAMETER Id
        The assignment's full id (RoleAssignmentId from Get-LabArmRoleAssignment):
        <scope>/providers/Microsoft.Authorization/roleAssignments/<GUID>.

    .EXAMPLE
        Get-LabArmRoleAssignment -Scope $scope -PrincipalId $id | ForEach-Object { Remove-LabArmRoleAssignment -Id $_.RoleAssignmentId }

    .NOTES
        Project: SkyCraft
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [ValidatePattern('/providers/Microsoft\.Authorization/roleAssignments/[^/]+$')]
        [string]$Id
    )

    if (-not $PSCmdlet.ShouldProcess($Id, 'Remove role assignment')) { return }
    Invoke-LabArmRequest -Method DELETE -Path "$($Id)?api-version=$script:LabRoleAssignmentApiVersion" | Out-Null
}

# --- Budgets through the Consumption API (issue #411) -----------------------------------------

# Az.Billing 2.3.0 sends 2018-01-31, which current subscriptions answer with 422; 2019-01-01 and
# later work. 2023-05-01 is what az consumption budget uses.
$script:LabBudgetApiVersion = '2023-05-01'

# One budget as the Consumption API returns it, in the shape the lab scripts read. Unit is the
# currency of currentSpend; the budget itself carries none.
function ConvertTo-LabArmBudget {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Item
    )

    $properties = $Item.properties
    $id = [string]$Item.id
    [pscustomobject]@{
        PSTypeName   = 'SkyCraft.LabBudget'
        Name         = [string]$Item.name
        Id           = $id
        Scope        = $id -replace '/providers/Microsoft\.Consumption/budgets/[^/]+$', ''
        Amount       = $properties.amount
        Category     = [string]$properties.category
        TimeGrain    = [string]$properties.timeGrain
        CurrentSpend = $properties.currentSpend.amount
        Unit         = [string]$properties.currentSpend.unit
    }
}

function Get-LabArmBudget {
    <#
    .SYNOPSIS
        Lists the budgets at a subscription or resource group scope from the Consumption API,
        without Az.Billing.

    .DESCRIPTION
        GET <scope>/providers/Microsoft.Consumption/budgets (api-version 2023-05-01) through
        Invoke-AzRestMethod, following nextLink until the last page. A status outside 2xx throws
        with the status, the error code and the service's message: a failed read is never an empty
        list. Get-AzConsumptionBudget is not used, because Az.Billing 2.3.0 sends api-version
        2018-01-31, which current subscriptions refuse with 422 (issue #411).

    .PARAMETER Scope
        /subscriptions/<id>, or /subscriptions/<id>/resourceGroups/<name>.

    .OUTPUTS
        SkyCraft.LabBudget objects: Name, Id, Scope (the part of Id before the budget), Amount,
        Category, TimeGrain, CurrentSpend and Unit (the currency of CurrentSpend).

    .EXAMPLE
        Get-LabArmBudget -Scope "/subscriptions/$subId/resourceGroups/prod-skycraft-swc-rg"

    .NOTES
        Project: SkyCraft
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidatePattern('^/subscriptions/[^/?#\s]+(/resourceGroups/[^/?#\s]+)?/?$')]
        [string]$Scope
    )

    $path = "$($Scope.TrimEnd('/'))/providers/Microsoft.Consumption/budgets?api-version=$script:LabBudgetApiVersion"
    foreach ($item in Invoke-LabArmList -Path $path -Caller 'Get-LabArmBudget') {
        ConvertTo-LabArmBudget -Item $item
    }
}

function Remove-LabArmBudget {
    <#
    .SYNOPSIS
        Deletes a budget by name at a subscription or resource group scope through the
        Consumption API, without Az.Billing.

    .DESCRIPTION
        DELETE <scope>/providers/Microsoft.Consumption/budgets/<name> (api-version 2023-05-01)
        through Invoke-AzRestMethod. Any 2xx is success. Any other status throws with the status,
        the error code and the service's message, a 404 included: the caller lists the budgets
        first, so a budget that vanished in between is reported, not assumed gone.
        Remove-AzConsumptionBudget is not used, for the reason Get-LabArmBudget gives (issue #411).

    .PARAMETER Scope
        /subscriptions/<id>, or /subscriptions/<id>/resourceGroups/<name>.

    .PARAMETER Name
        The budget's name: letters, digits, hyphens and underscores, as Azure allows.

    .EXAMPLE
        Remove-LabArmBudget -Scope "/subscriptions/$subId" -Name 'SkyCraft-Monthly-Budget'

    .NOTES
        Project: SkyCraft
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [ValidatePattern('^/subscriptions/[^/?#\s]+(/resourceGroups/[^/?#\s]+)?/?$')]
        [string]$Scope,

        [Parameter(Mandatory)]
        [ValidatePattern('^[A-Za-z0-9_-]{1,63}$')]
        [string]$Name
    )

    $scopePath = $Scope.TrimEnd('/')
    if (-not $PSCmdlet.ShouldProcess("$Name on $scopePath", 'Remove budget')) { return }
    Invoke-LabArmRequest -Method DELETE -Path "$scopePath/providers/Microsoft.Consumption/budgets/$($Name)?api-version=$script:LabBudgetApiVersion" | Out-Null
}

function Import-LabModule {
    <#
    .SYNOPSIS
        Imports the modules a lab script needs, the Microsoft Graph ones at one version, or names
        the commands that install what is missing and returns $false.

    .DESCRIPTION
        Use it instead of `#Requires -Modules` for a module Azure Cloud Shell does not ship
        (Microsoft.Graph.Users, issue #375). `#Requires` stops the script before its first line
        with PowerShell's own error, which names the module but not how to install it.

        Every Microsoft.Graph.* submodule pins Microsoft.Graph.Authentication to its own version
        in its manifest, and a session can load only one Authentication assembly. Importing
        Microsoft.Graph.Users 2.28.0 and then Microsoft.Graph.Groups 2.24.0 fails with "Could
        not load file or assembly 'Microsoft.Graph.Authentication, Version=2.24.0.0' ... Assembly
        with same name is already loaded". That is what a plain `Install-Module
        Microsoft.Graph.Users` sets up in Cloud Shell when the PowerShell Gallery holds a newer
        version than the Graph modules Cloud Shell ships. So the Graph modules in -Name are
        imported together at one version:

          - the version of Microsoft.Graph.Authentication already loaded in the session, when
            one is (another lab script or Connect-MgGraph loaded it), since no other can load;
          - otherwise the installed version that most of them share, the newest on a tie, which
            is the newest version all of them share when there is one.

        The other modules in -Name are imported by name.

        Returns $true when every module is imported. Otherwise it imports nothing and prints an
        [ERROR] line naming each module that is missing or not installed at that version, and the
        commands that install it for the current user (`Install-Module <name> -RequiredVersion
        <version> -Scope CurrentUser` for a Graph module where a version is set, `Install-Module
        <name>, <name> -Scope CurrentUser` otherwise), and returns $false. An import that fails all
        the same prints its error and returns $false, so the script still stops through Exit-Lab
        rather than with an unhandled error.

        It ends nothing itself: the script calls `Exit-Lab -FailureCount 1` when it returns
        $false, so the entry-point check in Exit-Lab sees the script, not this module (issue
        #257).

    .PARAMETER Name
        The modules the script needs, by name, in the order they are imported.

    .OUTPUTS
        [bool] $true when every module is imported.

    .EXAMPLE
        $labModule = @('Microsoft.Graph.Authentication', 'Microsoft.Graph.Users')
        if (-not (Import-LabModule -Name $labModule)) { Exit-Lab -FailureCount 1 }

    .NOTES
        Project: SkyCraft
        Issue: #375
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string[]]$Name
    )

    $installed = @{}
    foreach ($module in $Name) {
        $installed[$module] = @(Get-Module -ListAvailable -Name $module -Verbose:$false |
                ForEach-Object { [version]$_.Version } | Sort-Object -Unique -Descending)
    }

    # The Graph modules share one version: the one already loaded, or the one most of them have.
    $graph         = @($Name | Where-Object { $_ -like 'Microsoft.Graph.*' })
    $graphVersion  = $null
    $loadedVersion = $null
    if ($graph.Count -gt 0) {
        $loaded = @(Get-Module -Name 'Microsoft.Graph.Authentication' -Verbose:$false | Where-Object { $_ })
        if ($loaded.Count -gt 0) {
            $loadedVersion = [version]$loaded[0].Version
            $graphVersion  = $loadedVersion
        }
        else {
            $candidate = @($graph | ForEach-Object { $installed[$_] } | Sort-Object -Unique -Descending)
            $best = 0
            foreach ($version in $candidate) {
                $count = @($graph | Where-Object { $installed[$_] -contains $version }).Count
                if ($count -gt $best) { $best = $count; $graphVersion = $version }
            }
        }
    }

    $needsVersion = @(if ($graphVersion) { $graph | Where-Object { $installed[$_] -notcontains $graphVersion } })
    $needsAny     = @($Name | Where-Object { $installed[$_].Count -eq 0 -and $needsVersion -notcontains $_ })
    $missing      = @($Name | Where-Object { $installed[$_].Count -eq 0 })
    $otherVersion = @($needsVersion | Where-Object { $installed[$_].Count -gt 0 })

    if ($needsVersion.Count -eq 0 -and $needsAny.Count -eq 0) {
        foreach ($module in $Name) {
            # -Global: imported from inside this module, a module is otherwise visible only here,
            # not to the lab script that called Import-LabModule.
            $import = @{ Name = $module; Global = $true; Verbose = $false; ErrorAction = 'Stop' }
            if ($graphVersion -and $graph -contains $module) { $import['RequiredVersion'] = $graphVersion }
            try {
                Import-Module @import
            }
            catch {
                Write-Host "[ERROR] Could not import the PowerShell module $module$(if ($import['RequiredVersion']) { " $graphVersion" }): $($_.Exception.Message)" -ForegroundColor Red
                Write-Host '        Open a new PowerShell session and run the script again.' -ForegroundColor Yellow
                return $false
            }
        }
        return $true
    }

    if ($missing.Count -eq 1) {
        Write-Host "[ERROR] This script needs the PowerShell module $($missing[0]), which is not installed." -ForegroundColor Red
    }
    elseif ($missing.Count -gt 1) {
        Write-Host "[ERROR] This script needs these PowerShell modules, which are not installed: $($missing -join ', ')." -ForegroundColor Red
    }
    if ($otherVersion.Count -gt 0) {
        $found = @($otherVersion | ForEach-Object { "$_ ($($installed[$_] -join ', '))" }) -join ', '
        Write-Host "[ERROR] This script needs its Microsoft Graph modules at one version, $graphVersion, and these are installed only at another: $found." -ForegroundColor Red
    }
    if ($graphVersion -and $needsVersion.Count -gt 0) {
        $why = if ($loadedVersion) { "the Microsoft.Graph.Authentication this session has already loaded" } else { "the Microsoft Graph modules installed here" }
        Write-Host "        Microsoft Graph modules load only at one version per session; $graphVersion is the version of $why." -ForegroundColor Yellow
    }

    $it = if (($needsVersion.Count + $needsAny.Count) -eq 1) { 'it' } else { 'them' }
    Write-Host "        Install $it for your account, then run the script again:" -ForegroundColor Yellow
    foreach ($module in $needsVersion) {
        Write-Host "            Install-Module $module -RequiredVersion $graphVersion -Scope CurrentUser" -ForegroundColor Yellow
    }
    if ($needsAny.Count -gt 0) {
        Write-Host "            Install-Module $($needsAny -join ', ') -Scope CurrentUser" -ForegroundColor Yellow
    }
    if ($loadedVersion) {
        Write-Host "        Or open a new PowerShell session, which has no Microsoft Graph module loaded yet, and run the script there." -ForegroundColor Yellow
    }
    Write-Host "        In Azure Cloud Shell without a storage account, what you install is deleted when the session ends: install $it again in each new session." -ForegroundColor Yellow
    return $false
}

Export-ModuleMember -Function Exit-Lab, Get-LabBuiltInRoleId, Get-LabGraphSignInHint, Get-LabArmRoleAssignment, New-LabArmRoleAssignment, Remove-LabArmRoleAssignment, Get-LabArmBudget, Remove-LabArmBudget, Import-LabModule

<#
.SYNOPSIS
    Pester 5 test: a lab cleanup tells a resource that is gone from a lookup that failed.

.DESCRIPTION
    Issue #255 (after #227 for Lab 1.1 and #238 for Lab 5.2): the lab cleanups looked resources up
    with -ErrorAction SilentlyContinue, so a lookup that failed - a 403, throttling, a transient
    ARM error - read as "absent". The resource was skipped, and the run could exit 0 while it
    still existed.

    The fix is two helpers in each Remove-LabResource.ps1: Test-LabNotFoundError, which decides
    whether an error means "not found", and Invoke-LabLookup, which runs a lookup, reads a
    not-found error as absent and counts any other error as a failure. Each lab carries its own
    copy, because a lab folder must stay runnable on its own (docs/powershell-standards.md
    section 7.5). Copies drift, so this suite holds every copy to the same contract instead of
    each lab suite repeating it:

      1. Every Remove-LabResource.ps1 that defines either helper or calls Invoke-LabLookup
         defines both at the top level, where the parser can lift them - the script body never
         runs, so nothing is looked up. The cleanups known to carry them are listed, so a
         discovery that silently finds fewer fails.
      2. Test-LabNotFoundError reads every not-found shape the Az getters produce as "not found",
         and a 403, a 429, a transport error and a missing subscription as a failed lookup. A
         lab's copy may recognise more shapes (Lab 1.3 adds PolicyAssignmentNotFound); its own
         suite pins those.
      3. Invoke-LabLookup returns what a lookup found, reads "found nothing" and a not-found error
         as absent without counting them, and counts any other error in $script:cleanupFailures.
      4. A ratchet: no cleanup outside the labs #255 still has to convert gives a *-Az* command
         -ErrorAction SilentlyContinue or Ignore. The check walks the syntax tree, so it reads
         every spelling (-ErrorAction:X, -EA X, a quoted value, 0 or 4, the ActionPreference
         enum), a value carried in a splatted hashtable the script builds, and a command split by
         backtick continuations - and never a comment or a string.
      5. The pending list cannot outlive its purpose: every entry must name a lab whose cleanup
         still silences a lookup, so converting a lab fails this suite until the lab leaves the
         list, and a misspelled entry fails at once.

    Each lab's own tests/Remove-LabResource.Tests.ps1 runs the script end to end against stubbed
    Az commands and proves the exit code.

.EXAMPLE
    Invoke-Pester -Path .\tests\Lab-Cleanup-Lookup.Tests.ps1

.NOTES
    Project: SkyCraft
#>

#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

# ---------------------------------------------------------------------------------------------
# Discovery-time state. A -ForEach case list has to exist when Pester discovers the tests, so the
# scripts are found and parsed now; everything the assertions need is carried in the case itself.
# ---------------------------------------------------------------------------------------------

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path

$CleanupScripts = @(Get-ChildItem -Path $RepoRoot -Directory -Filter 'module-*' |
    Get-ChildItem -Directory |
    ForEach-Object { Join-Path $_.FullName 'scripts' 'Remove-LabResource.ps1' } |
    Where-Object { Test-Path -LiteralPath $_ })

# A cleanup takes part in the helper contract when it defines either helper or calls
# Invoke-LabLookup - read from the syntax tree, so the indentation of a definition does not matter.
$HelperCases = @(foreach ($cleanup in $CleanupScripts) {
    $cleanupAst = [System.Management.Automation.Language.Parser]::ParseFile($cleanup, [ref]$null, [ref]$null)
    $usesHelpers = $cleanupAst.Find({
        param($node)
        ($node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
            $node.Name -in 'Test-LabNotFoundError', 'Invoke-LabLookup') -or
        ($node -is [System.Management.Automation.Language.CommandAst] -and
            $node.GetCommandName() -eq 'Invoke-LabLookup')
    }, $true)
    if ($usesHelpers) {
        @{ file = ($cleanup.Substring($RepoRoot.Length + 1) -replace '\\', '/'); path = $cleanup }
    }
})

# The cleanups that carry the helpers today. Discovery must find at least these.
$ExpectedHelperFile = @(
    'module-1-identities-governance/1.2-rbac/scripts/Remove-LabResource.ps1'
    'module-1-identities-governance/1.3-governance/scripts/Remove-LabResource.ps1'
    'module-2-networking/2.1-virtual-networks/scripts/Remove-LabResource.ps1'
    'module-2-networking/2.2-secure-access/scripts/Remove-LabResource.ps1'
    'module-2-networking/2.3-name-resolution/scripts/Remove-LabResource.ps1'
    'module-3-compute/3.1-infrastructure-as-code/scripts/Remove-LabResource.ps1'
    'module-3-compute/3.2-virtual-machines/scripts/Remove-LabResource.ps1'
    'module-3-compute/3.3-containers/scripts/Remove-LabResource.ps1'
    'module-3-compute/3.4-app-service/scripts/Remove-LabResource.ps1'
    'module-4-storage/4.1-storage-accounts/scripts/Remove-LabResource.ps1'
    'module-4-storage/4.2-blob-storage/scripts/Remove-LabResource.ps1'
    'module-5-monitoring-maintenance/5.2-business-continuity/scripts/Remove-LabResource.ps1'
)

# The cleanups #255 still has to convert. The list only shrinks: the pending-list test below fails
# for an entry whose cleanup no longer silences a lookup.
$PendingLab = @(
    'module-4-storage/4.3-azure-files'
    'module-5-monitoring-maintenance/5.1-azure-monitor'
    'module-5-monitoring-maintenance/5.3-network-monitoring'
)

$PendingCases = @($PendingLab | ForEach-Object {
    @{ lab = $_; path = (Join-Path $RepoRoot $_ 'scripts' 'Remove-LabResource.ps1') }
})

$RatchetCases = @($CleanupScripts | ForEach-Object {
    $file = $_.Substring($RepoRoot.Length + 1) -replace '\\', '/'
    $lab  = ($file -split '/')[0..1] -join '/'
    if ($lab -notin $PendingLab) { @{ file = $file; path = $_ } }
})

BeforeAll {
    # The ratchet's reader. Returns one finding per *-Az* command that is given -ErrorAction
    # SilentlyContinue or Ignore, in any form the parser accepts:
    #   - the parameter as ErrorAction, any unambiguous prefix of it (-ErrorA...), or its alias EA;
    #   - the value after a space or a colon (-ErrorAction:Ignore), bare or quoted, as the enum
    #     name, its number (SilentlyContinue = 0, Ignore = 4), or [ActionPreference]::Name;
    #   - a splatted variable (@query) that the script assigns a hashtable literal holding the key,
    #     or whose key it sets afterwards ($query.ErrorAction = ..., $query['ErrorAction'] = ...).
    # A value held in another variable cannot be resolved without running the script, and is not
    # read. Comments and strings are not commands, so they never match.
    function Find-SilencedAzCommand {
        [CmdletBinding()]
        param([Parameter(Mandatory)][AllowEmptyString()][string]$Text)

        $silentValue = '^(SilentlyContinue|Ignore|0|4)$'
        $isErrorActionName = {
            param([string]$Name)
            $Name -eq 'EA' -or ($Name.Length -ge 6 -and 'ErrorAction'.StartsWith($Name, [System.StringComparison]::OrdinalIgnoreCase))
        }
        # The literal value of an argument or a hashtable entry, or $null when it is not a literal.
        $valueOf = $null
        $valueOf = {
            param($Node)
            switch ($Node) {
                { $_ -is [System.Management.Automation.Language.PipelineAst] } {
                    if ($_.PipelineElements.Count -eq 1) { return (& $valueOf $_.PipelineElements[0]) }
                    return $null
                }
                { $_ -is [System.Management.Automation.Language.CommandExpressionAst] } { return (& $valueOf $_.Expression) }
                { $_ -is [System.Management.Automation.Language.ParenExpressionAst] } { return (& $valueOf $_.Pipeline) }
                { $_ -is [System.Management.Automation.Language.ConvertExpressionAst] } { return (& $valueOf $_.Child) }
                { $_ -is [System.Management.Automation.Language.ConstantExpressionAst] } { return [string]$_.Value }
                { $_ -is [System.Management.Automation.Language.ExpandableStringExpressionAst] } { return $_.Value }
                { $_ -is [System.Management.Automation.Language.MemberExpressionAst] } { return ($_.Member.Extent.Text -replace '[''"]', '') }
            }
            return $null
        }

        $ast = [System.Management.Automation.Language.Parser]::ParseInput($Text, [ref]$null, [ref]$null)

        # Variables the script fills with a silencing ErrorAction, for splatting.
        $silencingSplat = @{}
        foreach ($assignment in $ast.FindAll({ $args[0] -is [System.Management.Automation.Language.AssignmentStatementAst] }, $true)) {
            $left = $assignment.Left
            if ($left -is [System.Management.Automation.Language.VariableExpressionAst]) {
                $table = $assignment.Right
                while ($table -and $table -isnot [System.Management.Automation.Language.HashtableAst]) {
                    $table = switch ($table) {
                        { $_ -is [System.Management.Automation.Language.PipelineAst] } { if ($_.PipelineElements.Count -eq 1) { $_.PipelineElements[0] } }
                        { $_ -is [System.Management.Automation.Language.CommandExpressionAst] } { $_.Expression }
                        { $_ -is [System.Management.Automation.Language.ConvertExpressionAst] } { $_.Child }
                        default { $null }
                    }
                }
                if (-not $table) { continue }
                foreach ($pair in $table.KeyValuePairs) {
                    if ((& $isErrorActionName (& $valueOf $pair.Item1)) -and ((& $valueOf $pair.Item2) -match $silentValue)) {
                        $silencingSplat[$left.VariablePath.UserPath] = $true
                    }
                }
            }
            elseif ($left -is [System.Management.Automation.Language.MemberExpressionAst] -or
                    $left -is [System.Management.Automation.Language.IndexExpressionAst]) {
                $target = if ($left -is [System.Management.Automation.Language.MemberExpressionAst]) { $left.Expression } else { $left.Target }
                $key    = if ($left -is [System.Management.Automation.Language.MemberExpressionAst]) { $left.Member } else { $left.Index }
                if ($target -is [System.Management.Automation.Language.VariableExpressionAst] -and
                    (& $isErrorActionName (& $valueOf $key)) -and ((& $valueOf $assignment.Right) -match $silentValue)) {
                    $silencingSplat[$target.VariablePath.UserPath] = $true
                }
            }
        }

        foreach ($command in $ast.FindAll({ $args[0] -is [System.Management.Automation.Language.CommandAst] }, $true)) {
            $name = $command.GetCommandName()
            if (-not $name -or $name -notmatch '^\w+-Az\w') { continue }
            $elements = $command.CommandElements
            $silenced = $false
            for ($index = 1; $index -lt $elements.Count; $index++) {
                $element = $elements[$index]
                if ($element -is [System.Management.Automation.Language.CommandParameterAst] -and (& $isErrorActionName $element.ParameterName)) {
                    $value = if ($element.Argument) { $element.Argument } elseif ($index + 1 -lt $elements.Count) { $elements[$index + 1] }
                    if ((& $valueOf $value) -match $silentValue) { $silenced = $true }
                }
                elseif ($element -is [System.Management.Automation.Language.VariableExpressionAst] -and $element.Splatted -and
                        $silencingSplat.ContainsKey($element.VariablePath.UserPath)) {
                    $silenced = $true
                }
            }
            if ($silenced) {
                [pscustomobject]@{
                    Line    = $command.Extent.StartLineNumber
                    Command = $name
                    Text    = ($command.Extent.Text -split "`r?`n")[0].Trim()
                }
            }
        }
    }
}

Describe 'Lab cleanup lookups - the helpers are there to check' {

    It 'finds every cleanup known to carry the helpers' -ForEach @(@{ files = @($HelperCases.file); expected = $ExpectedHelperFile }) {
        # A discovery that matches less produces Describes that pass by asserting nothing.
        foreach ($file in $expected) {
            $files | Should -Contain $file
        }
    }
}

Describe "Lab cleanup lookups - '<file>'" -ForEach $HelperCases {

    BeforeAll {
        # Lift the helpers with the parser: the script body never runs, so nothing is looked up.
        $parseError = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$null, [ref]$parseError)
        if ($parseError) { throw "$file does not parse: $($parseError[0].Message)" }
        $script:LiftedName = @()
        foreach ($function in $ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $false)) {
            if ($function.Name -notin 'Test-LabNotFoundError', 'Invoke-LabLookup') { continue }
            . ([scriptblock]::Create($function.Extent.Text))
            $script:LiftedName += $function.Name
        }

        # The shape of the SDK exceptions the Az getters raise: a message, plus the ARM error code
        # in Body and the HTTP status in Response (CloudException), in Status (Azure.Core's
        # RequestFailedException) or in ResponseStatusCode (the generated cmdlets' RestException).
        if (-not ('SkyCraftLookupStubAzureException' -as [type])) {
            Add-Type -TypeDefinition @'
public class SkyCraftLookupStubAzureException : System.Exception
{
    public SkyCraftLookupStubAzureException(string message) : base(message) { }
    public object Body { get; set; }
    public object Response { get; set; }
    public int Status { get; set; }
    public object ResponseStatusCode { get; set; }
}
'@
        }

        function Get-LookupErrorFixture {
            param(
                [string]$Message = 'Operation failed.',
                [string]$ErrorId = 'StubError',
                [string]$Code,
                [object]$StatusCode,
                [int]$Status,
                [object]$ResponseStatusCode,
                [switch]$Wrapped
            )
            $exception = [SkyCraftLookupStubAzureException]::new($Message)
            if ($Code) { $exception.Body = [pscustomobject]@{ Code = $Code } }
            if ($null -ne $StatusCode) { $exception.Response = [pscustomobject]@{ StatusCode = $StatusCode } }
            if ($Status) { $exception.Status = $Status }
            if ($null -ne $ResponseStatusCode) { $exception.ResponseStatusCode = $ResponseStatusCode }
            if ($Wrapped) { $exception = [System.Exception]::new('The lookup failed.', $exception) }
            [System.Management.Automation.ErrorRecord]::new($exception, $ErrorId, 'InvalidOperation', $null)
        }

        # What -ErrorAction Stop leaves of an error a generated cmdlet wrote without a usable error
        # id: ActionPreferenceStopException, its message the original one behind a fixed prefix.
        function Get-StopWrappedErrorFixture {
            param([string]$Message)
            $exception = [System.Management.Automation.ActionPreferenceStopException]::new(
                'The running command stopped because the preference variable "ErrorActionPreference" or common parameter is set to Stop: ' + $Message)
            [System.Management.Automation.ErrorRecord]::new($exception, '', 'OperationStopped', $null)
        }
    }

    It 'defines Test-LabNotFoundError and Invoke-LabLookup' {
        $script:LiftedName | Should -Contain 'Test-LabNotFoundError'
        $script:LiftedName | Should -Contain 'Invoke-LabLookup'
    }

    It 'reads <shape> as not found' -ForEach @(
        @{ shape  = 'the ARM ResourceNotFound message'
           record = { Get-LookupErrorFixture -Message "The Resource 'Microsoft.Network/virtualNetworks/prod-skycraft-swc-vnet' under resource group 'prod-skycraft-swc-rg' was not found. For more details please go to https://aka.ms/ARMResourceNotFoundFix" } }
        @{ shape  = 'the ARM ResourceGroupNotFound message (the group is gone too)'
           record = { Get-LookupErrorFixture -Message "Resource group 'platform-skycraft-swc-rg' could not be found." } }
        @{ shape  = 'an empty error body (invalid status code NotFound)'
           record = { Get-LookupErrorFixture -Message "Operation returned an invalid status code 'NotFound'" } }
        @{ shape  = 'the error id of a generated cmdlet'
           record = { Get-LookupErrorFixture -ErrorId 'ResourceNotFound' } }
        @{ shape  = 'the ARM error code in the exception body'
           record = { Get-LookupErrorFixture -Code 'ResourceNotFound' } }
        @{ shape  = 'a 404 HTTP status on the response'
           record = { Get-LookupErrorFixture -StatusCode ([System.Net.HttpStatusCode]::NotFound) } }
        @{ shape  = 'a 404 on a generated cmdlet RestException with no error body'
           record = { Get-LookupErrorFixture -ResponseStatusCode ([System.Net.HttpStatusCode]::NotFound) } }
        @{ shape  = 'the -ErrorAction Stop wrapping of a not-found, with no error id'
           record = { Get-StopWrappedErrorFixture -Message "The Resource 'Microsoft.Network/loadBalancers/dev-skycraft-swc-lb' under resource group 'dev-skycraft-swc-rg' was not found." } }
        @{ shape  = 'an Azure.Core 404 status'
           record = { Get-LookupErrorFixture -Status 404 } }
        @{ shape  = 'the Azure.Core message (Status 404 Not Found)'
           record = { Get-LookupErrorFixture -Message "Service request failed.`nStatus: 404 (Not Found)" } }
        @{ shape  = 'a not-found wrapped as the inner exception'
           record = { Get-LookupErrorFixture -Code 'ResourceGroupNotFound' -Wrapped } }
    ) {
        Test-LabNotFoundError -ErrorRecord (& $record) | Should -BeTrue
    }

    It 'reads <shape> as a failed lookup' -ForEach @(
        @{ shape  = 'a 403 AuthorizationFailed'
           record = { Get-LookupErrorFixture -ErrorId 'AuthorizationFailed' -Code 'AuthorizationFailed' -StatusCode ([System.Net.HttpStatusCode]::Forbidden) -Message "The client 'stub' does not have authorization to perform action 'Microsoft.Network/virtualNetworks/read' over scope '/subscriptions/0' or the scope is invalid." } }
        @{ shape  = 'a 429 throttling response'
           record = { Get-LookupErrorFixture -ErrorId 'TooManyRequests' -Status 429 -Message "Number of 'read' requests for subscription '0' actor 'stub' exceeded. Please try again after '17' seconds." } }
        @{ shape  = 'a 403 on a generated cmdlet RestException'
           record = { Get-LookupErrorFixture -ResponseStatusCode ([System.Net.HttpStatusCode]::Forbidden) } }
        @{ shape  = 'the -ErrorAction Stop wrapping of a 403, with no error id'
           record = { Get-StopWrappedErrorFixture -Message "The client 'stub' with object id '0' does not have authorization to perform action 'Microsoft.Network/dnszones/read' over scope '/subscriptions/0' or the scope is invalid." } }
        @{ shape  = 'a transient transport error'
           record = { Get-LookupErrorFixture -Message 'An error occurred while sending the request.' } }
        @{ shape  = 'a missing subscription, although ARM answers it with 404'
           record = { Get-LookupErrorFixture -Code 'SubscriptionNotFound' -StatusCode ([System.Net.HttpStatusCode]::NotFound) -Message "The subscription '00000000-0000-0000-0000-000000000000' could not be found." } }
    ) {
        Test-LabNotFoundError -ErrorRecord (& $record) | Should -BeFalse
    }

    Context 'Invoke-LabLookup' {

        BeforeEach { $script:cleanupFailures = 0 }

        It 'returns what a lookup found' {
            $result = Invoke-LabLookup -Target 'stub' -Lookup { 'first'; 'second' }
            $result.Value    | Should -Be @('first', 'second')
            $result.Failed   | Should -BeFalse
            $result.NotFound | Should -BeFalse
            $script:cleanupFailures | Should -Be 0
        }

        It 'reads a lookup that succeeds and finds nothing as absent, without counting it' {
            $result = Invoke-LabLookup -Target 'stub' -Lookup { }
            @($result.Value).Count | Should -Be 0
            $result.NotFound | Should -BeFalse
            $result.Failed   | Should -BeFalse
            $script:cleanupFailures | Should -Be 0
        }

        It 'reads a not-found error as absent, without counting it' {
            $result = Invoke-LabLookup -Target 'stub' -Lookup {
                Write-Error -ErrorId 'ResourceNotFound' -ErrorAction Stop -Message "The Resource 'Microsoft.Network/virtualNetworks/dev-skycraft-swc-vnet' under resource group 'dev-skycraft-swc-rg' was not found."
            }
            $result.NotFound | Should -BeTrue
            $result.Failed   | Should -BeFalse
            $script:cleanupFailures | Should -Be 0
        }

        It 'counts any other error as a failed lookup, and says it is not "absent"' {
            # 6>&1 merges the Write-Host lines (the information stream) into the output, so the
            # result object is the one record that carries a Failed property.
            $output = @(Invoke-LabLookup -Target 'stub' -Lookup {
                Write-Error -ErrorId 'AuthorizationFailed' -ErrorAction Stop -Message "The client 'stub' does not have authorization to perform action 'read'."
            } 6>&1)
            $lines  = @($output | Where-Object { $_.PSObject.Properties.Name -notcontains 'Failed' } | ForEach-Object { "$_" })
            $result = @($output | Where-Object { $_.PSObject.Properties.Name -contains 'Failed' })[0]
            $result.Failed   | Should -BeTrue
            $result.NotFound | Should -BeFalse
            @($result.Value).Count | Should -Be 0
            $script:cleanupFailures | Should -Be 1
            ($lines -join "`n") | Should -Match '\[ERROR\] Could not look up stub: [^\r\n]*does not have authorization'
        }
    }
}

Describe 'Lab cleanup lookups - the ratchet reads every way to silence a lookup' {

    It 'flags <case>' -ForEach @(
        @{ case = 'the plain form';                 text = 'Get-AzVM -Name x -ErrorAction SilentlyContinue' }
        @{ case = 'the colon form';                 text = 'Get-AzVM -Name x -ErrorAction:SilentlyContinue' }
        @{ case = 'the EA alias with Ignore';       text = 'Get-AzVM -Name x -EA Ignore' }
        @{ case = 'an unambiguous prefix';          text = 'Get-AzVM -Name x -ErrorAct SilentlyContinue' }
        @{ case = 'a quoted value';                 text = "Get-AzVM -Name x -ErrorAction 'SilentlyContinue'" }
        @{ case = 'the number of SilentlyContinue'; text = 'Get-AzVM -Name x -ErrorAction 0' }
        @{ case = 'the ActionPreference enum';      text = 'Get-AzVM -ErrorAction ([System.Management.Automation.ActionPreference]::Ignore)' }
        @{ case = 'any verb';                       text = 'New-AzResourceGroup -Name x -Location y -ErrorAction SilentlyContinue' }
        @{ case = 'a backtick continuation';        text = (@('Get-AzVM -Name x `', '    -ErrorAction SilentlyContinue') -join "`n") }
        @{ case = 'a splatted hashtable literal';   text = (@('$query = @{ Name = ''x''; ErrorAction = ''SilentlyContinue'' }', 'Get-AzVM @query') -join "`n") }
        @{ case = 'a splat key set afterwards';     text = (@('$query = @{ Name = ''x'' }', '$query.ErrorAction = ''Ignore''', 'Get-AzVM @query') -join "`n") }
        @{ case = 'a splat key set by index';       text = (@('$query = @{ Name = ''x'' }', '$query[''EA''] = ''SilentlyContinue''', 'Get-AzVM @query') -join "`n") }
        @{ case = 'a lookup nested in an expression'; text = 'if (Get-AzVM -Name x -ErrorAction SilentlyContinue) { }' }
    ) {
        @(Find-SilencedAzCommand -Text $text).Count | Should -Be 1
    }

    It 'does not flag <case>' -ForEach @(
        @{ case = 'a comment';                       text = '# Get-AzVM -ErrorAction SilentlyContinue' }
        @{ case = 'a string';                        text = "Write-Host 'Get-AzVM -ErrorAction SilentlyContinue'" }
        @{ case = '-ErrorAction Stop';               text = 'Get-AzVM -Name x -ErrorAction Stop' }
        @{ case = 'a command that is not Az';        text = 'Remove-Item x -ErrorAction SilentlyContinue' }
        @{ case = 'a splat that stops on error';     text = (@('$query = @{ ErrorAction = ''Stop'' }', 'Get-AzVM @query') -join "`n") }
        @{ case = '-ErrorVariable';                  text = 'Get-AzVM -Name x -ErrorVariable SilentlyContinue' }
    ) {
        @(Find-SilencedAzCommand -Text $text).Count | Should -Be 0
    }
}

Describe 'Lab cleanup lookups - the pending list only names labs still to convert' {

    It "'<lab>' has a cleanup that still silences a lookup" -ForEach $PendingCases {
        Test-Path -LiteralPath $path | Should -BeTrue -Because "a pending entry that names no cleanup exempts nothing - check its spelling"
        @(Find-SilencedAzCommand -Text (Get-Content -Raw -LiteralPath $path)).Count | Should -BeGreaterThan 0 -Because 'a converted cleanup must leave $PendingLab, or the ratchet stops guarding it'
    }
}

Describe 'Lab cleanup lookups - no converted cleanup reads a failed lookup as "absent" (#255)' {

    It 'has converted cleanups to check' -ForEach @(@{ count = $RatchetCases.Count }) {
        $count | Should -BeGreaterThan 0
    }

    It "'<file>' gives no *-Az* command -ErrorAction SilentlyContinue or Ignore" -ForEach $RatchetCases {
        $hits = @(Find-SilencedAzCommand -Text (Get-Content -Raw -LiteralPath $path) |
            ForEach-Object { "line $($_.Line): $($_.Text)" })
        $hits | Should -BeNullOrEmpty -Because "a lookup that fails would read as 'absent'; route it through Invoke-LabLookup (#255)"
    }
}

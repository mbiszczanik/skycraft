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
    copy, because a lab folder must stay runnable on its own (docs/powershell-standards.md section 7.3).
    Copies drift, so this suite holds every copy to the same contract instead of each lab suite
    repeating it:

      1. Every Remove-LabResource.ps1 that defines Test-LabNotFoundError also defines
         Invoke-LabLookup, and both lift out of the script with the parser - the script body
         never runs, so nothing is looked up.
      2. Test-LabNotFoundError reads every not-found shape the Az getters produce as "not found",
         and a 403, a 429, a transport error and a missing subscription as a failed lookup. A
         lab's copy may recognise more shapes (Lab 1.3 adds PolicyAssignmentNotFound); its own
         suite pins those.
      3. Invoke-LabLookup returns what a lookup found, reads "found nothing" and a not-found error
         as absent without counting them, and counts any other error in $script:cleanupFailures.
      4. A ratchet: no cleanup outside the labs #255 still has to convert passes -ErrorAction
         SilentlyContinue (or Ignore) to an Az getter or remover. Remove a lab from
         $PendingLab when its cleanup is converted; never add one.

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
# scripts are found now; everything the assertions need is carried in the case itself.
# ---------------------------------------------------------------------------------------------

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path

$CleanupScripts = @(Get-ChildItem -Path $RepoRoot -Directory -Filter 'module-*' |
    Get-ChildItem -Directory |
    ForEach-Object { Join-Path $_.FullName 'scripts' 'Remove-LabResource.ps1' } |
    Where-Object { Test-Path -LiteralPath $_ })

$HelperCases = @($CleanupScripts |
    Where-Object { (Get-Content -Raw -LiteralPath $_) -match '(?m)^function Test-LabNotFoundError\b' } |
    ForEach-Object {
        @{ file = ($_.Substring($RepoRoot.Length + 1) -replace '\\', '/'); path = $_ }
    })

# The cleanups #255 still has to convert. The list only shrinks.
$PendingLab = @(
    'module-3-compute/3.2-virtual-machines'
    'module-3-compute/3.3-containers'
    'module-3-compute/3.4-app-service'
    'module-4-storage/4.1-storage-accounts'
    'module-4-storage/4.2-blob-storage'
    'module-4-storage/4.3-azure-files'
    'module-5-monitoring-maintenance/5.1-azure-monitor'
    'module-5-monitoring-maintenance/5.3-network-monitoring'
)

$RatchetCases = @($CleanupScripts | ForEach-Object {
    $file = $_.Substring($RepoRoot.Length + 1) -replace '\\', '/'
    $lab  = ($file -split '/')[0..1] -join '/'
    if ($lab -notin $PendingLab) { @{ file = $file; path = $_ } }
})

Describe 'Lab cleanup lookups - the helpers are there to check' {

    It 'finds the cleanups that carry the helpers, Lab 5.2 among them' -ForEach @(@{ files = @($HelperCases.file) }) {
        # A filter that matches nothing produces Describes that pass by asserting nothing.
        $files | Should -Contain 'module-5-monitoring-maintenance/5.2-business-continuity/scripts/Remove-LabResource.ps1'
        $files | Should -Contain 'module-1-identities-governance/1.3-governance/scripts/Remove-LabResource.ps1'
        $files | Should -Contain 'module-2-networking/2.1-virtual-networks/scripts/Remove-LabResource.ps1'
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

Describe 'Lab cleanup lookups - no converted cleanup reads a failed lookup as "absent" (#255)' {

    It 'has converted cleanups to check' -ForEach @(@{ count = $RatchetCases.Count }) {
        $count | Should -BeGreaterThan 0
    }

    It "'<file>' passes no -ErrorAction SilentlyContinue or Ignore to an Az getter or remover" -ForEach $RatchetCases {
        $hits = @(Select-String -LiteralPath $path -Pattern '\b(Get|Remove|Set|Update|Disable)-Az\w+\b[^\r\n#]*-ErrorAction\s+(SilentlyContinue|Ignore)\b' |
            ForEach-Object { "line $($_.LineNumber): $($_.Line.Trim())" })
        $hits | Should -BeNullOrEmpty -Because "a lookup that fails would read as 'absent'; route it through Invoke-LabLookup (#255)"
    }
}

<#
.SYNOPSIS
    Pester 5 tests: the Lab 4.1 validator passes the accounts every path of the guide leaves and
    reports each broken setting as a counted failure, never a crash.

.DESCRIPTION
    Regression cover for issues #355 ("Crash instead of a [FAIL] line") and #358 (the Lab 4.1
    guide PR). These tests run the real Test-Lab.ps1 in a child pwsh against a generated stub of
    the Az commands it calls, and assert that:

      1. Accounts as the guide leaves them pass, and the script exits 0.
      2. An account with no tags at all fails its three tag checks, counted, and the script
         still prints its summary and exits 1 (#355: indexing $null Tags used to end the script
         with "Cannot index into a null array").
      3. An account left on RA-GRS (the Portal's "Make read access ..." box checked) fails its
         redundancy check, counted, with a hint that names the box (#358).
      4. An account without file share soft delete fails that check, counted (#358: the guide's
         PowerShell and CLI blocks now turn it on, as the Portal and the Bicep do).
      5. A blob service lookup that fails is a counted [FAIL] with its error, not a warning
         (docs/powershell-standards.md section 4, rule 7).

    No subscription is needed, and none is used: tests/Support/LabScriptStub.psm1 (issue #112)
    imports the real modules first, the stub last, and aborts the child with exit 99 unless every
    stubbed command resolves to the stub.

.EXAMPLE
    Invoke-Pester -Path .\Test-Lab.Tests.ps1

.NOTES
    Project: SkyCraft
    Lab: 4.1 - Storage Accounts
    Issue: #355, #358
#>

#Requires -Version 7.0
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..' '..' '..' 'tests' 'Support' 'LabScriptStub.psm1') -Force

    $script:ScriptPath     = (Resolve-Path (Join-Path $PSScriptRoot '..' 'scripts' 'Test-Lab.ps1')).Path
    $script:StubModuleName = 'SkyCraftLab41ValidatorStub'
    # Exactly the script's '#Requires -Modules' line.
    $script:RequiredModules = @('Az.Accounts', 'Az.Storage')

    $script:StubCommands = @(
        'Get-AzStorageAccount'
        'Get-AzStorageBlobServiceProperty'
        'Get-AzStorageFileServiceProperty'
    )

    #   SKYCRAFT_STUB_NOTAGS         storage account names that carry no tags at all ($null Tags)
    #   SKYCRAFT_STUB_RAGRS          storage account names whose SKU is Standard_RAGRS
    #   SKYCRAFT_STUB_NOSHARESD      storage account names with file share soft delete off
    #   SKYCRAFT_STUB_BLOBPROPS_FAIL storage account names whose blob service lookup throws
    $script:StubBody = @'
function Test-StubListed {
    param([string]$Variable, [string]$Name)
    @([Environment]::GetEnvironmentVariable($Variable) -split ',') -contains $Name
}

function Get-AzStorageAccount {
    [CmdletBinding()]
    param([string]$ResourceGroupName, [string]$Name, [Parameter(ValueFromRemainingArguments)]$Rest)
    $environmentTag = @{ platform = 'Platform'; dev = 'Development'; prod = 'Production' }[($ResourceGroupName -split '-')[0]]
    $sku            = @{ platform = 'Standard_GRS'; dev = 'Standard_LRS'; prod = 'Standard_GRS' }[($ResourceGroupName -split '-')[0]]
    if (Test-StubListed 'SKYCRAFT_STUB_RAGRS' $Name) { $sku = 'Standard_RAGRS' }
    $tags = if (Test-StubListed 'SKYCRAFT_STUB_NOTAGS' $Name) { $null } else { @{ Project = 'SkyCraft'; Environment = $environmentTag; CostCenter = 'MSDN' } }
    [pscustomobject]@{
        StorageAccountName     = $Name
        Sku                    = [pscustomobject]@{ Name = $sku }
        PrimaryLocation        = 'swedencentral'
        MinimumTlsVersion      = 'TLS1_2'
        EnableHttpsTrafficOnly = $true
        AllowBlobPublicAccess  = $false
        Encryption             = [pscustomobject]@{ Services = [pscustomobject]@{ Blob = [pscustomobject]@{ Enabled = $true }; File = [pscustomobject]@{ Enabled = $true } } }
        Tags                   = $tags
    }
}

function Get-AzStorageBlobServiceProperty {
    [CmdletBinding()]
    param([string]$StorageAccountName, [string]$ResourceGroupName, [Parameter(ValueFromRemainingArguments)]$Rest)
    if (Test-StubListed 'SKYCRAFT_STUB_BLOBPROPS_FAIL' $StorageAccountName) {
        throw "Operation returned an invalid status code 'Forbidden'"
    }
    [pscustomobject]@{
        DeleteRetentionPolicy          = [pscustomobject]@{ Enabled = $true }
        ContainerDeleteRetentionPolicy = [pscustomobject]@{ Enabled = $true }
    }
}

function Get-AzStorageFileServiceProperty {
    [CmdletBinding()]
    param([string]$StorageAccountName, [string]$ResourceGroupName, [Parameter(ValueFromRemainingArguments)]$Rest)
    $enabled = -not (Test-StubListed 'SKYCRAFT_STUB_NOSHARESD' $StorageAccountName)
    [pscustomobject]@{
        ShareDeleteRetentionPolicy = [pscustomobject]@{ Enabled = $enabled; Days = $(if ($enabled) { 7 } else { 0 }) }
    }
}
'@

    function Invoke-ValidatorScript {
        param(
            [pscustomobject]$Stub,
            [string[]]$NoTags = @(),
            [string[]]$RaGrs = @(),
            [string[]]$NoShareSoftDelete = @(),
            [string[]]$BlobPropsFail = @()
        )
        $run = Invoke-LabScriptWithStub -Stub $Stub -ScriptPath $script:ScriptPath -Environment @{
            SKYCRAFT_STUB_NOTAGS         = $NoTags -join ','
            SKYCRAFT_STUB_RAGRS          = $RaGrs -join ','
            SKYCRAFT_STUB_NOSHARESD      = $NoShareSoftDelete -join ','
            SKYCRAFT_STUB_BLOBPROPS_FAIL = $BlobPropsFail -join ','
        }
        return [pscustomobject]@{
            ExitCode  = $run.ExitCode
            Refused   = $run.Refused
            Output    = $run.Output
            FailLines = ([regex]::Matches($run.Output, '\[FAIL\]')).Count
        }
    }

    $script:Stub    = Initialize-LabScriptStub -Name $script:StubModuleName -Command $script:StubCommands `
        -Body $script:StubBody -RequiredModule $script:RequiredModules
    $script:StubDir = $script:Stub.Directory

    $script:AllTagged       = Invoke-ValidatorScript -Stub $script:Stub
    $script:Untagged        = Invoke-ValidatorScript -Stub $script:Stub -NoTags 'devskycraftswcsa'
    $script:ReadAccessGeo   = Invoke-ValidatorScript -Stub $script:Stub -RaGrs 'prodskycraftswcsa'
    $script:NoShareSoftDel  = Invoke-ValidatorScript -Stub $script:Stub -NoShareSoftDelete 'platformskycraftswcsa'
    $script:BlobLookupFails = Invoke-ValidatorScript -Stub $script:Stub -BlobPropsFail 'devskycraftswcsa'
    $script:AllRuns         = @($script:AllTagged, $script:Untagged, $script:ReadAccessGeo, $script:NoShareSoftDel, $script:BlobLookupFails)
}

AfterAll {
    if ($script:StubDir) { Remove-Item -LiteralPath $script:StubDir -Recurse -Force -ErrorAction SilentlyContinue }
}

Describe 'Lab 4.1 Test-Lab.ps1 - test harness' {

    It 'shadows the real Az commands instead of touching a subscription' {
        foreach ($run in $script:AllRuns) {
            $run.Refused | Should -BeFalse -Because "the harness must never fall through to the real Az commands (exit $($run.ExitCode)): $($run.Output)"
        }
    }

    It 'stubs every Az command the script calls' {
        $ast    = [System.Management.Automation.Language.Parser]::ParseFile($script:ScriptPath, [ref]$null, [ref]$null)
        $called = $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] }, $true) |
            ForEach-Object { $_.GetCommandName() } | Where-Object { $_ -match '^\w+-Az' } | Sort-Object -Unique
        @($called | Where-Object { $_ -notin $script:StubCommands }) | Should -BeNullOrEmpty
    }
}

Describe 'Lab 4.1 Test-Lab.ps1 - an untagged account is a failed check, not a crash (#355)' {

    It 'passes the three accounts as the guide leaves them' {
        $run = $script:AllTagged
        $run.ExitCode | Should -Be 0 -Because "output was:`n$($run.Output)"
        $run.FailLines | Should -Be 0
        $run.Output | Should -Match '\[PASS\] File share soft delete enabled'
    }

    It 'fails the three tag checks of an untagged account and still reaches the summary' {
        $run = $script:Untagged
        $run.ExitCode | Should -Be 1 -Because "output was:`n$($run.Output)"
        $run.Output | Should -Not -Match 'Cannot index into a null array'
        $run.Output | Should -Match "\[FAIL\] Tag 'Project' = 'SkyCraft'"
        $run.FailLines | Should -Be 3
        $run.Output | Should -Match 'Tests Failed:\s+3'
    }
}

Describe 'Lab 4.1 Test-Lab.ps1 - the Portal defaults the guide names (#358)' {

    It 'fails, counted, an account left on RA-GRS and names the Basics tab check box' {
        $run = $script:ReadAccessGeo
        $run.ExitCode | Should -Be 1 -Because "output was:`n$($run.Output)"
        $run.Output | Should -Match '\[FAIL\] Redundancy is Standard_GRS'
        $run.Output | Should -Match 'Actual: Standard_RAGRS - .Make read access to data available'
        $run.FailLines | Should -Be 1
        $run.Output | Should -Match 'Tests Failed:\s+1'
    }

    It 'fails, counted, an account without file share soft delete' {
        $run = $script:NoShareSoftDel
        $run.ExitCode | Should -Be 1 -Because "output was:`n$($run.Output)"
        $run.Output | Should -Match '\[FAIL\] File share soft delete enabled'
        $run.FailLines | Should -Be 1
        $run.Output | Should -Match 'Tests Failed:\s+1'
    }

    It 'fails, counted, a blob service lookup that fails, and prints its error' {
        $run = $script:BlobLookupFails
        $run.ExitCode | Should -Be 1 -Because "output was:`n$($run.Output)"
        $run.Output | Should -Match '\[FAIL\] Blob service properties readable'
        $run.Output | Should -Match "invalid status code 'Forbidden'"
        $run.Output | Should -Not -Match '\[WARN\]'
        $run.FailLines | Should -Be 1
        $run.Output | Should -Match 'Tests Failed:\s+1'
    }
}

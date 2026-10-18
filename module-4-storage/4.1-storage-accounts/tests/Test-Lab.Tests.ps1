<#
.SYNOPSIS
    Pester 5 tests: the Lab 4.1 validator reports an untagged account as failed tag checks.

.DESCRIPTION
    Regression cover for issue #355 ("Crash instead of a [FAIL] line"). Test-Lab.ps1 indexed the
    account's Tags with $tags['Project'] outside any try. An account without tags returns $null
    there, and indexing $null throws "Cannot index into a null array" under
    $ErrorActionPreference = 'Stop', which ended the script before its summary and its exit code.
    These tests run the real Test-Lab.ps1 in a child pwsh against a generated stub of the Az
    commands it calls, and assert that:

      1. Accounts as the guide leaves them pass, and the script exits 0.
      2. An account with no tags at all fails its three tag checks, counted, and the script
         still prints its summary and exits 1.

    No subscription is needed, and none is used: tests/Support/LabScriptStub.psm1 (issue #112)
    imports the real modules first, the stub last, and aborts the child with exit 99 unless every
    stubbed command resolves to the stub.

.EXAMPLE
    Invoke-Pester -Path .\Test-Lab.Tests.ps1

.NOTES
    Project: SkyCraft
    Lab: 4.1 - Storage Accounts
    Issue: #355
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
    )

    #   SKYCRAFT_STUB_NOTAGS   storage account names that carry no tags at all ($null Tags)
    $script:StubBody = @'
function Get-AzStorageAccount {
    [CmdletBinding()]
    param([string]$ResourceGroupName, [string]$Name, [Parameter(ValueFromRemainingArguments)]$Rest)
    $environmentTag = @{ platform = 'Platform'; dev = 'Development'; prod = 'Production' }[($ResourceGroupName -split '-')[0]]
    $sku            = @{ platform = 'Standard_GRS'; dev = 'Standard_LRS'; prod = 'Standard_GRS' }[($ResourceGroupName -split '-')[0]]
    $tags = if (@($env:SKYCRAFT_STUB_NOTAGS -split ',') -contains $Name) { $null } else { @{ Project = 'SkyCraft'; Environment = $environmentTag; CostCenter = 'MSDN' } }
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
    [pscustomobject]@{
        DeleteRetentionPolicy          = [pscustomobject]@{ Enabled = $true }
        ContainerDeleteRetentionPolicy = [pscustomobject]@{ Enabled = $true }
    }
}
'@

    function Invoke-ValidatorScript {
        param([pscustomobject]$Stub, [string[]]$NoTags = @())
        $run = Invoke-LabScriptWithStub -Stub $Stub -ScriptPath $script:ScriptPath -Environment @{
            SKYCRAFT_STUB_NOTAGS = $NoTags -join ','
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

    $script:AllTagged = Invoke-ValidatorScript -Stub $script:Stub
    $script:Untagged  = Invoke-ValidatorScript -Stub $script:Stub -NoTags 'devskycraftswcsa'
    $script:AllRuns   = @($script:AllTagged, $script:Untagged)
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

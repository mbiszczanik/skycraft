#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }
<#
.SYNOPSIS
    Pester 5 test: role-assignments.bicep has a deployment path, and that path cannot drift from
    the template it deploys.

.DESCRIPTION
    Issue #81: role-assignments.bicep declared four mandatory principal-ID parameters and nothing
    deployed it - its header pointed at New-LabRoleAssignment.ps1, which is imperative and never
    touches Bicep. Deploy-Bicep.ps1 -IncludeRoleAssignments now resolves the principals from Entra
    ID and deploys the template with them. This suite pins that contract without a tenant:

      - the switch exists and is documented, and the template's header points at it
      - every parameter the template requires is one the script passes, so a new mandatory
        parameter in the Bicep file fails here rather than at deployment time
      - every deployment the script makes has a matching what-if preview (issue #74)
      - the principal resolver, lifted out of the script with the PowerShell parser the way
        tests/Lab11-Graph-Auth.Tests.ps1 does, refuses ambiguity and absence rather than deploying
        a role to whichever object came back first
      - Lab 1.1's user is looked up by its full address on the tenant's initial *.onmicrosoft.com
        domain, where Lab 1.1 creates it (issue #237): the domain list is read through
        Invoke-AzRestMethod, a failed read is an error, and a tenant with no initial domain stops
        the script with [ERROR] and exit 1 before anything is looked up or deployed. That part runs
        the real script in a child pwsh through tests/Support/LabScriptStub.psm1 (issue #112),
        which refuses to run (exit 99) unless every stubbed command resolves to the stub.
      - a lab built in the Portal or by New-LabRoleAssignment.ps1 gets no second assignment
        (issue #406): the script reads which of the five exist at their exact scope, prints
        [KEEP] / [CREATE] for each, hands the held keys to both the what-if and the deployment as
        parExistingAssignments, and with all five held neither previews nor deploys. The template
        skips exactly the listed keys, and its five keys are the script's. That part runs the real
        script through the same harness, with the ARM role assignments API answered by
        Get-LabArmRoleAssignmentStub.
      - an Owner for Malfurion that has a condition, which Test-Lab.ps1 fails and ARM keeps no
        second one beside (guide Troubleshooting, Issue 6), stops the run with [ERROR] and exit 1
        before the what-if or the deployment, instead of being kept as the lab's.

    Evaluating only the FunctionDefinitionAst nodes means no script body runs, so no Azure call is
    made and no Az module is needed - while the code under test is the code the lab ships.

.EXAMPLE
    Invoke-Pester -Path .\module-1-identities-governance\1.2-rbac\tests\RoleAssignments-DeployPath.Tests.ps1

.NOTES
    Project: SkyCraft
    Lab: 1.2 - RBAC
#>

BeforeAll {
    $script:LabRoot      = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    $script:ScriptPath   = Join-Path $script:LabRoot 'scripts/Deploy-Bicep.ps1'
    $script:TemplatePath = Join-Path $script:LabRoot 'bicep/role-assignments.bicep'
    $script:ScriptText   = Get-Content -Raw -LiteralPath $script:ScriptPath
    $script:TemplateText = Get-Content -Raw -LiteralPath $script:TemplatePath

    $tokens = $null
    $parseError = $null
    $script:ScriptAst = [System.Management.Automation.Language.Parser]::ParseFile($script:ScriptPath, [ref]$tokens, [ref]$parseError)
    if ($parseError) { throw "Deploy-Bicep.ps1 does not parse: $($parseError[0].Message)" }

    function Get-CommandCount {
        param([string]$Name)
        $commands = $script:ScriptAst.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] }, $true)
        @($commands | Where-Object { $_.GetCommandName() -eq $Name }).Count
    }

    # The script's own helpers: Get-LabGraphSignInHint, Get-LabBuiltInRoleId and
    # Get-LabArmRoleAssignment (mocked below, so no request is sent).
    Import-Module (Join-Path $script:LabRoot '../../tools/LabCommon.psm1') -Force

    # Top level only ($false): a nested helper would not be callable on its own.
    foreach ($functionName in 'Resolve-LabPrincipalId', 'Get-LabExistingAssignmentKey') {
        $functionAst = $script:ScriptAst.FindAll({
            param($n)
            $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $functionName
        }, $false) | Select-Object -First 1
        if (-not $functionAst) { throw "Deploy-Bicep.ps1 does not define $functionName." }
        . ([scriptblock]::Create($functionAst.Extent.Text))
    }

    foreach ($helper in 'Get-LabDirectoryDomain', 'Select-LabInitialDomain') {
        $helperAst = $script:ScriptAst.FindAll({
            param($n)
            $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $helper
        }, $false) | Select-Object -First 1
        if (-not $helperAst) { throw "Deploy-Bicep.ps1 does not define $helper." }
        . ([scriptblock]::Create($helperAst.Extent.Text))
    }

    # Stubs so the Az.Resources cmdlets can be mocked on a runner that has no Az module. Unmocked
    # they return nothing, which is the "not found" answer; the parameters exist so a
    # -ParameterFilter can bind them.
    function Get-AzADUser  { [CmdletBinding()] param($Filter)      Write-Verbose "stub Get-AzADUser -Filter $Filter" }
    function Get-AzADGroup { [CmdletBinding()] param($DisplayName) Write-Verbose "stub Get-AzADGroup -DisplayName $DisplayName" }
    function Invoke-AzRestMethod { [CmdletBinding()] param($Method, $Uri) Write-Verbose "stub Invoke-AzRestMethod -Method $Method -Uri $Uri" }
}

Describe 'Lab 1.2 - role-assignments.bicep has a deployment path (#81)' {

    It 'Deploy-Bicep.ps1 declares an -IncludeRoleAssignments switch' {
        $script:ScriptText | Should -Match '\[switch\]\$IncludeRoleAssignments'
    }

    It 'documents the switch in its comment-based help, with an example' {
        $script:ScriptText | Should -Match '\.PARAMETER IncludeRoleAssignments'
        $script:ScriptText | Should -Match '(?m)^\s+\.\\Deploy-Bicep\.ps1.*-IncludeRoleAssignments'
    }

    It 'deploys role-assignments.bicep, not only resource-groups.bicep' {
        $script:ScriptText | Should -Match 'role-assignments\.bicep'
    }

    It 'previews every deployment it makes: one what-if call per New-AzSubscriptionDeployment' {
        # docs/powershell-standards.md 5: one shared splat, two cmdlets. A second template added
        # to the script without a second preview would leave -WhatIf silent about half the change.
        $deploys = Get-CommandCount -Name 'New-AzSubscriptionDeployment'
        $deploys | Should -BeGreaterThan 1 -Because 'the script now sends two templates'
        (Get-CommandCount -Name 'Get-AzSubscriptionDeploymentWhatIfResult') | Should -Be $deploys
    }

    It 'the template header names the switch as its deployment path' {
        $deploymentLine = ($script:TemplateText -split "`r?`n" | Where-Object { $_ -match '^DEPLOYMENT:' }) -join ' '
        $deploymentLine | Should -Match 'Deploy-Bicep\.ps1 -IncludeRoleAssignments'
    }
}

Describe 'Lab 1.2 - the script passes every parameter the template requires' {

    BeforeAll {
        # A `param name type` line with no `= default` is mandatory. Decorators sit on the lines
        # above and are irrelevant here.
        $script:RequiredParam = @(
            [regex]::Matches($script:TemplateText, '(?m)^param\s+(\w+)\s+\w+\s*$') |
                ForEach-Object { $_.Groups[1].Value }
        )
    }

    It 'finds the mandatory parameters to check, so the loop below cannot pass by vacuity' {
        $script:RequiredParam.Count | Should -BeGreaterThan 0
    }

    It 'passes <_> to the role-assignments deployment' -ForEach @(
        [regex]::Matches((Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot '../bicep/role-assignments.bicep')), '(?m)^param\s+(\w+)\s+\w+\s*$') |
            ForEach-Object { $_.Groups[1].Value }
    ) {
        $script:ScriptText | Should -Match "\b$_\b"
    }
}

Describe 'Lab 1.2 - Resolve-LabPrincipalId refuses to guess' {

    BeforeEach {
        Mock Get-AzADUser  { }
        Mock Get-AzADGroup { }
    }

    It 'resolves a member user by its full userPrincipalName, on the domain the caller names (#237)' {
        Mock Get-AzADUser { [pscustomobject]@{ Id = 'aaaaaaaa-0000-0000-0000-000000000001'; UserPrincipalName = 'malfurion.stormrage@contoso.onmicrosoft.com' } }
        Resolve-LabPrincipalId -Type User -Name 'malfurion.stormrage@contoso.onmicrosoft.com' | Should -Be 'aaaaaaaa-0000-0000-0000-000000000001'
        Should -Invoke Get-AzADUser -Times 1 -Exactly -ParameterFilter { $Filter -eq "userPrincipalName eq 'malfurion.stormrage@contoso.onmicrosoft.com'" }
    }

    It 'resolves a group by exact display name' {
        Mock Get-AzADGroup { [pscustomobject]@{ Id = 'bbbbbbbb-0000-0000-0000-000000000002'; DisplayName = 'SkyCraft-Developers' } }
        Resolve-LabPrincipalId -Type Group -Name 'SkyCraft-Developers' | Should -Be 'bbbbbbbb-0000-0000-0000-000000000002'
        Should -Invoke Get-AzADGroup -Times 1 -Exactly -ParameterFilter { $DisplayName -eq 'SkyCraft-Developers' }
    }

    It 'resolves a guest by mail, because a guest''s userPrincipalName is rewritten on invitation' {
        Mock Get-AzADUser { [pscustomobject]@{ Id = 'cccccccc-0000-0000-0000-000000000003'; Mail = 'istormrage@illidari.com' } }
        Resolve-LabPrincipalId -Type Guest -Name 'istormrage@illidari.com' | Should -Be 'cccccccc-0000-0000-0000-000000000003'
        Should -Invoke Get-AzADUser -Times 1 -Exactly -ParameterFilter { $Filter -eq "mail eq 'istormrage@illidari.com'" }
    }

    It 'throws, naming Lab 1.1, when the principal does not exist' {
        { Resolve-LabPrincipalId -Type Group -Name 'SkyCraft-Nobody' } | Should -Throw -ExpectedMessage '*Lab 1.1*'
    }

    It 'throws rather than picking the first of several matches' {
        Mock Get-AzADUser {
            [pscustomobject]@{ Id = 'dddddddd-0000-0000-0000-000000000004'; UserPrincipalName = 'malfurion.stormrage@a.example' }
            [pscustomobject]@{ Id = 'eeeeeeee-0000-0000-0000-000000000005'; UserPrincipalName = 'malfurion.stormrage@b.example' }
        }
        { Resolve-LabPrincipalId -Type User -Name 'malfurion.stormrage' } | Should -Throw -ExpectedMessage '*2*'
    }

    It 'returns a single string, never an array, even when the cmdlet returns one object in a collection' {
        Mock Get-AzADGroup { , @([pscustomobject]@{ Id = 'ffffffff-0000-0000-0000-000000000006' }) }
        $id = Resolve-LabPrincipalId -Type Group -Name 'SkyCraft-Testers'
        $id | Should -BeOfType [string]
        $id | Should -Be 'ffffffff-0000-0000-0000-000000000006'
    }
}

Describe 'Lab 1.2 - Get-LabDirectoryDomain reads the tenant''s domains through the Az token (#237)' {

    It 'returns the domains Microsoft Graph lists, ready for Select-LabInitialDomain' {
        Mock Invoke-AzRestMethod {
            [pscustomobject]@{ StatusCode = 200; Content = '{"value":[{"id":"contoso.example","isInitial":false},{"id":"contoso.onmicrosoft.com","isInitial":true}]}' }
        }
        $domains = @(Get-LabDirectoryDomain)
        $domains.Count | Should -Be 2
        Select-LabInitialDomain -Domain $domains | Should -Be 'contoso.onmicrosoft.com'
        Should -Invoke Invoke-AzRestMethod -Times 1 -Exactly -ParameterFilter { $Method -eq 'GET' -and $Uri -like 'https://graph.microsoft.com/v1.0/domains*' }
    }

    It 'throws on an HTTP error instead of returning an empty list' {
        # Invoke-AzRestMethod answers an HTTP error with a status code, not an exception.
        Mock Invoke-AzRestMethod { [pscustomobject]@{ StatusCode = 403; Content = '{"error":{"code":"Authorization_RequestDenied"}}' } }
        { Get-LabDirectoryDomain } | Should -Throw '*403*'
    }
}

Describe 'Lab 1.2 - Deploy-Bicep.ps1 -IncludeRoleAssignments looks Lab 1.1''s user up on the initial domain (#237)' {

    BeforeAll {
        Import-Module (Join-Path $PSScriptRoot '..' '..' '..' 'tests' 'Support' 'LabScriptStub.psm1') -Force

        # Exactly the script's '#Requires -Modules' line: these are imported for real before the stub.
        $requiredModules = @('Az.Accounts', 'Az.Resources')

        # Every Az command the script can reach. New-AzDeployment and Get-AzDeploymentWhatIfResult
        # are what the script's New-AzSubscriptionDeployment and Get-AzSubscriptionDeploymentWhatIfResult
        # aliases resolve to in Az.Resources: stubbing the alias names would not shadow them, the
        # targets do. No scenario here should get that far; the stubs throw if one does.
        $stubCommands = @(
            'Get-AzContext'
            'Connect-AzAccount'
            'Invoke-AzRestMethod'
            'Get-AzADUser'
            'Get-AzADGroup'
            'Get-AzResourceGroup'
            'Get-AzRoleAssignment'
            'New-AzDeployment'
            'Get-AzDeploymentWhatIfResult'
        )

        # SKYCRAFT_STUB_DOMAIN picks the GET /v1.0/domains answer: 'custom' (a custom default domain
        # next to the initial one), 'noinitial', 'http403'. Get-AzADGroup finds nothing, so a run
        # that gets past the user lookup stops at the first group with [ERROR] and exit 1, before
        # any deployment.
        $stubBody = @'
$script:LogPath = $env:SKYCRAFT_STUB_LOG

function Write-StubCall {
    param([string]$Name)
    if ($script:LogPath) { Add-Content -LiteralPath $script:LogPath -Value $Name }
}

function Get-AzContext {
    [CmdletBinding()]
    param()
    [pscustomobject]@{
        Subscription = [pscustomobject]@{ Id = '11111111-1111-1111-1111-111111111111'; Name = 'stub-subscription' }
        Tenant       = [pscustomobject]@{ Id = '00000000-0000-0000-0000-000000000000' }
    }
}

function Connect-AzAccount {
    [CmdletBinding()]
    param([Parameter(ValueFromRemainingArguments)]$Rest)
    Write-StubCall -Name 'Connect-AzAccount'
}

function Invoke-AzRestMethod {
    [CmdletBinding()]
    param([string]$Method, [string]$Uri, [Parameter(ValueFromRemainingArguments)]$Rest)
    Write-StubCall -Name "Invoke-AzRestMethod|$Method $Uri"
    switch ($env:SKYCRAFT_STUB_DOMAIN) {
        'http403'   { [pscustomobject]@{ StatusCode = 403; Content = '{"error":{"code":"Authorization_RequestDenied"}}' } }
        'noinitial' { [pscustomobject]@{ StatusCode = 200; Content = '{"value":[{"id":"contoso.example","isDefault":true,"isInitial":false}]}' } }
        default {
            [pscustomobject]@{ StatusCode = 200; Content = '{"value":[{"id":"contoso.example","isDefault":true,"isInitial":false},{"id":"contoso.onmicrosoft.com","isDefault":false,"isInitial":true}]}' }
        }
    }
}

function Get-AzADUser {
    [CmdletBinding()]
    param([string]$Filter, [Parameter(ValueFromRemainingArguments)]$Rest)
    Write-StubCall -Name "Get-AzADUser|$Filter"
    [pscustomobject]@{ Id = 'aaaaaaaa-0000-0000-0000-000000000001' }
}

function Get-AzADGroup {
    [CmdletBinding()]
    param([string]$DisplayName, [Parameter(ValueFromRemainingArguments)]$Rest)
    Write-StubCall -Name "Get-AzADGroup|$DisplayName"
}

function Get-AzResourceGroup {
    [CmdletBinding()]
    param([Parameter(ValueFromRemainingArguments)]$Rest)
    Write-StubCall -Name 'Get-AzResourceGroup'
}

function Get-AzRoleAssignment {
    [CmdletBinding()]
    param([Parameter(ValueFromRemainingArguments)]$Rest)
    Write-StubCall -Name 'Get-AzRoleAssignment'
}

function New-AzDeployment {
    [CmdletBinding()]
    param([Parameter(ValueFromRemainingArguments)]$Rest)
    Write-StubCall -Name 'New-AzDeployment'
    throw 'stub: this scenario must not deploy'
}

function Get-AzDeploymentWhatIfResult {
    [CmdletBinding()]
    param([Parameter(ValueFromRemainingArguments)]$Rest)
    Write-StubCall -Name 'Get-AzDeploymentWhatIfResult'
    throw 'stub: this scenario must not reach the what-if'
}
'@

        $script:DeployScriptPath = (Resolve-Path $script:ScriptPath).Path
        $script:DeployStub = Initialize-LabScriptStub -Name 'SkyCraftLab12DeployStub' -Command $stubCommands `
            -Body $stubBody -RequiredModule $requiredModules

        function Invoke-DeployScript {
            param([string]$Domain)

            $logPath = Join-Path $script:DeployStub.Directory 'calls.log'
            Remove-Item -LiteralPath $logPath -Force -ErrorAction SilentlyContinue

            $run = Invoke-LabScriptWithStub -Stub $script:DeployStub -ScriptPath $script:DeployScriptPath `
                -ArgumentList '-IncludeRoleAssignments', '-WhatIf' -Environment @{
                    SKYCRAFT_STUB_DOMAIN = $Domain
                    SKYCRAFT_STUB_LOG    = $logPath
                }

            $calls = if (Test-Path -LiteralPath $logPath) { @(Get-Content -LiteralPath $logPath) } else { @() }
            [pscustomobject]@{ ExitCode = $run.ExitCode; Refused = $run.Refused; Output = $run.Output; Calls = $calls }
        }

        # One invocation per scenario - each child process costs several seconds.
        $script:Custom    = Invoke-DeployScript -Domain 'custom'
        $script:NoInitial = Invoke-DeployScript -Domain 'noinitial'
        $script:Http403   = Invoke-DeployScript -Domain 'http403'
    }

    AfterAll {
        if ($script:DeployStub) { Remove-Item -LiteralPath $script:DeployStub.Directory -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'shadows the real Az commands instead of touching a tenant or a subscription' {
        foreach ($run in @($script:Custom, $script:NoInitial, $script:Http403)) {
            $run.Refused | Should -BeFalse -Because "the harness must never fall through to the real Az commands (exit $($run.ExitCode)): $($run.Output)"
            $run.Calls | Should -Not -Contain 'New-AzDeployment'
            $run.Calls | Should -Not -Contain 'Get-AzDeploymentWhatIfResult'
        }
    }

    It 'looks Malfurion up on the initial domain in a tenant whose default domain is a custom one' {
        $run = $script:Custom
        $run.Calls | Should -Contain "Get-AzADUser|userPrincipalName eq 'malfurion.stormrage@contoso.onmicrosoft.com'" -Because "Lab 1.1 creates him there; output was:`n$($run.Output)"
        ($run.Calls -join "`n") | Should -Not -Match '@contoso\.example'
        $run.Output | Should -Match 'Initial domain: contoso\.onmicrosoft\.com'
        # The stub tenant has no groups, so the run stops at the first one - after the user lookup.
        $run.Output | Should -Match "\[ERROR\] Group 'SkyCraft-Developers' not found"
        $run.ExitCode | Should -Be 1
    }

    It 'stops with [ERROR] and exit 1 when <case>, before any lookup or deployment' -ForEach @(
        @{ scenario = 'NoInitial'; case = 'the tenant lists no initial domain'; detail = 'no domain marked IsInitial' }
        @{ scenario = 'Http403';   case = 'the domain list cannot be read';     detail = '403' }
    ) {
        $run = Get-Variable -Scope Script -Name $scenario -ValueOnly
        $run.ExitCode | Should -Be 1 -Because "a guessed domain names users Lab 1.1 never created; output was:`n$($run.Output)"
        $run.Output | Should -Match ('\[ERROR\] Could not determine the tenant''s initial \*\.onmicrosoft\.com domain: [^\r\n]*' + [regex]::Escape($detail))
        @($run.Calls | Where-Object { $_ -like 'Invoke-AzRestMethod|GET https://graph.microsoft.com/v1.0/domains*' }).Count | Should -Be 1
        @($run.Calls | Where-Object { $_ -like 'Get-AzADUser|*' -or $_ -like 'Get-AzADGroup|*' -or $_ -eq 'Get-AzResourceGroup' }) |
            Should -BeNullOrEmpty -Because 'nothing may be looked up or deployed on a guessed domain'
    }
}

Describe 'Lab 1.2 - Resolve-LabPrincipalId names the Graph sign-in only when the lookup fails (#397)' {

    BeforeEach {
        Mock Get-AzADUser  { }
        Mock Get-AzADGroup { }
    }

    It 'throws with the sign-in that provides Microsoft Graph when the directory cannot be read' {
        Mock Get-AzADGroup { throw 'Authentication failed against resource MicrosoftGraphEndpointResourceId. User interaction is required. (stub)' }
        $thrown = $null
        try { Resolve-LabPrincipalId -Type Group -Name 'SkyCraft-Developers' } catch { $thrown = $_ }
        $thrown | Should -Not -BeNullOrEmpty
        "$thrown" | Should -Match "Could not look up Group 'SkyCraft-Developers' in Entra ID: Authentication failed"
        "$thrown" | Should -Match 'Connect-AzAccount -AuthScope MicrosoftGraphEndpointResourceId'
    }

    It 'does not name the sign-in when the principal <case>: signing in again does not help' -ForEach @(
        @{ case = 'does not exist'; twice = $false }
        @{ case = 'matches twice'; twice = $true }
    ) {
        if ($twice) {
            Mock Get-AzADGroup {
                [pscustomobject]@{ Id = 'dddddddd-0000-0000-0000-000000000004' }
                [pscustomobject]@{ Id = 'eeeeeeee-0000-0000-0000-000000000005' }
            }
        }
        $thrown = $null
        try { Resolve-LabPrincipalId -Type Group -Name 'SkyCraft-Developers' } catch { $thrown = $_ }
        $thrown | Should -Not -BeNullOrEmpty
        "$thrown" | Should -Not -Match 'AuthScope|Connect-'
    }
}

Describe 'Lab 1.2 - Get-LabExistingAssignmentKey reads exactly, and a failed read stops the run (#397, #406)' {

    BeforeAll {
        $script:Sub = '/subscriptions/00000000-0000-0000-0000-000000000000'
        $script:Desired = @(
            @{ Key = 'admin-owner';       ObjectId = 'aaaaaaaa-0000-0000-0000-000000000001'; Role = 'Owner';  Scope = $script:Sub; NoCondition = $true }
            @{ Key = 'tester-reader-dev'; ObjectId = 'aaaaaaaa-0000-0000-0000-000000000003'; Role = 'Reader'; Scope = "$script:Sub/resourceGroups/dev-skycraft-swc-rg" }
        )
    }

    It 'returns the key of an assignment made at the scope, and not of one of the same role inherited from above' {
        # The Testers' Reader on the subscription is listed at the resource group too, but it is
        # not the resource-group assignment the template makes.
        Mock Get-LabArmRoleAssignment {
            if ($PrincipalId -eq 'aaaaaaaa-0000-0000-0000-000000000001') {
                [pscustomobject]@{ RoleDefinitionId = '8e3af657-a8ff-443c-a75c-2fe8c4bcb635'; Scope = $Scope }
            }
            else {
                [pscustomobject]@{ RoleDefinitionId = 'acdd72a7-3385-48ef-bd42-f606fba81ae7'; Scope = '/subscriptions/00000000-0000-0000-0000-000000000000' }
            }
        }
        $held = @(Get-LabExistingAssignmentKey -Desired $script:Desired)
        $held | Should -Be @('admin-owner')
        Should -Invoke Get-LabArmRoleAssignment -Times 2 -Exactly
    }

    It 'returns both keys when both are made at their scope, in the order of the list' {
        Mock Get-LabArmRoleAssignment {
            $role = if ($PrincipalId -eq 'aaaaaaaa-0000-0000-0000-000000000001') { '8e3af657-a8ff-443c-a75c-2fe8c4bcb635' } else { 'acdd72a7-3385-48ef-bd42-f606fba81ae7' }
            [pscustomobject]@{ RoleDefinitionId = $role; Scope = $Scope }
        }
        @(Get-LabExistingAssignmentKey -Desired $script:Desired) | Should -Be @('admin-owner', 'tester-reader-dev')
    }

    It 'returns no key for an assignment of another role at the scope' {
        Mock Get-LabArmRoleAssignment { [pscustomobject]@{ RoleDefinitionId = 'b24988ac-6180-42a0-ab88-20f7382dd24c'; Scope = $Scope } }
        @(Get-LabExistingAssignmentKey -Desired $script:Desired).Count | Should -Be 0
    }

    It 'throws, naming the key, when the Owner it needs without a condition is there only with one' {
        # Test-Lab.ps1 fails it, and the template cannot add a second one beside it.
        Mock Get-LabArmRoleAssignment {
            $role = if ($PrincipalId -eq 'aaaaaaaa-0000-0000-0000-000000000001') { '8e3af657-a8ff-443c-a75c-2fe8c4bcb635' } else { 'acdd72a7-3385-48ef-bd42-f606fba81ae7' }
            [pscustomobject]@{ RoleDefinitionId = $role; Scope = $Scope; Condition = "((!(ActionMatches{'Microsoft.Authorization/roleAssignments/write'})))" }
        }
        { Get-LabExistingAssignmentKey -Desired $script:Desired } |
            Should -Throw -ExpectedMessage "admin-owner: the Owner assignment at $script:Sub has a condition*Issue 6*"
    }

    It 'keeps the Owner when one of its assignments has no condition, and a conditioned Reader the lab does not check' {
        Mock Get-LabArmRoleAssignment {
            if ($PrincipalId -eq 'aaaaaaaa-0000-0000-0000-000000000001') {
                [pscustomobject]@{ RoleDefinitionId = '8e3af657-a8ff-443c-a75c-2fe8c4bcb635'; Scope = $Scope; Condition = 'stub condition' }
                [pscustomobject]@{ RoleDefinitionId = '8e3af657-a8ff-443c-a75c-2fe8c4bcb635'; Scope = $Scope; Condition = '' }
            }
            else {
                [pscustomobject]@{ RoleDefinitionId = 'acdd72a7-3385-48ef-bd42-f606fba81ae7'; Scope = $Scope; Condition = 'stub condition' }
            }
        }
        @(Get-LabExistingAssignmentKey -Desired $script:Desired) | Should -Be @('admin-owner', 'tester-reader-dev')
    }

    It 'throws, naming the scope, when a read fails, instead of counting the assignment as missing' {
        Mock Get-LabArmRoleAssignment { throw 'ARM GET /subscriptions/0/providers/Microsoft.Authorization/roleAssignments returned HTTP 403 (AuthorizationFailed): stub' }
        { Get-LabExistingAssignmentKey -Desired $script:Desired } |
            Should -Throw -ExpectedMessage "Could not read the role assignments at $script:Sub*HTTP 403 (AuthorizationFailed)*"
    }

    It 'is what the script calls before it deploys, inside the block whose catch ends the run with exit 1' {
        # The catch around the role deployment prints [ERROR] and calls Exit-Lab -FailureCount 1;
        # the read must happen inside that try, so a failed read never reaches the deployment.
        # Command nodes, not text: a comment in the same block names the function too.
        $cmd = {
            param($t, $name)
            $t.Body.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] -and $n.GetCommandName() -eq $name }, $true) |
                Select-Object -First 1
        }
        $tryAst = $script:ScriptAst.FindAll({
            param($n)
            $n -is [System.Management.Automation.Language.TryStatementAst] -and
            (& $cmd $n 'Get-LabExistingAssignmentKey') -and
            (& $cmd $n 'New-AzSubscriptionDeployment')
        }, $true) | Select-Object -First 1
        $tryAst | Should -Not -BeNullOrEmpty
        $read = (& $cmd $tryAst 'Get-LabExistingAssignmentKey').Extent.StartOffset
        $whatIf = (& $cmd $tryAst 'Get-AzSubscriptionDeploymentWhatIfResult').Extent.StartOffset
        $deploy = (& $cmd $tryAst 'New-AzSubscriptionDeployment').Extent.StartOffset
        $whatIf | Should -Not -BeNullOrEmpty
        $read | Should -BeLessThan $whatIf
        $read | Should -BeLessThan $deploy
        $tryAst.CatchClauses[0].Body.Extent.Text | Should -Match 'Exit-Lab -FailureCount 1'
    }
}

Describe 'Lab 1.2 - role-assignments.bicep skips the assignments the script lists, under the same five keys (#406)' {

    BeforeAll {
        # Each module of the template as key|principal parameter|role|resource group ('' for the
        # subscription), and each of the script's $desired entries the same way.
        $rgDefault = @{}
        foreach ($m in [regex]::Matches($script:TemplateText, "(?m)^param\s+(\w+)\s+string\s*=\s*'([^']+)'")) {
            $rgDefault[$m.Groups[1].Value] = $m.Groups[2].Value
        }
        $script:TemplateModules = @([regex]::Matches($script:TemplateText, "(?m)^module\s+\w+\s+'[^']*role-assignment[^']*'"))
        $script:TemplateEntries = @(
            foreach ($m in [regex]::Matches($script:TemplateText, "(?ms)^module\s+\w+\s+'[^']*role-assignment[^']*'\s*=\s*if\s*\(!contains\(parExistingAssignments,\s*'([^']+)'\)\)\s*\{(.*?)^\}")) {
                $body = $m.Groups[2].Value
                $principalParam = [regex]::Match($body, 'principalId:\s*(\w+)').Groups[1].Value
                $role = [regex]::Match($body, 'var(Owner|Contributor|Reader)RoleId').Groups[1].Value
                $rgParam = [regex]::Match($body, 'scope:\s*resourceGroup\((\w+)\)').Groups[1].Value
                $rg = if ($rgParam) { $rgDefault[$rgParam] } else { '' }
                "$($m.Groups[1].Value)|$principalParam|$role|$rg"
            }
        )
        $script:ScriptEntries = @(
            foreach ($m in [regex]::Matches($script:ScriptText, '@\{\s*Key\s*=\s*''([^'']+)'';\s*ObjectId\s*=\s*\$principal\.(\w+);\s*Role\s*=\s*''(\w+)'';\s*Scope\s*=\s*"/subscriptions/\$subscriptionId(?:/resourceGroups/([^"]+))?"(?:;\s*NoCondition\s*=\s*\$true)?\s*\}')) {
                "$($m.Groups[1].Value)|$($m.Groups[2].Value)|$($m.Groups[3].Value)|$($m.Groups[4].Value)"
            }
        )
        $allowedBlock = [regex]::Match($script:TemplateText, "(?s)@allowed\(\[([^\]]*)\]\)\s*param\s+parExistingAssignments\s+array\s*=\s*\[\]").Groups[1].Value
        $script:AllowedKeys = @([regex]::Matches($allowedBlock, "'([^']+)'") | ForEach-Object { $_.Groups[1].Value })
    }

    It 'declares parExistingAssignments as an optional array, limited to the five keys' {
        $script:TemplateText | Should -Match '(?m)^param parExistingAssignments array = \[\]'
        $script:AllowedKeys.Count | Should -Be 5
    }

    It 'deploys each of its five role-assignment modules only when its key is not listed' {
        $script:TemplateModules.Count | Should -Be 5
        $script:TemplateEntries.Count | Should -Be $script:TemplateModules.Count -Because 'a module without the condition would create a second assignment over a Portal-made one'
    }

    It 'uses the keys the script hands it, each on the module for the same principal, role and scope' {
        $script:ScriptEntries.Count | Should -Be 5
        @($script:TemplateEntries | Sort-Object) | Should -Be @($script:ScriptEntries | Sort-Object)
        @($script:AllowedKeys | Sort-Object) | Should -Be @($script:ScriptEntries | ForEach-Object { ($_ -split '\|')[0] } | Sort-Object)
    }

    It 'hands the held keys to the template as parExistingAssignments' {
        $script:ScriptText | Should -Match 'parExistingAssignments\s*=\s*\$heldKeys'
    }
}

Describe 'Lab 1.2 - Deploy-Bicep.ps1 -IncludeRoleAssignments creates only the missing assignments (#406)' {

    BeforeAll {
        Import-Module (Join-Path $PSScriptRoot '..' '..' '..' 'tests' 'Support' 'LabScriptStub.psm1') -Force

        $requiredModules = @('Az.Accounts', 'Az.Resources')

        # New-AzDeployment and Get-AzDeploymentWhatIfResult are what the script's
        # New-AzSubscriptionDeployment and Get-AzSubscriptionDeploymentWhatIfResult aliases resolve
        # to in Az.Resources (see the #237 suite above).
        $stubCommands = @(
            'Get-AzContext'
            'Connect-AzAccount'
            'Invoke-AzRestMethod'
            'Get-AzADUser'
            'Get-AzADGroup'
            'Get-AzResourceGroup'
            'New-AzDeployment'
            'Get-AzDeploymentWhatIfResult'
        )

        # SKYCRAFT_STUB_HELD lists the keys of the assignments that exist, made outside the
        # template (random names). Two decoys are always there: the Testers' Reader on the
        # subscription, listed at every resource group by inheritance, and a Contributor for the
        # partner on the platform group. Neither is one of the template's five.
        # SKYCRAFT_STUB_CONDITIONED lists the held keys whose assignment carries a condition.
        # SKYCRAFT_STUB_ROLEFAIL '1' makes the role assignment listing fail with HTTP 403.
        $stubBody = @'
$script:LogPath = $env:SKYCRAFT_STUB_LOG
$script:Sub = '/subscriptions/11111111-1111-1111-1111-111111111111'
$script:Admin = 'aaaaaaaa-0000-0000-0000-000000000001'
$script:Developers = 'bbbbbbbb-0000-0000-0000-000000000002'
$script:Testers = 'cccccccc-0000-0000-0000-000000000003'
$script:Partner = 'dddddddd-0000-0000-0000-000000000004'

function Write-StubCall {
    param([string]$Name)
    if ($script:LogPath) { Add-Content -LiteralPath $script:LogPath -Value $Name }
}

function Get-AzContext {
    [CmdletBinding()]
    param()
    [pscustomobject]@{
        Subscription = [pscustomobject]@{ Id = '11111111-1111-1111-1111-111111111111'; Name = 'stub-subscription' }
        Tenant       = [pscustomobject]@{ Id = '00000000-0000-0000-0000-000000000000' }
    }
}

function Connect-AzAccount { [CmdletBinding()] param([Parameter(ValueFromRemainingArguments)]$Rest) throw 'stub: the script must not sign in when a context exists' }

# Graph (-Uri) answers the domain list; ARM (-Path) goes to the role assignments fake below.
function Invoke-AzRestMethod {
    [CmdletBinding()]
    param([string]$Method = 'GET', [string]$Uri, [string]$Path, [string]$Payload)
    if ($Uri) {
        Write-StubCall -Name "Graph|$Method $Uri"
        return [pscustomobject]@{ StatusCode = 200; Content = '{"value":[{"id":"contoso.onmicrosoft.com","isInitial":true}]}' }
    }
    Invoke-StubArmRestMethod -Method $Method -Path $Path -Payload $Payload
}

function Get-AzADUser {
    [CmdletBinding()]
    param([string]$Filter, [Parameter(ValueFromRemainingArguments)]$Rest)
    if ($Filter -like 'mail eq *') { [pscustomobject]@{ Id = $script:Partner } } else { [pscustomobject]@{ Id = $script:Admin } }
}

function Get-AzADGroup {
    [CmdletBinding()]
    param([string]$DisplayName, [Parameter(ValueFromRemainingArguments)]$Rest)
    switch ($DisplayName) {
        'SkyCraft-Developers' { [pscustomobject]@{ Id = $script:Developers } }
        'SkyCraft-Testers'    { [pscustomobject]@{ Id = $script:Testers } }
    }
}

function Get-AzResourceGroup {
    [CmdletBinding()]
    param([string]$Name, [Parameter(ValueFromRemainingArguments)]$Rest)
    [pscustomobject]@{ ResourceGroupName = $Name }
}

function Get-StubRoleAssignment {
    [CmdletBinding()]
    param([string]$Scope, [string]$PrincipalId)
    if ($env:SKYCRAFT_STUB_ROLEFAIL -eq '1') { Write-Error -Message 'stub: the client does not have authorization' -ErrorId 'AuthorizationFailed'; return }
    $held = @($env:SKYCRAFT_STUB_HELD -split ',' | Where-Object { $_ })
    $conditioned = @($env:SKYCRAFT_STUB_CONDITIONED -split ',' | Where-Object { $_ })
    $rg = "$script:Sub/resourceGroups"
    $records = @(
        @{ Key = 'admin-owner';               Scope = $script:Sub;                      PrincipalId = $script:Admin;      RoleDefinitionId = '8e3af657-a8ff-443c-a75c-2fe8c4bcb635' }
        @{ Key = 'developer-contributor-dev'; Scope = "$rg/dev-skycraft-swc-rg";        PrincipalId = $script:Developers; RoleDefinitionId = 'b24988ac-6180-42a0-ab88-20f7382dd24c'; PrincipalType = 'Group' }
        @{ Key = 'tester-reader-dev';         Scope = "$rg/dev-skycraft-swc-rg";        PrincipalId = $script:Testers;    RoleDefinitionId = 'acdd72a7-3385-48ef-bd42-f606fba81ae7'; PrincipalType = 'Group' }
        @{ Key = 'tester-reader-prod';        Scope = "$rg/prod-skycraft-swc-rg";       PrincipalId = $script:Testers;    RoleDefinitionId = 'acdd72a7-3385-48ef-bd42-f606fba81ae7'; PrincipalType = 'Group' }
        @{ Key = 'partner-reader-platform';   Scope = "$rg/platform-skycraft-swc-rg";   PrincipalId = $script:Partner;    RoleDefinitionId = 'acdd72a7-3385-48ef-bd42-f606fba81ae7' }
    )
    $all = @(foreach ($r in $records) {
        if ($r.Key -in $held) {
            $r.Name = [guid]::NewGuid().ToString()
            if ($r.Key -in $conditioned) { $r.Condition = "((!(ActionMatches{'Microsoft.Authorization/roleAssignments/write'})))" }
            $r
        }
    })
    $all += @{ Name = 'inherited-reader'; Scope = $script:Sub; PrincipalId = $script:Testers; RoleDefinitionId = 'acdd72a7-3385-48ef-bd42-f606fba81ae7'; PrincipalType = 'Group' }
    $all += @{ Name = 'other-role'; Scope = "$rg/platform-skycraft-swc-rg"; PrincipalId = $script:Partner; RoleDefinitionId = 'b24988ac-6180-42a0-ab88-20f7382dd24c' }
    # What ARM lists for a scope: the assignments at it, above it and below it.
    foreach ($a in $all) {
        if ($Scope.StartsWith($a.Scope, [System.StringComparison]::OrdinalIgnoreCase) -or $a.Scope.StartsWith($Scope, [System.StringComparison]::OrdinalIgnoreCase)) {
            [pscustomobject]$a
        }
    }
}

function Format-StubDeployment {
    param([string]$Kind, [hashtable]$Bound)
    $template = Split-Path -Leaf $Bound.TemplateFile
    $has = $Bound.ContainsKey('parExistingAssignments')
    $existing = [object[]]@()
    if ($has) { $existing = [object[]]@($Bound.parExistingAssignments) }
    $passed = [ordered]@{ HasExisting = $has; Existing = $existing }
    foreach ($key in @($Bound.Keys | Where-Object { $_ -like 'par*Id' })) { $passed[$key] = $Bound[$key] }
    "${Kind}|${template}|$($passed | ConvertTo-Json -Compress -Depth 5)"
}

function New-AzDeployment {
    [CmdletBinding()]
    param([string]$Name, [string]$Location, [string]$TemplateFile,
        [string]$parAdminPrincipalId, [string]$parDeveloperGroupPrincipalId, [string]$parTesterGroupPrincipalId, [string]$parPartnerPrincipalId,
        [object[]]$parExistingAssignments)
    Write-StubCall -Name (Format-StubDeployment -Kind 'Deploy' -Bound $PSBoundParameters)
    [pscustomobject]@{ ProvisioningState = 'Succeeded' }
}

function Get-AzDeploymentWhatIfResult {
    [CmdletBinding()]
    param([string]$Name, [string]$Location, [string]$TemplateFile,
        [string]$parAdminPrincipalId, [string]$parDeveloperGroupPrincipalId, [string]$parTesterGroupPrincipalId, [string]$parPartnerPrincipalId,
        [object[]]$parExistingAssignments)
    Write-StubCall -Name (Format-StubDeployment -Kind 'WhatIf' -Bound $PSBoundParameters)
}

# Az.Resources defines these two as aliases; on a runner without Az the stub provides them.
Set-Alias -Name New-AzSubscriptionDeployment -Value New-AzDeployment -Scope Global -Force
Set-Alias -Name Get-AzSubscriptionDeploymentWhatIfResult -Value Get-AzDeploymentWhatIfResult -Scope Global -Force
'@
        # The ARM fake answers -Path requests only; the stub's own Invoke-AzRestMethod routes to it.
        $armFake = (Get-LabArmRoleAssignmentStub).Replace('function Invoke-AzRestMethod {', 'function Invoke-StubArmRestMethod {')
        if ($armFake -notmatch 'function Invoke-StubArmRestMethod \{') { throw 'Get-LabArmRoleAssignmentStub no longer defines Invoke-AzRestMethod as this suite expects.' }

        $script:KeyDeployPath = (Resolve-Path $script:ScriptPath).Path
        $script:KeyStub = Initialize-LabScriptStub -Name 'SkyCraftLab12ExistingStub' -Command $stubCommands `
            -Body ($stubBody + $armFake) -RequiredModule $requiredModules

        function Invoke-KeyDeployScript {
            param([string[]]$Held = @(), [string[]]$Conditioned = @(), [switch]$Deploy, [switch]$RoleFail)

            $logPath = Join-Path $script:KeyStub.Directory 'calls.log'
            Remove-Item -LiteralPath $logPath -Force -ErrorAction SilentlyContinue

            $arguments = @('-IncludeRoleAssignments') + @(if (-not $Deploy) { '-WhatIf' })
            $run = Invoke-LabScriptWithStub -Stub $script:KeyStub -ScriptPath $script:KeyDeployPath `
                -ArgumentList $arguments -Environment @{
                    SKYCRAFT_STUB_HELD        = ($Held -join ',')
                    SKYCRAFT_STUB_CONDITIONED = ($Conditioned -join ',')
                    SKYCRAFT_STUB_ROLEFAIL = if ($RoleFail) { '1' } else { '0' }
                    SKYCRAFT_STUB_LOG      = $logPath
                }

            $calls = if (Test-Path -LiteralPath $logPath) { @(Get-Content -LiteralPath $logPath) } else { @() }
            $roleCalls = @($calls | Where-Object { $_ -like '*|role-assignments.bicep|*' })
            $parse = { param($line) ($line -split '\|', 3)[2] | ConvertFrom-Json -AsHashtable }
            [pscustomobject]@{
                ExitCode    = $run.ExitCode
                Refused     = $run.Refused
                Output      = $run.Output
                Calls       = $calls
                RoleWhatIf  = @($roleCalls | Where-Object { $_ -like 'WhatIf|*' } | ForEach-Object { & $parse $_ })
                RoleDeploy  = @($roleCalls | Where-Object { $_ -like 'Deploy|*' } | ForEach-Object { & $parse $_ })
            }
        }

        $script:PartialKeys = @('admin-owner', 'developer-contributor-dev', 'tester-reader-dev')
        $script:AllKeys = @('admin-owner', 'developer-contributor-dev', 'tester-reader-dev', 'tester-reader-prod', 'partner-reader-platform')

        # One invocation per scenario - each child process costs several seconds.
        $script:FreshWhatIf   = Invoke-KeyDeployScript
        $script:PartialWhatIf = Invoke-KeyDeployScript -Held $script:PartialKeys
        $script:PartialDeploy = Invoke-KeyDeployScript -Held $script:PartialKeys -Deploy
        $script:AllWhatIf     = Invoke-KeyDeployScript -Held $script:AllKeys
        $script:AllDeploy     = Invoke-KeyDeployScript -Held $script:AllKeys -Deploy
        $script:ReadFails     = Invoke-KeyDeployScript -Deploy -RoleFail
        $script:Conditioned   = Invoke-KeyDeployScript -Held $script:PartialKeys -Conditioned 'admin-owner' -Deploy
        $script:KeyRuns = @($script:FreshWhatIf, $script:PartialWhatIf, $script:PartialDeploy, $script:AllWhatIf, $script:AllDeploy, $script:ReadFails, $script:Conditioned)
    }

    AfterAll {
        if ($script:KeyStub) { Remove-Item -LiteralPath $script:KeyStub.Directory -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'shadows the real Az commands instead of touching a tenant or a subscription' {
        foreach ($run in $script:KeyRuns) {
            $run.Refused | Should -BeFalse -Because "the harness must never fall through to the real Az commands (exit $($run.ExitCode)): $($run.Output)"
        }
    }

    It 'previews all five over a subscription that holds none, with an empty parExistingAssignments' {
        $run = $script:FreshWhatIf
        $run.ExitCode | Should -Be 0 -Because "output was:`n$($run.Output)"
        $run.Output | Should -Match 'Existing assignments: 0 of 5'
        ([regex]::Matches($run.Output, '\[CREATE\]')).Count | Should -Be 5
        $run.RoleWhatIf.Count | Should -Be 1
        $run.RoleWhatIf[0].HasExisting | Should -BeTrue
        @($run.RoleWhatIf[0].Existing).Count | Should -Be 0
        $run.RoleWhatIf[0].parAdminPrincipalId | Should -Be 'aaaaaaaa-0000-0000-0000-000000000001'
        $run.RoleDeploy.Count | Should -Be 0
    }

    It 'keeps the three held and creates the two missing, not counting an inherited Reader or another role' {
        # Without the scope check the Testers' Reader on the subscription would count as
        # tester-reader-prod; without the role check the partner's Contributor as partner-reader-platform.
        $run = $script:PartialWhatIf
        $run.ExitCode | Should -Be 0 -Because "output was:`n$($run.Output)"
        $run.Output | Should -Match 'Existing assignments: 3 of 5'
        foreach ($key in $script:PartialKeys) { $run.Output | Should -Match "\[KEEP\]\s+$key " }
        foreach ($key in 'tester-reader-prod', 'partner-reader-platform') { $run.Output | Should -Match "\[CREATE\]\s+$key " }
    }

    It 'hands only the held keys to the what-if, and does not deploy under -WhatIf' {
        $run = $script:PartialWhatIf
        $run.RoleWhatIf.Count | Should -Be 1
        @($run.RoleWhatIf[0].Existing | Sort-Object) | Should -Be @($script:PartialKeys | Sort-Object)
        $run.RoleDeploy.Count | Should -Be 0
        @($run.Calls | Where-Object { $_ -like 'Deploy|*' }) | Should -BeNullOrEmpty
    }

    It 'hands the same held keys to the deployment' {
        $run = $script:PartialDeploy
        $run.ExitCode | Should -Be 0 -Because "output was:`n$($run.Output)"
        $run.RoleDeploy.Count | Should -Be 1
        $run.RoleDeploy[0].HasExisting | Should -BeTrue
        @($run.RoleDeploy[0].Existing | Sort-Object) | Should -Be @($script:PartialKeys | Sort-Object)
        $run.RoleDeploy[0].parTesterGroupPrincipalId | Should -Be 'cccccccc-0000-0000-0000-000000000003'
        $run.RoleWhatIf.Count | Should -Be 0
        $run.Output | Should -Match '\[SUCCESS\] Role assignments deployed successfully'
    }

    It 'neither previews nor deploys the template when all five are held (<case>)' -ForEach @(
        @{ case = '-WhatIf'; scenario = 'AllWhatIf'; complete = $false }
        @{ case = 'deploy';  scenario = 'AllDeploy'; complete = $true }
    ) {
        $run = Get-Variable -Scope Script -Name $scenario -ValueOnly
        $run.ExitCode | Should -Be 0 -Because "output was:`n$($run.Output)"
        $run.Output | Should -Match 'Existing assignments: 5 of 5'
        ([regex]::Matches($run.Output, '\[KEEP\]')).Count | Should -Be 5
        $run.Output | Should -Match '\[SKIP\] All 5 role assignments already exist'
        $run.RoleWhatIf.Count | Should -Be 0
        $run.RoleDeploy.Count | Should -Be 0
        # A dry run deploys nothing, so it must not say it did.
        if ($complete) { $run.Output | Should -Match 'Deployment Complete' } else { $run.Output | Should -Not -Match 'Deployment Complete' }
    }

    It 'stops with [ERROR] and exit 1, deploying no role assignment, when the listing fails' {
        $run = $script:ReadFails
        $run.ExitCode | Should -Be 1 -Because "output was:`n$($run.Output)"
        $run.Output | Should -Match '\[ERROR\] Role assignment deployment failed: Could not read the role assignments at /subscriptions/'
        $run.Output | Should -Not -Match 'Existing assignments:'
        $run.RoleWhatIf.Count | Should -Be 0
        $run.RoleDeploy.Count | Should -Be 0
    }

    It 'stops with [ERROR] and exit 1, previewing and deploying no role assignment, when Malfurion''s Owner has a condition' {
        # It used to print [KEEP] and exit 0, while Test-Lab.ps1 fails it.
        $run = $script:Conditioned
        $run.ExitCode | Should -Be 1 -Because "output was:`n$($run.Output)"
        $run.Output | Should -Match '\[ERROR\] Role assignment deployment failed: admin-owner: the Owner assignment at /subscriptions/11111111-1111-1111-1111-111111111111 has a condition[^\r\n]*Issue 6'
        $run.Output | Should -Not -Match '\[KEEP\]|Deployment Complete'
        $run.RoleWhatIf.Count | Should -Be 0
        $run.RoleDeploy.Count | Should -Be 0
    }
}

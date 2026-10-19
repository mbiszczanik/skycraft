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
    foreach ($functionName in 'Resolve-LabPrincipalId', 'Get-LabExistingAssignmentCount') {
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

Describe 'Lab 1.2 - Get-LabExistingAssignmentCount reads exactly, and a failed read stops the run (#397)' {

    BeforeAll {
        $script:Sub = '/subscriptions/00000000-0000-0000-0000-000000000000'
        $script:Desired = @(
            @{ ObjectId = 'aaaaaaaa-0000-0000-0000-000000000001'; Role = 'Owner';  Scope = $script:Sub }
            @{ ObjectId = 'aaaaaaaa-0000-0000-0000-000000000003'; Role = 'Reader'; Scope = "$script:Sub/resourceGroups/dev-skycraft-swc-rg" }
        )
    }

    It 'counts an assignment made at the scope, and not one of the same role inherited from above' {
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
        Get-LabExistingAssignmentCount -Desired $script:Desired | Should -Be 1
        Should -Invoke Get-LabArmRoleAssignment -Times 2 -Exactly
    }

    It 'does not count an assignment of another role at the scope' {
        Mock Get-LabArmRoleAssignment { [pscustomobject]@{ RoleDefinitionId = 'b24988ac-6180-42a0-ab88-20f7382dd24c'; Scope = $Scope } }
        Get-LabExistingAssignmentCount -Desired $script:Desired | Should -Be 0
    }

    It 'throws, naming the scope, when a read fails, instead of counting the assignment as missing' {
        Mock Get-LabArmRoleAssignment { throw 'ARM GET /subscriptions/0/providers/Microsoft.Authorization/roleAssignments returned HTTP 403 (AuthorizationFailed): stub' }
        { Get-LabExistingAssignmentCount -Desired $script:Desired } |
            Should -Throw -ExpectedMessage "Could not read the role assignments at $script:Sub*HTTP 403 (AuthorizationFailed)*"
    }

    It 'is what the script calls before it deploys, inside the block whose catch ends the run with exit 1' {
        # The catch around the role deployment prints [ERROR] and calls Exit-Lab -FailureCount 1;
        # the count must happen inside that try, so a failed read never reaches the deployment.
        $tryAst = $script:ScriptAst.FindAll({
            param($n)
            $n -is [System.Management.Automation.Language.TryStatementAst] -and
            $n.Body.Extent.Text -match 'Get-LabExistingAssignmentCount' -and
            $n.Body.Extent.Text -match 'New-AzSubscriptionDeployment'
        }, $true) | Select-Object -First 1
        $tryAst | Should -Not -BeNullOrEmpty
        $count = $tryAst.Body.Extent.Text.IndexOf('Get-LabExistingAssignmentCount')
        $deploy = $tryAst.Body.Extent.Text.IndexOf('New-AzSubscriptionDeployment')
        $count | Should -BeLessThan $deploy
        $tryAst.CatchClauses[0].Body.Extent.Text | Should -Match 'Exit-Lab -FailureCount 1'
    }
}

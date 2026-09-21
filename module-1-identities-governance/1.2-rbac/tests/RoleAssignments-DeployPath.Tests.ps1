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

    # Top level only ($false): a nested helper would not be callable on its own.
    $resolverAst = $script:ScriptAst.FindAll({
        param($n)
        $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Resolve-LabPrincipalId'
    }, $false) | Select-Object -First 1
    if (-not $resolverAst) { throw 'Deploy-Bicep.ps1 does not define Resolve-LabPrincipalId.' }
    . ([scriptblock]::Create($resolverAst.Extent.Text))

    # Stubs so the Az.Resources cmdlets can be mocked on a runner that has no Az module. Unmocked
    # they return nothing, which is the "not found" answer; the parameters exist so a
    # -ParameterFilter can bind them.
    function Get-AzADUser  { [CmdletBinding()] param($Filter)      Write-Verbose "stub Get-AzADUser -Filter $Filter" }
    function Get-AzADGroup { [CmdletBinding()] param($DisplayName) Write-Verbose "stub Get-AzADGroup -DisplayName $DisplayName" }
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

    It 'resolves a member user by userPrincipalName prefix, so the tenant domain is never hard-coded' {
        Mock Get-AzADUser { [pscustomobject]@{ Id = 'aaaaaaaa-0000-0000-0000-000000000001'; UserPrincipalName = 'malfurion.stormrage@contoso.onmicrosoft.com' } }
        Resolve-LabPrincipalId -Type User -Name 'malfurion.stormrage' | Should -Be 'aaaaaaaa-0000-0000-0000-000000000001'
        Should -Invoke Get-AzADUser -Times 1 -Exactly -ParameterFilter { $Filter -like "startsWith(userPrincipalName,'malfurion.stormrage@')*" }
    }

    It 'resolves a group by exact display name' {
        Mock Get-AzADGroup { [pscustomobject]@{ Id = 'bbbbbbbb-0000-0000-0000-000000000002'; DisplayName = 'SkyCraft-Developers' } }
        Resolve-LabPrincipalId -Type Group -Name 'SkyCraft-Developers' | Should -Be 'bbbbbbbb-0000-0000-0000-000000000002'
        Should -Invoke Get-AzADGroup -Times 1 -Exactly -ParameterFilter { $DisplayName -eq 'SkyCraft-Developers' }
    }

    It 'resolves a guest by mail, because a guest''s userPrincipalName is rewritten on invitation' {
        Mock Get-AzADUser { [pscustomobject]@{ Id = 'cccccccc-0000-0000-0000-000000000003'; Mail = 'illidan@externalcompany.com' } }
        Resolve-LabPrincipalId -Type Guest -Name 'illidan@externalcompany.com' | Should -Be 'cccccccc-0000-0000-0000-000000000003'
        Should -Invoke Get-AzADUser -Times 1 -Exactly -ParameterFilter { $Filter -eq "mail eq 'illidan@externalcompany.com'" }
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

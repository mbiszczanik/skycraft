<#
.SYNOPSIS
    Pester 5 test: every Module 1 script that builds a Lab 1.1 user's address picks the tenant's
    initial domain with one and the same function.

.DESCRIPTION
    Lab 1.1 creates its users on the tenant's initial *.onmicrosoft.com domain, as its guide says
    ('<name>@[yourtenant].onmicrosoft.com'). Issue #193 found Lab 1.1's scripts using the default
    domain instead, and issue #237 found the same in Lab 1.2: in a tenant whose default domain is
    a custom one, the scripts named users Lab 1.1 never created, and a failed lookup fell back to
    a guess.

    The five scripts that build such an address - New-LabUser.ps1, Test-Lab.ps1 and
    Remove-LabResource.ps1 in Lab 1.1, New-LabRoleAssignment.ps1 and Deploy-Bicep.ps1 in Lab 1.2 -
    each carry a byte-identical copy of Select-LabInitialDomain rather than import a shared module:
    docs/powershell-standards.md 7.3 keeps connection checks and lookups in each lab. This suite
    holds the copies together the way tests/Lab11-Graph-Auth.Tests.ps1 holds the Graph sign-in
    together:

      - every script defines the function and calls it, and the copies do not drift;
      - no Module 1 script reads the default domain (IsDefault) any more;
      - the function, lifted out with the parser, picks the initial domain next to a custom
        default one, from Get-MgDomain objects and from the JSON of GET /v1.0/domains alike, and
        throws - never guesses - when there is no initial domain.

    What each script does with the answer (exit 1 with [ERROR] when it throws) is proved by
    running the scripts: Lab 1.1's tests/Guide-Addresses.Tests.ps1 and Lab 1.2's
    tests/New-LabRoleAssignment.Tests.ps1 and tests/RoleAssignments-DeployPath.Tests.ps1.

.EXAMPLE
    Invoke-Pester -Path .\tests\Module1-Initial-Domain.Tests.ps1

.NOTES
    Project: SkyCraft
#>

#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    $module1 = Join-Path $script:RepoRoot 'module-1-identities-governance'

    $script:ScriptPath = [ordered]@{
        '1.1 New-LabUser.ps1'           = Join-Path $module1 '1.1-entra-users-groups/scripts/New-LabUser.ps1'
        '1.1 Test-Lab.ps1'              = Join-Path $module1 '1.1-entra-users-groups/scripts/Test-Lab.ps1'
        '1.1 Remove-LabResource.ps1'    = Join-Path $module1 '1.1-entra-users-groups/scripts/Remove-LabResource.ps1'
        '1.2 New-LabRoleAssignment.ps1' = Join-Path $module1 '1.2-rbac/scripts/New-LabRoleAssignment.ps1'
        '1.2 Deploy-Bicep.ps1'          = Join-Path $module1 '1.2-rbac/scripts/Deploy-Bicep.ps1'
    }

    $script:Ast = @{}
    foreach ($name in $script:ScriptPath.Keys) {
        $parseError = $null
        $script:Ast[$name] = [System.Management.Automation.Language.Parser]::ParseFile($script:ScriptPath[$name], [ref]$null, [ref]$parseError)
        if ($parseError) { throw "$name does not parse: $($parseError[0].Message)" }
    }

    function Get-SelectFunctionAst {
        param([string]$Name)
        # Top level only ($false): a nested helper would not be callable on its own.
        @($script:Ast[$Name].FindAll({
            $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $args[0].Name -eq 'Select-LabInitialDomain'
        }, $false))
    }

    $lifted = Get-SelectFunctionAst -Name '1.1 New-LabUser.ps1'
    if ($lifted.Count -ne 1) { throw 'New-LabUser.ps1 does not define Select-LabInitialDomain once.' }
    . ([scriptblock]::Create($lifted[0].Extent.Text))
}

Describe 'Module 1 initial domain - five scripts, one lookup (#193, #237)' {

    It '<name> defines Select-LabInitialDomain once, at the top level' -ForEach @(
        @{ name = '1.1 New-LabUser.ps1' }, @{ name = '1.1 Test-Lab.ps1' }, @{ name = '1.1 Remove-LabResource.ps1' }
        @{ name = '1.2 New-LabRoleAssignment.ps1' }, @{ name = '1.2 Deploy-Bicep.ps1' }
    ) {
        @(Get-SelectFunctionAst -Name $name).Count | Should -Be 1
    }

    It 'ships byte-identical copies in all five scripts' {
        $text = foreach ($name in $script:ScriptPath.Keys) {
            (Get-SelectFunctionAst -Name $name)[0].Extent.Text -replace "`r`n", "`n"
        }
        @($text).Count | Should -Be 5
        ($text | Sort-Object -Unique).Count | Should -Be 1 -Because 'each lab reads on its own (7.3), so the copies must not drift'
    }

    It '<name> calls Select-LabInitialDomain exactly once, outside the function itself' -ForEach @(
        @{ name = '1.1 New-LabUser.ps1' }, @{ name = '1.1 Test-Lab.ps1' }, @{ name = '1.1 Remove-LabResource.ps1' }
        @{ name = '1.2 New-LabRoleAssignment.ps1' }, @{ name = '1.2 Deploy-Bicep.ps1' }
    ) {
        $calls = @($script:Ast[$name].FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.CommandAst] -and $node.GetCommandName() -eq 'Select-LabInitialDomain'
        }, $true))
        $calls.Count | Should -Be 1
    }

    It 'no Module 1 script reads the default domain' {
        $module1 = Join-Path $script:RepoRoot 'module-1-identities-governance'
        # Lab directories first, then their scripts: a wildcard path with -Recurse -File returns
        # nothing on pwsh 7.6, and an empty list would pass this test by vacuity.
        $scripts = @(Get-ChildItem -LiteralPath $module1 -Directory |
            ForEach-Object { Join-Path $_.FullName 'scripts' } |
            Where-Object { Test-Path -LiteralPath $_ } |
            Get-ChildItem -File -Filter '*.ps1')
        $scripts.Count | Should -BeGreaterThan 5

        $offenders = @($scripts | Where-Object { (Get-Content -Raw -LiteralPath $_.FullName) -match '\bIsDefault\b' } | ForEach-Object Name)
        $offenders | Should -BeNullOrEmpty -Because 'Lab 1.1 creates its users on the initial domain, not the default one'
    }
}

Describe 'Select-LabInitialDomain - picks the initial domain, never guesses' {

    It 'picks the initial domain in a tenant whose default domain is a custom one' {
        $domains = @(
            [pscustomobject]@{ Id = 'contoso.example';         IsDefault = $true;  IsInitial = $false }
            [pscustomobject]@{ Id = 'contoso.onmicrosoft.com'; IsDefault = $false; IsInitial = $true }
        )
        Select-LabInitialDomain -Domain $domains | Should -Be 'contoso.onmicrosoft.com'
    }

    It 'reads the JSON of GET /v1.0/domains, whose property names are camelCase' {
        $json = '{"value":[{"id":"contoso.example","isInitial":false},{"id":"contoso.onmicrosoft.com","isInitial":true}]}'
        Select-LabInitialDomain -Domain @(($json | ConvertFrom-Json).value) | Should -Be 'contoso.onmicrosoft.com'
    }

    It 'returns a single string' {
        $result = Select-LabInitialDomain -Domain @([pscustomobject]@{ Id = 'contoso.onmicrosoft.com'; IsInitial = $true })
        $result | Should -BeOfType [string]
    }

    It 'throws when <case>, instead of guessing a domain' -ForEach @(
        @{ case = 'no domain is marked initial'; domains = @([pscustomobject]@{ Id = 'contoso.example'; IsDefault = $true; IsInitial = $false }) }
        @{ case = 'the tenant lists no domain';  domains = @() }
        @{ case = 'the initial domain has no id'; domains = @([pscustomobject]@{ Id = $null; IsInitial = $true }) }
    ) {
        { Select-LabInitialDomain -Domain $domains } | Should -Throw '*no domain marked IsInitial*'
    }

    It 'throws when the lookup returned nothing at all' {
        { Select-LabInitialDomain -Domain $null } | Should -Throw '*no domain marked IsInitial*'
    }
}

<#
.SYNOPSIS
    Pester 5 test: the decisions the resource audit makes about what counts as drift.

.DESCRIPTION
    Follows the pattern established by tests/Lab53-Cleanup-Logic.Tests.ps1 (#115):
    it lifts the decision helpers out of scripts/Invoke-ResourceAudit.ps1 with the
    PowerShell parser and runs them against synthetic sources and synthetic
    resources. Evaluating only the FunctionDefinitionAst nodes means the script
    body never executes, so no Azure call is made and no Az module is needed -
    while the code under test is the real code the audit ships.

    Why this exists (issue #116): a tagged VM - prod-skycraft-swc-traffic-vm -
    ran and billed in prod-skycraft-swc-rg while nothing in the repository
    referred to it. The audit's job is to notice that.

    The naive form of the check proposed in #116 - flag a resource whose name is
    not referenced by a current .bicep, .bicepparam or Remove-LabResource.ps1 -
    cannot work here, because roughly half of all resource names are composed at
    deploy time from an environment parameter and a suffix and never appear in
    the sources as literals. Grepping for the literal name flags
    prod-skycraft-swc-kv, -asp and -app01 - all legitimate, actively deployed
    lab resources - exactly as loudly as it flags the real orphan. Those three
    are pinned below as regression guards.

.EXAMPLE
    Invoke-Pester -Path .\tests\Resource-Audit.Tests.ps1

.NOTES
    Project: SkyCraft
#>

#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    $RepoRoot   = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    $ScriptPath = Join-Path $RepoRoot 'scripts/Invoke-ResourceAudit.ps1'

    if (-not (Test-Path -LiteralPath $ScriptPath)) {
        throw "Invoke-ResourceAudit.ps1 not found at $ScriptPath"
    }

    $parseError = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($ScriptPath, [ref]$null, [ref]$parseError)
    if ($parseError) {
        throw "Invoke-ResourceAudit.ps1 does not parse: $($parseError[0].Message)"
    }

    # Top level only ($false): nested helpers would not be callable on their own.
    $functionAst = $ast.FindAll(
        { $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $false)
    foreach ($function in $functionAst) {
        . ([scriptblock]::Create($function.Extent.Text))
    }

    $script:LiftedName  = @($functionAst.Name)
    $script:RealRepoRoot = $RepoRoot
    $script:ScriptText   = Get-Content -Raw -LiteralPath $ScriptPath

    function Get-ResourceFixture {
        param([string]$Name, [string]$ResourceType = 'Microsoft.Compute/virtualMachines')
        [PSCustomObject]@{
            Name              = $Name
            ResourceType      = $ResourceType
            ResourceGroupName = 'prod-skycraft-swc-rg'
            ResourceId        = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/prod-skycraft-swc-rg/providers/$ResourceType/$Name"
        }
    }
}

Describe 'Resource audit - the script exposes its decisions as functions' {

    It 'defines every decision helper the audit relies on' {
        foreach ($name in @(
                'Get-KnownResourceName'
                'Test-LabResourceKnown'
                'Select-UnreferencedResource')) {
            $script:LiftedName | Should -Contain $name
        }
    }
}

Describe 'Resource audit - name expansion over synthetic sources' {

    BeforeAll {
        $script:Fixture = Join-Path $TestDrive 'sources'
        New-Item -ItemType Directory -Path (Join-Path $script:Fixture 'bicep') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $script:Fixture 'scripts') -Force | Out-Null

        # A literal name, exactly as Lab 5.3 spells its flow log.
        Set-Content -LiteralPath (Join-Path $script:Fixture 'bicep/main.bicep') -Encoding utf8 -Value @'
var varLiteralName = 'prod-skycraft-swc-vnet-flowlog'
var varNamePrefix = '${parEnvironment}-${parProject}-${varLocationShortCode}'
var varWidgetName = '${varNamePrefix}-widget'
'@

        # A PowerShell-composed name, exactly as the lab scripts spell theirs.
        Set-Content -LiteralPath (Join-Path $script:Fixture 'scripts/Remove-LabResource.ps1') -Encoding utf8 -Value @'
$gadgetName = "$Environment-skycraft-swc-gadget"
'@

        $script:Known = @(Get-KnownResourceName -RepoRoot $script:Fixture)
    }

    It 'keeps a name a source spells literally' {
        $script:Known | Should -Contain 'prod-skycraft-swc-vnet-flowlog'
    }

    It 'expands a bicep prefix template over every allowed environment' {
        foreach ($env in @('dev', 'prod', 'platform')) {
            $script:Known | Should -Contain "$env-skycraft-swc-widget"
        }
    }

    It 'expands a PowerShell-composed name over every allowed environment' {
        foreach ($env in @('dev', 'prod', 'platform')) {
            $script:Known | Should -Contain "$env-skycraft-swc-gadget"
        }
    }

    It 'does not invent a name no source produces' {
        $script:Known | Should -Not -Contain 'prod-skycraft-swc-sprocket'
    }
}

Describe 'Resource audit - the known set stays a set of resource names' {

    BeforeAll {
        $script:RealKnown = @(Get-KnownResourceName -RepoRoot $script:RealRepoRoot)
    }

    # The audit prints the size of this set, so the number has to mean something.
    # Description strings and resource-ID templates also mention the project and
    # would otherwise be expanded and counted alongside the real names - no Azure
    # resource can be called 'Development team for SkyCraft deployment'.
    It 'holds nothing that Azure could not name a resource' {
        $implausible = @($script:RealKnown | Where-Object { $_ -match '[\s/\\:]' -or $_.Length -gt 90 })
        $implausible | Should -BeNullOrEmpty
    }

    It 'still holds the names the labs really deploy' {
        foreach ($name in @('prod-skycraft-swc-auth-vm', 'devskycraftswcsa', 'NetworkWatcher_swedencentral')) {
            $script:RealKnown | Should -Contain $name
        }
    }
}

Describe 'Resource audit - regression guards for issue #116' {

    BeforeAll {
        $script:RealKnown = @(Get-KnownResourceName -RepoRoot $script:RealRepoRoot)
    }

    # The false positives the naive literal-name grep produces. None of these
    # three appears as a literal in any .bicep, .bicepparam or Remove-LabResource.ps1,
    # yet every one of them is deployed by a current lab.
    It 'recognises <_>, which no source spells literally' -ForEach @(
        'prod-skycraft-swc-kv'
        'prod-skycraft-swc-asp'
        'prod-skycraft-swc-app01'
    ) {
        Test-LabResourceKnown -Name $_ -KnownName $script:RealKnown | Should -BeTrue
    }

    It 'recognises names the sources do spell literally' {
        foreach ($name in @('prod-skycraft-swc-vnet', 'dev-skycraft-swc-lb-pip')) {
            Test-LabResourceKnown -Name $name -KnownName $script:RealKnown | Should -BeTrue
        }
    }

    It 'recognises the VM and disk names Lab 3.2 composes' {
        foreach ($name in @('prod-skycraft-swc-auth-vm', 'prod-skycraft-swc-world-vm-osdisk')) {
            Test-LabResourceKnown -Name $name -KnownName $script:RealKnown | Should -BeTrue
        }
    }

    # Storage account names carry no dashes, so they do not fit the dashed
    # grammar the rest of the estate follows. Lab 4.1 composes them as
    # '${env}skycraftswcsa' - the environment placeholder abuts the next segment
    # with no separator, which the expansion has to survive.
    It 'recognises the dashless storage account name <_>' -ForEach @(
        'devskycraftswcsa'
        'prodskycraftswcsa'
        'platformskycraftswcsa'
    ) {
        Test-LabResourceKnown -Name $_ -KnownName $script:RealKnown | Should -BeTrue
    }

    It 'recognises the container registry named by a bicepparam default' {
        Test-LabResourceKnown -Name 'devskycraftswcacr01' -KnownName $script:RealKnown | Should -BeTrue
    }

    # Found by the first live run against the subscription. Lab 5.3 re-declares
    # the Network Watcher and tags it, so it comes back tagged Project=SkyCraft -
    # but its name carries neither the project token nor the dashed prefix, being
    # composed as 'NetworkWatcher_${parLocation}' over the location domain the
    # template declares in @allowed. It was the audit's only false positive.
    It 'recognises the Network Watcher Lab 5.3 names after its location' {
        Test-LabResourceKnown -Name 'NetworkWatcher_swedencentral' -KnownName $script:RealKnown | Should -BeTrue
    }

    It 'recognises the resource group the live subscription still holds' {
        Test-LabResourceKnown -Name 'dev-skycraft-swc-rg' -KnownName $script:RealKnown | Should -BeTrue
    }

    # The resource that actually drifted. Its suffix - traffic-vm - is produced
    # by no template in the repository, which is what separates it from the above.
    It 'does not recognise prod-skycraft-swc-traffic-vm' {
        Test-LabResourceKnown -Name 'prod-skycraft-swc-traffic-vm' -KnownName $script:RealKnown | Should -BeFalse
    }

    # Drift that borrows a legitimate prefix must still be caught - the suffix is
    # the discriminator, not the prefix.
    It 'does not recognise a plausible-looking name no template emits' {
        Test-LabResourceKnown -Name 'prod-skycraft-swc-jumpbox-vm' -KnownName $script:RealKnown | Should -BeFalse
    }
}

Describe 'Resource audit - selection reports drift without deleting' {

    BeforeAll {
        $script:RealKnown = @(Get-KnownResourceName -RepoRoot $script:RealRepoRoot)
    }

    It 'returns only the resource no source accounts for' {
        $resources = @(
            Get-ResourceFixture -Name 'prod-skycraft-swc-auth-vm'
            Get-ResourceFixture -Name 'prod-skycraft-swc-kv' -ResourceType 'Microsoft.KeyVault/vaults'
            Get-ResourceFixture -Name 'prod-skycraft-swc-traffic-vm'
        )

        $drift = @(Select-UnreferencedResource -Resource $resources -KnownName $script:RealKnown)

        $drift.Count | Should -Be 1
        $drift[0].Name | Should -Be 'prod-skycraft-swc-traffic-vm'
    }

    It 'returns nothing when every resource is accounted for' {
        $resources = @(
            Get-ResourceFixture -Name 'prod-skycraft-swc-auth-vm'
            Get-ResourceFixture -Name 'dev-skycraft-swc-world-vm'
        )

        @(Select-UnreferencedResource -Resource $resources -KnownName $script:RealKnown).Count | Should -Be 0
    }

    # #116: "Report, do not delete - a false positive must not tear down live lab state."
    It 'contains no resource-deleting call' {
        $script:ScriptText | Should -Not -Match 'Remove-Az\w+'
    }
}

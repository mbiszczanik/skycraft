<#
.SYNOPSIS
    Pester 5 tests: the Lab 4.4 validator accepts the state every path leaves and fails a broken lab.

.DESCRIPTION
    Regression cover for issues #355 and #361. Test-Lab.ps1 once required a container named
    'dev-assets' that only the Bicep created, while step 4.4.3 used "scripts (or any container)";
    a learner who followed the guide failed "[FAIL] Container 'dev-assets' not found." and the
    script printed "Found Policy ''". Since #361 every path creates dev-assets (Step 4.4.3), the
    guide teaches the two sections it promised (key rotation, Storage Blob Data Contributor), and
    the validator checks the role assignment. These tests run the real Test-Lab.ps1 in a child
    pwsh against a generated stub of the Az commands it calls, and assert that:

      1. dev-assets passes with its policy (between Steps 4.4.3 and 4.4.4) and without it (after
         Step 4.4.4, and on the Bicep path), and every policy found is printed by name.
      2. A container that holds DevRevokePolicy, as an older guide left it, still passes.
      3. A lab with neither fails, and so does a container listing that fails.
      4. Policy reads blocked by the firewall are not counted while dev-assets exists.
      5. A missing Storage Blob Data Contributor assignment on the account fails, an inherited
         one does not count, and a lookup that fails is a counted [FAIL].
      6. The firewall must deny by default, have a rule for WorldSubnet in state Succeeded, and the
         account must not be left Failed (#371).
      7. Key rotation is reported and never counted, as the Bicep path cannot rotate.

    No subscription is needed, and none is used: tests/Support/LabScriptStub.psm1 (issue #112)
    imports the real modules first, the stub last, and aborts the child with exit 99 unless every
    stubbed command resolves to the stub.

.EXAMPLE
    Invoke-Pester -Path .\Test-Lab.Tests.ps1

.NOTES
    Project: SkyCraft
    Lab: 4.4 - Storage Security
    Issue: #355, #361
#>

#Requires -Version 7.0
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..' '..' '..' 'tests' 'Support' 'LabScriptStub.psm1') -Force

    $script:ScriptPath     = (Resolve-Path (Join-Path $PSScriptRoot '..' 'scripts' 'Test-Lab.ps1')).Path
    $script:StubModuleName = 'SkyCraftLab44ValidatorStub'
    # Exactly the script's '#Requires -Modules' line.
    $script:RequiredModules = @('Az.Accounts', 'Az.Resources', 'Az.Storage', 'Az.Network')

    $script:StubCommands = @(
        'Get-AzContext'
        'Get-AzStorageAccount'
        'Get-AzVirtualNetwork'
        'Get-AzRmStorageContainer'
        'Get-AzStorageContainerStoredAccessPolicy'
        'Get-AzRoleAssignment'
    )

    # WorldSubnet with its service endpoint is always in place. The rest varies:
    #   SKYCRAFT_STUB_CONTAINERS   'policy'  Lab 4.2's containers and dev-assets, which holds
    #                                        DevRevokePolicy; server-config holds another policy
    #                              'done'    Lab 4.2's containers and dev-assets, no policy (after
    #                                        Step 4.4.4, and the Bicep path)
    #                              'older'   Lab 4.2's containers, game-assets holds DevRevokePolicy
    #                              'missing' Lab 4.2's containers, no policy
    #                              'fail'    the container listing fails
    #   SKYCRAFT_STUB_POLICYFAIL   '1' makes every stored access policy read fail, as the storage
    #                              firewall does when the client IP is not allowed
    #   SKYCRAFT_STUB_ROLE         'account' Storage Blob Data Contributor on the account
    #                              'inherited' the role only on the resource group
    #                              'none'    no assignment
    #                              'fail'    the lookup fails
    #   SKYCRAFT_STUB_ACCOUNT      'ok'      provisioned, Deny, a WorldSubnet rule, keys rotated
    #                              'allow'   default action Allow
    #                              'othersubnet' the only rule is for AuthSubnet
    #                              'rulestate'   the WorldSubnet rule is in state NetworkSourceDeleted
    #                              'failed'  provisioning state Failed
    #                              'unrotated' the keys are as old as the account
    $script:StubBody = @'
function Get-AzContext {
    [CmdletBinding()]
    param()
    [pscustomobject]@{ Subscription = [pscustomobject]@{ Id = '00000000-0000-0000-0000-000000000000' } }
}

function Get-AzStorageAccount {
    [CmdletBinding()]
    param([string]$ResourceGroupName, [string]$Name, [Parameter(ValueFromRemainingArguments)]$Rest)
    $mode   = $env:SKYCRAFT_STUB_ACCOUNT
    $vnetId = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/$ResourceGroupName/providers/Microsoft.Network/virtualNetworks/prod-skycraft-swc-vnet"
    $subnet = if ($mode -eq 'othersubnet') { 'AuthSubnet' } else { 'worldsubnet' }   # the Portal may lower-case it
    $created = [datetime]'2026-10-01T08:00:00Z'
    $rotated = if ($mode -eq 'unrotated') { $created.AddMinutes(1) } else { [datetime]'2026-10-18T09:00:00Z' }
    [pscustomobject]@{
        StorageAccountName = $Name
        Id                 = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/$ResourceGroupName/providers/Microsoft.Storage/storageAccounts/$Name"
        ProvisioningState  = if ($mode -eq 'failed') { 'Failed' } else { 'Succeeded' }
        CreationTime       = $created
        KeyCreationTime    = [pscustomobject]@{ Key1 = $rotated; Key2 = $rotated }
        Context            = [pscustomobject]@{ StorageAccountName = $Name }
        NetworkRuleSet     = [pscustomobject]@{
            DefaultAction       = if ($mode -eq 'allow') { 'Allow' } else { 'Deny' }
            VirtualNetworkRules = @([pscustomobject]@{
                VirtualNetworkResourceId = "$vnetId/subnets/$subnet"
                State                    = if ($mode -eq 'rulestate') { 'NetworkSourceDeleted' } else { 'Succeeded' }
            })
            IpRules             = @([pscustomobject]@{ IPAddressOrRange = '203.0.113.10' })
        }
    }
}

function Get-AzVirtualNetwork {
    [CmdletBinding()]
    param([string]$ResourceGroupName, [string]$Name, [Parameter(ValueFromRemainingArguments)]$Rest)
    [pscustomobject]@{
        Name    = $Name
        Subnets = @([pscustomobject]@{ Name = 'WorldSubnet'; ServiceEndpoints = @([pscustomobject]@{ Service = 'Microsoft.Storage' }) })
    }
}

function Get-AzRmStorageContainer {
    [CmdletBinding()]
    param([string]$ResourceGroupName, [string]$StorageAccountName, [string]$Name, [Parameter(ValueFromRemainingArguments)]$Rest)
    if ($Name) { throw "stub: the lab lists the containers rather than reading one by name ($Name)" }
    if ($env:SKYCRAFT_STUB_CONTAINERS -eq 'fail') { Write-Error 'stub lookup failure: Get-AzRmStorageContainer'; return }
    $names = @('game-assets', 'player-backups', 'server-config', 'game-logs')
    if ($env:SKYCRAFT_STUB_CONTAINERS -in 'policy', 'done') { $names += 'dev-assets' }
    foreach ($n in $names) { [pscustomobject]@{ Name = $n } }
}

# Shaped like the real cmdlet's output: the identifier is in .Policy, the permissions in
# .Permissions; there is no .Id.
function Get-AzStorageContainerStoredAccessPolicy {
    [CmdletBinding()]
    param([string]$Container, $Context, [string]$Policy, [Parameter(ValueFromRemainingArguments)]$Rest)
    if ($env:SKYCRAFT_STUB_POLICYFAIL -eq '1') { Write-Error "stub lookup failure: This request is not authorized to perform this operation. ($Container)"; return }
    $holder = switch ($env:SKYCRAFT_STUB_CONTAINERS) { 'policy' { 'dev-assets' } 'older' { 'game-assets' } default { $null } }
    if ($holder -and $Container -eq $holder) {
        [pscustomobject]@{ Policy = 'DevRevokePolicy'; Permissions = 'rl'; StartTime = $null; ExpiryTime = [datetime]'2026-10-19' }
    }
    if ($env:SKYCRAFT_STUB_CONTAINERS -eq 'policy' -and $Container -eq 'server-config') {
        [pscustomobject]@{ Policy = 'OpsReadPolicy'; Permissions = 'r'; StartTime = $null; ExpiryTime = [datetime]'2026-11-17' }
    }
}

function Get-AzRoleAssignment {
    [CmdletBinding()]
    param([string]$Scope, [Parameter(ValueFromRemainingArguments)]$Rest)
    switch ($env:SKYCRAFT_STUB_ROLE) {
        'fail'      { Write-Error 'stub lookup failure: Get-AzRoleAssignment'; return }
        'none'      { return }
        'inherited' {
            [pscustomobject]@{ RoleDefinitionName = 'Storage Blob Data Contributor'; ObjectType = 'User'; DisplayName = 'Learner'
                               ObjectId = '11111111-1111-1111-1111-111111111111'; Scope = ($Scope -replace '/providers/Microsoft\.Storage/.*$', '') }
        }
        default {
            [pscustomobject]@{ RoleDefinitionName = 'Owner'; ObjectType = 'User'; DisplayName = 'Learner'
                               ObjectId = '11111111-1111-1111-1111-111111111111'; Scope = '/subscriptions/00000000-0000-0000-0000-000000000000' }
            [pscustomobject]@{ RoleDefinitionName = 'Storage Blob Data Contributor'; ObjectType = 'User'; DisplayName = 'Learner'
                               ObjectId = '11111111-1111-1111-1111-111111111111'; Scope = $Scope }
        }
    }
}
'@

    function Invoke-ValidatorScript {
        param(
            [pscustomobject]$Stub,
            [ValidateSet('policy', 'done', 'older', 'missing', 'fail')]
            [string]$Containers = 'done',
            [switch]$PolicyFail,
            [ValidateSet('account', 'inherited', 'none', 'fail')]
            [string]$Role = 'account',
            [ValidateSet('ok', 'allow', 'othersubnet', 'rulestate', 'failed', 'unrotated')]
            [string]$Account = 'ok'
        )
        $run = Invoke-LabScriptWithStub -Stub $Stub -ScriptPath $script:ScriptPath -Environment @{
            SKYCRAFT_STUB_CONTAINERS = $Containers
            SKYCRAFT_STUB_POLICYFAIL = if ($PolicyFail) { '1' } else { '0' }
            SKYCRAFT_STUB_ROLE       = $Role
            SKYCRAFT_STUB_ACCOUNT    = $Account
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

    $script:WithPolicy       = Invoke-ValidatorScript -Stub $script:Stub -Containers 'policy'
    $script:Done             = Invoke-ValidatorScript -Stub $script:Stub -Containers 'done'
    $script:Older            = Invoke-ValidatorScript -Stub $script:Stub -Containers 'older'
    $script:Missing          = Invoke-ValidatorScript -Stub $script:Stub -Containers 'missing'
    $script:ListFails        = Invoke-ValidatorScript -Stub $script:Stub -Containers 'fail'
    $script:MissingReadFails = Invoke-ValidatorScript -Stub $script:Stub -Containers 'missing' -PolicyFail
    $script:DoneReadFails    = Invoke-ValidatorScript -Stub $script:Stub -Containers 'done' -PolicyFail
    $script:NoRole           = Invoke-ValidatorScript -Stub $script:Stub -Role 'none'
    $script:InheritedRole    = Invoke-ValidatorScript -Stub $script:Stub -Role 'inherited'
    $script:RoleFails        = Invoke-ValidatorScript -Stub $script:Stub -Role 'fail'
    $script:Open             = Invoke-ValidatorScript -Stub $script:Stub -Account 'allow'
    $script:OtherSubnet      = Invoke-ValidatorScript -Stub $script:Stub -Account 'othersubnet'
    $script:RuleState        = Invoke-ValidatorScript -Stub $script:Stub -Account 'rulestate'
    $script:FailedAccount    = Invoke-ValidatorScript -Stub $script:Stub -Account 'failed'
    $script:Unrotated        = Invoke-ValidatorScript -Stub $script:Stub -Account 'unrotated'
    $script:AllRuns = @($script:WithPolicy, $script:Done, $script:Older, $script:Missing, $script:ListFails,
        $script:MissingReadFails, $script:DoneReadFails, $script:NoRole, $script:InheritedRole, $script:RoleFails,
        $script:Open, $script:OtherSubnet, $script:RuleState, $script:FailedAccount, $script:Unrotated)
}

AfterAll {
    if ($script:StubDir) { Remove-Item -LiteralPath $script:StubDir -Recurse -Force -ErrorAction SilentlyContinue }
}

Describe 'Lab 4.4 Test-Lab.ps1 - test harness' {

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

Describe 'Lab 4.4 Test-Lab.ps1 - the SAS exercise container dev-assets and its stored access policy (#355, #361)' {

    It 'passes dev-assets while it holds DevRevokePolicy (between Steps 4.4.3 and 4.4.4)' {
        $run = $script:WithPolicy
        $run.ExitCode | Should -Be 0 -Because "output was:`n$($run.Output)"
        $run.FailLines | Should -Be 0
        $run.Output | Should -Match "Container 'dev-assets' found\."
        $run.Output | Should -Match "\[INFO\] 'dev-assets' still holds 'DevRevokePolicy': Step 4\.4\.4 deletes it at its end\. Not counted\."
    }

    It 'prints every stored access policy it finds by name, not an empty one' {
        $run = $script:WithPolicy
        $run.Output | Should -Match "Checking container 'dev-assets' and stored access policy 'DevRevokePolicy'\.\.\."
        $run.Output | Should -Match "Found stored access policy 'DevRevokePolicy' \(permissions: rl\) on container 'dev-assets'\."
        $run.Output | Should -Match "Found stored access policy 'OpsReadPolicy' \(permissions: r\) on container 'server-config'\."
        $run.Output | Should -Not -Match "policy ''"
    }

    It 'passes dev-assets without a policy, as Step 4.4.4 and the Bicep path leave it' {
        $run = $script:Done
        $run.ExitCode | Should -Be 0 -Because "output was:`n$($run.Output)"
        $run.FailLines | Should -Be 0
        $run.Output | Should -Match "\[INFO\] No container holds 'DevRevokePolicy', as after Step 4\.4\.4\. Not counted\."
    }

    It 'still passes a container that holds DevRevokePolicy when dev-assets is missing (an older guide)' {
        $run = $script:Older
        $run.ExitCode | Should -Be 0 -Because "output was:`n$($run.Output)"
        $run.FailLines | Should -Be 0
        $run.Output | Should -Match "Container 'game-assets' holds stored access policy 'DevRevokePolicy'"
    }

    It 'fails a lab with no dev-assets and no container holding the policy, and names the step' {
        $run = $script:Missing
        $run.ExitCode | Should -Be 1 -Because "output was:`n$($run.Output)"
        $run.FailLines | Should -Be 1
        $run.Output | Should -Match "\[FAIL\] Container 'dev-assets' not found, and no container holds 'DevRevokePolicy'\. Step 4\.4\.3 creates 'dev-assets'\."
    }

    It 'counts a container listing that fails, says why, and still reaches the summary' {
        $run = $script:ListFails
        $run.ExitCode | Should -Be 1 -Because "output was:`n$($run.Output)"
        $run.Output | Should -Match "\[FAIL\] Could not list the containers of 'prodskycraftswcsa': stub lookup failure: Get-AzRmStorageContainer"
        $run.FailLines | Should -Be 1
        $run.Output | Should -Match 'Validation Complete\. Failures: 1'
    }

    It 'counts policy reads that fail when dev-assets is missing, and names the firewall step' {
        $run = $script:MissingReadFails
        $run.ExitCode | Should -Be 1 -Because "output was:`n$($run.Output)"
        $run.Output | Should -Match "\[FAIL\] Container 'dev-assets' not found, and the stored access policies of 4 container\(s\) could not be read \(is your client IP allowed, step 4\.4\.2\?\)"
        $run.FailLines | Should -Be 1
    }

    It 'does not count policy reads that fail while dev-assets exists, because the control plane found it' {
        $run = $script:DoneReadFails
        $run.ExitCode | Should -Be 0 -Because "output was:`n$($run.Output)"
        $run.Output | Should -Match "Container 'dev-assets' found\."
        $run.Output | Should -Match "\[INFO\] The stored access policies of 5 container\(s\) could not be read"
    }
}

Describe 'Lab 4.4 Test-Lab.ps1 - Storage Blob Data Contributor on the account (Step 4.4.7)' {

    It 'passes an assignment made on the account and names who holds it' {
        $run = $script:Done
        $run.Output | Should -Match "'Storage Blob Data Contributor' is assigned on the account to 'Learner' \(User\)\."
    }

    It 'fails when no assignment exists, and names the step' {
        $run = $script:NoRole
        $run.ExitCode | Should -Be 1 -Because "output was:`n$($run.Output)"
        $run.FailLines | Should -Be 1
        $run.Output | Should -Match "\[FAIL\] No 'Storage Blob Data Contributor' assignment on 'prodskycraftswcsa' itself\. Step 4\.4\.7 assigns it to your account\."
    }

    It 'does not count an assignment inherited from the resource group' {
        $run = $script:InheritedRole
        $run.ExitCode | Should -Be 1 -Because "output was:`n$($run.Output)"
        $run.FailLines | Should -Be 1
    }

    It 'counts a role assignment lookup that fails, says why, and still reaches the summary' {
        $run = $script:RoleFails
        $run.ExitCode | Should -Be 1 -Because "output was:`n$($run.Output)"
        $run.Output | Should -Match "\[FAIL\] Could not read the role assignments of 'prodskycraftswcsa': stub lookup failure: Get-AzRoleAssignment"
        $run.Output | Should -Match 'Validation Complete\. Failures: 1'
    }
}

Describe 'Lab 4.4 Test-Lab.ps1 - the account and its firewall (Step 4.4.2, #371)' {

    It 'passes a provisioned account that denies by default and lets WorldSubnet through, whatever the subnet id''s case' {
        $run = $script:Done
        $run.Output | Should -Match 'Storage account is provisioned \(Succeeded\)\.'
        $run.Output | Should -Match "Firewall is correctly set to 'Deny' by default\."
        $run.Output | Should -Match "Virtual network rule for 'prod-skycraft-swc-vnet/WorldSubnet' found\."
        $run.Output | Should -Match '\[INFO\] 1 IP address rule\(s\)\.'
    }

    It 'fails <name>' -ForEach @(
        @{ name = 'a firewall that allows by default'; run = 'Open'; pattern = "\[FAIL\] Firewall default action is 'Allow'\. Expected: Deny" }
        @{ name = 'a firewall without a rule for WorldSubnet'; run = 'OtherSubnet'; pattern = "\[FAIL\] No virtual network rule for 'prod-skycraft-swc-vnet/WorldSubnet' \(1 rule\(s\) in total\)" }
        @{ name = 'a WorldSubnet rule that is not Succeeded'; run = 'RuleState'; pattern = "\[FAIL\] The virtual network rule for 'WorldSubnet' is in state 'NetworkSourceDeleted'" }
        @{ name = 'an account Azure left Failed'; run = 'FailedAccount'; pattern = "\[FAIL\] Storage account provisioning state is 'Failed'\. Expected: Succeeded\." }
    ) {
        $result = Get-Variable -Scope Script -Name $run -ValueOnly
        $result.ExitCode | Should -Be 1 -Because "output was:`n$($result.Output)"
        $result.FailLines | Should -Be 1
        $result.Output | Should -Match $pattern
    }
}

Describe 'Lab 4.4 Test-Lab.ps1 - key rotation is reported, not counted (Steps 4.4.5 and 4.4.6)' {

    It 'reports rotated keys' {
        $script:Done.Output | Should -Match 'key1 last rotated'
        $script:Done.Output | Should -Match 'key2 last rotated'
    }

    It 'reports keys as old as the account without failing, as the Bicep path leaves them' {
        $run = $script:Unrotated
        $run.ExitCode | Should -Be 0 -Because "output was:`n$($run.Output)"
        $run.FailLines | Should -Be 0
        $run.Output | Should -Match '\[INFO\] key1 has not been rotated since the account was created'
        $run.Output | Should -Match '\[INFO\] key2 has not been rotated since the account was created'
    }
}

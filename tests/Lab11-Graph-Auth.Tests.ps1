<#
.SYNOPSIS
    Pester 5 test: the Lab 1.1 Microsoft Graph sign-in never falls back to a prompt it cannot win.

.DESCRIPTION
    Lifts Get-LabGraphAuthPlan out of the three Lab 1.1 scripts with the PowerShell parser and runs
    it against synthetic environments, the same way tests/Lab53-Cleanup-Logic.Tests.ps1 does for Lab
    5.3. Evaluating only the FunctionDefinitionAst nodes means no script body runs, so no Graph call
    is made and no Microsoft.Graph module is needed - while the code under test is the code the lab
    ships.

    Why this exists (issue #76): Lab 1.1 is the only lab that talks to Entra ID rather than ARM, and
    the only one that hung. Connect-MgGraph with -Scopes binds the delegated parameter set, so a run
    whose cached token needed a refresh the broker could not complete silently sat on a prompt
    nobody could answer; the lab-cycle mitigation was a step timeout, which turns a hang into a
    killed phase rather than into a run that works. The scripts now choose app-only (client
    credentials) when a service principal is configured, and the cases that matter - fully
    configured, half configured, not configured at all, and not configured in a session that cannot
    prompt - are pinned here.

    The three copies of the decision are asserted identical rather than factored into a shared
    module: docs/powershell-standards.md 7.3 requires every lab folder to stay runnable and
    readable on its own.

    Issue #242 adds two more. Connect-MgGraph can return without an error and without a context
    (a delegated sign-in for scopes the account never consented to), so Connect-LabGraph - lifted
    the same way, with the Graph commands replaced by plain functions - must throw on an empty
    context rather than return it. And the validator must ask only for scopes the setup and
    cleanup scripts ask for too, so the consent the lab already has covers it.

.EXAMPLE
    Invoke-Pester -Path .\tests\Lab11-Graph-Auth.Tests.ps1

.NOTES
    Project: SkyCraft
#>

#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    $script:LabRoot  = Join-Path $script:RepoRoot 'module-1-identities-governance/1.1-entra-users-groups/scripts'

    $script:LabScriptName = @('New-LabUser.ps1', 'Test-Lab.ps1', 'Remove-LabResource.ps1')

    function Get-TopLevelFunctionAst {
        param([string]$Path)

        $parseError = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$null, [ref]$parseError)
        if ($parseError) {
            throw "$(Split-Path -Leaf $Path) does not parse: $($parseError[0].Message)"
        }
        # Top level only ($false): a nested helper would not be callable on its own.
        $ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $false)
    }

    $script:FunctionByScript = @{}
    foreach ($name in $script:LabScriptName) {
        $script:FunctionByScript[$name] = Get-TopLevelFunctionAst -Path (Join-Path $script:LabRoot $name)
    }

    # The decision under test comes from New-LabUser.ps1; the parity Describe below is what makes
    # that a statement about all three scripts.
    $planAst = $script:FunctionByScript['New-LabUser.ps1'] |
        Where-Object { $_.Name -eq 'Get-LabGraphAuthPlan' }
    if (-not $planAst) { throw 'New-LabUser.ps1 does not define Get-LabGraphAuthPlan.' }
    . ([scriptblock]::Create($planAst.Extent.Text))

    $script:Scope    = @('User.ReadWrite.All', 'Group.ReadWrite.All')
    $script:TenantId = '11111111-1111-1111-1111-111111111111'
    $script:ClientId = '22222222-2222-2222-2222-222222222222'
    $script:Secret   = 'not-a-real-secret-value'
    $script:Thumb    = 'ABCDEF0123456789ABCDEF0123456789ABCDEF01'

    function Get-EnvFixture {
        param(
            [string]$TenantId,
            [string]$ClientId,
            [string]$ClientSecret,
            [string]$CertThumbprint
        )
        @{
            TenantId       = $TenantId
            ClientId       = $ClientId
            ClientSecret   = $ClientSecret
            CertThumbprint = $CertThumbprint
        }
    }

    $script:EmptyEnv = Get-EnvFixture
}

Describe 'Lab 1.1 Graph sign-in - the three scripts share one decision' {

    It "'<name>' defines Get-LabGraphAuthPlan and Connect-LabGraph" -ForEach @(
        @{ name = 'New-LabUser.ps1' }, @{ name = 'Test-Lab.ps1' }, @{ name = 'Remove-LabResource.ps1' }
    ) {
        $defined = @($script:FunctionByScript[$name].Name)
        $defined | Should -Contain 'Get-LabGraphAuthPlan'
        $defined | Should -Contain 'Connect-LabGraph'
    }

    It 'ships byte-identical copies of <function> in all three scripts' -ForEach @(
        @{ function = 'Get-LabGraphAuthPlan' }, @{ function = 'Connect-LabGraph' }
    ) {
        $text = foreach ($name in $script:LabScriptName) {
            ($script:FunctionByScript[$name] | Where-Object { $_.Name -eq $function }).Extent.Text -replace "`r`n", "`n"
        }
        ($text | Sort-Object -Unique).Count | Should -Be 1 -Because 'a lab folder is self-contained (7.3), so the copies must not drift'
    }

    It "'<name>' calls Connect-MgGraph only from inside Connect-LabGraph" -ForEach @(
        @{ name = 'New-LabUser.ps1' }, @{ name = 'Test-Lab.ps1' }, @{ name = 'Remove-LabResource.ps1' }
    ) {
        $path = Join-Path $script:LabRoot $name
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$null, [ref]$null)

        $calls = $ast.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.CommandAst] -and
            $node.GetCommandName() -eq 'Connect-MgGraph'
        }, $true)

        @($calls).Count | Should -Be 1 -Because 'a second call site would be a second sign-in policy'

        $connectAst = $script:FunctionByScript[$name] | Where-Object { $_.Name -eq 'Connect-LabGraph' }
        $calls[0].Extent.StartOffset | Should -BeGreaterThan $connectAst.Extent.StartOffset
        $calls[0].Extent.EndOffset   | Should -BeLessThan  $connectAst.Extent.EndOffset
    }

    It "'<name>' no longer installs the Microsoft.Graph meta-module behind the learner's back" -ForEach @(
        @{ name = 'New-LabUser.ps1' }, @{ name = 'Test-Lab.ps1' }, @{ name = 'Remove-LabResource.ps1' }
    ) {
        # #Requires already blocks the script when a submodule is missing, so the old
        # 'Install-Module Microsoft.Graph -Force' block could only ever fire when the submodules
        # were installed correctly - installing ~40 modules, for minutes, for nothing.
        $text = Get-Content -Raw -LiteralPath (Join-Path $script:LabRoot $name)
        $text | Should -Not -Match 'Install-Module'
    }

    It "'<name>' declares every Graph submodule it uses" -ForEach @(
        @{ name = 'New-LabUser.ps1';        required = @('Microsoft.Graph.Identity.DirectoryManagement', 'Microsoft.Graph.Identity.SignIns') }
        @{ name = 'Test-Lab.ps1';           required = @('Microsoft.Graph.Identity.DirectoryManagement') }
        @{ name = 'Remove-LabResource.ps1'; required = @('Microsoft.Graph.Identity.DirectoryManagement') }
    ) {
        $head = (Get-Content -LiteralPath (Join-Path $script:LabRoot $name) -TotalCount 60) -join "`n"
        foreach ($module in $required) {
            $head | Should -Match ([regex]::Escape($module))
        }
    }
}

Describe 'Lab 1.1 Graph sign-in - one consent covers all three scripts (#242)' {

    BeforeAll {
        # The string constants in the -Scope argument of the script's one Connect-LabGraph call.
        function Get-RequestedScope {
            param([string]$Name)

            $ast = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $script:LabRoot $Name), [ref]$null, [ref]$null)
            $calls = @($ast.FindAll({
                param($node)
                $node -is [System.Management.Automation.Language.CommandAst] -and
                $node.GetCommandName() -eq 'Connect-LabGraph'
            }, $true))
            if ($calls.Count -ne 1) { throw "$Name calls Connect-LabGraph $($calls.Count) times, expected once." }

            $elements = $calls[0].CommandElements
            for ($i = 0; $i -lt $elements.Count - 1; $i++) {
                if ($elements[$i] -is [System.Management.Automation.Language.CommandParameterAst] -and
                    $elements[$i].ParameterName -eq 'Scope') {
                    return @($elements[$i + 1].FindAll({
                        $args[0] -is [System.Management.Automation.Language.StringConstantExpressionAst]
                    }, $true).Value)
                }
            }
            throw "$Name calls Connect-LabGraph without -Scope."
        }

        $script:SetupScope    = Get-RequestedScope -Name 'New-LabUser.ps1'
        $script:CleanupScope  = Get-RequestedScope -Name 'Remove-LabResource.ps1'
        $script:ValidateScope = Get-RequestedScope -Name 'Test-Lab.ps1'
    }

    It 'Test-Lab.ps1 requests scopes' {
        $script:ValidateScope | Should -Not -BeNullOrEmpty
    }

    It 'Test-Lab.ps1 requests only scopes that New-LabUser.ps1 and Remove-LabResource.ps1 request too' {
        # A scope only the validator asks for is a consent the lab's own setup never gave: in a
        # tenant where it is missing, Connect-MgGraph returned no context and no prompt (#242).
        foreach ($scope in $script:ValidateScope) {
            $script:SetupScope   | Should -Contain $scope -Because "New-LabUser.ps1 must already have consented to $scope"
            $script:CleanupScope | Should -Contain $scope -Because "Remove-LabResource.ps1 must already have consented to $scope"
        }
    }
}

Describe 'Connect-LabGraph - a sign-in that leaves no Graph context is a failed sign-in (#242)' {

    BeforeAll {
        # From New-LabUser.ps1, like Get-LabGraphAuthPlan above; the parity test makes it all three.
        $connectAst = $script:FunctionByScript['New-LabUser.ps1'] |
            Where-Object { $_.Name -eq 'Connect-LabGraph' }
        . ([scriptblock]::Create($connectAst.Extent.Text))

        # Plain functions in place of the SDK and of the plan, scoped to this Describe. Get-MgContext
        # returns $script:ContextBefore until Connect-MgGraph has run, $script:ContextAfter after.
        function Get-LabGraphAuthPlan { $script:Plan }
        function Get-MgContext { if ($script:Connected) { $script:ContextAfter } else { $script:ContextBefore } }
        function Connect-MgGraph { $script:Connected = $true }
        function Disconnect-MgGraph { }

        $script:InteractivePlan = [pscustomobject]@{
            Mode             = 'Interactive'
            Reason           = 'stub interactive plan'
            TenantId         = $null
            ConnectParameter = @{ Scopes = $script:Scope; ErrorAction = 'Stop' }
        }
        $script:AppOnlyPlan = [pscustomobject]@{
            Mode             = 'ClientSecret'
            Reason           = 'stub app-only plan'
            TenantId         = $script:TenantId
            ConnectParameter = @{ TenantId = $script:TenantId; ErrorAction = 'Stop' }
        }
    }

    BeforeEach {
        $script:Plan          = $script:InteractivePlan
        $script:Connected     = $false
        $script:ContextBefore = $null
        $script:ContextAfter  = $null
    }

    It 'throws "sign-in did not complete" when Connect-MgGraph leaves no context' {
        { Connect-LabGraph -Scope $script:Scope } | Should -Throw '*sign-in did not complete*'
        $script:Connected | Should -BeTrue -Because 'the empty context must be the one the sign-in left'
    }

    It 'names the requested scopes in the error, as a hint at missing consent' {
        { Connect-LabGraph -Scope $script:Scope } | Should -Throw '*consent*User.ReadWrite.All, Group.ReadWrite.All*'
    }

    It 'throws when the context has <case>' -ForEach @(
        @{ case = 'no tenant';                   context = @{ TenantId = $null; Account = 'admin@contoso.example'; AppName = $null } }
        @{ case = 'neither account nor app name'; context = @{ TenantId = '11111111-1111-1111-1111-111111111111'; Account = $null; AppName = $null } }
    ) {
        $script:ContextAfter = [pscustomobject]$context
        { Connect-LabGraph -Scope $script:Scope } | Should -Throw '*sign-in did not complete*'
    }

    It 'returns the context a delegated sign-in leaves' {
        $script:ContextAfter = [pscustomobject]@{ TenantId = $script:TenantId; Account = 'admin@contoso.example'; AppName = $null }
        $context = Connect-LabGraph -Scope $script:Scope
        $context.Account | Should -Be 'admin@contoso.example'
    }

    It 'returns the context an app-only sign-in leaves, which has an app name and no account' {
        $script:Plan = $script:AppOnlyPlan
        $script:ContextAfter = [pscustomobject]@{ TenantId = $script:TenantId; Account = $null; AppName = 'SkyCraft-Lab-Automation' }
        $context = Connect-LabGraph -Scope $script:Scope
        $context.AppName | Should -Be 'SkyCraft-Lab-Automation'
    }

    It 'still reuses a signed-in context without calling Connect-MgGraph' {
        $script:ContextBefore = [pscustomobject]@{ TenantId = $script:TenantId; Account = 'admin@contoso.example'; AppName = $null }
        $context = Connect-LabGraph -Scope $script:Scope
        $context.Account     | Should -Be 'admin@contoso.example'
        $script:Connected    | Should -BeFalse
    }

    It 'does not reuse a cached context with <case>, and signs in instead' -ForEach @(
        @{ case = 'no account or app name'; context = @{ TenantId = '11111111-1111-1111-1111-111111111111'; Account = $null; AppName = $null } }
        @{ case = 'no tenant';              context = @{ TenantId = $null; Account = 'admin@contoso.example'; AppName = $null } }
    ) {
        # A partial cached context returned as-is printed "Connected to Tenant:  as" just as an
        # empty one after Connect-MgGraph did.
        $script:ContextBefore = [pscustomobject]$context
        $script:ContextAfter  = [pscustomobject]@{ TenantId = $script:TenantId; Account = 'admin@contoso.example'; AppName = $null }

        $result = Connect-LabGraph -Scope $script:Scope

        $script:Connected | Should -BeTrue -Because 'a partial context must go on to Connect-MgGraph'
        $result.TenantId  | Should -Be $script:TenantId
    }

    It 'still throws when a partial cached context is followed by a sign-in that leaves none' {
        $script:ContextBefore = [pscustomobject]@{ TenantId = $script:TenantId; Account = $null; AppName = $null }
        { Connect-LabGraph -Scope $script:Scope } | Should -Throw '*sign-in did not complete*'
        $script:Connected | Should -BeTrue
    }
}

Describe 'Get-LabGraphAuthPlan - nothing configured' {

    It 'signs in interactively when a human is there to answer' {
        $plan = Get-LabGraphAuthPlan -Scope $script:Scope -EnvironmentValue $script:EmptyEnv -Unattended $false

        $plan.Mode                          | Should -Be 'Interactive'
        $plan.ConnectParameter.Scopes       | Should -Be $script:Scope
        $plan.ConnectParameter.Keys         | Should -Not -Contain 'ClientSecretCredential'
        $plan.ConnectParameter.Keys         | Should -Not -Contain 'CertificateThumbprint'
    }

    It 'does not pin the interactive sign-in to the process token cache' {
        # ContextScope Process would make a learner re-authenticate for every script in the lab.
        $plan = Get-LabGraphAuthPlan -Scope $script:Scope -EnvironmentValue $script:EmptyEnv -Unattended $false
        $plan.ConnectParameter.Keys | Should -Not -Contain 'ContextScope'
    }

    It 'blocks instead of prompting when the session cannot prompt' {
        $plan = Get-LabGraphAuthPlan -Scope $script:Scope -EnvironmentValue $script:EmptyEnv -Unattended $true

        $plan.Mode             | Should -Be 'Blocked'
        $plan.ConnectParameter | Should -BeNullOrEmpty
        $plan.Reason           | Should -Match 'SKYCRAFT_GRAPH_CLIENT_ID'
    }

    # The two below drive the DEFAULT of -Unattended rather than passing it, so they pin what the
    # scripts actually do when nobody tells them anything.
    It 'reads SKYCRAFT_UNATTENDED, and nothing else, as the automated-caller signal' {
        $saved = $env:SKYCRAFT_UNATTENDED
        try {
            $env:SKYCRAFT_UNATTENDED = '1'
            (Get-LabGraphAuthPlan -Scope $script:Scope -EnvironmentValue $script:EmptyEnv).Mode |
                Should -Be 'Blocked'
        }
        finally { $env:SKYCRAFT_UNATTENDED = $saved }
    }

    It 'still offers a sign-in when only a stream is redirected' {
        # Pester runs this with stdin redirected. Sniffing that - [Console]::IsInputRedirected was
        # tried - refuses a prompt to a learner who is sitting right there, and Lab 1.1 is run by
        # hand. This asserts the heuristic stays gone.
        [Console]::IsInputRedirected | Should -BeTrue -Because 'otherwise this test proves nothing'

        $saved = $env:SKYCRAFT_UNATTENDED
        try {
            $env:SKYCRAFT_UNATTENDED = ''
            (Get-LabGraphAuthPlan -Scope $script:Scope -EnvironmentValue $script:EmptyEnv).Mode |
                Should -Be 'Interactive'
        }
        finally { $env:SKYCRAFT_UNATTENDED = $saved }
    }

    It 'carries an explicit -TenantId into the interactive sign-in' {
        $plan = Get-LabGraphAuthPlan -Scope $script:Scope -TenantId $script:TenantId `
            -EnvironmentValue $script:EmptyEnv -Unattended $false

        $plan.Mode                      | Should -Be 'Interactive'
        $plan.ConnectParameter.TenantId | Should -Be $script:TenantId
    }
}

Describe 'Get-LabGraphAuthPlan - a client secret' {

    BeforeAll {
        $script:SecretEnv = Get-EnvFixture -TenantId $script:TenantId -ClientId $script:ClientId -ClientSecret $script:Secret
    }

    It 'binds the app-only parameter set' {
        $plan = Get-LabGraphAuthPlan -Scope $script:Scope -EnvironmentValue $script:SecretEnv -Unattended $true

        $plan.Mode                        | Should -Be 'ClientSecret'
        $plan.ClientId                    | Should -Be $script:ClientId
        $plan.ConnectParameter.TenantId   | Should -Be $script:TenantId
        $plan.ConnectParameter.NoWelcome  | Should -BeTrue
        $plan.ConnectParameter.ContextScope | Should -Be 'Process'
    }

    It 'never passes -Scopes app-only (delegated scopes are not a valid app-only request)' {
        $plan = Get-LabGraphAuthPlan -Scope $script:Scope -EnvironmentValue $script:SecretEnv -Unattended $true
        $plan.ConnectParameter.Keys | Should -Not -Contain 'Scopes'
    }

    It 'prefers the service principal even when a human could have answered' {
        $plan = Get-LabGraphAuthPlan -Scope $script:Scope -EnvironmentValue $script:SecretEnv -Unattended $false
        $plan.Mode | Should -Be 'ClientSecret'
    }

    It 'hands the secret over as a PSCredential keyed on the client id' {
        $plan = Get-LabGraphAuthPlan -Scope $script:Scope -EnvironmentValue $script:SecretEnv -Unattended $true

        $credential = $plan.ConnectParameter.ClientSecretCredential
        $credential | Should -BeOfType [System.Management.Automation.PSCredential]
        $credential.UserName | Should -Be $script:ClientId
        $credential.GetNetworkCredential().Password | Should -Be $script:Secret
    }

    It 'keeps the plaintext secret out of the plan itself' {
        $plan = Get-LabGraphAuthPlan -Scope $script:Scope -EnvironmentValue $script:SecretEnv -Unattended $true

        ($plan | Format-List | Out-String)                | Should -Not -Match ([regex]::Escape($script:Secret))
        ($plan.ConnectParameter | Out-String)             | Should -Not -Match ([regex]::Escape($script:Secret))
        $plan.Reason                                      | Should -Not -Match ([regex]::Escape($script:Secret))
    }

    It 'lets an explicit -TenantId override the environment' {
        $other = '33333333-3333-3333-3333-333333333333'
        $plan = Get-LabGraphAuthPlan -Scope $script:Scope -TenantId $other `
            -EnvironmentValue $script:SecretEnv -Unattended $true

        $plan.ConnectParameter.TenantId | Should -Be $other
    }
}

Describe 'Get-LabGraphAuthPlan - a certificate' {

    It 'binds the certificate parameter set' {
        $certEnv = Get-EnvFixture -TenantId $script:TenantId -ClientId $script:ClientId -CertThumbprint $script:Thumb
        $plan = Get-LabGraphAuthPlan -Scope $script:Scope -EnvironmentValue $certEnv -Unattended $true

        $plan.Mode                                    | Should -Be 'Certificate'
        $plan.ConnectParameter.ClientId               | Should -Be $script:ClientId
        $plan.ConnectParameter.CertificateThumbprint  | Should -Be $script:Thumb
        $plan.ConnectParameter.Keys                   | Should -Not -Contain 'Scopes'
        $plan.ConnectParameter.Keys                   | Should -Not -Contain 'ClientSecretCredential'
    }

    It 'prefers the certificate when both credentials are set' {
        $certEnv = Get-EnvFixture -TenantId $script:TenantId -ClientId $script:ClientId `
            -ClientSecret $script:Secret -CertThumbprint $script:Thumb
        $plan = Get-LabGraphAuthPlan -Scope $script:Scope -EnvironmentValue $certEnv -Unattended $true

        $plan.Mode | Should -Be 'Certificate'
    }
}

Describe 'Get-LabGraphAuthPlan - configured by halves' {

    It 'blocks and names what is missing: <case>' -ForEach @(
        @{ case = 'no tenant';      envValue = @{ ClientId = 'cid'; ClientSecret = 'sec' };                      missing = 'SKYCRAFT_GRAPH_TENANT_ID' }
        @{ case = 'no client id';   envValue = @{ TenantId = 'tid'; ClientSecret = 'sec' };                      missing = 'SKYCRAFT_GRAPH_CLIENT_ID' }
        @{ case = 'no credential';  envValue = @{ TenantId = 'tid'; ClientId = 'cid' };                          missing = 'SKYCRAFT_GRAPH_CLIENT_SECRET' }
        @{ case = 'secret only';    envValue = @{ ClientSecret = 'sec' };                                        missing = 'SKYCRAFT_GRAPH_CLIENT_ID' }
    ) {
        $fixture = Get-EnvFixture -TenantId $envValue['TenantId'] -ClientId $envValue['ClientId'] `
            -ClientSecret $envValue['ClientSecret'] -CertThumbprint $envValue['CertThumbprint']

        # Attended on purpose: falling back to a prompt here is exactly the hang this removes,
        # because a half-configured principal is a mistake to report, not a mode to degrade into.
        $plan = Get-LabGraphAuthPlan -Scope $script:Scope -EnvironmentValue $fixture -Unattended $false

        $plan.Mode             | Should -Be 'Blocked'
        $plan.ConnectParameter | Should -BeNullOrEmpty
        $plan.Reason           | Should -Match $missing
    }

    It 'treats an exported-but-empty variable as absent' {
        $fixture = Get-EnvFixture -TenantId '   ' -ClientId '' -ClientSecret "`t"
        $plan = Get-LabGraphAuthPlan -Scope $script:Scope -EnvironmentValue $fixture -Unattended $false

        $plan.Mode | Should -Be 'Interactive'
    }

    It 'trims a value pasted with trailing whitespace' {
        $fixture = Get-EnvFixture -TenantId " $($script:TenantId) " -ClientId " $($script:ClientId) " -ClientSecret " $($script:Secret) "
        $plan = Get-LabGraphAuthPlan -Scope $script:Scope -EnvironmentValue $fixture -Unattended $true

        $plan.Mode                      | Should -Be 'ClientSecret'
        $plan.ConnectParameter.TenantId | Should -Be $script:TenantId
        $plan.ConnectParameter.ClientSecretCredential.UserName | Should -Be $script:ClientId
    }
}

# Skipped rather than failed where Microsoft.Graph.Authentication is not installed - the CI runner
# installs Pester and nothing else. Everything above is a statement about the repository and runs
# everywhere; this one is a statement about the SDK, and needs the SDK present to make it.
Describe 'Get-LabGraphAuthPlan - the parameters bind to a real Connect-MgGraph parameter set' -Skip:(-not (Get-Module -ListAvailable -Name Microsoft.Graph.Authentication)) {

    BeforeAll {
        Import-Module Microsoft.Graph.Authentication -ErrorAction Stop
        $script:ParameterSet = (Get-Command Connect-MgGraph).ParameterSets

        function Get-MatchingParameterSetName {
            param([hashtable]$ConnectParameter)

            # ErrorAction is common to every set and says nothing about which one was chosen.
            $named = @($ConnectParameter.Keys | Where-Object { $_ -ne 'ErrorAction' })
            @($script:ParameterSet | Where-Object {
                $available = $_.Parameters.Name
                -not @($named | Where-Object { $_ -notin $available })
            }).Name
        }
    }

    It 'binds <mode> to exactly <set>' -ForEach @(
        @{ mode = 'Interactive';  set = 'UserParameterSet';                fixture = @{} }
        @{ mode = 'ClientSecret'; set = 'AppSecretCredentialParameterSet'; fixture = @{ TenantId = 't'; ClientId = 'c'; ClientSecret = 's' } }
        @{ mode = 'Certificate';  set = 'AppCertificateParameterSet';      fixture = @{ TenantId = 't'; ClientId = 'c'; CertThumbprint = 'ab' } }
    ) {
        $plan = Get-LabGraphAuthPlan -Scope $script:Scope -EnvironmentValue $fixture -Unattended $false

        $plan.Mode | Should -Be $mode
        # Exactly one: a set of parameters that fits two of them would leave the SDK to guess.
        @(Get-MatchingParameterSetName -ConnectParameter $plan.ConnectParameter) | Should -Be @($set)
    }
}

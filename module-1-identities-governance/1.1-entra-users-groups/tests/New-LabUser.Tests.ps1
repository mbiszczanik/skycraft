<#
.SYNOPSIS
    Pester 5 tests for New-LabUser.ps1 password handling and Microsoft Graph sign-in.

.DESCRIPTION
    Verifies four things:
      1. Regression: the historical hard-coded password is no longer in the file.
      2. Parameter shape: the script exposes -InitialPassword as [SecureString].
      3. Password generator: New-LabRandomPassword yields a 20-character string
         containing at least one upper, lower, digit, and symbol.
      4. Sign-in (issue #242): a Connect-MgGraph that returns without an error but leaves no
         Graph context ends the run with [ERROR] and exit 1 before anything is looked up, instead
         of printing "Connected to Tenant:  as" and carrying on. The real script runs in a child
         pwsh with -DemoMode against a generated stub of every Graph command it calls, through
         tests/Support/LabScriptStub.psm1 (issue #112), which refuses to run (exit 99) unless
         every stubbed command resolves to the stub. No tenant is needed, and none is used.

.EXAMPLE
    Invoke-Pester -Path .\New-LabUser.Tests.ps1

.NOTES
    Project: SkyCraft
    Lab: 1.1 - Entra Users & Groups
#>

#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

# PSAvoidUsingInvokeExpression: intentional — injects the generator function
# extracted via AST so it can be tested in isolation without sourcing the full script.
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingInvokeExpression', '')]
param()

BeforeAll {
    $script:ScriptPath = Join-Path $PSScriptRoot '..\scripts\New-LabUser.ps1' | Resolve-Path
    $script:ScriptText = Get-Content -Raw -LiteralPath $script:ScriptPath

    $errs   = $null
    $tokens = $null
    $script:Ast = [System.Management.Automation.Language.Parser]::ParseFile(
        $script:ScriptPath, [ref]$tokens, [ref]$errs
    )
    if ($errs.Count -gt 0) {
        throw "Parse errors in New-LabUser.ps1: $($errs.Message -join '; ')"
    }
}

Describe 'New-LabUser.ps1 — hard-coded password regression' {
    It 'does not contain the legacy shared password literal' {
        $script:ScriptText | Should -Not -Match 'LoveAzeroth!2004'
    }

    It 'does not contain any `Password = "..."` literal assignment' {
        $script:ScriptText | Should -Not -Match 'Password\s*=\s*"[^"$]+"'
    }
}

Describe 'New-LabUser.ps1 — parameter contract' {
    BeforeAll {
        $paramAst = $script:Ast.Find({
            param($node)
            $node -is [System.Management.Automation.Language.ParameterAst] -and
            $node.Name.VariablePath.UserPath -eq 'InitialPassword'
        }, $true)
        $script:InitialPasswordParam = $paramAst
    }

    It 'exposes an -InitialPassword parameter' {
        $script:InitialPasswordParam | Should -Not -BeNullOrEmpty
    }

    It 'types -InitialPassword as [SecureString]' {
        $script:InitialPasswordParam.StaticType.FullName | Should -Be 'System.Security.SecureString'
    }
}

Describe 'New-LabUser.ps1 — random password generator' {
    BeforeAll {
        $funcAst = $script:Ast.Find({
            param($node)
            $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
            $node.Name -eq 'New-LabRandomPassword'
        }, $true)
        if (-not $funcAst) { throw 'New-LabRandomPassword not found.' }
        Invoke-Expression $funcAst.Extent.Text
    }

    It 'produces a 20-character password' {
        $password = New-LabRandomPassword
        $password.Length | Should -Be 20
    }

    It 'produces passwords with all four character classes' {
        1..20 | ForEach-Object {
            $password = New-LabRandomPassword
            $password | Should -Match '[A-Z]'
            $password | Should -Match '[a-z]'
            $password | Should -Match '[0-9]'
            $password | Should -Match '[!@#\$%\^&\*\(\)\-_=\+\[\]\{\}]'
        }
    }

    It 'produces distinct passwords across 10 invocations' {
        $results = 1..10 | ForEach-Object { New-LabRandomPassword }
        ($results | Sort-Object -Unique).Count | Should -Be 10
    }
}

Describe 'New-LabUser.ps1 — a sign-in that leaves no Graph context is a failed sign-in (#242)' {
    BeforeAll {
        Import-Module (Join-Path $PSScriptRoot '..' '..' '..' 'tests' 'Support' 'LabScriptStub.psm1') -Force

        # Exactly the script's '#Requires -Modules' line: these are imported for real before the stub.
        $requiredModules = @(
            'Microsoft.Graph.Authentication'
            'Microsoft.Graph.Users'
            'Microsoft.Graph.Groups'
            'Microsoft.Graph.Identity.DirectoryManagement'
            'Microsoft.Graph.Identity.SignIns'
        )

        # Every Graph command the script calls, the writes included: -DemoMode keeps the run from
        # reaching them, and the stub makes sure a regression that does reach them touches nothing.
        $stubCommands = @(
            'Get-MgContext'
            'Connect-MgGraph'
            'Disconnect-MgGraph'
            'Get-MgDomain'
            'Get-MgUser'
            'Get-MgGroup'
            'Get-MgGroupMember'
            'New-MgUser'
            'New-MgGroup'
            'New-MgGroupMember'
            'New-MgInvitation'
        )

        # SKYCRAFT_STUB_NOCONTEXT '1' leaves no Graph context, before or after Connect-MgGraph,
        # which returns without an error either way - the shape issue #242 describes.
        $stubBody = @'
$script:LogPath = $env:SKYCRAFT_STUB_LOG

function Write-StubCall {
    param([string]$Name)
    if ($script:LogPath) { Add-Content -LiteralPath $script:LogPath -Value $Name }
}

function Get-MgContext {
    [CmdletBinding()]
    param()
    if ($env:SKYCRAFT_STUB_NOCONTEXT -eq '1') { return }
    [pscustomobject]@{
        TenantId = '00000000-0000-0000-0000-000000000000'
        Account  = 'stub-admin@contoso.example'
        AppName  = $null
    }
}

function Connect-MgGraph {
    [CmdletBinding()]
    param([string[]]$Scopes, [Parameter(ValueFromRemainingArguments)]$Rest)
    Write-StubCall -Name 'Connect-MgGraph'
}

function Disconnect-MgGraph { [CmdletBinding()] param() }

function Get-MgDomain {
    [CmdletBinding()]
    param([Parameter(ValueFromRemainingArguments)]$Rest)
    Write-StubCall -Name 'Get-MgDomain'
    [pscustomobject]@{ Id = 'contoso.example'; IsDefault = $true; IsInitial = $true }
}

function Get-MgUser         { [CmdletBinding()] param([Parameter(ValueFromRemainingArguments)]$Rest) Write-StubCall -Name 'Get-MgUser' }
function Get-MgGroup        { [CmdletBinding()] param([Parameter(ValueFromRemainingArguments)]$Rest) Write-StubCall -Name 'Get-MgGroup' }
function Get-MgGroupMember  { [CmdletBinding()] param([Parameter(ValueFromRemainingArguments)]$Rest) Write-StubCall -Name 'Get-MgGroupMember' }
function New-MgUser         { [CmdletBinding()] param([Parameter(ValueFromRemainingArguments)]$Rest) Write-StubCall -Name 'New-MgUser' }
function New-MgGroup        { [CmdletBinding()] param([Parameter(ValueFromRemainingArguments)]$Rest) Write-StubCall -Name 'New-MgGroup' }
function New-MgGroupMember  { [CmdletBinding()] param([Parameter(ValueFromRemainingArguments)]$Rest) Write-StubCall -Name 'New-MgGroupMember' }
function New-MgInvitation   { [CmdletBinding()] param([Parameter(ValueFromRemainingArguments)]$Rest) Write-StubCall -Name 'New-MgInvitation' }
'@

        function Invoke-SetupScript {
            param([pscustomobject]$Stub, [switch]$NoContext)

            $logPath = Join-Path $Stub.Directory 'calls.log'
            Remove-Item -LiteralPath $logPath -Force -ErrorAction SilentlyContinue

            $run = Invoke-LabScriptWithStub -Stub $Stub -ScriptPath $script:ScriptPath -ArgumentList '-DemoMode' -Environment @{
                SKYCRAFT_STUB_NOCONTEXT        = if ($NoContext) { '1' } else { '0' }
                SKYCRAFT_STUB_LOG              = $logPath
                # Interactive plan, so the script reuses the stub's context or calls the stub's
                # Connect-MgGraph instead of signing in.
                SKYCRAFT_GRAPH_TENANT_ID       = ''
                SKYCRAFT_GRAPH_CLIENT_ID       = ''
                SKYCRAFT_GRAPH_CLIENT_SECRET   = ''
                SKYCRAFT_GRAPH_CERT_THUMBPRINT = ''
                SKYCRAFT_UNATTENDED            = ''
            }

            $calls = if (Test-Path -LiteralPath $logPath) { @(Get-Content -LiteralPath $logPath) } else { @() }
            return [pscustomobject]@{
                ExitCode = $run.ExitCode
                Refused  = $run.Refused
                Output   = $run.Output
                Calls    = $calls
            }
        }

        $script:SetupStub = Initialize-LabScriptStub -Name 'SkyCraftGraphSetupStub' -Command $stubCommands `
            -Body $stubBody -RequiredModule $requiredModules

        # The signed-in run is the control: it shows the harness gets the script past its sign-in,
        # so the no-context run's failure is the empty context and nothing else.
        $script:SignedIn  = Invoke-SetupScript -Stub $script:SetupStub
        $script:NoContext = Invoke-SetupScript -Stub $script:SetupStub -NoContext
    }

    AfterAll {
        if ($script:SetupStub) { Remove-Item -LiteralPath $script:SetupStub.Directory -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'shadows the real Microsoft Graph commands instead of touching a tenant' {
        foreach ($run in @($script:SignedIn, $script:NoContext)) {
            $run.Refused | Should -BeFalse -Because "the harness must never fall through to the real Graph commands (exit $($run.ExitCode)): $($run.Output)"
        }
    }

    It 'gets past the sign-in when a Graph context is there' {
        $run = $script:SignedIn
        $run.ExitCode | Should -Be 0 -Because "output was:`n$($run.Output)"
        $run.Output | Should -Match 'Connected to Tenant: 00000000-0000-0000-0000-000000000000 as stub-admin@contoso\.example'
        $run.Calls | Should -Contain 'Get-MgDomain'
    }

    It 'exits 1 with an [ERROR] when the sign-in leaves no Graph context, and looks nothing up' {
        $run = $script:NoContext
        $run.ExitCode | Should -Be 1 -Because "a sign-in that did not complete must not look like a connection; output was:`n$($run.Output)"
        $run.Output | Should -Match '\[ERROR\] Failed to connect to Microsoft Graph: [^\r\n]*sign-in did not complete'
        $run.Output | Should -Not -Match 'Connected to Tenant'
        $run.Calls | Should -Contain 'Connect-MgGraph' -Because 'the empty context must be the one the sign-in left'
        $run.Calls | Should -Not -Contain 'Get-MgDomain'
    }
}

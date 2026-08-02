<#
.SYNOPSIS
    Pester 5 test: deploy scripts handle their .bicepparam files the way the standards require.

.DESCRIPTION
    Two rules, both about a deploy script's relationship with its parameter file. Neither is an
    automation-contract property: each breaks the lab identically for a student at a prompt and
    for an orchestrator, so they do not belong beside the rules about exit codes and prompting.

    RULE A - hydrate before deploying. Az PowerShell resolves a .bicepparam handed to
    -TemplateParameterFile by shelling out to a bare `bicep` on PATH. The only Bicep install
    this project documents is `az bicep install`, which puts the binary inside the Azure CLI's
    private directory and not on PATH, so on a machine provisioned from this repository's own
    prerequisites the cmdlet fails while binding its dynamic parameters - before it reaches
    Azure at all. Scripts must compile the file with `az bicep build-params`, which uses the
    CLI's own binary, and pass -TemplateParameterObject.

    RULE B - overlay only what the script computes. docs/bicep-standards.md:86. Re-asserting a
    static value makes the parameter file inert for that key: the file supplies a value, the
    script overwrites it with a constant, and the deployment silently uses the constant.

    Lab 3.3 did exactly that for two keys, and because its parameter files DO vary the other
    resource names, a -Environment prod run produced prod-named container resources inside the
    dev resource group. Nothing failed; the wrong thing deployed successfully.

    This rule is static by design. Compiling a .bicepparam needs `az bicep`, which
    .github/workflows/lint.yml installs only in the Bicep job - the Pester job has Pester and
    PSScriptAnalyzer and nothing else. A test that shelled out to `az` would pass locally and
    fail in CI. The parameter files' own contents are already validated there by the
    build-params loop; what needs guarding here is the script's behaviour.

    SCOPE, so nobody reads either rule as broader than it is. Rule A covers all 16 deploy
    scripts. Rule B is a regression guard over one script and two named keys, not a general
    overlay policy: which keys a script legitimately computes is not decidable from the AST, and
    its predicate hardcodes the variable name `params`, so a lab hydrating into
    `$deploymentParams` - as lab 4.1 does - is outside it entirely. Widening Rule B means adding
    cases and generalising that name, deliberately.

    The file is still named Overlay-Policy for Rule B's sake; Rule A arrived later and the two
    share a subject rather than a name.

.EXAMPLE
    Invoke-Pester -Path .\tests\Overlay-Policy.Tests.ps1

.NOTES
    Project: SkyCraft
#>

#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'Key', Justification = 'False positive: captured by GetNewClosure into the overlay predicate.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', 'OverlayCases', Justification = 'False positive: consumed by -ForEach on the Rule B It block, which PSSA cannot correlate across Pester scriptblock scopes.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', 'DeployCases', Justification = 'False positive: consumed by -ForEach on the Rule A It block, which PSSA cannot correlate across Pester scriptblock scopes.')]
param()

BeforeDiscovery {
    Import-Module (Join-Path $PSScriptRoot 'LabScripts.psm1') -Force

    $DeployCases = @(Get-ScriptCase -FileName 'Deploy-Bicep.ps1')

    $Lab33Deploy = Join-Path (Get-LabScriptRoot) 'module-3-compute/3.3-containers/scripts/Deploy-Bicep.ps1'

    # One case per key the script must leave to the parameter file. Both values live in
    # prod.bicepparam and platform.bicepparam, and in main.bicep's defaults for dev.
    $OverlayCases = @(
        @{ lab = '3.3-containers'; path = $Lab33Deploy; key = 'parResourceGroupName'; default = 'main.bicep:22' }
        @{ lab = '3.3-containers'; path = $Lab33Deploy; key = 'parAcrName';           default = 'main.bicep:34' }
    )
}

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot 'ScriptAst.psm1') -Force

    function Get-UnhydratedParameterFile {
        # Rule A: bindings of -TemplateParameterFile on a deployment cmdlet.
        #
        # Two shapes, because the corpus contains both: the named parameter written directly on
        # the call, and a key in a hashtable that is later splatted into it - lab 3.1 uses the
        # second. Tying a splatted hashtable back to its call site is more machinery than this
        # earns, so any hashtable key of that name counts. In these scripts such a key exists
        # only to be splatted into a deployment, and the false-positive cost is a script being
        # told to hydrate, which it should do anyway.
        param($Ast)

        $onCall = {
            param($node)
            $node.GetCommandName() -match '^New-Az\w*Deployment$' -and
            @($node.CommandElements | Where-Object {
                $_ -is [System.Management.Automation.Language.CommandParameterAst] -and
                $_.ParameterName -eq 'TemplateParameterFile'
            }).Count -gt 0
        }
        $inSplat = {
            param($node)
            @($node.KeyValuePairs | Where-Object { $_.Item1.Extent.Text -eq 'TemplateParameterFile' }).Count -gt 0
        }
        @(
            Find-AstNode -Ast $Ast -Type ([System.Management.Automation.Language.CommandAst])   -Where $onCall
            Find-AstNode -Ast $Ast -Type ([System.Management.Automation.Language.HashtableAst]) -Where $inSplat
        )
    }

    function Get-ParamsOverlay {
        # Assignments onto the hydrated parameter hashtable for one key.
        #
        # Both notations are matched - $params.parAcrName = ... and $params['parAcrName'] = ...
        # even though the script only uses the first. Matching one would let a future edit
        # switch notation and escape the rule without anything failing, which is the silent
        # kind of regression this suite exists to catch.
        param($Ast, [string]$Key)

        $isOverlay = {
            param($node)
            $left = $node.Left
            if ($left -is [System.Management.Automation.Language.MemberExpressionAst]) {
                return $left.Expression -is [System.Management.Automation.Language.VariableExpressionAst] -and
                       $left.Expression.VariablePath.UserPath -eq 'params' -and
                       $left.Member.Value -eq $Key
            }
            if ($left -is [System.Management.Automation.Language.IndexExpressionAst]) {
                return $left.Target -is [System.Management.Automation.Language.VariableExpressionAst] -and
                       $left.Target.VariablePath.UserPath -eq 'params' -and
                       $left.Index.Value -eq $Key
            }
            $false
        }.GetNewClosure()

        Find-AstNode -Ast $Ast -Type ([System.Management.Automation.Language.AssignmentStatementAst]) -Where $isOverlay
    }
}

Describe 'Deploy scripts compile their parameter file rather than handing it to Az' {
    It "'<file>' does not pass a .bicepparam to -TemplateParameterFile" -ForEach $DeployCases {
        $found = @(Get-UnhydratedParameterFile -Ast (Get-ScriptAst -Path $path))
        $lines = ($found | ForEach-Object { $_.Extent.StartLineNumber }) -join ', '
        $found.Count | Should -Be 0 -Because "Az resolves a .bicepparam by shelling out to a bare 'bicep' on PATH, which 'az bicep install' does not provide, so '$file' fails while binding its dynamic parameters on a machine provisioned as this repository documents. Compile with 'az bicep build-params' and pass -TemplateParameterObject instead; line(s) $lines."
    }
}

Describe 'Lab 3.3 leaves its parameter file authoritative for two keys' {
    It "lab <lab> leaves `$params.<key> to the parameter file" -ForEach $OverlayCases {
        $found = @(Get-ParamsOverlay -Ast (Get-ScriptAst -Path $path) -Key $key)
        $lines = ($found | ForEach-Object { $_.Extent.StartLineNumber }) -join ', '
        $found.Count | Should -Be 0 -Because "the parameter file and $default already supply $key; overwriting it with a script constant makes the file inert for that key and deploys the wrong resource under -Environment prod or platform. Lab $lab assigns it at line(s) $lines."
    }
}

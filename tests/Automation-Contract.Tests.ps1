<#
.SYNOPSIS
    Pester 5 test: every lab deployment script and validator honours the automation contract.

.DESCRIPTION
    An orchestrator can only trust a script that reports failure through its exit code and never
    waits for a human. These rules are enforced statically against the PowerShell AST so a
    violation is caught in CI rather than ninety minutes into a live Azure run.

    Rule 1  Deploy-Bicep.ps1 contains no Read-Host.
    Rule 2  No lab script calls Connect-AzAccount.
    Rule 3  Every statement block that reports a failure also exits non-zero.
    Rule 4  Test-Lab.ps1 ends in an unconditional exit.

    Which files count as lab scripts is defined once in tests/LabScripts.psm1 and shared with
    the script-standards and CBH-coverage suites, so all three lint the same set.

.EXAMPLE
    Invoke-Pester -Path .\tests\Automation-Contract.Tests.ps1

.NOTES
    Project: SkyCraft
#>

#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

# ValidatorCases really is unused until Rule 4 lands. Its suppression is targeted and says so,
# so a dead variable added later still surfaces instead of hiding behind a file-wide waiver.
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'Type', Justification = 'False positive: read inside the GetNewClosure predicate handed to FindAll.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'Where', Justification = 'False positive: read inside the GetNewClosure predicate handed to FindAll.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'Name', Justification = 'False positive: captured by GetNewClosure into the command-name predicate.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', 'DeployCases', Justification = 'False positive: consumed by -ForEach on the Rule 1 and Rule 3 It blocks, which PSSA cannot correlate across Pester scriptblock scopes.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', 'ValidatorCases', Justification = 'Genuinely unused here. Scaffold for Rule 4 (Test-Lab.ps1 ends in an unconditional exit), landed early so the discovery block is written once.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', 'AllLabCases', Justification = 'False positive: consumed by -ForEach on the Rule 2 It block, which PSSA cannot correlate across Pester scriptblock scopes.')]
param()

BeforeDiscovery {
    Import-Module (Join-Path $PSScriptRoot 'LabScripts.psm1') -Force

    $DeployCases    = @(Get-ScriptCase -FileName 'Deploy-Bicep.ps1')
    $ValidatorCases = @(Get-ScriptCase -FileName 'Test-Lab.ps1')
    $AllLabCases    = @(Get-ScriptCase)
}

BeforeAll {
    function Get-ScriptAst {
        param([string]$Path)
        $tokens = $null; $errors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$tokens, [ref]$errors)
        if ($errors.Count -gt 0) { throw "Parse error in '$Path': $($errors[0].Message)" }
        $ast
    }

    # One walk, shared by every rule. `exit` is an ExitStatementAst rather than a CommandAst,
    # and Rule 3 has to climb from a node to its enclosing block, so a command-only helper
    # would have forced each later rule to hand-roll its own FindAll predicate.
    function Find-AstNode {
        param(
            [Parameter(Mandatory)]$Ast,
            [Parameter(Mandatory)][type]$Type,
            [scriptblock]$Where
        )
        $predicate = {
            param($node)
            $node -is $Type -and (-not $Where -or (& $Where $node))
        }.GetNewClosure()
        @($Ast.FindAll($predicate, $true))
    }

    function Get-CommandCall {
        param($Ast, [string]$Name)
        # GetNewClosure captures $Name; without it the predicate would resolve the name in
        # whatever scope FindAll happens to invoke it from.
        $match = { param($node) $node.GetCommandName() -eq $Name }.GetNewClosure()
        Find-AstNode -Ast $Ast -Type ([System.Management.Automation.Language.CommandAst]) -Where $match
    }

    function Get-ExitStatement {
        param($Ast)
        Find-AstNode -Ast $Ast -Type ([System.Management.Automation.Language.ExitStatementAst])
    }

    function Get-TerminalStatement {
        # Rule 4: the last statement of the script body, where an unconditional exit has to
        # sit for a validator to report its verdict through the exit code.
        param($Ast)
        $statements = @($Ast.EndBlock.Statements)
        if ($statements.Count -eq 0) { return $null }
        $statements[-1]
    }

    function Get-EnclosingStatementBlock {
        # Rule 3: from a failure-reporting call, climb to the block that must also exit.
        param($Node)
        $current = $Node
        while ($current -and $current -isnot [System.Management.Automation.Language.StatementBlockAst]) {
            $current = $current.Parent
        }
        $current
    }

    function Get-FailureMessage {
        # Rule 3: the literals through which a script announces failure to the user. Both AST
        # shapes are needed - "[ERROR] Deployment failed!" parses as StringConstantExpressionAst,
        # while "[FAILED] state: $($d.ProvisioningState)" parses as ExpandableStringExpressionAst.
        # The two share no base type below ExpressionAst, so they are collected separately.
        param($Ast)
        $isFailure = { param($node) $node.Value -match '\[(FAILED|ERROR)\]' }
        @(
            Find-AstNode -Ast $Ast -Type ([System.Management.Automation.Language.StringConstantExpressionAst])   -Where $isFailure
            Find-AstNode -Ast $Ast -Type ([System.Management.Automation.Language.ExpandableStringExpressionAst]) -Where $isFailure
        )
    }

    function Test-NonZeroExit {
        # A bare `exit` and `exit 0` both hand the caller a success code, so neither discharges
        # the obligation; `exit $var` is accepted because the value is not knowable statically.
        param($Block)
        $exits = @(Get-ExitStatement -Ast $Block)
        @($exits | Where-Object { $_.Pipeline -and $_.Pipeline.Extent.Text -ne '0' }).Count -gt 0
    }
}

Describe 'Deploy scripts run unattended - no interactive prompt' {
    It "'<file>' calls no Read-Host" -ForEach $DeployCases {
        $found = @(Get-CommandCall -Ast (Get-ScriptAst -Path $path) -Name 'Read-Host')
        $lines = ($found | ForEach-Object { $_.Extent.StartLineNumber }) -join ', '
        $found.Count | Should -Be 0 -Because "an orchestrator cannot answer a prompt; '$file' asks at line(s) $lines. Expose a parameter instead."
    }
}

Describe 'Lab scripts never authenticate on their own' {
    # Matched as a command in the AST, not as text, so the many scripts that merely name
    # Connect-AzAccount inside a "please run ..." message are not flagged.
    It "'<file>' calls no Connect-AzAccount" -ForEach $AllLabCases {
        $found = @(Get-CommandCall -Ast (Get-ScriptAst -Path $path) -Name 'Connect-AzAccount')
        $lines = ($found | ForEach-Object { $_.Extent.StartLineNumber }) -join ', '
        $found.Count | Should -Be 0 -Because "in a child process with no console this blocks until the phase timeout; '$file' calls it at line(s) $lines. Fail fast and let the caller authenticate."
    }
}

Describe 'Deploy scripts report failure through the exit code' {
    # Scoped to the block holding the message, not the whole script: a script can exit 1 from its
    # catch and still fall through the else branch of a provisioning-state check, which is exactly
    # the shape this rule exists to catch. A whole-script check would call that script clean.
    It "'<file>' exits non-zero after announcing a failure" -ForEach $DeployCases {
        $ast = Get-ScriptAst -Path $path
        $lines = @(
            Get-FailureMessage -Ast $ast |
                ForEach-Object {
                    # No deploy script announces a failure outside a statement block today. The
                    # fallback keeps such a message in scope instead of silently skipping it.
                    $block = Get-EnclosingStatementBlock -Node $_
                    if ($block) { $block } else { $ast.EndBlock }
                } |
                Where-Object { -not (Test-NonZeroExit -Block $_) } |
                ForEach-Object { $_.Extent.StartLineNumber } |
                Sort-Object -Unique
        )
        $lines.Count | Should -Be 0 -Because "an orchestrator gates on the exit code, so a reported failure that falls through to exit 0 is recorded as a pass; '$file' does that in the block(s) starting at line(s) $($lines -join ', ')."
    }
}

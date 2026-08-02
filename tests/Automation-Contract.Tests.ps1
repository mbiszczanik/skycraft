<#
.SYNOPSIS
    Pester 5 test: every lab deployment script and validator honours the automation contract.

.DESCRIPTION
    An orchestrator can only trust a script that reports failure through its exit code and never
    waits for a human. These rules are enforced statically against the PowerShell AST so a
    violation is caught in CI rather than ninety minutes into a live Azure run.

    Rule 1  Deploy-Bicep.ps1 contains no Read-Host.
    Rule 2  No lab script calls Connect-AzAccount.
    Rule 3  Announcing failure - a [FAILED] or [ERROR] message, or Write-Host in Red -
            obliges the script to exit non-zero on its way out.
    Rule 4  Test-Lab.ps1 ends in an exit on every path out of its last statement.
    Rule 4a Test-Lab.ps1 does not end in an unconditional 'exit 0'.
    Rule 5  Deploy-Bicep.ps1 declares no mandatory parameter, which the binder would prompt for.

    Which files count as lab scripts is defined once in tests/LabScripts.psm1 and shared with
    the script-standards and CBH-coverage suites, so all three lint the same set.

.EXAMPLE
    Invoke-Pester -Path .\tests\Automation-Contract.Tests.ps1

.NOTES
    Project: SkyCraft
#>

#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

# Every suppression here is targeted at one variable, so a genuinely dead variable added later
# still surfaces instead of hiding behind a file-wide waiver.
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'Type', Justification = 'False positive: read inside the GetNewClosure predicate handed to FindAll.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'Where', Justification = 'False positive: read inside the GetNewClosure predicate handed to FindAll.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'Name', Justification = 'False positive: captured by GetNewClosure into the command-name predicate.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', 'DeployCases', Justification = 'False positive: consumed by -ForEach on the Rule 1 and Rule 3 It blocks, which PSSA cannot correlate across Pester scriptblock scopes.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', 'ValidatorCases', Justification = 'False positive: consumed by -ForEach on the Rule 4 and Rule 4a It blocks, which PSSA cannot correlate across Pester scriptblock scopes.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', 'AllLabCases', Justification = 'False positive: consumed by -ForEach on the Rule 2 It block, which PSSA cannot correlate across Pester scriptblock scopes.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', 'Lab52Assertions', Justification = 'False positive: consumed by -ForEach on the lab 5.2 invariant It block, which PSSA cannot correlate across Pester scriptblock scopes.')]
param()

BeforeDiscovery {
    Import-Module (Join-Path $PSScriptRoot 'LabScripts.psm1') -Force

    $DeployCases    = @(Get-ScriptCase -FileName 'Deploy-Bicep.ps1')
    $ValidatorCases = @(Get-ScriptCase -FileName 'Test-Lab.ps1')
    $AllLabCases    = @(Get-ScriptCase)

    # Lab 5.2's deploy script warns and continues when a backup policy fails to create, on the
    # stated grounds that these two assertions fail the lab instead.
    $Lab52ValidatorPath = Join-Path (Get-LabScriptRoot) 'module-5-monitoring-maintenance/5.2-business-continuity/scripts/Test-Lab.ps1'
    $Lab52Assertions    = @(
        "Policy 'SkyCraft-Daily-Prod' exists"
        "Policy 'SkyCraft-Blob-Policy' exists"
    ) | ForEach-Object { @{ label = $_; path = $Lab52ValidatorPath } }
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

    function Get-EnclosingStatementBlockChain {
        # Rule 3: every block enclosing a node, innermost first, with the script end block last.
        # The rule has to ask whether anything on the way out of the script terminates it, not
        # just the innermost block, because a failure message is routinely one line of a nested
        # diagnostic block whose enclosing branch is the one that exits.
        #
        # The end block is appended rather than found by the climb because NamedBlockAst does
        # not derive from StatementBlockAst, so a message at script top level would otherwise
        # run off the top to $null - and $null passed to Find-AstNode binds to a
        # [Parameter(Mandatory)], which prompts, hanging the very unattended run this suite
        # exists to protect.
        param($Node, $ScriptAst)
        $chain = @()
        $current = $Node
        while ($current) {
            if ($current -is [System.Management.Automation.Language.StatementBlockAst]) { $chain += $current }
            $current = $current.Parent
        }
        $chain + $ScriptAst.EndBlock
    }

    function Get-EnclosingStatementBlock {
        # The innermost enclosing block, which is what Rule 3 reports as the offending location.
        # Expressed in terms of the chain so there is only one climb to keep correct, and it
        # inherits the chain's guarantee of always returning a block.
        param($Node, $ScriptAst)
        (Get-EnclosingStatementBlockChain -Node $Node -ScriptAst $ScriptAst)[0]
    }

    function Get-FailureMessage {
        # Rule 3: the nodes through which a script announces failure. Two signals, because the
        # repository announces failure in two ways:
        #   - a [FAILED] or [ERROR] token in the message text
        #   - Write-Host ... -ForegroundColor Red, which docs/powershell-standards.md:106
        #     defines as the colour for an error
        # Keying on both is what stops a plain Write-Host "Deployment failed!" -ForegroundColor
        # Red from shipping unnoticed; five such announcements already exist that carry no
        # bracketed token at all.
        #
        # For the text signal both string AST shapes are needed: "[ERROR] Deployment failed!"
        # parses as StringConstantExpressionAst and "[FAILED] $($d.ProvisioningState)" as
        # ExpandableStringExpressionAst, and the two share no base type below ExpressionAst.
        param($Ast)
        $isFailureText = { param($node) $node.Value -match '\[(FAILED|ERROR)\]' }
        $isRedWriteHost = {
            param($node)
            if ($node.GetCommandName() -ne 'Write-Host') { return $false }
            $elements = @($node.CommandElements)
            for ($i = 0; $i -lt $elements.Count - 1; $i++) {
                if ($elements[$i] -is [System.Management.Automation.Language.CommandParameterAst] -and
                    $elements[$i].ParameterName -eq 'ForegroundColor' -and
                    $elements[$i + 1].Extent.Text.Trim("'", '"') -eq 'Red') { return $true }
            }
            $false
        }
        @(
            Find-AstNode -Ast $Ast -Type ([System.Management.Automation.Language.StringConstantExpressionAst])   -Where $isFailureText
            Find-AstNode -Ast $Ast -Type ([System.Management.Automation.Language.ExpandableStringExpressionAst]) -Where $isFailureText
            Find-AstNode -Ast $Ast -Type ([System.Management.Automation.Language.CommandAst])                    -Where $isRedWriteHost
        )
    }

    function Get-MandatoryParameter {
        # Rule 5: parameters the binder would stop and prompt for.
        #
        # Three shapes declare it - `Mandatory = $true`, `Mandatory=$true`, and a bare
        # `Mandatory`, which is also true. The first two differ only in whitespace and the AST
        # gives both the same argument expression, so only the bare form needs its own branch:
        # it parses with the expression omitted. Measured: this corpus contains `Mandatory` in
        # 110 places, all of them the spaced form, two of them true.
        param($Ast)
        foreach ($parameter in (Find-AstNode -Ast $Ast -Type ([System.Management.Automation.Language.ParameterAst]))) {
            $isMandatory = $false
            foreach ($attribute in @($parameter.Attributes | Where-Object { $_ -is [System.Management.Automation.Language.AttributeAst] })) {
                if ($attribute.TypeName.GetReflectionAttributeType() -ne [System.Management.Automation.ParameterAttribute]) { continue }
                foreach ($named in @($attribute.NamedArguments)) {
                    if ($named.ArgumentName -ne 'Mandatory') { continue }
                    if ($named.ExpressionOmitted -or $named.Argument.Extent.Text -eq '$true') { $isMandatory = $true }
                }
            }
            if ($isMandatory) { $parameter }
        }
    }

    function Test-ExitOnEveryPath {
        # Rule 4: does control always leave the script at this statement? An exit does. An if
        # does only when every branch does and an else exists - without an else the fall-through
        # path carries on past the if and off the end of the script.
        #
        # $null here means the script body has no statements, which is a real answer rather than
        # a gap to paper over: such a script cannot exit, so it fails. That is why this is not
        # made total the way Get-EnclosingStatementBlock was. There the $null would have reached
        # a mandatory parameter and prompted; this one is consumed on the next line.
        param($Statement)
        if (-not $Statement) { return $false }
        if ($Statement -is [System.Management.Automation.Language.ExitStatementAst]) { return $true }
        if ($Statement -is [System.Management.Automation.Language.IfStatementAst]) {
            if (-not $Statement.ElseClause) { return $false }
            $bodies = @($Statement.Clauses | ForEach-Object { $_.Item2 }) + @($Statement.ElseClause)
            foreach ($body in $bodies) {
                $last = @($body.Statements) | Select-Object -Last 1
                if (-not (Test-ExitOnEveryPath -Statement $last)) { return $false }
            }
            return $true
        }
        $false
    }

    function Test-ExitIsNonZero {
        # The value predicate on a single exit. A bare `exit` and `exit 0` both hand the caller
        # a success code, so neither discharges the obligation; `exit $var` is accepted because
        # the value is not knowable statically. Rule 4 needs this on its own, without the block
        # search below, which is why the two are separate.
        param($Exit)
        [bool]($Exit.Pipeline -and $Exit.Pipeline.Extent.Text -ne '0')
    }

    function Test-BlockExitsDirectly {
        # Whether this block itself terminates the script - an exit among its own statements,
        # not one buried in a conditional inside it.
        #
        # That distinction is what makes walking the chain safe rather than merely permissive,
        # and it is the part most likely to look like over-complication later. Lab 2.2's failing
        # branch sits inside a try whose body does contain an exit 1, nested in an if. A search
        # that counted any descendant exit would therefore mark it covered - passing the exact
        # defect Rule 3 was written to catch. Measured: with the descendant search this rule
        # reports 12 blocks across the corpus, 7 of them false; with the direct check, 5, all
        # real, matching the known defect list exactly.
        param($Block)
        @(@($Block.Statements) | Where-Object {
            $_ -is [System.Management.Automation.Language.ExitStatementAst] -and (Test-ExitIsNonZero -Exit $_)
        }).Count -gt 0
    }
}

Describe 'Deploy scripts run unattended - no interactive prompt' {
    It "'<file>' calls no Read-Host" -ForEach $DeployCases {
        $found = @(Get-CommandCall -Ast (Get-ScriptAst -Path $path) -Name 'Read-Host')
        $lines = ($found | ForEach-Object { $_.Extent.StartLineNumber }) -join ', '
        $found.Count | Should -Be 0 -Because "an orchestrator cannot answer a prompt; '$file' asks at line(s) $lines. Expose a parameter instead."
    }
}

Describe 'Deploy scripts declare no mandatory parameter' {
    # The third way a script can stop and wait for a human, after Read-Host (Rule 1) and
    # Connect-AzAccount (Rule 2). This one arrives through the parameter binder rather than a
    # statement: a missing mandatory value makes PowerShell prompt, and in a child process with
    # no console that blocks until the phase timeout.
    #
    # Read from the AST rather than (Get-Command $path).Parameters. Every lab script carries
    # #Requires -Modules, and Get-Command on such a script fails when those modules are absent.
    # .github/workflows/lint.yml installs only PSScriptAnalyzer and Pester, so a Get-Command
    # rule would pass on a developer machine with the Az modules and break in CI. The AST also
    # binds nothing and executes nothing.
    It "'<file>' declares no mandatory parameter" -ForEach $DeployCases {
        $found = @(Get-MandatoryParameter -Ast (Get-ScriptAst -Path $path))
        $names = ($found | ForEach-Object { "-$($_.Name.VariablePath.UserPath) at line $($_.Extent.StartLineNumber)" }) -join ', '
        $found.Count | Should -Be 0 -Because "an orchestrator cannot answer the binder's prompt any more than it can answer Read-Host; '$file' declares $names. Give the parameter a default instead."
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
    # A failure is covered when some block on the way out of the script terminates it directly.
    #
    # Not the whole script: lab 2.2 exits 1 from its catch while the else branch of its
    # provisioning-state check falls through, and a whole-script check would call that clean.
    # Not the innermost block alone either: a failure message is often one line of a nested
    # diagnostic block whose enclosing branch is the one that exits, and demanding an exit from
    # the innermost block reports 7 such places falsely.
    It "'<file>' exits non-zero after announcing a failure" -ForEach $DeployCases {
        $ast = Get-ScriptAst -Path $path
        $lines = @(
            Get-FailureMessage -Ast $ast |
                Where-Object {
                    $chain = Get-EnclosingStatementBlockChain -Node $_ -ScriptAst $ast
                    @($chain | Where-Object { Test-BlockExitsDirectly -Block $_ }).Count -eq 0
                } |
                ForEach-Object { (Get-EnclosingStatementBlock -Node $_ -ScriptAst $ast).Extent.StartLineNumber } |
                Sort-Object -Unique
        )
        $lines.Count | Should -Be 0 -Because "an orchestrator gates on the exit code, so a reported failure that falls through to exit 0 is recorded as a pass; '$file' does that in the block(s) starting at line(s) $($lines -join ', ')."
    }
}

Describe 'Validators report their verdict through the exit code' {
    # Scoped to the last top-level statement, not "contains an exit somewhere". Sixteen of the
    # seventeen validators hold an exit outside their terminal statement - a guard, or a catch -
    # so containment is nearly vacuous here: measured against the pre-fix tree it would have
    # missed three of the four defects this rule caught, flagging only lab 1.2, which at that
    # point held no exit statement at all. Lab 4.1 is the single file whose only exits are both
    # inside its terminal if; it has no not-logged-in guard.
    #
    # This rule needs no Find-AstNode: it asks what the script's final statement is, not whether
    # some node exists anywhere in it, so there is nothing to search for.
    It "'<file>' ends in an exit on every path" -ForEach $ValidatorCases {
        $terminal = Get-TerminalStatement -Ast (Get-ScriptAst -Path $path)
        $where = if ($terminal) {
            "its last statement is at line $($terminal.Extent.StartLineNumber): $((($terminal.Extent.Text -split "`n")[0]).Trim())"
        } else {
            'its body has no statements at all'
        }
        Test-ExitOnEveryPath -Statement $terminal |
            Should -BeTrue -Because "an orchestrator reads this script's exit code as the lab's verdict, so one that ends without exiting reports success however many checks failed; in '$file' $where."
    }

    # Rule 4a. Rule 4 alone would accept a validator ending in a flat `exit 0`, which reports
    # success unconditionally - the same defect one step removed. Only a terminal statement that
    # is *itself* a literal `exit 0` is rejected: labs 4.1 and 4.2 end in an if that exits 0 on
    # the success branch of a real counter, which is correct and must stay legal.
    #
    # WHERE THIS STOPS: no rule here can see whether the counter behind `exit $failCount` is ever
    # incremented. A validator that declares a counter, prints [FAIL] without incrementing it and
    # exits that counter satisfies both Rule 4 and Rule 4a while always reporting success. That
    # gap is closed by reading the code, not by this suite.
    It "'<file>' does not end in an unconditional 'exit 0'" -ForEach $ValidatorCases {
        $terminal = Get-TerminalStatement -Ast (Get-ScriptAst -Path $path)
        $isFlatZero = $terminal -is [System.Management.Automation.Language.ExitStatementAst] -and
                      -not (Test-ExitIsNonZero -Exit $terminal)
        $isFlatZero | Should -BeFalse -Because "'$file' would report success whatever its checks found. Exit a failure count, or branch on one."
    }
}

Describe 'Lab 5.2 keeps the validator assertions its deploy script defers to' {
    # Lab 5.2's Deploy-Bicep.ps1 catches a backup-policy failure, warns and continues, on the
    # explicit grounds that Test-Lab.ps1 fails the lab instead. That is a cross-file invariant,
    # and a comment cannot hold it: delete these assertions and the deploy script silently
    # becomes the fall-through Rule 3 exists to forbid, while Rule 3 itself still passes
    # because the message says [WARNING]. This is the assertion that breaks instead.
    It "Test-Lab.ps1 still asserts '<label>'" -ForEach $Lab52Assertions {
        $labels = @(
            Get-CommandCall -Ast (Get-ScriptAst -Path $path) -Name 'Invoke-Test' |
                Where-Object { $_.CommandElements.Count -gt 1 } |
                ForEach-Object { $_.CommandElements[1].Value }
        )
        $labels | Should -Contain $label -Because "lab 5.2's deploy script treats a failed backup-policy creation as non-fatal only because this assertion catches it. Removing it makes that lab pass with the policy missing. Restore it, or make the deploy script exit non-zero again."
    }
}

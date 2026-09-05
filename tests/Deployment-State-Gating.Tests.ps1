<#
.SYNOPSIS
    Pester 5 test: a deployment that does not reach 'Succeeded' fails the script that ran it.

.DESCRIPTION
    Regression guard for issue #75 (AUDIT-modules-2-5.md 5.3).

    'New-AzSubscriptionDeployment' does not throw for every unhappy ending. A deployment
    whose resources fail to provision can still return an object to the caller - with
    'ProvisioningState' set to 'Failed' or 'Canceled' - and the pipeline carries on as if
    nothing happened. A lab script that ignores that value prints its success banner, exits
    0, and hands the learner a half-built environment; the lab cycle then reports green for
    a lab that never deployed.

    The contract this file enforces, for every real (non -WhatIf) deployment invocation in
    the lab scripts:

      captured  The result is assigned to a variable. A deployment piped to Out-Null
                cannot be inspected at all, so its outcome is unknowable by construction.
      gated     Some 'if' in the same script tests that variable's 'ProvisioningState'
                against 'Succeeded', and the branch taken when it does not match ends the
                script with a non-zero 'exit' (or a 'throw').

    Which branch is the failure branch follows from the operator: '-ne Succeeded' fails in
    the if body, '-eq Succeeded' fails in the else clause.

    Pairing the guard with the exit code itself is left to Exit-Code-Propagation.Tests.ps1,
    which requires every non-zero 'exit' in a script declaring '#Requires -Modules' to be preceded
    by $Host.SetShouldExit. This file keeps the wider scope on purpose (#124): New-Az*Deployment
    returns an ungated 'Failed' whatever the script requires, so the rule here follows the call
    rather than the declaration.

.EXAMPLE
    Invoke-Pester -Path .\tests\Deployment-State-Gating.Tests.ps1

.NOTES
    Project: SkyCraft
#>

#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path

# Every real deployment invocation in a file, with the evidence that its outcome is checked.
# Parsed rather than regex-matched so that a call spread over several lines, or a name that
# only appears in a comment, is handled correctly.
function Get-DeploymentSite {
    param([string]$Path)

    $tokens = $null
    $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$tokens, [ref]$errors)

    $ifStatements = @($ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.IfStatementAst] }, $true))

    foreach ($command in $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] }, $true)) {

        $name = $command.GetCommandName()
        if ($name -notmatch '^New-Az[A-Za-z]*Deployment$') { continue }

        # '-WhatIf' provisions nothing, so there is no provisioning state to gate on.
        $isWhatIf = @($command.CommandElements | Where-Object {
            $_ -is [System.Management.Automation.Language.CommandParameterAst] -and $_.ParameterName -eq 'WhatIf'
        }).Count -gt 0
        if ($isWhatIf) { continue }

        # The result is captured when the pipeline holding the call is the right-hand side
        # of an assignment: '$deployment = New-AzSubscriptionDeployment ...'.
        $variable = ''
        $node = $command.Parent
        while ($null -ne $node -and $node -isnot [System.Management.Automation.Language.StatementBlockAst]) {
            if ($node -is [System.Management.Automation.Language.AssignmentStatementAst] -and
                $node.Left -is [System.Management.Automation.Language.VariableExpressionAst]) {
                $variable = $node.Left.VariablePath.UserPath
                break
            }
            $node = $node.Parent
        }

        $gated = $false
        if ($variable) {
            foreach ($if in $ifStatements) {
                foreach ($clause in $if.Clauses) {

                    $condition = $clause.Item1.Extent.Text
                    if ($condition -notmatch ('\$' + [regex]::Escape($variable) + '\b[^\r\n]*\.ProvisioningState')) { continue }
                    if ($condition -notmatch "Succeeded") { continue }

                    # '-ne Succeeded' fails in the body; '-eq Succeeded' fails in the else.
                    $failureBranch = if ($condition -match '-(ne|notmatch|cne)\b') {
                        $clause.Item2
                    }
                    elseif ($condition -match '-(eq|ceq)\b') {
                        $if.ElseClause
                    }

                    if ($null -eq $failureBranch) { continue }

                    $endsScript = @($failureBranch.FindAll({ param($n)
                        ($n -is [System.Management.Automation.Language.ExitStatementAst] -and
                         $null -ne $n.Pipeline -and $n.Pipeline.Extent.Text.Trim() -ne '0') -or
                        $n -is [System.Management.Automation.Language.ThrowStatementAst]
                    }, $true)).Count -gt 0

                    if ($endsScript) { $gated = $true }
                }
            }
        }

        [PSCustomObject]@{
            Line     = $command.Extent.StartLineNumber
            Variable = $variable
            Gated    = $gated
        }
    }
}

# Path matching is separator-agnostic so the suite runs identically on the Windows dev box
# and the Linux CI runner.
$DeploymentCases = Get-ChildItem -Path $RepoRoot -Recurse -File -Filter '*.ps1' |
                   Where-Object { (($_.FullName.Substring($RepoRoot.Length + 1)) -replace '\\', '/') -match '^(module-\d.*/)?(scripts|tools)/' } |
                   ForEach-Object {
                       $file = $_.FullName.Substring($RepoRoot.Length + 1) -replace '\\', '/'
                       foreach ($site in Get-DeploymentSite -Path $_.FullName) {
                           @{
                               file     = $file
                               line     = $site.Line
                               variable = $site.Variable
                               gated    = $site.Gated
                           }
                       }
                   }

Describe 'SkyCraft PowerShell - a deployment that is not Succeeded fails its script' {

    It "'<file>':<line> assigns the deployment result to a variable" -ForEach $DeploymentCases {
        # An uncaptured result cannot be inspected, so the failure can never be noticed.
        $variable | Should -Not -BeNullOrEmpty -Because 'the provisioning state has to be readable to be checked'
    }

    It "'<file>':<line> exits non-zero when ProvisioningState is not 'Succeeded'" -ForEach $DeploymentCases {
        # New-Az*Deployment returns a Failed/Canceled deployment instead of throwing, so an
        # ungated script reports success for a deployment that never completed.
        $gated | Should -BeTrue -Because "`$$variable.ProvisioningState must be compared with 'Succeeded' and the failing branch must end the script"
    }
}

<#
.SYNOPSIS
    Pester 5 test: a lab cleanup tells a resource that is gone from a lookup that failed.

.DESCRIPTION
    Issue #255 (after #227 for Lab 1.1 and #238 for Lab 5.2): the lab cleanups looked resources up
    with -ErrorAction SilentlyContinue, so a lookup that failed - a 403, throttling, a transient
    ARM error - read as "absent". The resource was skipped, and the run could exit 0 while it
    still existed.

    The fix is two helpers in each Remove-LabResource.ps1: Test-LabNotFoundError, which decides
    whether an error means "not found", and Invoke-LabLookup, which runs a lookup, reads a
    not-found error as absent and counts any other error as a failure. Each lab carries its own
    copy, because a lab folder must stay runnable on its own (docs/powershell-standards.md
    section 7.5). Copies drift, so this suite holds every copy to the same contract instead of
    each lab suite repeating it:

      1. Every Remove-LabResource.ps1 that defines either helper or calls Invoke-LabLookup
         defines both at the top level, where the parser can lift them - the script body never
         runs, so nothing is looked up. The cleanups known to carry them are listed, so a
         discovery that silently finds fewer fails.
      2. Test-LabNotFoundError reads every not-found shape the Az getters produce as "not found",
         and a 403, a 429, a transport error and a missing subscription as a failed lookup. A
         lab's copy may recognise more shapes (Lab 1.3 adds PolicyAssignmentNotFound); its own
         suite pins those.
      3. Invoke-LabLookup returns what a lookup found, reads "found nothing" and a not-found error
         as absent without counting them, and counts any other error in $script:cleanupFailures.
      4. A ratchet over every cleanup, and over the lab cycle's tools/Remove-LabCycle.ps1 and
         tools/LabCycle.psm1 where a rule fits them. No cleanup, and neither tool:
           a. gives a *-Az* command -ErrorAction SilentlyContinue or Ignore;
           b. sets $ErrorActionPreference to SilentlyContinue or Ignore, at any scope;
           c. gives $PSDefaultParameterValues an ErrorAction default of SilentlyContinue or Ignore
              for a key that can reach an Az command ('*:ErrorAction', '*-Az*:EA', 'Get-*:...').
         And no cleanup (the tools count differently - see $ToolRatchetCases):
           d. catches the error of a *-Az* command in a catch clause that, on the path a failure
              takes, neither counts it (++ or += on $script:cleanupFailures) nor throws or exits -
              the catch that read any error as "not there" in Labs 3.1 and 4.4 before #297.
              Test-LabNotFoundError counts only as the test that decides which path is which.
              Every verb counts, not only Get: Lab 3.1 read a failed delete as "may not exist".
              Invoke-AzRestMethod is left out, and only commands written inside the try block
              are read - not a scriptblock invoked with &, not a trap (see Find-UnhandledAzCatch).
              The few catches that report a failure as [WARN] on purpose, in a diagnostic that
              must not change the exit code, are listed in $DiagnosticCatch.
         The checks walk the syntax tree, never a comment or a string. They read the spellings
         their fixtures below cover - for (a), -ErrorAction:X, -EA X, a prefix, a quoted value, 0
         or 4, the ActionPreference enum, a value carried in a splatted hashtable the script
         builds, and a command split by backtick continuations - and nothing else: a value held
         in another variable, or a default computed at run time, is not resolved. A form a
         fixture does not cover is not read; add a fixture before relying on it. Nor is an error
         hidden without silencing the command: -ErrorAction Continue with 2>$null or *>$null,
         or $ErrorActionPreference = 'Continue', is not read. There is no pending list: #290
         converted the last labs on it, so a new lab's cleanup is held to the ratchet from its
         first commit.

    Each lab's own tests/Remove-LabResource.Tests.ps1 runs the script end to end against stubbed
    Az commands and proves the exit code.

.EXAMPLE
    Invoke-Pester -Path .\tests\Lab-Cleanup-Lookup.Tests.ps1

.NOTES
    Project: SkyCraft
#>

#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

# ---------------------------------------------------------------------------------------------
# Discovery-time state. A -ForEach case list has to exist when Pester discovers the tests, so the
# scripts are found and parsed now; everything the assertions need is carried in the case itself.
# ---------------------------------------------------------------------------------------------

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path

$CleanupScripts = @(Get-ChildItem -Path $RepoRoot -Directory -Filter 'module-*' |
    Get-ChildItem -Directory |
    ForEach-Object { Join-Path $_.FullName 'scripts' 'Remove-LabResource.ps1' } |
    Where-Object { Test-Path -LiteralPath $_ })

# A cleanup takes part in the helper contract when it defines either helper or calls
# Invoke-LabLookup - read from the syntax tree, so the indentation of a definition does not matter.
$HelperCases = @(foreach ($cleanup in $CleanupScripts) {
    $cleanupAst = [System.Management.Automation.Language.Parser]::ParseFile($cleanup, [ref]$null, [ref]$null)
    $usesHelpers = $cleanupAst.Find({
        param($node)
        ($node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
            $node.Name -in 'Test-LabNotFoundError', 'Invoke-LabLookup') -or
        ($node -is [System.Management.Automation.Language.CommandAst] -and
            $node.GetCommandName() -eq 'Invoke-LabLookup')
    }, $true)
    if ($usesHelpers) {
        @{ file = ($cleanup.Substring($RepoRoot.Length + 1) -replace '\\', '/'); path = $cleanup }
    }
})

# The cleanups that carry the helpers today. Discovery must find at least these.
$ExpectedHelperFile = @(
    'module-1-identities-governance/1.2-rbac/scripts/Remove-LabResource.ps1'
    'module-1-identities-governance/1.3-governance/scripts/Remove-LabResource.ps1'
    'module-2-networking/2.1-virtual-networks/scripts/Remove-LabResource.ps1'
    'module-2-networking/2.2-secure-access/scripts/Remove-LabResource.ps1'
    'module-2-networking/2.3-name-resolution/scripts/Remove-LabResource.ps1'
    'module-3-compute/3.1-infrastructure-as-code/scripts/Remove-LabResource.ps1'
    'module-3-compute/3.2-virtual-machines/scripts/Remove-LabResource.ps1'
    'module-3-compute/3.3-containers/scripts/Remove-LabResource.ps1'
    'module-3-compute/3.4-app-service/scripts/Remove-LabResource.ps1'
    'module-4-storage/4.1-storage-accounts/scripts/Remove-LabResource.ps1'
    'module-4-storage/4.2-blob-storage/scripts/Remove-LabResource.ps1'
    'module-4-storage/4.3-azure-files/scripts/Remove-LabResource.ps1'
    'module-4-storage/4.4-storage-security/scripts/Remove-LabResource.ps1'
    'module-5-monitoring-maintenance/5.1-azure-monitor/scripts/Remove-LabResource.ps1'
    'module-5-monitoring-maintenance/5.2-business-continuity/scripts/Remove-LabResource.ps1'
    'module-5-monitoring-maintenance/5.3-network-monitoring/scripts/Remove-LabResource.ps1'
)

# Every cleanup is held to the ratchet. There is no pending list any more: #290 converted the
# last labs on it, and a list that may hold an entry is a way to exempt a new lab's cleanup from
# its first commit - so a new lab meets the rules or fails here.
$RatchetCases = @($CleanupScripts | ForEach-Object {
    @{ file = ($_.Substring($RepoRoot.Length + 1) -replace '\\', '/'); path = $_ }
})

# The lab cycle's teardown asserts what the cleanups left behind, and its preflight (in
# LabCycle.psm1) checks for leftovers before a run; both read a failed check as "gone" or
# "clear" the same way (#290). They are held to the rules about silencing errors. Their catch
# clauses report a failure as a failed result or a failed check, not in $script:cleanupFailures,
# which the catch rule does not read.
$ToolRatchetCases = @(
    @{ file = 'tools/Remove-LabCycle.ps1'; path = (Join-Path $RepoRoot 'tools' 'Remove-LabCycle.ps1') }
    @{ file = 'tools/LabCycle.psm1';       path = (Join-Path $RepoRoot 'tools' 'LabCycle.psm1') }
)

# The catch clauses that report a failed lookup as a [WARN] and do not count it, on purpose: each
# sits in a diagnostic whose answer must not change the exit code, and tells "not found" from
# "could not tell" with Test-LabNotFoundError instead. Keyed by file and caught command, with how
# many such clauses may catch it there: one more fails the catch rule, and an entry that no longer
# matches fails the Describe that checks this list, so it cannot outlive the code it excuses.
# Entries are counted, not pinned to lines: a listed clause made to count while a new silent one
# catches the same command in the same file keeps the count, and an Az call added inside a listed
# diagnostic try is not seen.
$DiagnosticCatch = @(
    @{ file = 'module-2-networking/2.1-virtual-networks/scripts/Remove-LabResource.ps1'; command = 'Get-AzVirtualNetwork'; count = 1
       why  = 'the service association link preflight is diagnostic and never touches the failure count (#110); the delete steps look the VNet up again, and count' }
    @{ file = 'module-2-networking/2.1-virtual-networks/scripts/Remove-LabResource.ps1'; command = 'Get-AzResource'; count = 1
       why  = 'in the same preflight, a link target that cannot be read is reported "target unverified", never "orphaned" (#110)' }
    @{ file = 'module-3-compute/3.4-app-service/scripts/Remove-LabResource.ps1'; command = 'Get-AzVirtualNetwork'; count = 1
       why  = 'Get-SubnetLinkSnapshot feeds the informational subnet report; it returns $null for "unknown", and the plan is kept or deleted on other, counted grounds' }
)
foreach ($case in $RatchetCases) {
    $case.allowed = @($DiagnosticCatch | Where-Object { $_.file -eq $case.file })
}
$DiagnosticCases = @($DiagnosticCatch | ForEach-Object { $_ + @{ path = (Join-Path $RepoRoot $_.file) } })

BeforeAll {
    # What the ratchet's readers share: the values that silence an error, and how a parameter
    # name and a literal value are read from the syntax tree.
    $script:SilentValue = '^(SilentlyContinue|Ignore|0|4)$'

    # ErrorAction, any unambiguous prefix of it (-ErrorA...), or its alias EA.
    function Test-RatchetErrorActionName {
        param([string]$Name)
        $Name -eq 'EA' -or ($Name.Length -ge 6 -and 'ErrorAction'.StartsWith($Name, [System.StringComparison]::OrdinalIgnoreCase))
    }

    # The literal value of an argument or a hashtable entry, or $null when it is not a literal.
    function Get-RatchetLiteral {
        param($Node)
        switch ($Node) {
            { $_ -is [System.Management.Automation.Language.PipelineAst] } {
                if ($_.PipelineElements.Count -eq 1) { return (Get-RatchetLiteral -Node $_.PipelineElements[0]) }
                return $null
            }
            { $_ -is [System.Management.Automation.Language.CommandExpressionAst] } { return (Get-RatchetLiteral -Node $_.Expression) }
            { $_ -is [System.Management.Automation.Language.ParenExpressionAst] } { return (Get-RatchetLiteral -Node $_.Pipeline) }
            { $_ -is [System.Management.Automation.Language.ConvertExpressionAst] } { return (Get-RatchetLiteral -Node $_.Child) }
            { $_ -is [System.Management.Automation.Language.ConstantExpressionAst] } { return [string]$_.Value }
            { $_ -is [System.Management.Automation.Language.ExpandableStringExpressionAst] } { return $_.Value }
            { $_ -is [System.Management.Automation.Language.MemberExpressionAst] } { return ($_.Member.Extent.Text -replace '[''"]', '') }
        }
        return $null
    }

    # The ratchet's reader. Returns one finding per *-Az* command that is given -ErrorAction
    # SilentlyContinue or Ignore, in any form the parser accepts:
    #   - the parameter as ErrorAction, any unambiguous prefix of it (-ErrorA...), or its alias EA;
    #   - the value after a space or a colon (-ErrorAction:Ignore), bare or quoted, as the enum
    #     name, its number (SilentlyContinue = 0, Ignore = 4), or [ActionPreference]::Name;
    #   - a splatted variable (@query) that the script assigns a hashtable literal holding the key,
    #     or whose key it sets afterwards ($query.ErrorAction = ..., $query['ErrorAction'] = ...).
    # A value held in another variable cannot be resolved without running the script, and is not
    # read. Comments and strings are not commands, so they never match.
    function Find-SilencedAzCommand {
        [CmdletBinding()]
        param([Parameter(Mandatory)][AllowEmptyString()][string]$Text)

        $silentValue = $script:SilentValue
        $isErrorActionName = { param([string]$Name) Test-RatchetErrorActionName -Name $Name }
        $valueOf = { param($Node) Get-RatchetLiteral -Node $Node }

        $ast = [System.Management.Automation.Language.Parser]::ParseInput($Text, [ref]$null, [ref]$null)

        # Variables the script fills with a silencing ErrorAction, for splatting.
        $silencingSplat = @{}
        foreach ($assignment in $ast.FindAll({ $args[0] -is [System.Management.Automation.Language.AssignmentStatementAst] }, $true)) {
            $left = $assignment.Left
            if ($left -is [System.Management.Automation.Language.VariableExpressionAst]) {
                $table = $assignment.Right
                while ($table -and $table -isnot [System.Management.Automation.Language.HashtableAst]) {
                    $table = switch ($table) {
                        { $_ -is [System.Management.Automation.Language.PipelineAst] } { if ($_.PipelineElements.Count -eq 1) { $_.PipelineElements[0] } }
                        { $_ -is [System.Management.Automation.Language.CommandExpressionAst] } { $_.Expression }
                        { $_ -is [System.Management.Automation.Language.ConvertExpressionAst] } { $_.Child }
                        default { $null }
                    }
                }
                if (-not $table) { continue }
                foreach ($pair in $table.KeyValuePairs) {
                    if ((& $isErrorActionName (& $valueOf $pair.Item1)) -and ((& $valueOf $pair.Item2) -match $silentValue)) {
                        $silencingSplat[$left.VariablePath.UserPath] = $true
                    }
                }
            }
            elseif ($left -is [System.Management.Automation.Language.MemberExpressionAst] -or
                    $left -is [System.Management.Automation.Language.IndexExpressionAst]) {
                $target = if ($left -is [System.Management.Automation.Language.MemberExpressionAst]) { $left.Expression } else { $left.Target }
                $key    = if ($left -is [System.Management.Automation.Language.MemberExpressionAst]) { $left.Member } else { $left.Index }
                if ($target -is [System.Management.Automation.Language.VariableExpressionAst] -and
                    (& $isErrorActionName (& $valueOf $key)) -and ((& $valueOf $assignment.Right) -match $silentValue)) {
                    $silencingSplat[$target.VariablePath.UserPath] = $true
                }
            }
        }

        foreach ($command in $ast.FindAll({ $args[0] -is [System.Management.Automation.Language.CommandAst] }, $true)) {
            $name = $command.GetCommandName()
            if (-not $name -or $name -notmatch '^\w+-Az\w') { continue }
            $elements = $command.CommandElements
            $silenced = $false
            for ($index = 1; $index -lt $elements.Count; $index++) {
                $element = $elements[$index]
                if ($element -is [System.Management.Automation.Language.CommandParameterAst] -and (& $isErrorActionName $element.ParameterName)) {
                    $value = if ($element.Argument) { $element.Argument } elseif ($index + 1 -lt $elements.Count) { $elements[$index + 1] }
                    if ((& $valueOf $value) -match $silentValue) { $silenced = $true }
                }
                elseif ($element -is [System.Management.Automation.Language.VariableExpressionAst] -and $element.Splatted -and
                        $silencingSplat.ContainsKey($element.VariablePath.UserPath)) {
                    $silenced = $true
                }
            }
            if ($silenced) {
                [pscustomobject]@{
                    Line    = $command.Extent.StartLineNumber
                    Command = $name
                    Text    = ($command.Extent.Text -split "`r?`n")[0].Trim()
                }
            }
        }
    }

    # The name of a variable without its scope: $script:x, $global:x and ${x} are all 'x'.
    function Get-RatchetVariableName {
        param($Node)
        if ($Node -isnot [System.Management.Automation.Language.VariableExpressionAst]) { return $null }
        $Node.VariablePath.UserPath -replace '^(global|script|local|private):', ''
    }

    # The reader for preferences that silence every command at once. Returns one finding per
    #   - assignment of SilentlyContinue or Ignore (any literal spelling Get-RatchetLiteral reads)
    #     to $ErrorActionPreference, at any scope ($global:, $script:, ${...}), or a Set-Variable
    #     call that sets it, by name or by position;
    #   - $PSDefaultParameterValues entry whose key names ErrorAction (or EA, or a prefix) for a
    #     command pattern that can match an Az command, and whose value silences it: set by index
    #     ($PSDefaultParameterValues['*:ErrorAction'] = ...), by member ($x.'*:EA' = ...), by
    #     .Add(key, value), or in a hashtable literal assigned or added (=, +=) to the variable.
    # A command pattern can match an Az command when it names '-Az', or matches Get-AzStub or
    # Remove-AzStub as a wildcard ('*', '*-Az*', 'Get-*', 'Get-Az*'). A value held in another
    # variable is not resolved.
    function Find-SilencingPreference {
        [CmdletBinding()]
        param([Parameter(Mandatory)][AllowEmptyString()][string]$Text)

        $ast = [System.Management.Automation.Language.Parser]::ParseInput($Text, [ref]$null, [ref]$null)

        $reachesAz = {
            param([string]$Key)
            $command, $parameter = $Key -split ':', 2
            if (-not $parameter -or -not (Test-RatchetErrorActionName -Name $parameter)) { return $false }
            if ($command -match '-Az') { return $true }
            $pattern = [System.Management.Automation.WildcardPattern]::new($command, 'IgnoreCase')
            return ($pattern.IsMatch('Get-AzStub') -or $pattern.IsMatch('Remove-AzStub'))
        }
        $finding = {
            param($Node, [string]$What)
            [pscustomobject]@{
                Line = $Node.Extent.StartLineNumber
                What = $What
                Text = ($Node.Extent.Text -split "`r?`n")[0].Trim()
            }
        }
        # The pairs of a hashtable literal an expression holds, or nothing.
        $pairsOf = {
            param($Node)
            while ($Node -and $Node -isnot [System.Management.Automation.Language.HashtableAst]) {
                $Node = switch ($Node) {
                    { $_ -is [System.Management.Automation.Language.PipelineAst] } { if ($_.PipelineElements.Count -eq 1) { $_.PipelineElements[0] } }
                    { $_ -is [System.Management.Automation.Language.CommandExpressionAst] } { $_.Expression }
                    { $_ -is [System.Management.Automation.Language.ConvertExpressionAst] } { $_.Child }
                    { $_ -is [System.Management.Automation.Language.ParenExpressionAst] } { $_.Pipeline }
                    default { $null }
                }
            }
            if ($Node) { $Node.KeyValuePairs }
        }

        foreach ($assignment in $ast.FindAll({ $args[0] -is [System.Management.Automation.Language.AssignmentStatementAst] }, $true)) {
            $left = $assignment.Left
            if ($left -is [System.Management.Automation.Language.ConvertExpressionAst]) { $left = $left.Child }
            $leftName = Get-RatchetVariableName -Node $left

            if ($leftName -eq 'ErrorActionPreference' -and (Get-RatchetLiteral -Node $assignment.Right) -match $script:SilentValue) {
                & $finding $assignment '$ErrorActionPreference'
            }
            elseif ($leftName -eq 'PSDefaultParameterValues') {
                foreach ($pair in @(& $pairsOf $assignment.Right)) {
                    if ((& $reachesAz (Get-RatchetLiteral -Node $pair.Item1)) -and (Get-RatchetLiteral -Node $pair.Item2) -match $script:SilentValue) {
                        & $finding $assignment '$PSDefaultParameterValues'
                    }
                }
            }
            elseif ($left -is [System.Management.Automation.Language.IndexExpressionAst] -or
                    $left -is [System.Management.Automation.Language.MemberExpressionAst]) {
                $target = if ($left -is [System.Management.Automation.Language.IndexExpressionAst]) { $left.Target } else { $left.Expression }
                $key    = if ($left -is [System.Management.Automation.Language.IndexExpressionAst]) { $left.Index } else { $left.Member }
                if ((Get-RatchetVariableName -Node $target) -eq 'PSDefaultParameterValues' -and
                    (& $reachesAz (Get-RatchetLiteral -Node $key)) -and (Get-RatchetLiteral -Node $assignment.Right) -match $script:SilentValue) {
                    & $finding $assignment '$PSDefaultParameterValues'
                }
            }
        }

        foreach ($call in $ast.FindAll({ $args[0] -is [System.Management.Automation.Language.InvokeMemberExpressionAst] }, $true)) {
            if ((Get-RatchetVariableName -Node $call.Expression) -ne 'PSDefaultParameterValues') { continue }
            if ((Get-RatchetLiteral -Node $call.Member) -ne 'Add' -or @($call.Arguments).Count -ne 2) { continue }
            if ((& $reachesAz (Get-RatchetLiteral -Node $call.Arguments[0])) -and (Get-RatchetLiteral -Node $call.Arguments[1]) -match $script:SilentValue) {
                & $finding $call '$PSDefaultParameterValues'
            }
        }

        foreach ($command in $ast.FindAll({ $args[0] -is [System.Management.Automation.Language.CommandAst] }, $true)) {
            if ($command.GetCommandName() -notin 'Set-Variable', 'sv') { continue }
            $named = @{}
            $positional = [System.Collections.Generic.List[object]]::new()
            $elements = $command.CommandElements
            for ($index = 1; $index -lt $elements.Count; $index++) {
                $element = $elements[$index]
                if ($element -is [System.Management.Automation.Language.CommandParameterAst]) {
                    $value = $element.Argument
                    if (-not $value -and $index + 1 -lt $elements.Count -and
                        $elements[$index + 1] -isnot [System.Management.Automation.Language.CommandParameterAst]) {
                        $index++
                        $value = $elements[$index]
                    }
                    foreach ($parameter in 'Name', 'Value') {
                        if ($element.ParameterName.Length -ge 2 -and $parameter.StartsWith($element.ParameterName, [System.StringComparison]::OrdinalIgnoreCase)) { $named[$parameter] = $value }
                    }
                }
                else { $positional.Add($element) }
            }
            $nameNode  = if ($named.ContainsKey('Name')) { $named.Name } elseif ($positional.Count -ge 1) { $positional[0] }
            $valueNode = if ($named.ContainsKey('Value')) { $named.Value } elseif ($named.ContainsKey('Name') -and $positional.Count -ge 1) { $positional[0] } elseif ($positional.Count -ge 2) { $positional[1] }
            if ((Get-RatchetLiteral -Node $nameNode) -eq 'ErrorActionPreference' -and (Get-RatchetLiteral -Node $valueNode) -match $script:SilentValue) {
                & $finding $command '$ErrorActionPreference'
            }
        }
    }

    # What a catch clause must do with the error of an Az command it caught: count it, or end the
    # run (throw, exit), on the path a failure takes.
    #   - Counting is ++ (prefix or postfix) or += on $script:cleanupFailures, the counter every
    #     converted cleanup keeps and exits 1 on, with its scope written out. A plain assignment
    #     (= 0) resets rather than counts, and an unscoped $cleanupFailures++ inside a function
    #     counts a local that the exit never reads. No cleanup has a reporting helper that counts
    #     (a Write-LabError), so none is accepted.
    #   - Test-LabNotFoundError tells a not-found from a failure, and helps only when its answer
    #     decides a branch: a count, throw or exit inside the branch taken for "not found" does not
    #     handle a failure. That branch is the if's body for `if (Test-LabNotFoundError ...)`, and
    #     its else for `if (-not (Test-LabNotFoundError ...))`. So `if (Test-LabNotFoundError $_) {}`
    #     with nothing else, or a catch that counts only the not-found case, is flagged.
    # Read anywhere else in the clause's body, nested blocks included.
    function Test-CatchHandlesError {
        param([Parameter(Mandatory)][System.Management.Automation.Language.StatementBlockAst]$Body)

        $isCounter = {
            param($Node)
            $Node -is [System.Management.Automation.Language.VariableExpressionAst] -and
                $Node.VariablePath.UserPath -eq 'script:cleanupFailures'
        }
        # The blocks that run only for a not-found error.
        $notFoundBranch = [System.Collections.Generic.List[object]]::new()
        foreach ($if in $Body.FindAll({ $args[0] -is [System.Management.Automation.Language.IfStatementAst] }, $true)) {
            foreach ($clause in $if.Clauses) {
                $condition = $clause.Item1
                $decides = $condition.Find({
                    $args[0] -is [System.Management.Automation.Language.CommandAst] -and $args[0].GetCommandName() -eq 'Test-LabNotFoundError'
                }, $true)
                if (-not $decides) { continue }
                $expression = if ($condition -is [System.Management.Automation.Language.PipelineAst] -and $condition.PipelineElements.Count -eq 1 -and
                                  $condition.PipelineElements[0] -is [System.Management.Automation.Language.CommandExpressionAst]) { $condition.PipelineElements[0].Expression }
                $negated = $expression -is [System.Management.Automation.Language.UnaryExpressionAst] -and $expression.TokenKind -in 'Not', 'Exclaim'
                if (-not $negated) { $notFoundBranch.Add($clause.Item2) }
                elseif ($if.ElseClause) { $notFoundBranch.Add($if.ElseClause) }
            }
        }
        $onNotFoundPath = {
            param($Node)
            for ($parent = $Node; $parent; $parent = $parent.Parent) {
                if ($notFoundBranch.Contains($parent)) { return $true }
            }
            return $false
        }

        [bool]$Body.Find({
            param($node)
            $handles = $node -is [System.Management.Automation.Language.ThrowStatementAst] -or
                $node -is [System.Management.Automation.Language.ExitStatementAst] -or
                ($node -is [System.Management.Automation.Language.UnaryExpressionAst] -and
                    $node.TokenKind -in 'PlusPlus', 'PostfixPlusPlus' -and (& $isCounter $node.Child)) -or
                ($node -is [System.Management.Automation.Language.AssignmentStatementAst] -and
                    $node.Operator -eq 'PlusEquals' -and (& $isCounter $node.Left))
            $handles -and -not (& $onNotFoundPath $node)
        }, $true)
    }

    # The reader for catch clauses. Returns one finding per catch clause that catches the error of
    # a *-Az* command and does not handle it (Test-CatchHandlesError). The command's nearest
    # enclosing try is the one whose catch clauses see its error; an inner try that handles it
    # hides it from an outer one. It sees only commands written lexically inside the try block.
    # Not followed: a command in a function body (its caller's try is unknown to the parser); a
    # command in a scriptblock kept in a variable and invoked with & inside the try (Lab 3.3's
    # $steps), which is judged only by the try it is written in, if any; a trap statement, which is
    # not read at all; and a lookup inside Invoke-LabLookup's -Lookup block, whose error
    # Invoke-LabLookup itself handles and counts. Nor Invoke-AzRestMethod: it reports an HTTP
    # failure through StatusCode and throws only when no response came back, so a script routes
    # both through one status check after the call - Lab 3.4 records the error in its catch and
    # counts it there - and that flow is beyond what this reader follows.
    function Find-UnhandledAzCatch {
        [CmdletBinding()]
        param([Parameter(Mandatory)][AllowEmptyString()][string]$Text)

        $ast = [System.Management.Automation.Language.Parser]::ParseInput($Text, [ref]$null, [ref]$null)
        $reported = @{}

        foreach ($command in $ast.FindAll({ $args[0] -is [System.Management.Automation.Language.CommandAst] }, $true)) {
            $name = $command.GetCommandName()
            if (-not $name -or $name -notmatch '^\w+-Az\w' -or $name -eq 'Invoke-AzRestMethod') { continue }

            $try = $null
            $child = $command
            for ($parent = $command.Parent; $parent; $parent = $parent.Parent) {
                if ($parent -is [System.Management.Automation.Language.FunctionDefinitionAst]) { break }
                if ($parent -is [System.Management.Automation.Language.ScriptBlockExpressionAst]) {
                    $owner = $parent.Parent
                    if ($owner -is [System.Management.Automation.Language.CommandParameterAst]) { $owner = $owner.Parent }
                    if ($owner -is [System.Management.Automation.Language.CommandAst] -and $owner.GetCommandName() -eq 'Invoke-LabLookup') { break }
                }
                if ($parent -is [System.Management.Automation.Language.TryStatementAst] -and $child -eq $parent.Body) {
                    $try = $parent
                    break
                }
                $child = $parent
            }
            if (-not $try) { continue }

            foreach ($clause in $try.CatchClauses) {
                $key = $clause.Extent.StartOffset
                if ($reported.ContainsKey($key) -or (Test-CatchHandlesError -Body $clause.Body)) { continue }
                $reported[$key] = $true
                [pscustomobject]@{
                    Line    = $clause.Extent.StartLineNumber
                    Command = $name
                    Text    = ($clause.Extent.Text -split "`r?`n")[0].Trim()
                }
            }
        }
    }
}

Describe 'Lab cleanup lookups - the helpers are there to check' {

    It 'finds every cleanup known to carry the helpers' -ForEach @(@{ files = @($HelperCases.file); expected = $ExpectedHelperFile }) {
        # A discovery that matches less produces Describes that pass by asserting nothing.
        foreach ($file in $expected) {
            $files | Should -Contain $file
        }
    }
}

Describe "Lab cleanup lookups - '<file>'" -ForEach $HelperCases {

    BeforeAll {
        # Lift the helpers with the parser: the script body never runs, so nothing is looked up.
        $parseError = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$null, [ref]$parseError)
        if ($parseError) { throw "$file does not parse: $($parseError[0].Message)" }
        $script:LiftedName = @()
        foreach ($function in $ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $false)) {
            if ($function.Name -notin 'Test-LabNotFoundError', 'Invoke-LabLookup') { continue }
            . ([scriptblock]::Create($function.Extent.Text))
            $script:LiftedName += $function.Name
        }

        # The shape of the SDK exceptions the Az getters raise: a message, plus the ARM error code
        # in Body and the HTTP status in Response (CloudException), in Status (Azure.Core's
        # RequestFailedException) or in ResponseStatusCode (the generated cmdlets' RestException).
        if (-not ('SkyCraftLookupStubAzureException' -as [type])) {
            Add-Type -TypeDefinition @'
public class SkyCraftLookupStubAzureException : System.Exception
{
    public SkyCraftLookupStubAzureException(string message) : base(message) { }
    public object Body { get; set; }
    public object Response { get; set; }
    public int Status { get; set; }
    public object ResponseStatusCode { get; set; }
}
'@
        }

        function Get-LookupErrorFixture {
            param(
                [string]$Message = 'Operation failed.',
                [string]$ErrorId = 'StubError',
                [string]$Code,
                [object]$StatusCode,
                [int]$Status,
                [object]$ResponseStatusCode,
                [switch]$Wrapped
            )
            $exception = [SkyCraftLookupStubAzureException]::new($Message)
            if ($Code) { $exception.Body = [pscustomobject]@{ Code = $Code } }
            if ($null -ne $StatusCode) { $exception.Response = [pscustomobject]@{ StatusCode = $StatusCode } }
            if ($Status) { $exception.Status = $Status }
            if ($null -ne $ResponseStatusCode) { $exception.ResponseStatusCode = $ResponseStatusCode }
            if ($Wrapped) { $exception = [System.Exception]::new('The lookup failed.', $exception) }
            [System.Management.Automation.ErrorRecord]::new($exception, $ErrorId, 'InvalidOperation', $null)
        }

        # What -ErrorAction Stop leaves of an error a generated cmdlet wrote without a usable error
        # id: ActionPreferenceStopException, its message the original one behind a fixed prefix.
        function Get-StopWrappedErrorFixture {
            param([string]$Message)
            $exception = [System.Management.Automation.ActionPreferenceStopException]::new(
                'The running command stopped because the preference variable "ErrorActionPreference" or common parameter is set to Stop: ' + $Message)
            [System.Management.Automation.ErrorRecord]::new($exception, '', 'OperationStopped', $null)
        }
    }

    It 'defines Test-LabNotFoundError and Invoke-LabLookup' {
        $script:LiftedName | Should -Contain 'Test-LabNotFoundError'
        $script:LiftedName | Should -Contain 'Invoke-LabLookup'
    }

    It 'reads <shape> as not found' -ForEach @(
        @{ shape  = 'the ARM ResourceNotFound message'
           record = { Get-LookupErrorFixture -Message "The Resource 'Microsoft.Network/virtualNetworks/prod-skycraft-swc-vnet' under resource group 'prod-skycraft-swc-rg' was not found. For more details please go to https://aka.ms/ARMResourceNotFoundFix" } }
        @{ shape  = 'the ARM ResourceGroupNotFound message (the group is gone too)'
           record = { Get-LookupErrorFixture -Message "Resource group 'platform-skycraft-swc-rg' could not be found." } }
        @{ shape  = 'an empty error body (invalid status code NotFound)'
           record = { Get-LookupErrorFixture -Message "Operation returned an invalid status code 'NotFound'" } }
        @{ shape  = 'the error id of a generated cmdlet'
           record = { Get-LookupErrorFixture -ErrorId 'ResourceNotFound' } }
        @{ shape  = 'the ARM error code in the exception body'
           record = { Get-LookupErrorFixture -Code 'ResourceNotFound' } }
        @{ shape  = 'a 404 HTTP status on the response'
           record = { Get-LookupErrorFixture -StatusCode ([System.Net.HttpStatusCode]::NotFound) } }
        @{ shape  = 'a 404 on a generated cmdlet RestException with no error body'
           record = { Get-LookupErrorFixture -ResponseStatusCode ([System.Net.HttpStatusCode]::NotFound) } }
        @{ shape  = 'the -ErrorAction Stop wrapping of a not-found, with no error id'
           record = { Get-StopWrappedErrorFixture -Message "The Resource 'Microsoft.Network/loadBalancers/dev-skycraft-swc-lb' under resource group 'dev-skycraft-swc-rg' was not found." } }
        @{ shape  = 'an Azure.Core 404 status'
           record = { Get-LookupErrorFixture -Status 404 } }
        @{ shape  = 'the Azure.Core message (Status 404 Not Found)'
           record = { Get-LookupErrorFixture -Message "Service request failed.`nStatus: 404 (Not Found)" } }
        @{ shape  = 'a not-found wrapped as the inner exception'
           record = { Get-LookupErrorFixture -Code 'ResourceGroupNotFound' -Wrapped } }
    ) {
        Test-LabNotFoundError -ErrorRecord (& $record) | Should -BeTrue
    }

    It 'reads <shape> as a failed lookup' -ForEach @(
        @{ shape  = 'a 403 AuthorizationFailed'
           record = { Get-LookupErrorFixture -ErrorId 'AuthorizationFailed' -Code 'AuthorizationFailed' -StatusCode ([System.Net.HttpStatusCode]::Forbidden) -Message "The client 'stub' does not have authorization to perform action 'Microsoft.Network/virtualNetworks/read' over scope '/subscriptions/0' or the scope is invalid." } }
        @{ shape  = 'a 429 throttling response'
           record = { Get-LookupErrorFixture -ErrorId 'TooManyRequests' -Status 429 -Message "Number of 'read' requests for subscription '0' actor 'stub' exceeded. Please try again after '17' seconds." } }
        @{ shape  = 'a 403 on a generated cmdlet RestException'
           record = { Get-LookupErrorFixture -ResponseStatusCode ([System.Net.HttpStatusCode]::Forbidden) } }
        @{ shape  = 'the -ErrorAction Stop wrapping of a 403, with no error id'
           record = { Get-StopWrappedErrorFixture -Message "The client 'stub' with object id '0' does not have authorization to perform action 'Microsoft.Network/dnszones/read' over scope '/subscriptions/0' or the scope is invalid." } }
        @{ shape  = 'a transient transport error'
           record = { Get-LookupErrorFixture -Message 'An error occurred while sending the request.' } }
        @{ shape  = 'a missing subscription, although ARM answers it with 404'
           record = { Get-LookupErrorFixture -Code 'SubscriptionNotFound' -StatusCode ([System.Net.HttpStatusCode]::NotFound) -Message "The subscription '00000000-0000-0000-0000-000000000000' could not be found." } }
    ) {
        Test-LabNotFoundError -ErrorRecord (& $record) | Should -BeFalse
    }

    Context 'Invoke-LabLookup' {

        BeforeEach { $script:cleanupFailures = 0 }

        It 'returns what a lookup found' {
            $result = Invoke-LabLookup -Target 'stub' -Lookup { 'first'; 'second' }
            $result.Value    | Should -Be @('first', 'second')
            $result.Failed   | Should -BeFalse
            $result.NotFound | Should -BeFalse
            $script:cleanupFailures | Should -Be 0
        }

        It 'reads a lookup that succeeds and finds nothing as absent, without counting it' {
            $result = Invoke-LabLookup -Target 'stub' -Lookup { }
            @($result.Value).Count | Should -Be 0
            $result.NotFound | Should -BeFalse
            $result.Failed   | Should -BeFalse
            $script:cleanupFailures | Should -Be 0
        }

        It 'reads a not-found error as absent, without counting it' {
            $result = Invoke-LabLookup -Target 'stub' -Lookup {
                Write-Error -ErrorId 'ResourceNotFound' -ErrorAction Stop -Message "The Resource 'Microsoft.Network/virtualNetworks/dev-skycraft-swc-vnet' under resource group 'dev-skycraft-swc-rg' was not found."
            }
            $result.NotFound | Should -BeTrue
            $result.Failed   | Should -BeFalse
            $script:cleanupFailures | Should -Be 0
        }

        It 'counts any other error as a failed lookup, and says it is not "absent"' {
            # 6>&1 merges the Write-Host lines (the information stream) into the output, so the
            # result object is the one record that carries a Failed property.
            $output = @(Invoke-LabLookup -Target 'stub' -Lookup {
                Write-Error -ErrorId 'AuthorizationFailed' -ErrorAction Stop -Message "The client 'stub' does not have authorization to perform action 'read'."
            } 6>&1)
            $lines  = @($output | Where-Object { $_.PSObject.Properties.Name -notcontains 'Failed' } | ForEach-Object { "$_" })
            $result = @($output | Where-Object { $_.PSObject.Properties.Name -contains 'Failed' })[0]
            $result.Failed   | Should -BeTrue
            $result.NotFound | Should -BeFalse
            @($result.Value).Count | Should -Be 0
            $script:cleanupFailures | Should -Be 1
            ($lines -join "`n") | Should -Match '\[ERROR\] Could not look up stub: [^\r\n]*does not have authorization'
        }
    }
}

Describe 'Lab cleanup lookups - the ratchet reads every way to silence a lookup' {

    It 'flags <case>' -ForEach @(
        @{ case = 'the plain form';                 text = 'Get-AzVM -Name x -ErrorAction SilentlyContinue' }
        @{ case = 'the colon form';                 text = 'Get-AzVM -Name x -ErrorAction:SilentlyContinue' }
        @{ case = 'the EA alias with Ignore';       text = 'Get-AzVM -Name x -EA Ignore' }
        @{ case = 'an unambiguous prefix';          text = 'Get-AzVM -Name x -ErrorAct SilentlyContinue' }
        @{ case = 'a quoted value';                 text = "Get-AzVM -Name x -ErrorAction 'SilentlyContinue'" }
        @{ case = 'the number of SilentlyContinue'; text = 'Get-AzVM -Name x -ErrorAction 0' }
        @{ case = 'the ActionPreference enum';      text = 'Get-AzVM -ErrorAction ([System.Management.Automation.ActionPreference]::Ignore)' }
        @{ case = 'any verb';                       text = 'New-AzResourceGroup -Name x -Location y -ErrorAction SilentlyContinue' }
        @{ case = 'a backtick continuation';        text = (@('Get-AzVM -Name x `', '    -ErrorAction SilentlyContinue') -join "`n") }
        @{ case = 'a splatted hashtable literal';   text = (@('$query = @{ Name = ''x''; ErrorAction = ''SilentlyContinue'' }', 'Get-AzVM @query') -join "`n") }
        @{ case = 'a splat key set afterwards';     text = (@('$query = @{ Name = ''x'' }', '$query.ErrorAction = ''Ignore''', 'Get-AzVM @query') -join "`n") }
        @{ case = 'a splat key set by index';       text = (@('$query = @{ Name = ''x'' }', '$query[''EA''] = ''SilentlyContinue''', 'Get-AzVM @query') -join "`n") }
        @{ case = 'a lookup nested in an expression'; text = 'if (Get-AzVM -Name x -ErrorAction SilentlyContinue) { }' }
    ) {
        @(Find-SilencedAzCommand -Text $text).Count | Should -Be 1
    }

    It 'does not flag <case>' -ForEach @(
        @{ case = 'a comment';                       text = '# Get-AzVM -ErrorAction SilentlyContinue' }
        @{ case = 'a string';                        text = "Write-Host 'Get-AzVM -ErrorAction SilentlyContinue'" }
        @{ case = '-ErrorAction Stop';               text = 'Get-AzVM -Name x -ErrorAction Stop' }
        @{ case = 'a command that is not Az';        text = 'Remove-Item x -ErrorAction SilentlyContinue' }
        @{ case = 'a splat that stops on error';     text = (@('$query = @{ ErrorAction = ''Stop'' }', 'Get-AzVM @query') -join "`n") }
        @{ case = '-ErrorVariable';                  text = 'Get-AzVM -Name x -ErrorVariable SilentlyContinue' }
    ) {
        @(Find-SilencedAzCommand -Text $text).Count | Should -Be 0
    }
}

Describe 'Lab cleanup lookups - the ratchet reads a preference that silences every command' {

    It 'flags <case>' -ForEach @(
        @{ case = '$ErrorActionPreference, quoted';          text = '$ErrorActionPreference = ''SilentlyContinue''' }
        @{ case = '$ErrorActionPreference at global scope';  text = '$global:ErrorActionPreference = ''Ignore''' }
        @{ case = '$ErrorActionPreference by number';        text = '$script:ErrorActionPreference = 0' }
        @{ case = '${ErrorActionPreference} and the enum';   text = '${ErrorActionPreference} = [System.Management.Automation.ActionPreference]::SilentlyContinue' }
        @{ case = '$ErrorActionPreference in a function';    text = 'function Find-It { $ErrorActionPreference = ''SilentlyContinue''; Get-AzVM -Name x }' }
        @{ case = '$ErrorActionPreference in a scriptblock'; text = '$lookup = { $ErrorActionPreference = ''Ignore''; Get-AzVM -Name x }' }
        @{ case = 'Set-Variable by name';                    text = 'Set-Variable -Name ErrorActionPreference -Value SilentlyContinue' }
        @{ case = 'Set-Variable by position';                text = 'Set-Variable ErrorActionPreference Ignore -Scope Global' }
        @{ case = 'a default for every command';             text = '$PSDefaultParameterValues[''*:ErrorAction''] = ''SilentlyContinue''' }
        @{ case = 'a default for every Az command';          text = '$PSDefaultParameterValues[''*-Az*:ErrorAction''] = ''Ignore''' }
        @{ case = 'a default by the EA alias, global';       text = '$global:PSDefaultParameterValues[''Get-Az*:EA''] = ''SilentlyContinue''' }
        @{ case = 'a default for every getter, as a member'; text = '$PSDefaultParameterValues.''Get-*:ErrorAction'' = ''SilentlyContinue''' }
        @{ case = 'a default for one Az command';            text = '$PSDefaultParameterValues[''Get-AzVM:ErrorAction''] = 4' }
        @{ case = 'a hashtable literal assigned';            text = '$PSDefaultParameterValues = @{ ''*:ErrorAction'' = ''SilentlyContinue'' }' }
        @{ case = 'a hashtable literal added';               text = '$PSDefaultParameterValues += @{ ''Remove-Az*:ErrorAction'' = ''Ignore'' }' }
        @{ case = 'the Add method';                          text = '$PSDefaultParameterValues.Add(''*:ErrorAction'', ''SilentlyContinue'')' }
    ) {
        @(Find-SilencingPreference -Text $text).Count | Should -Be 1
    }

    It 'does not flag <case>' -ForEach @(
        @{ case = '$ErrorActionPreference = Stop';          text = '$ErrorActionPreference = ''Stop''' }
        @{ case = '$ErrorActionPreference = Continue';      text = '$ErrorActionPreference = ''Continue''' }
        @{ case = 'another preference';                     text = '$WarningPreference = ''SilentlyContinue''' }
        @{ case = 'another variable';                       text = '$preference = ''SilentlyContinue''' }
        @{ case = 'a comment';                              text = '# $ErrorActionPreference = ''SilentlyContinue''' }
        @{ case = 'a string';                               text = 'Write-Host ''$PSDefaultParameterValues["*:ErrorAction"] = "Ignore"''' }
        @{ case = 'Set-Variable on another variable';       text = 'Set-Variable -Name other -Value SilentlyContinue' }
        @{ case = 'a default that stops';                   text = '$PSDefaultParameterValues[''*:ErrorAction''] = ''Stop''' }
        @{ case = 'a default for a command that is not Az'; text = '$PSDefaultParameterValues[''Remove-Item:ErrorAction''] = ''SilentlyContinue''' }
        @{ case = 'a default for another parameter';        text = '$PSDefaultParameterValues[''*:ErrorVariable''] = ''SilentlyContinue''' }
        @{ case = 'a hashtable without the key';            text = '$PSDefaultParameterValues = @{ ''*:Verbose'' = ''SilentlyContinue'' }' }
    ) {
        @(Find-SilencingPreference -Text $text).Count | Should -Be 0
    }
}

Describe 'Lab cleanup lookups - the ratchet reads a catch that swallows an Az error' {

    It 'flags <case>' -ForEach @(
        @{ case = 'a failed delete read as "may not exist" (Lab 3.1 before #297)'
           text = 'try { Remove-AzResourceGroup -Name x -Force -ErrorAction Stop } catch { Write-Host "[FAIL] Could not delete x. It may not exist." }' }
        @{ case = 'any error read as "not found" (Lab 4.4 before #297)'
           text = 'try { $sa = Get-AzStorageAccount -Name x -ErrorAction Stop } catch { Write-Host "[INFO] Container not found or already removed." }' }
        @{ case = 'an error turned into a local flag'
           text = 'try { Get-AzVM -Name x -ErrorAction Stop } catch { $found = $false }' }
        @{ case = 'a typed catch clause'
           text = 'try { Get-AzVM -Name x -ErrorAction Stop } catch [System.Exception] { Write-Warning "$_" }' }
        @{ case = 'the one clause of two that does not count'
           text = 'try { Get-AzVM -Name x -ErrorAction Stop } catch [System.Net.WebException] { $script:cleanupFailures++ } catch { Write-Host "$_" }' }
        @{ case = 'a lookup nested in a block inside the try'
           text = 'try { if ($x) { foreach ($n in $names) { Get-AzVM -Name $n -ErrorAction Stop } } } catch { }' }
        @{ case = 'a lookup in a pipeline block inside the try'
           text = 'try { $names | ForEach-Object { Get-AzVM -Name $_ -ErrorAction Stop } } catch { Write-Host "$_" }' }
        @{ case = 'a counter that is not the cleanup''s'
           text = 'try { Get-AzVM -Name x -ErrorAction Stop } catch { $failures++ }' }
        @{ case = 'several Az commands in one try, reported once'
           text = 'try { Get-AzVM -Name x -ErrorAction Stop; Remove-AzVM -Name x -Force -ErrorAction Stop } catch { Write-Host "$_" }' }
        @{ case = 'a failed change printed and not counted (Lab 4.4''s firewall revert before #297)'
           text = 'try { Update-AzStorageAccountNetworkRuleSet -Name x -DefaultAction Allow -ErrorAction Stop } catch { Write-Host "[ERROR] Failed to revert firewall." }' }
        @{ case = 'Test-LabNotFoundError deciding nothing'
           text = 'try { Get-AzVM -Name x -ErrorAction Stop } catch { if (Test-LabNotFoundError -ErrorRecord $_) { } }' }
        @{ case = 'a count only on the not-found branch'
           text = 'try { Get-AzVM -Name x -ErrorAction Stop } catch { if (Test-LabNotFoundError -ErrorRecord $_) { $script:cleanupFailures++ } }' }
        @{ case = 'a count only on the not-found branch of a negated test'
           text = 'try { Get-AzVM -Name x -ErrorAction Stop } catch { if (-not (Test-LabNotFoundError -ErrorRecord $_)) { Write-Host "$_" } else { $script:cleanupFailures++ } }' }
        @{ case = 'a failure branch that only warns'
           text = 'try { Get-AzVM -Name x -ErrorAction Stop } catch { if (-not (Test-LabNotFoundError -ErrorRecord $_)) { Write-Host "[WARN] $_" } }' }
        @{ case = 'an if expression whose failure branch only yields $null'
           text = 'try { $x = Get-AzResource -ResourceId $id -ErrorAction Stop } catch { $x = if (Test-LabNotFoundError -ErrorRecord $_) { $false } else { $null } }' }
        @{ case = 'a plain assignment to the counter, which resets it'
           text = 'try { Get-AzVM -Name x -ErrorAction Stop } catch { $script:cleanupFailures = 0 }' }
        @{ case = 'an unscoped counter in a function, which is a local'
           text = 'function Remove-It { try { Remove-AzVM -Name x -Force -ErrorAction Stop } catch { $cleanupFailures++ } }' }
    ) {
        @(Find-UnhandledAzCatch -Text $text).Count | Should -Be 1
    }

    It 'does not flag <case>' -ForEach @(
        @{ case = 'a negated Test-LabNotFoundError whose branch counts'
           text = 'try { Get-AzVM -Name x -ErrorAction Stop } catch { if (-not (Test-LabNotFoundError -ErrorRecord $_)) { $script:cleanupFailures++; Write-Host "[ERROR] $_" } }' }
        @{ case = 'Test-LabNotFoundError whose else branch counts'
           text = 'try { Get-AzVM -Name x -ErrorAction Stop } catch { if (Test-LabNotFoundError -ErrorRecord $_) { $gone = $true } else { $script:cleanupFailures++ } }' }
        @{ case = 'Test-LabNotFoundError that returns, then a count for the rest'
           text = 'try { Get-AzVM -Name x -ErrorAction Stop } catch { if (Test-LabNotFoundError -ErrorRecord $_) { return }; $script:cleanupFailures++ }' }
        @{ case = 'a negated Test-LabNotFoundError whose branch throws'
           text = 'try { Get-AzVM -Name x -ErrorAction Stop } catch { if (-not (Test-LabNotFoundError -ErrorRecord $_)) { throw } }' }
        @{ case = 'a catch that counts with ++'
           text = 'try { Remove-AzVM -Name x -Force -ErrorAction Stop } catch { $script:cleanupFailures++; Write-Host "[ERROR] $_" }' }
        @{ case = 'a catch that counts with a prefix ++'
           text = 'try { Remove-AzVM -Name x -Force -ErrorAction Stop } catch { ++$script:cleanupFailures }' }
        @{ case = 'a catch that counts with +='
           text = 'try { Remove-AzVM -Name x -Force -ErrorAction Stop } catch { $script:cleanupFailures += 1 }' }
        @{ case = 'a catch that counts in a nested block'
           text = 'try { Remove-AzVM -Name x -Force -ErrorAction Stop } catch { if ($_) { $script:cleanupFailures++ } }' }
        @{ case = 'a catch that throws'
           text = 'try { Get-AzVM -Name x -ErrorAction Stop } catch { throw }' }
        @{ case = 'a catch that exits'
           text = 'try { Get-AzVM -Name x -ErrorAction Stop } catch { $Host.SetShouldExit(1); exit 1 }' }
        @{ case = 'a try around a command that is not Az'
           text = 'try { Remove-Item x -ErrorAction Stop } catch { }' }
        @{ case = 'a lookup inside Invoke-LabLookup, which counts it'
           text = 'try { $r = Invoke-LabLookup -Target x -Lookup { Get-AzVM -Name x -ErrorAction Stop } } catch { Write-Host "$_" }' }
        @{ case = 'an inner try that handles the error'
           text = 'try { try { Get-AzVM -Name x -ErrorAction Stop } catch { $script:cleanupFailures++ } } catch { Write-Host "$_" }' }
        @{ case = 'Invoke-AzRestMethod, whose failure is checked after the call'
           text = 'try { $response = Invoke-AzRestMethod -Method DELETE -Path $p -ErrorAction Stop } catch { $problem = "no response: $_" }' }
        @{ case = 'a try with only a finally'
           text = 'try { Get-AzVM -Name x -ErrorAction Stop } finally { Write-Host done }' }
        @{ case = 'a comment'
           text = '# try { Get-AzVM -Name x } catch { }' }
    ) {
        @(Find-UnhandledAzCatch -Text $text).Count | Should -Be 0
    }
}

Describe 'Lab cleanup lookups - no cleanup reads a failed lookup as "absent"' {

    It 'checks every cleanup discovery found' -ForEach @(@{ count = $RatchetCases.Count; expected = $ExpectedHelperFile.Count }) {
        # A discovery that matches less checks less and still passes.
        $count | Should -BeGreaterOrEqual $expected
    }

    It "'<file>' gives no *-Az* command -ErrorAction SilentlyContinue or Ignore" -ForEach ($RatchetCases + $ToolRatchetCases) {
        $hits = @(Find-SilencedAzCommand -Text (Get-Content -Raw -LiteralPath $path) |
            ForEach-Object { "line $($_.Line): $($_.Text)" })
        $hits | Should -BeNullOrEmpty -Because "a lookup that fails would read as 'absent'; route it through Invoke-LabLookup (#255, #290)"
    }

    It "'<file>' does not silence every command through `$ErrorActionPreference or `$PSDefaultParameterValues" -ForEach ($RatchetCases + $ToolRatchetCases) {
        $hits = @(Find-SilencingPreference -Text (Get-Content -Raw -LiteralPath $path) |
            ForEach-Object { "line $($_.Line): $($_.Text)" })
        $hits | Should -BeNullOrEmpty -Because "a preference silences every lookup at once, and each one that fails reads as 'absent' (#290)"
    }

    It "'<file>' has no catch clause that swallows the error of an Az command" -ForEach $RatchetCases {
        $findings = @(Find-UnhandledAzCatch -Text (Get-Content -Raw -LiteralPath $path))
        $hits = foreach ($group in ($findings | Group-Object Command)) {
            $budget = [int](@($allowed | Where-Object { $_.command -eq $group.Name } | ForEach-Object { $_.count }) | Measure-Object -Sum).Sum
            $group.Group | Select-Object -Skip $budget | ForEach-Object { "line $($_.Line): $($_.Text) (catches $($_.Command))" }
        }
        @($hits) | Should -BeNullOrEmpty -Because "a catch that neither counts the error nor throws or exits on the path a failure takes reads a failure as 'not there' (#290)"
    }
}

Describe 'Lab cleanup lookups - the diagnostic catches the catch rule allows are still there' {

    It "'<file>' still catches <command> in <count> diagnostic catch clause(s)" -ForEach $DiagnosticCases {
        # An entry whose catch is gone, or was made to count, would excuse the next one written.
        Test-Path -LiteralPath $path | Should -BeTrue
        $found = @(Find-UnhandledAzCatch -Text (Get-Content -Raw -LiteralPath $path) | Where-Object { $_.Command -eq $command })
        $found.Count | Should -Be $count -Because "remove or correct the `$DiagnosticCatch entry: $why"
    }
}

<#
.SYNOPSIS
    Pester 5 test: a lab script's exit code reaches its caller, and a learner's session stays open.

.DESCRIPTION
    Regression guard for issues #104 and #257.

    #104: PowerShell 7 drops the exit code of a script that is run as `pwsh -File` when that
    script declares `#Requires -Modules` for a module it has to auto-import - Az.Accounts
    qualifies. The `exit <code>` statement still unwinds the script, but the host never applies
    the code, so the process exits 0 and the automated lab cycle reads a failed run as clean.
    `$Host.SetShouldExit(<code>)` before the `exit` carries the code out.

    #257: `$Host.SetShouldExit` asks the host to end the whole process. Called from a script the
    learner ran at the prompt (a lab's validator, as the guides say), it closes their
    PowerShell window - even with code 0, after a passing run.

    Every lab script therefore ends through Exit-Lab (tools/LabCommon.psm1): exit 1 when the
    failure count is above zero, 0 otherwise, with $Host.SetShouldExit only when the script is
    the entry point of a `pwsh -File` process. This file enforces that contract:

      - structurally, over every lab script (module-*/**/scripts/*.ps1 and scripts/*.ps1): no
        direct $Host.SetShouldExit, no non-zero `exit` (`exit $failCount` included, which wraps
        to 0 at 256 failures), and every lab script calls Exit-Lab and imports the module by a
        path relative to $PSScriptRoot that resolves to tools/LabCommon.psm1, before the first
        call. A script that never calls Exit-Lab exits 0 after printing [FAIL] (#104, #241), so
        the only lab scripts excused are the helpers listed in $DotSourcedHelpers, which other
        lab scripts dot-source and which end nothing themselves - the suite holds them to that;
      - the successful run too: a lab script's last top-level statement is an Exit-Lab call or an
        `exit`. One that falls off its end after a closing Write-Host, a try or an if leaves
        $LASTEXITCODE as the previous command set it, so a passing re-run reads 1 (#398);
      - the failure paths too: a lab script that sets $ErrorActionPreference to 'Stop' calls no
        Write-Error outside a function. Under Stop it ends the script before the Exit-Lab after
        it, so at the prompt a failed run leaves the previous run's $LASTEXITCODE (#398);
      - those two #398 rules only for the lab folders listed in $ConvertedLabs, which each
        module's pull request extends as it converts its scripts; a listed folder that does not
        exist, or holds no lab script, fails the suite;
      - for the entry-point decision, every command-line shape it has to tell apart;
      - behaviourally, with real pwsh processes and no Azure: `pwsh -File` returns 1 for a failed
        run and takes the SetShouldExit branch, an interactive session keeps running after the
        script with $LASTEXITCODE 1, and `-Command` and the lab cycle's launcher shim
        (tools/Invoke-LabScript.ps1) see 1 too through a plain `exit`.

    WHAT CI PROVES, AND WHAT ONLY A LOCAL RUN DOES. The #104 fault needs a module that has to be
    auto-imported from the module path; Az.Accounts qualifies, and a dummy module next to the
    fixture does not reproduce it. The CI runner has no Az.Accounts, so the test that shows a
    `pwsh -File` run would lose its code without SetShouldExit is skipped there. CI still proves
    the decision Exit-Lab makes in each real process - Exit-Lab says with -Verbose which branch it
    took - so a broken entry-point detection fails CI; that SetShouldExit is what carries the code
    out under #104 is proven only where Az.Accounts is installed (the maintainer's machine).

    THE TOOLS KEEP THE OLD RULE (#124). The maintainer tools under tools/ are process entry points
    with exit codes above 1 (the lab cycle reports a count), not lab scripts. A tools script that
    declares `#Requires -Modules` must still precede every non-zero `exit` with a matching
    $Host.SetShouldExit; today none declares one, and tools/Invoke-LabScript.ps1 exists to be the
    one process with no module requirement (tests/LabCycle.Tests.ps1 holds it to that).

.EXAMPLE
    Invoke-Pester -Path .\tests\Exit-Code-Propagation.Tests.ps1

.NOTES
    Project: SkyCraft
#>

#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

$RepoRoot      = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$LabCommonPath = Join-Path $RepoRoot 'tools/LabCommon.psm1'

# Whether the #104 fault can reach a script at all: it needs a module to auto-import. Read from
# the parsed requirements rather than matched with a regex, so that a '#Requires' line quoted in
# the help block is not mistaken for a declaration.
function Test-RequiresModule {
    param([string]$Text)

    $ast = [System.Management.Automation.Language.Parser]::ParseInput($Text, [ref]$null, [ref]$null)
    $requirements = $ast.ScriptRequirements

    return ($null -ne $requirements -and @($requirements.RequiredModules).Count -gt 0)
}

# Every non-zero `exit` site in a tools script, with the statement that precedes it. Parsed
# rather than regex-matched so that `exit` inside a string or a comment is not counted.
function Get-ExitSite {
    param([string]$Text)

    $ast = [System.Management.Automation.Language.Parser]::ParseInput($Text, [ref]$null, [ref]$null)

    foreach ($exit in $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.ExitStatementAst] }, $true)) {

        $code = if ($exit.Pipeline) { $exit.Pipeline.Extent.Text.Trim() } else { '0' }
        if ($code -eq '0') { continue }

        $statements = @($exit.Parent.Statements)
        $index = -1
        for ($i = 0; $i -lt $statements.Count; $i++) {
            if ($statements[$i].Extent.StartOffset -eq $exit.Extent.StartOffset) { $index = $i; break }
        }

        $previous = if ($index -gt 0) { $statements[$index - 1].Extent.Text.Trim() } else { '' }

        [PSCustomObject]@{
            Line     = $exit.Extent.StartLineNumber
            Code     = $code
            Previous = $previous
        }
    }
}

# How a lab script ends, read from its syntax tree: direct $Host.SetShouldExit calls, non-zero
# exits, Exit-Lab calls and the LabCommon import. -ScriptDirectory resolves the import path the
# way $PSScriptRoot would at run time.
function Get-LabExitShape {
    param(
        [Parameter(Mandatory)][string]$Text,
        [Parameter(Mandatory)][string]$ScriptDirectory
    )

    $ast = [System.Management.Automation.Language.Parser]::ParseInput($Text, [ref]$null, [ref]$null)

    $setShouldExit = @($ast.FindAll({ param($n)
        $n -is [System.Management.Automation.Language.InvokeMemberExpressionAst] -and
        $n.Member.Extent.Text -eq 'SetShouldExit'
    }, $true) | ForEach-Object { "line $($_.Extent.StartLineNumber): $($_.Extent.Text)" })

    $exits = @($ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.ExitStatementAst] }, $true))

    $nonZeroExit = @($exits |
        Where-Object { $_.Pipeline -and $_.Pipeline.Extent.Text.Trim() -ne '0' } |
        ForEach-Object { "line $($_.Extent.StartLineNumber): $($_.Extent.Text)" })

    $exitLab = @($ast.FindAll({ param($n)
        $n -is [System.Management.Automation.Language.CommandAst] -and $n.GetCommandName() -eq 'Exit-Lab'
    }, $true))

    $import = @($ast.FindAll({ param($n)
        $n -is [System.Management.Automation.Language.CommandAst] -and $n.GetCommandName() -eq 'Import-Module' -and
        $n.Extent.Text -match 'LabCommon\.psm1'
    }, $true)) | Select-Object -First 1

    # The path the import names, with $PSScriptRoot standing for the script's own directory.
    $resolved = $null
    if ($import -and $import.Extent.Text -match "Join-Path \`$PSScriptRoot '(?<relative>[^']+)'") {
        $resolved = [System.IO.Path]::GetFullPath((Join-Path $ScriptDirectory $Matches['relative']))
    }

    # The statement a run ends on when nothing exited earlier (#398). A try or an if whose
    # branches all exit does not count: the rule is the plain last statement.
    $endStatements = if ($ast.EndBlock) { @($ast.EndBlock.Statements) } else { @() }
    $last = if ($endStatements.Count) { $endStatements[-1] } else { $null }
    $endsThroughExit = $last -is [System.Management.Automation.Language.ExitStatementAst] -or (
        $last -is [System.Management.Automation.Language.PipelineAst] -and
        $last.PipelineElements.Count -eq 1 -and
        $last.PipelineElements[0] -is [System.Management.Automation.Language.CommandAst] -and
        $last.PipelineElements[0].GetCommandName() -eq 'Exit-Lab')

    # Write-Error outside a function under a script-level 'Stop' preference (#398). One with its
    # own -ErrorAction does not terminate on the preference.
    $inFunction = {
        param($node)
        for ($p = $node.Parent; $p; $p = $p.Parent) {
            if ($p -is [System.Management.Automation.Language.FunctionDefinitionAst]) { return $true }
        }
        return $false
    }
    $stopPreference = @($ast.FindAll({ param($n)
        $n -is [System.Management.Automation.Language.AssignmentStatementAst] -and
        $n.Left -is [System.Management.Automation.Language.VariableExpressionAst] -and
        $n.Left.VariablePath.UserPath -match '^((script|global):)?ErrorActionPreference$' -and
        $n.Right.Extent.Text -match '\bStop\b'
    }, $true) | Where-Object { -not (& $inFunction $_) }).Count -gt 0
    $writeError = @($ast.FindAll({ param($n)
        $n -is [System.Management.Automation.Language.CommandAst] -and $n.GetCommandName() -eq 'Write-Error' -and
        -not ($n.CommandElements | Where-Object {
            $_ -is [System.Management.Automation.Language.CommandParameterAst] -and $_.ParameterName -match '^(ErrorAction|ea)$'
        })
    }, $true) | Where-Object { -not (& $inFunction $_) } |
        ForEach-Object { "line $($_.Extent.StartLineNumber): $($_.Extent.Text)" })

    [PSCustomObject]@{
        EndsThroughExit = $endsThroughExit
        StopWriteError = if ($stopPreference) { $writeError } else { @() }
        LastStatement  = if ($last) { "line $($last.Extent.StartLineNumber): $(($last.Extent.Text -split '\r?\n')[0].Trim())" } else { '' }
        SetShouldExit  = $setShouldExit
        NonZeroExit    = $nonZeroExit
        ExitCount      = $exits.Count
        ExitLabCount   = $exitLab.Count
        FirstExitLabAt = if ($exitLab.Count) { ($exitLab | Measure-Object -Property { $_.Extent.StartOffset } -Minimum).Minimum } else { $null }
        ImportAt       = if ($import) { $import.Extent.StartOffset } else { $null }
        ImportPath     = $resolved
    }
}

# Lab scripts: module directories first, then recurse - `Get-ChildItem -Path 'module-*' -Recurse
# -File -Filter` returns nothing on pwsh 7.6 - plus the repository-level scripts/ (the resource
# audit, run at the prompt like a lab script).
$LabScriptFiles = @(
    Get-ChildItem -LiteralPath $RepoRoot -Directory -Filter 'module-*' |
        ForEach-Object { Get-ChildItem -LiteralPath $_.FullName -Recurse -File -Filter '*.ps1' } |
        Where-Object { $_.Directory.Name -eq 'scripts' }
    Get-ChildItem -LiteralPath (Join-Path $RepoRoot 'scripts') -File -Filter '*.ps1'
)

# The lab scripts that are not run on their own but dot-sourced by the other scripts of their
# lab, so they share one function definition. They end nothing: the script that dot-sources
# them calls Exit-Lab. Each entry is held to that below, so the list cannot hide a lab script.
$DotSourcedHelpers = @(
    'module-1-identities-governance/1.3-governance/scripts/LabPolicyAssignment.ps1'
)

$LabCases = foreach ($item in $LabScriptFiles) {
    $text  = Get-Content -Raw -LiteralPath $item.FullName
    $shape = Get-LabExitShape -Text $text -ScriptDirectory $item.DirectoryName
    $file  = $item.FullName.Substring($RepoRoot.Length + 1) -replace '\\', '/'
    @{
        file           = $file
        name           = $item.Name
        directory      = $item.DirectoryName
        helper         = $file -in $DotSourcedHelpers
        setShouldExit  = $shape.SetShouldExit
        nonZeroExit    = $shape.NonZeroExit
        exitCount      = $shape.ExitCount
        exitLabCount   = $shape.ExitLabCount
        firstExitLabAt = $shape.FirstExitLabAt
        importAt       = $shape.ImportAt
        importPath     = $shape.ImportPath
        labCommonPath  = $LabCommonPath
        endsThroughExit = $shape.EndsThroughExit
        lastStatement  = $shape.LastStatement
        stopWriteError = $shape.StopWriteError
    }
}
$EntryLabCases = @($LabCases | Where-Object { -not $_.helper })

# Lab folders held to the #398 rules (last statement, Write-Error under Stop). Each module's pull
# request adds its folders when it converts their scripts, until the list covers every lab.
$ConvertedLabs = @(
    'module-1-identities-governance/1.1-entra-users-groups'
    'module-1-identities-governance/1.2-rbac'
    'module-1-identities-governance/1.3-governance'
)

function Test-ConvertedLabScript {
    param(
        [Parameter(Mandatory)][string]$File,
        [string[]]$ConvertedLabs
    )

    foreach ($lab in $ConvertedLabs) {
        if ($File.StartsWith("$($lab.TrimEnd('/'))/scripts/", [System.StringComparison]::Ordinal)) { return $true }
    }
    return $false
}

$ConvertedLabCases      = @($LabCases | Where-Object { Test-ConvertedLabScript -File $_.file -ConvertedLabs $ConvertedLabs })
$ConvertedEntryLabCases = @($ConvertedLabCases | Where-Object { -not $_.helper })
$ConvertedLabFolderCases = @($ConvertedLabs | ForEach-Object {
    $lab = $_
    @{
        lab         = $lab
        exists      = Test-Path -LiteralPath (Join-Path $RepoRoot $lab) -PathType Container
        entryScripts = @($ConvertedEntryLabCases | Where-Object { Test-ConvertedLabScript -File $_.file -ConvertedLabs @($lab) }).Count
    }
})
$HelperCases   = @($DotSourcedHelpers | ForEach-Object {
    $entry = $_
    $case  = $LabCases | Where-Object { $_.file -eq $entry } | Select-Object -First 1
    $dotSource = if ($case) { '\.\s*\(Join-Path \$PSScriptRoot ''' + [regex]::Escape($case.name) + '''\)' }
    @{
        file         = $entry
        found        = [bool]$case
        exitCount    = if ($case) { $case.exitCount } else { $null }
        exitLabCount = if ($case) { $case.exitLabCount } else { $null }
        dotSourcedBy = @(if ($case) {
            Get-ChildItem -LiteralPath $case.directory -File -Filter '*.ps1' |
                Where-Object { $_.Name -ne $case.name -and (Get-Content -Raw -LiteralPath $_.FullName) -match $dotSource } |
                ForEach-Object Name
        })
    }
})

# Tools that declare a module requirement keep the #104 guard. None does today, so the per-site
# test below generates no case; the reader it relies on is held to its fixtures instead.
$ToolScriptFiles = @(Get-ChildItem -LiteralPath (Join-Path $RepoRoot 'tools') -File -Filter '*.ps1')
$ToolExitCases = $ToolScriptFiles |
    Where-Object { Test-RequiresModule -Text (Get-Content -Raw -LiteralPath $_.FullName) } |
    ForEach-Object {
        $file = $_.FullName.Substring($RepoRoot.Length + 1) -replace '\\', '/'
        foreach ($site in Get-ExitSite -Text (Get-Content -Raw -LiteralPath $_.FullName)) {
            @{ file = $file; line = $site.Line; code = $site.Code; previous = $site.Previous }
        }
    }

$ExitSiteFixtures = @(
    @{ name = 'a guarded exit carries its guard'
       sites = @(Get-ExitSite -Text "Write-Host x`n`$Host.SetShouldExit(2)`nexit 2")
       expected = @{ count = 1; code = '2'; previous = '$Host.SetShouldExit(2)' } }
    @{ name = 'an unguarded exit carries the statement before it'
       sites = @(Get-ExitSite -Text "Write-Host x`nexit 3")
       expected = @{ count = 1; code = '3'; previous = 'Write-Host x' } }
    @{ name = 'exit 0 and a bare exit are not sites'
       sites = @(Get-ExitSite -Text "exit 0`nexit")
       expected = @{ count = 0 } }
)

# Fixtures that hold the structural rule to failing what it is there to fail.
$FixtureDirectory = Join-Path $RepoRoot 'module-0-fixture/0.1-fixture/scripts'
$FixtureImport    = "Import-Module (Join-Path `$PSScriptRoot '../../../tools/LabCommon.psm1') -Force -Verbose:`$false"
$FixtureCases = @(
    @{ name = 'the #104 idiom is a direct SetShouldExit'
       shape = Get-LabExitShape -ScriptDirectory $FixtureDirectory -Text "`$Host.SetShouldExit(1)`nexit 1"
       property = 'SetShouldExit'; expected = 1 }
    @{ name = 'the #104 idiom is a non-zero exit'
       shape = Get-LabExitShape -ScriptDirectory $FixtureDirectory -Text "`$Host.SetShouldExit(1)`nexit 1"
       property = 'NonZeroExit'; expected = 1 }
    @{ name = 'exit $failCount is a non-zero exit'
       shape = Get-LabExitShape -ScriptDirectory $FixtureDirectory -Text 'exit $failCount'
       property = 'NonZeroExit'; expected = 1 }
    @{ name = 'exit 0 is not a non-zero exit'
       shape = Get-LabExitShape -ScriptDirectory $FixtureDirectory -Text 'exit 0'
       property = 'NonZeroExit'; expected = 0 }
    @{ name = 'SetShouldExit quoted in a comment is not a call'
       shape = Get-LabExitShape -ScriptDirectory $FixtureDirectory -Text "# `$Host.SetShouldExit(1)`nExit-Lab -FailureCount 1"
       property = 'SetShouldExit'; expected = 0 }
)

$ImportFixtures = @(
    @{ name = 'a script that prints [FAIL] and falls off the end calls no Exit-Lab and imports nothing'
       shape = Get-LabExitShape -ScriptDirectory $FixtureDirectory -Text "`$failCount = 1`nWrite-Host '[FAIL] x'"
       check = { param($s) $s.ExitLabCount -eq 0 -and $null -eq $s.ImportAt } }
    @{ name = 'a script that imports the module but never calls Exit-Lab calls no Exit-Lab'
       shape = Get-LabExitShape -ScriptDirectory $FixtureDirectory -Text "$FixtureImport`nWrite-Host '[FAIL] x'"
       check = { param($s) $s.ExitLabCount -eq 0 -and $null -ne $s.ImportAt } }
    @{ name = 'a bare exit is an exit, so a helper that has one is caught'
       shape = Get-LabExitShape -ScriptDirectory $FixtureDirectory -Text "function Get-X { }`nexit"
       check = { param($s) $s.ExitCount -eq 1 } }
    @{ name = 'an Exit-Lab with no import has no import'
       shape = Get-LabExitShape -ScriptDirectory $FixtureDirectory -Text 'Exit-Lab -FailureCount 1'
       check = { param($s) $null -eq $s.ImportAt } }
    @{ name = 'an import after the first Exit-Lab comes too late'
       shape = Get-LabExitShape -ScriptDirectory $FixtureDirectory -Text "Exit-Lab -FailureCount 1`n$FixtureImport"
       check = { param($s) $s.ImportAt -gt $s.FirstExitLabAt } }
    @{ name = 'the standard import resolves to tools/LabCommon.psm1 from a lab scripts folder'
       shape = Get-LabExitShape -ScriptDirectory $FixtureDirectory -Text "$FixtureImport`nExit-Lab -FailureCount 1"
       check = { param($s) $s.ImportPath -eq [System.IO.Path]::GetFullPath((Join-Path $RepoRoot 'tools/LabCommon.psm1')) } }
)

$LastStatementFixtures = @(
    @{ name = 'a closing Write-Host after the failure path does not end through an exit'
       shape = Get-LabExitShape -ScriptDirectory $FixtureDirectory -Text "if (`$f) { Exit-Lab -FailureCount 1 }`nWrite-Host 'done'"
       expected = $false }
    @{ name = 'a closing try whose catch calls Exit-Lab does not end through an exit'
       shape = Get-LabExitShape -ScriptDirectory $FixtureDirectory -Text "try { Get-X } catch { Exit-Lab -FailureCount 1 }"
       expected = $false }
    @{ name = 'a closing if whose branches both exit does not end through an exit'
       shape = Get-LabExitShape -ScriptDirectory $FixtureDirectory -Text "if (`$f) { exit 0 } else { Exit-Lab -FailureCount 1 }"
       expected = $false }
    @{ name = 'Exit-Lab quoted in a comment after the last statement is not a call'
       shape = Get-LabExitShape -ScriptDirectory $FixtureDirectory -Text "Write-Host 'done'`n# Exit-Lab -FailureCount 0"
       expected = $false }
    @{ name = 'a function defined after the last Exit-Lab is the last statement'
       shape = Get-LabExitShape -ScriptDirectory $FixtureDirectory -Text "Exit-Lab -FailureCount 0`nfunction Get-X { }"
       expected = $false }
    @{ name = 'Exit-Lab -FailureCount 0 as the last statement ends through an exit'
       shape = Get-LabExitShape -ScriptDirectory $FixtureDirectory -Text "Write-Host 'done'`nExit-Lab -FailureCount 0"
       expected = $true }
    @{ name = 'Exit-Lab with a count as the last statement ends through an exit'
       shape = Get-LabExitShape -ScriptDirectory $FixtureDirectory -Text "function Get-X { }`nExit-Lab -FailureCount `$failCount"
       expected = $true }
    @{ name = 'exit 0 as the last statement ends through an exit'
       shape = Get-LabExitShape -ScriptDirectory $FixtureDirectory -Text "Write-Host 'done'`nexit 0"
       expected = $true }
)

$StopWriteErrorFixtures = @(
    @{ name = 'Write-Error before Exit-Lab under a Stop preference is caught'
       shape = Get-LabExitShape -ScriptDirectory $FixtureDirectory -Text "`$ErrorActionPreference = 'Stop'`nif (`$f) { Write-Error 'x'; Exit-Lab -FailureCount 1 }`nExit-Lab -FailureCount 0"
       expected = 1 }
    @{ name = 'Write-Error in a catch block under a Stop preference is caught'
       shape = Get-LabExitShape -ScriptDirectory $FixtureDirectory -Text "`$ErrorActionPreference = `"Stop`"`ntry { Get-X } catch { Write-Error `$_; Exit-Lab -FailureCount 1 }`nExit-Lab -FailureCount 0"
       expected = 1 }
    @{ name = 'Write-Error without a Stop preference is not caught'
       shape = Get-LabExitShape -ScriptDirectory $FixtureDirectory -Text "if (`$f) { Write-Error 'x'; Exit-Lab -FailureCount 1 }`nExit-Lab -FailureCount 0"
       expected = 0 }
    @{ name = 'Write-Error inside a function is not caught'
       shape = Get-LabExitShape -ScriptDirectory $FixtureDirectory -Text "`$ErrorActionPreference = 'Stop'`nfunction Get-X { Write-Error 'x' }`nExit-Lab -FailureCount 0"
       expected = 0 }
    @{ name = 'Write-Error with its own -ErrorAction is not caught'
       shape = Get-LabExitShape -ScriptDirectory $FixtureDirectory -Text "`$ErrorActionPreference = 'Stop'`nWrite-Error 'x' -ErrorAction Continue`nExit-Lab -FailureCount 1"
       expected = 0 }
    @{ name = 'a Stop preference set only inside a function is not a script-level one'
       shape = Get-LabExitShape -ScriptDirectory $FixtureDirectory -Text "function Get-X { `$ErrorActionPreference = 'Stop' }`nWrite-Error 'x'`nExit-Lab -FailureCount 1"
       expected = 0 }
    @{ name = 'an [ERROR] line before Exit-Lab under a Stop preference is not caught'
       shape = Get-LabExitShape -ScriptDirectory $FixtureDirectory -Text "`$ErrorActionPreference = 'Stop'`nWrite-Host '[ERROR] x' -ForegroundColor Red`nExit-Lab -FailureCount 1"
       expected = 0 }
)

$ConvertedLabFixtures = @(
    @{ name = 'a script in a listed lab''s scripts folder is in scope'
       result = Test-ConvertedLabScript -File 'module-1-x/1.1-lab/scripts/Lab-Fixture.ps1' -ConvertedLabs @('module-1-x/1.1-lab')
       expected = $true }
    @{ name = 'a script in a lab that is not listed is out of scope'
       result = Test-ConvertedLabScript -File 'module-2-x/2.1-lab/scripts/Lab-Fixture.ps1' -ConvertedLabs @('module-1-x/1.1-lab')
       expected = $false }
    @{ name = 'a lab whose name only starts with a listed one is out of scope'
       result = Test-ConvertedLabScript -File 'module-1-x/1.1-lab-old/scripts/Lab-Fixture.ps1' -ConvertedLabs @('module-1-x/1.1-lab')
       expected = $false }
    @{ name = 'an empty list puts nothing in scope'
       result = Test-ConvertedLabScript -File 'module-1-x/1.1-lab/scripts/Lab-Fixture.ps1' -ConvertedLabs @()
       expected = $false }
)

# Discovery and run are separate phases in Pester 5: what the It blocks need at run time is set
# up again here.
BeforeAll {
    $RepoRoot      = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    $script:LabCommonPath = Join-Path $RepoRoot 'tools/LabCommon.psm1'

    function Test-RequiresModule {
        param([string]$Text)

        $ast = [System.Management.Automation.Language.Parser]::ParseInput($Text, [ref]$null, [ref]$null)
        $requirements = $ast.ScriptRequirements

        return ($null -ne $requirements -and @($requirements.RequiredModules).Count -gt 0)
    }
}

Describe 'SkyCraft PowerShell - every lab script ends through Exit-Lab (#257)' {

    It 'has lab scripts in scope to check' -ForEach @(@{ count = @($LabCases).Count; entry = $EntryLabCases.Count }) {
        # A filter that matches nothing produces a Describe that passes by asserting nothing.
        $count | Should -BeGreaterThan 0
        $entry | Should -BeGreaterThan 0
    }

    It "'<file>' calls no `$Host.SetShouldExit" -ForEach $LabCases {
        # Called at the prompt, it closes the learner's PowerShell session (#257). Exit-Lab calls
        # it only when the script is the entry point of a pwsh -File process.
        $setShouldExit | Should -BeNullOrEmpty -Because 'a lab script ends with Exit-Lab -FailureCount <n> (tools/LabCommon.psm1)'
    }

    It "'<file>' has no non-zero exit" -ForEach $LabCases {
        # A bare `exit 1` loses its code under pwsh -File (#104), and `exit $failCount` wraps to 0
        # at 256 failures (#257). `exit 0` and a bare `exit` are the success path.
        $nonZeroExit | Should -BeNullOrEmpty -Because 'a lab script ends with Exit-Lab -FailureCount <n> (tools/LabCommon.psm1)'
    }

    It "'<file>' calls Exit-Lab" -ForEach $EntryLabCases {
        # A lab script that never calls it exits 0 after printing [FAIL] (#104, #241). A helper
        # that other lab scripts dot-source belongs in $DotSourcedHelpers instead.
        $exitLabCount | Should -BeGreaterThan 0 -Because 'a lab script ends a failed run with Exit-Lab -FailureCount <n> (tools/LabCommon.psm1)'
    }

    It "'<file>' imports tools/LabCommon.psm1 by a path relative to `$PSScriptRoot, before its first Exit-Lab" -ForEach $EntryLabCases {
        $importAt | Should -Not -BeNullOrEmpty -Because "Import-Module (Join-Path `$PSScriptRoot '<relative>/tools/LabCommon.psm1') makes Exit-Lab available"
        $importPath | Should -Be ([System.IO.Path]::GetFullPath($labCommonPath)) -Because 'the path must hold in any clone, Cloud Shell included'
        if ($null -ne $firstExitLabAt) { $importAt | Should -BeLessThan $firstExitLabAt }
    }

    It "'<lab>', listed in `$ConvertedLabs, is a lab folder with lab scripts to check (#398)" -ForEach $ConvertedLabFolderCases {
        # A renamed or mistyped entry would hold nothing to the #398 rules and still pass.
        $exists | Should -BeTrue -Because 'every folder named in $ConvertedLabs must exist under the repository root'
        $entryScripts | Should -BeGreaterThan 0 -Because 'a converted lab has scripts under <lab>/scripts/ for the #398 rules to read'
    }

    It 'has converted lab scripts in scope for the #398 rules' -ForEach @(@{ count = $ConvertedEntryLabCases.Count; labs = $ConvertedLabs.Count }) {
        $labs | Should -BeGreaterThan 0
        $count | Should -BeGreaterThan 0
    }

    It "'<file>' ends with an Exit-Lab call or an exit as its last top-level statement (#398)" -ForEach $ConvertedEntryLabCases {
        # Falling off the end leaves $LASTEXITCODE at the previous run's value, so a passing
        # re-run in the same session reads as a failure.
        $endsThroughExit | Should -BeTrue -Because "the last top-level statement is '$lastStatement'; end the successful run with Exit-Lab -FailureCount 0 (or the count)"
    }

    It "'<file>', under a Stop error preference, calls no Write-Error outside a function (#398)" -ForEach $ConvertedLabCases {
        # Under Stop, Write-Error ends the script before the Exit-Lab after it, so at the prompt a
        # failed run leaves the previous run's $LASTEXITCODE.
        $stopWriteError | Should -BeNullOrEmpty -Because "report the failure with Write-Host '[ERROR] <message>' -ForegroundColor Red, then Exit-Lab -FailureCount <n>"
    }

    It "'<file>', excused as a dot-sourced helper, is one: a sibling dot-sources it and it ends nothing" -ForEach $HelperCases {
        $found | Should -BeTrue -Because 'a stale entry in $DotSourcedHelpers excuses nothing and hides a rename'
        $dotSourcedBy | Should -Not -BeNullOrEmpty -Because "a lab script in the same folder runs it with . (Join-Path `$PSScriptRoot '<helper file name>')"
        $exitLabCount | Should -Be 0 -Because 'Exit-Lab belongs to the script that dot-sources the helper (its entry-point check compares files)'
        $exitCount | Should -Be 0 -Because 'an exit in a dot-sourced file ends the script that loaded it'
    }
}

Describe 'SkyCraft PowerShell - the lab script rule fails what it is there to fail' {

    It '<name>' -ForEach $FixtureCases {
        @($shape.$property).Count | Should -Be $expected
    }

    It '<name>' -ForEach $ImportFixtures {
        & $check $shape | Should -BeTrue
    }

    It '<name>' -ForEach $LastStatementFixtures {
        $shape.EndsThroughExit | Should -Be $expected
    }

    It '<name>' -ForEach $StopWriteErrorFixtures {
        @($shape.StopWriteError).Count | Should -Be $expected
    }

    It 'the converted-labs scope: <name>' -ForEach $ConvertedLabFixtures {
        $result | Should -Be $expected
    }
}

Describe 'SkyCraft PowerShell - a tools script declaring #Requires -Modules guards a non-zero exit (#104)' {

    It 'has tools scripts in scope to read' -ForEach @(@{ count = $ToolScriptFiles.Count }) {
        # The per-site test below has no case today (no tools script declares a module
        # requirement); this keeps an empty discovery from passing as well.
        $count | Should -BeGreaterThan 0
    }

    It 'the exit-site reader: <name>' -ForEach $ExitSiteFixtures {
        $sites.Count | Should -Be $expected.count
        if ($expected.count -gt 0) {
            $sites[0].Code | Should -BeExactly $expected.code
            $sites[0].Previous | Should -BeExactly $expected.previous
        }
    }

    It "'<file>':<line> guards 'exit <code>' with `$Host.SetShouldExit(<code>)" -ForEach $ToolExitCases {
        $previous | Should -Match '^\$Host\.SetShouldExit\('

        $argument = [regex]::Match($previous, '^\$Host\.SetShouldExit\((?<arg>.*)\)$').Groups['arg'].Value.Trim()
        $argument | Should -BeExactly $code -Because 'the guard must carry the same code the exit does'
    }

    It "the lab cycle launcher shim, as it ships, declares no module requirement (#124)" {
        Test-RequiresModule -Text (Get-Content -Raw -LiteralPath (Join-Path $RepoRoot 'tools/Invoke-LabScript.ps1')) |
            Should -BeFalse
    }

    It "a '#Requires -Modules' line quoted in a help block is not a declaration" {
        $text = @('<#', '.DESCRIPTION', '    #Requires -Modules Az.Accounts', '#>', '#Requires -Version 7.0', 'exit 1') -join "`n"
        Test-RequiresModule -Text $text | Should -BeFalse
        Test-RequiresModule -Text "#Requires -Modules Az.Accounts`nexit 1" | Should -BeTrue
    }
}

Describe 'SkyCraft PowerShell - Exit-Lab tells the entry point of a pwsh -File process from everything else' {

    BeforeAll {
        $script:LabCommon = Import-Module $LabCommonPath -Force -PassThru
        $script:Lab  = if ($IsWindows) { 'C:\repo\module-1\1.1\scripts\Lab-Fixture.ps1' } else { '/repo/module-1/1.1/scripts/Lab-Fixture.ps1' }
        $script:Shim = if ($IsWindows) { 'C:\repo\tools\Invoke-LabScript.ps1' } else { '/repo/tools/Invoke-LabScript.ps1' }
    }

    AfterAll {
        Remove-Module -ModuleInfo $script:LabCommon -Force -ErrorAction SilentlyContinue
    }

    It '<name>' -ForEach @(
        @{ name = 'pwsh -File <lab script> is the entry point';                 cmd = @('pwsh', '-NoProfile', '-File', 'LAB');                 outer = 'LAB';  expected = $true }
        @{ name = 'pwsh -f <lab script> is the entry point';                    cmd = @('pwsh', '-f', 'LAB');                                  outer = 'LAB';  expected = $true }
        @{ name = 'pwsh <lab script>, with -File implied, is the entry point';  cmd = @('pwsh', '-NoProfile', 'LAB');                          outer = 'LAB';  expected = $true }
        @{ name = 'a switch value before -File does not hide it';               cmd = @('pwsh', '-ExecutionPolicy', 'Bypass', '-File', 'LAB'); outer = 'LAB';  expected = $true }
        @{ name = 'a -NoExit after the script path belongs to the script';      cmd = @('pwsh', '-File', 'LAB', '-NoExit');                    outer = 'LAB';  expected = $true }
        @{ name = 'pwsh -NoExit -File keeps the session, so it is not';         cmd = @('pwsh', '-NoExit', '-File', 'LAB');                    outer = 'LAB';  expected = $false }
        @{ name = 'pwsh -noe -File keeps the session, so it is not';            cmd = @('pwsh', '-noe', '-File', 'LAB');                       outer = 'LAB';  expected = $false }
        @{ name = 'pwsh -Command runs typed text, so it is not';                cmd = @('pwsh', '-Command', '& LAB');                          outer = 'LAB';  expected = $false }
        @{ name = 'pwsh -c runs typed text, so it is not';                      cmd = @('pwsh', '-c', '& LAB');                                outer = 'LAB';  expected = $false }
        @{ name = 'pwsh -EncodedCommand runs typed text, so it is not';         cmd = @('pwsh', '-EncodedCommand', 'AAAA');                    outer = 'LAB';  expected = $false }
        @{ name = 'pwsh -CommandWithArgs runs typed text, so it is not';        cmd = @('pwsh', '-CommandWithArgs', '& LAB', 'x.ps1');         outer = 'LAB';  expected = $false }
        @{ name = 'pwsh -cwa runs typed text, so it is not';                    cmd = @('pwsh', '-cwa', '& LAB', 'x.ps1');                     outer = 'LAB';  expected = $false }
        @{ name = 'an interactive prompt is not';                               cmd = @('pwsh');                                               outer = '';     expected = $false }
        @{ name = 'a lab script run by the launcher shim is not';               cmd = @('pwsh', '-NoProfile', '-File', 'SHIM');                outer = 'SHIM'; expected = $false }
        @{ name = 'a lab script typed at a -Command prompt is not';             cmd = @('pwsh', '-NoProfile', '-NoExit', '-Command', '-');     outer = '';     expected = $false }
    ) {
        $commandLine = $cmd | ForEach-Object { $_ -replace '^LAB$', $script:Lab -replace '^SHIM$', $script:Shim -replace '& LAB', "& $($script:Lab)" }
        $outermost   = switch ($outer) { 'LAB' { $script:Lab } 'SHIM' { $script:Shim } default { '' } }

        $result = & $script:LabCommon {
            param($c, $o, $l) Test-LabProcessEntryPoint -CommandLineArgs $c -OutermostScript $o -CallerScript $l
        } $commandLine $outermost $script:Lab

        $result | Should -Be $expected
    }

    It 'exports Exit-Lab and nothing else yet' {
        @($script:LabCommon.ExportedFunctions.Keys) | Should -Be @('Exit-Lab')
    }
}

Describe 'SkyCraft PowerShell - Exit-Lab reaches both callers (real pwsh processes, no Azure)' {

    BeforeAll {
        $script:Pwsh  = (Get-Process -Id $PID).Path
        $script:HasAz = [bool](Get-Module -ListAvailable -Name Az.Accounts)

        # A lab-shaped script: it declares Az.Accounts where it is installed - the condition the
        # #104 fault needs - and ends the way every lab script does. -Trace makes Exit-Lab say
        # which branch it took, which is how CI, without Az.Accounts, sees the decision.
        $requires = if ($script:HasAz) { '#Requires -Modules Az.Accounts' } else { '' }
        $script:LabScript = Join-Path $TestDrive 'Lab-Fixture.ps1'
        @(
            '#Requires -Version 7.0'
            $requires
            '[CmdletBinding()]'
            'param([int]$Count, [switch]$Trace)'
            "`$ErrorActionPreference = 'Stop'"
            "Import-Module '$LabCommonPath' -Force -Verbose:`$false"
            'Write-Host "lab: $Count failure(s)"'
            'Exit-Lab -FailureCount $Count -Verbose:$Trace'
        ) | Set-Content -LiteralPath $script:LabScript -Encoding utf8

        # The #104 idiom the lab scripts used before #257, for the control case.
        $script:OldIdiom = Join-Path $TestDrive 'Old-Idiom.ps1'
        @(
            '#Requires -Version 7.0'
            'Write-Host "old idiom"'
            '$Host.SetShouldExit(1)'
            'exit 1'
        ) | Set-Content -LiteralPath $script:OldIdiom -Encoding utf8

        # Commands fed on stdin to a session that stays open (-NoExit), as a learner types them.
        function Invoke-InteractiveSession {
            param([string[]]$Line)
            $text = ($Line + 'exit 0') -join "`n"
            ($text | & $script:Pwsh -NoProfile -NoLogo -NoExit -Command - 2>&1 | Out-String)
        }
    }

    It 'pwsh -File returns 1 to its caller for a failed run' -Skip:(-not [bool](Get-Module -ListAvailable -Name Az.Accounts)) {
        # The #104 case: without SetShouldExit, a script declaring Az.Accounts exits 0 here.
        & $script:Pwsh -NoProfile -File $script:LabScript -Count 3 | Out-Null
        $LASTEXITCODE | Should -Be 1
    }

    It 'pwsh -File takes the SetShouldExit branch; -Command, the launcher shim and a prompt take a plain exit' {
        # Runs without Az.Accounts, so CI proves the entry-point decision in real processes even
        # where the test above is skipped. A broken detection shows up here as the wrong branch.
        $file = & $script:Pwsh -NoProfile -File $script:LabScript -Count 3 -Trace 2>&1 | Out-String
        $file | Should -Match 'Exit-Lab: entry point of a pwsh -File process, SetShouldExit\(1\)' -Because "output was:`n$file"

        $command = & $script:Pwsh -NoProfile -Command "& '$($script:LabScript)' -Count 3 -Trace" 2>&1 | Out-String
        $command | Should -Match 'Exit-Lab: not the process entry point, plain exit 1' -Because "output was:`n$command"

        $shim = & $script:Pwsh -NoProfile -File (Join-Path $RepoRoot 'tools/Invoke-LabScript.ps1') `
            -TargetScript $script:LabScript -ArgumentJson '{"Count":3,"Trace":true}' 2>&1 | Out-String
        $shim | Should -Match 'Exit-Lab: not the process entry point, plain exit 1' -Because "output was:`n$shim"

        $prompt = Invoke-InteractiveSession -Line @("& '$($script:LabScript)' -Count 3 -Trace")
        $prompt | Should -Match 'Exit-Lab: not the process entry point, plain exit 1' -Because "output was:`n$prompt"
    }

    It 'Exit-Lab typed at the prompt, after a lab script loaded it, warns and leaves the session open' {
        $output = Invoke-InteractiveSession -Line @(
            "& '$($script:LabScript)' -Count 0"
            'Exit-Lab -FailureCount 1'
            'Write-Host "MARKER after Exit-Lab at the prompt"'
        )
        $output | Should -Match 'typed at the prompt it does nothing' -Because "output was:`n$output"
        $output | Should -Match 'MARKER after Exit-Lab at the prompt' -Because "output was:`n$output"
    }

    It 'pwsh -File returns 0 for a passing run and 1, not 0, for 256 failures' {
        & $script:Pwsh -NoProfile -File $script:LabScript -Count 0 | Out-Null
        $LASTEXITCODE | Should -Be 0

        & $script:Pwsh -NoProfile -File $script:LabScript -Count 256 | Out-Null
        $LASTEXITCODE | Should -Be 1 -Because 'exit $failCount would wrap to 0 here'
    }

    It 'an interactive session keeps running after a failed run, with $LASTEXITCODE 1 (the #257 repro)' {
        $output = Invoke-InteractiveSession -Line @(
            "& '$($script:LabScript)' -Count 3"
            'Write-Host "MARKER after the script, LASTEXITCODE=$LASTEXITCODE"'
        )
        $output | Should -Match 'MARKER after the script, LASTEXITCODE=1' -Because "the session must survive the script; output was:`n$output"
    }

    It 'an interactive session keeps running after a passing run, with $LASTEXITCODE 0' {
        $output = Invoke-InteractiveSession -Line @(
            "& '$($script:LabScript)' -Count 0"
            'Write-Host "MARKER after the script, LASTEXITCODE=$LASTEXITCODE"'
        )
        $output | Should -Match 'MARKER after the script, LASTEXITCODE=0' -Because "output was:`n$output"
    }

    It 'a passing run after a failed one in the same session sets $LASTEXITCODE back to 0 (#398)' {
        $output = Invoke-InteractiveSession -Line @(
            "& '$($script:LabScript)' -Count 3"
            "& '$($script:LabScript)' -Count 0"
            'Write-Host "MARKER after the re-run, LASTEXITCODE=$LASTEXITCODE"'
        )
        $output | Should -Match 'MARKER after the re-run, LASTEXITCODE=0' -Because "output was:`n$output"
    }

    It 'control: a passing script that falls off its end keeps the failed run''s $LASTEXITCODE (#398)' {
        # Proves the case above can fail: this is what #398 reported.
        $fallsOff = Join-Path $TestDrive 'Falls-Off.ps1'
        @('#Requires -Version 7.0', 'Write-Host "passed"') | Set-Content -LiteralPath $fallsOff -Encoding utf8
        $output = Invoke-InteractiveSession -Line @(
            "& '$($script:LabScript)' -Count 3"
            "& '$fallsOff'"
            'Write-Host "MARKER after the re-run, LASTEXITCODE=$LASTEXITCODE"'
        )
        $output | Should -Match 'MARKER after the re-run, LASTEXITCODE=1' -Because "output was:`n$output"
    }

    It 'control: a Write-Error before Exit-Lab under Stop keeps the passing run''s $LASTEXITCODE (#398)' {
        # Proves the Write-Error rule guards a real fault: the failed run reads as a pass.
        $writeError = Join-Path $TestDrive 'Write-Error-Stop.ps1'
        @(
            '#Requires -Version 7.0'
            "`$ErrorActionPreference = 'Stop'"
            "Import-Module '$LabCommonPath' -Force -Verbose:`$false"
            'Write-Error "not signed in"'
            'Exit-Lab -FailureCount 1'
        ) | Set-Content -LiteralPath $writeError -Encoding utf8
        $output = Invoke-InteractiveSession -Line @(
            "& '$($script:LabScript)' -Count 0"
            "try { & '$writeError' } catch { }"
            'Write-Host "MARKER after the failed run, LASTEXITCODE=$LASTEXITCODE"'
        )
        $output | Should -Match 'MARKER after the failed run, LASTEXITCODE=0' -Because "output was:`n$output"
    }

    It 'control: the old SetShouldExit idiom ends the same session before the next command' {
        # Proves the case above can fail: this is what #257 reported.
        $output = Invoke-InteractiveSession -Line @(
            "& '$($script:OldIdiom)'"
            'Write-Host "MARKER after the script"'
        )
        $output | Should -Match 'old idiom'
        $output | Should -Not -Match 'MARKER after the script'
    }

    It 'pwsh -Command runs the next statement and the process reports the code' {
        $output = & $script:Pwsh -NoProfile -Command "& '$($script:LabScript)' -Count 3; Write-Host ""MARKER LASTEXITCODE=`$LASTEXITCODE""" 2>&1 | Out-String
        $output | Should -Match 'MARKER LASTEXITCODE=1'

        & $script:Pwsh -NoProfile -Command "& '$($script:LabScript)' -Count 3" | Out-Null
        $LASTEXITCODE | Should -Be 1
    }

    It 'the lab cycle launcher shim (pwsh -File tools/Invoke-LabScript.ps1) returns the code' {
        $shim = Join-Path $RepoRoot 'tools/Invoke-LabScript.ps1'

        & $script:Pwsh -NoProfile -File $shim -TargetScript $script:LabScript -ArgumentJson '{"Count":3}' | Out-Null
        $LASTEXITCODE | Should -Be 1

        & $script:Pwsh -NoProfile -File $shim -TargetScript $script:LabScript -ArgumentJson '{"Count":0}' | Out-Null
        $LASTEXITCODE | Should -Be 0
    }
}

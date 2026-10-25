<#
.SYNOPSIS
    Pester 5 test: no lab script or tool reads or changes budgets through the Az.Billing budget
    cmdlets, and no budget read is silenced.

.DESCRIPTION
    Az.Billing 2.3.0 sends every Consumption request at api-version 2018-01-31. Current
    subscriptions refuse that version with 422 ("Please use version 2018-12-01-preview or
    later"), so Get-AzConsumptionBudget and Remove-AzConsumptionBudget failed in Lab 1.3's
    validation and cleanup, and in the two checklist commands a learner types (issue #411, seen
    live on 2026-10-21). The lab scripts go through Get-LabArmBudget and Remove-LabArmBudget in
    tools/LabCommon.psm1 instead, which call the Consumption budgets API at 2023-05-01.

    The test parses every tracked PowerShell file under module-*/*/scripts/ and tools/, and fails
    on:

      1. a command call to Get-, New-, Set- or Remove-AzConsumptionBudget (a comment or a string
         that names them is fine);
      2. a call to Get-LabArmBudget with -ErrorAction SilentlyContinue or Ignore, which would turn
         a failed read back into "no budget".

    It also reads the lab guides and checklists (module-*/*/*.md), and fails on:

      3. a PowerShell block that calls one of the four cmdlets, because the learner who types it
         meets the same 422.

    And, in scripts, tools, guides and checklists alike:

      4. a Microsoft.Consumption/budgets path written with an api-version before 2019-01-01, the
         first version the service accepted in the test subscription.

    Lab tests/ folders are not scanned; their stubs may name the cmdlets on purpose. The test
    fails when it finds no file, no call to the budget helpers or no guide, so a broken scan
    cannot pass as a green check, and a fixture proves each rule catches what it is meant to
    catch.

.EXAMPLE
    Invoke-Pester -Path .\tests\Budget-Consumption-Api.Tests.ps1

.NOTES
    Project: SkyCraft
    Issue: #411
#>

#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeDiscovery {
    $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path

    # Tracked files only: a worktree under .claude/ or a scratch file is not the repository.
    $tracked = @(git -C $repoRoot ls-files -- 'module-*' 'tools')
    $script:Files = foreach ($relative in $tracked) {
        if ($relative -notmatch '^(module-[^/]+/[^/]+/scripts/[^/]+|tools/.+)\.(ps1|psm1)$') { continue }
        @{ file = $relative; path = (Join-Path $repoRoot $relative) }
    }

    # The lab guides and checklists: the Markdown files at the root of each lab folder.
    $script:Docs = foreach ($relative in $tracked) {
        if ($relative -notmatch '^module-[^/]+/[^/]+/[^/]+\.md$') { continue }
        @{ file = $relative; path = (Join-Path $repoRoot $relative) }
    }
}

BeforeAll {
    $script:ForbiddenCmdlets = @('Get-AzConsumptionBudget', 'New-AzConsumptionBudget', 'Set-AzConsumptionBudget', 'Remove-AzConsumptionBudget')
    $script:OldestAcceptedVersion = '2019-01-01'

    # Budget paths written with an api-version the service refuses (rule 4), as 'version' strings.
    function Get-OldBudgetApiVersion {
        param([string]$Text)
        foreach ($match in [regex]::Matches($Text, '(?i)Microsoft\.Consumption/budgets[^\s''"`]*?[?&]api-version=(?<version>\d{4}-\d{2}-\d{2}[^\s&''"`]*)')) {
            $version = $match.Groups['version'].Value
            if ([string]::CompareOrdinal($version.Substring(0, 10), $script:OldestAcceptedVersion) -lt 0) { $version }
        }
    }

    # The findings of one script's text, as 'line: text' strings, for rules 1, 2 and 4.
    function Get-BudgetFinding {
        param([string]$Text)

        $tokens = $null
        $errors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseInput($Text, [ref]$tokens, [ref]$errors)
        $commands = @($ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] }, $true))

        $cmdlets = foreach ($command in $commands) {
            $name = $command.GetCommandName()
            if ($name -and ($script:ForbiddenCmdlets -contains ($name -replace '^Az\.Billing\\', ''))) {
                "$($command.Extent.StartLineNumber): $($command.Extent.Text)"
            }
        }

        $helperCalls = @($commands | Where-Object { $_.GetCommandName() -in 'Get-LabArmBudget', 'Remove-LabArmBudget' })
        $silenced = foreach ($command in @($helperCalls | Where-Object { $_.GetCommandName() -eq 'Get-LabArmBudget' })) {
            $elements = @($command.CommandElements)
            for ($i = 0; $i -lt $elements.Count; $i++) {
                $element = $elements[$i]
                if ($element -isnot [System.Management.Automation.Language.CommandParameterAst]) { continue }
                if ($element.ParameterName -notmatch '^(ErrorAction|ea)$') { continue }
                $value = if ($element.Argument) { $element.Argument.Extent.Text } elseif ($i + 1 -lt $elements.Count) { $elements[$i + 1].Extent.Text } else { '' }
                if ($value -match 'SilentlyContinue|Ignore') { "$($command.Extent.StartLineNumber): $($command.Extent.Text)" }
            }
        }

        [pscustomobject]@{
            Cmdlets     = @($cmdlets)
            Silenced    = @($silenced)
            OldVersions = @(Get-OldBudgetApiVersion -Text $Text)
            HelperCalls = $helperCalls.Count
            ParseErrors = @($errors).Count
        }
    }

    # A guide's or checklist's PowerShell blocks that call a budget cmdlet (rule 3), and the old
    # api-versions it writes (rule 4).
    function Get-BudgetDocFinding {
        param([string]$Text)

        $blocks = [regex]::Matches($Text, '(?ms)^[ \t]*```(?:powershell|pwsh|ps1)[ \t]*\r?$(?<body>.*?)^[ \t]*```')
        $calling = @($blocks | Where-Object { $_.Groups['body'].Value -match '\b(Get|New|Set|Remove)-AzConsumptionBudget\b' })
        [pscustomobject]@{
            Blocks      = $calling.Count
            OldVersions = @(Get-OldBudgetApiVersion -Text $Text)
        }
    }
}

Describe 'Budgets without Az.Billing - the rule catches what it should (#411)' {

    It 'flags a call to <cmdlet>' -ForEach @(
        @{ cmdlet = 'Get-AzConsumptionBudget'; text = 'Get-AzConsumptionBudget -ErrorAction Stop | Where-Object { $_ }' }
        @{ cmdlet = 'New-AzConsumptionBudget'; text = "New-AzConsumptionBudget -Name 'b' -Amount 50 -Category Cost -TimeGrain Monthly" }
        @{ cmdlet = 'Set-AzConsumptionBudget'; text = "Set-AzConsumptionBudget -Name 'b' -Amount 60" }
        @{ cmdlet = 'Remove-AzConsumptionBudget'; text = "Remove-AzConsumptionBudget -Name 'b' -ResourceGroupName rg | Out-Null" }
        @{ cmdlet = 'Get-AzConsumptionBudget, module-qualified'; text = 'Az.Billing\Get-AzConsumptionBudget' }
    ) {
        (Get-BudgetFinding -Text $text).Cmdlets.Count | Should -Be 1
    }

    It 'does not flag a comment or a string that names the cmdlets' {
        $text = "# Get-AzConsumptionBudget sends 2018-01-31`nWrite-Host 'Remove-AzConsumptionBudget is not used'"
        (Get-BudgetFinding -Text $text).Cmdlets | Should -BeNullOrEmpty
    }

    It 'flags a budget read silenced with <form>' -ForEach @(
        @{ form = '-ErrorAction SilentlyContinue'; text = 'Get-LabArmBudget -Scope $s -ErrorAction SilentlyContinue' }
        @{ form = '-ErrorAction:Ignore'; text = 'Get-LabArmBudget -Scope $s -ErrorAction:Ignore' }
        @{ form = '-ea SilentlyContinue'; text = 'Get-LabArmBudget -Scope $s -ea SilentlyContinue' }
    ) {
        (Get-BudgetFinding -Text $text).Silenced.Count | Should -Be 1
    }

    It 'does not flag a read that lets its error through, and counts the helper calls' {
        $finding = Get-BudgetFinding -Text "Get-LabArmBudget -Scope `$s`nRemove-LabArmBudget -Scope `$s -Name b"
        $finding.Silenced | Should -BeNullOrEmpty
        $finding.HelperCalls | Should -Be 2
    }

    It 'flags a budget path at api-version <version>' -ForEach @(
        @{ version = '2018-01-31' }
        @{ version = '2018-12-01-preview' }
        @{ version = '2017-12-30-preview' }
    ) {
        $text = "Invoke-AzRestMethod -Path `"/subscriptions/`$id/providers/Microsoft.Consumption/budgets?api-version=$version`""
        (Get-BudgetFinding -Text $text).OldVersions -join ',' | Should -Be $version
    }

    It 'does not flag a budget path at api-version <version>' -ForEach @(
        @{ version = '2019-01-01' }
        @{ version = '2023-05-01' }
    ) {
        $text = "Invoke-AzRestMethod -Path `"/subscriptions/`$id/resourceGroups/rg/providers/Microsoft.Consumption/budgets/b?api-version=$version`""
        (Get-BudgetFinding -Text $text).OldVersions | Should -BeNullOrEmpty
    }

    It 'finds a guide''s PowerShell block that calls a budget cmdlet' {
        $fence = '```'
        $block = "Text`r`n`r`n$($fence)powershell`r`nGet-AzConsumptionBudget -ResourceGroupName rg |`r`n    Format-Table`r`n$fence`r`n"
        (Get-BudgetDocFinding -Text $block).Blocks | Should -Be 1
    }

    It 'does not count a budget cmdlet named in prose or in a Bash block' {
        $fence = '```'
        $text = "Get-AzConsumptionBudget sends 2018-01-31.`n`n$($fence)bash`naz consumption budget list # not Get-AzConsumptionBudget`n$fence`n"
        (Get-BudgetDocFinding -Text $text).Blocks | Should -Be 0
    }
}

Describe 'Budgets without Az.Billing - every lab script and tool (#411)' {

    It 'finds lab scripts and tools to check' -TestCases @(@{ count = @($script:Files).Count }) {
        $count | Should -BeGreaterThan 20 -Because 'finding none means the scan is broken'
    }

    It 'finds the budget helpers in use' -TestCases @(@{ files = $script:Files }) {
        $calls = 0
        foreach ($entry in $files) {
            $calls += (Get-BudgetFinding -Text (Get-Content -Raw -LiteralPath $entry.path)).HelperCalls
        }
        $calls | Should -BeGreaterOrEqual 3 -Because 'Lab 1.3''s Test-Lab.ps1 reads budgets, and its Remove-LabResource.ps1 reads and deletes them, through the LabCommon helpers'
    }

    It '<file> calls no Az.Billing budget cmdlet, silences no budget read and writes no refused api-version' -ForEach $script:Files {
        $finding = Get-BudgetFinding -Text (Get-Content -Raw -LiteralPath $path)
        $finding.ParseErrors | Should -Be 0
        $finding.Cmdlets | Should -BeNullOrEmpty -Because 'Az.Billing sends api-version 2018-01-31, which current subscriptions refuse with 422; use Get-LabArmBudget / Remove-LabArmBudget from tools/LabCommon.psm1 (issue #411)'
        $finding.Silenced | Should -BeNullOrEmpty -Because 'a failed budget read is a failure, never "no budget" (issue #411)'
        $finding.OldVersions | Should -BeNullOrEmpty -Because 'the Consumption budgets API refuses versions before 2019-01-01 (issue #411)'
    }
}

Describe 'Budgets without Az.Billing - the guides and checklists a learner types from (#411)' {

    It 'finds lab guides and checklists to check' -TestCases @(@{ count = @($script:Docs).Count }) {
        $count | Should -BeGreaterThan 20 -Because 'finding none means the scan is broken'
    }

    It '<file> teaches no budget command that fails on a current subscription' -ForEach $script:Docs {
        $finding = Get-BudgetDocFinding -Text (Get-Content -Raw -LiteralPath $path)
        $finding.Blocks | Should -Be 0 -Because 'Get-/New-/Set-/Remove-AzConsumptionBudget fail with 422 on current subscriptions; teach the Portal path or the Consumption API at 2023-05-01 (issue #411)'
        $finding.OldVersions | Should -BeNullOrEmpty -Because 'the Consumption budgets API refuses versions before 2019-01-01 (issue #411)'
    }
}

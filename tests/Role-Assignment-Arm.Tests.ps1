<#
.SYNOPSIS
    Pester 5 test: no lab script reads, creates or removes role assignments through the Az role
    cmdlets, and no role assignment read is silenced.

.DESCRIPTION
    Every form of Get-AzRoleAssignment (Az.Resources 8), -Scope alone included, and
    New-AzRoleAssignment and Remove-AzRoleAssignment call Microsoft Graph to resolve the
    principals. Where the Az sign-in cannot get a Graph token without interaction they fail with
    "Authentication failed against resource MicrosoftGraphEndpointResourceId", although the
    Azure Resource Manager token works; a script that passed -ErrorAction SilentlyContinue read
    "no assignment" when there was one (issue #397, seen live on 2026-10-19). The lab scripts go
    through Get-LabArmRoleAssignment, New-LabArmRoleAssignment and Remove-LabArmRoleAssignment in
    tools/LabCommon.psm1 instead, which call the ARM role assignments API.

    The test parses every tracked PowerShell file under module-*/*/scripts/ and tools/, and fails
    on:

      1. a command call to Get-AzRoleAssignment, New-AzRoleAssignment or Remove-AzRoleAssignment
         (a comment or a string that names them is fine);
      2. a call to Get-LabArmRoleAssignment with -ErrorAction SilentlyContinue or Ignore, which
         would turn a failed read back into "no assignment".

    The guides and checklists (module-*/*/*.md) may keep the cmdlets in the PowerShell blocks a
    learner types, because those blocks teach them. They fail there in the same way: Az does not
    prompt for the Graph sign-in in the middle of a command, it reports "User interaction is
    required". So the test also fails on:

      3. a guide or checklist with a PowerShell block that calls one of the three cmdlets, but
         that does not name MicrosoftGraphEndpointResourceId, the error text a learner searches
         for in TROUBLESHOOTING.md, whose entry gives the sign-in that provides the token.

    Lab tests/ folders are not scanned; their stubs name the cmdlets on purpose. The test fails
    when it finds no file, no call to the ARM helpers or no such block in the guides, so a broken
    scan cannot pass as a green check, and a fixture proves each rule catches what it is meant to
    catch.

.EXAMPLE
    Invoke-Pester -Path .\tests\Role-Assignment-Arm.Tests.ps1

.NOTES
    Project: SkyCraft
    Issue: #397
#>

#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeDiscovery {
    $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path

    # Tracked files only: a worktree under a tool folder or a scratch file is not the repository.
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
    $script:ForbiddenCmdlets = @('Get-AzRoleAssignment', 'New-AzRoleAssignment', 'Remove-AzRoleAssignment')

    # The findings of one file's text, as 'line: text' strings, for each rule.
    function Get-RoleAssignmentFinding {
        param([string]$Text)

        $tokens = $null
        $errors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseInput($Text, [ref]$tokens, [ref]$errors)
        $commands = @($ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] }, $true))

        $cmdlets = foreach ($command in $commands) {
            $name = $command.GetCommandName()
            if ($name -and ($script:ForbiddenCmdlets -contains ($name -replace '^Az\.Resources\\', ''))) {
                "$($command.Extent.StartLineNumber): $($command.Extent.Text)"
            }
        }

        $helperCalls = @($commands | Where-Object { $_.GetCommandName() -eq 'Get-LabArmRoleAssignment' })
        $silenced = foreach ($command in $helperCalls) {
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
            HelperCalls = $helperCalls.Count
            ParseErrors = @($errors).Count
        }
    }

    # A guide's or checklist's PowerShell blocks that call one of the role cmdlets, and whether the
    # file names the error a learner meets with them (rule 3).
    function Get-RoleCmdletDocFinding {
        param([string]$Text)

        $blocks = [regex]::Matches($Text, '(?ms)^[ \t]*```(?:powershell|pwsh|ps1)[ \t]*\r?$(?<body>.*?)^[ \t]*```')
        $calling = @($blocks | Where-Object { $_.Groups['body'].Value -match '\b(Get|New|Remove)-AzRoleAssignment\b' })
        [pscustomobject]@{
            Blocks      = $calling.Count
            NamesError  = $Text -match 'MicrosoftGraphEndpointResourceId'
        }
    }
}

Describe 'Role assignments without Microsoft Graph - the rule catches what it should (#397)' {

    It 'flags a call to <cmdlet>' -ForEach @(
        @{ cmdlet = 'Get-AzRoleAssignment'; text = 'Get-AzRoleAssignment -Scope $scope -ErrorAction Stop' }
        @{ cmdlet = 'New-AzRoleAssignment'; text = "New-AzRoleAssignment -ObjectId `$id -RoleDefinitionName 'Reader' -Scope `$scope" }
        @{ cmdlet = 'Remove-AzRoleAssignment'; text = "`$x | Remove-AzRoleAssignment" }
        @{ cmdlet = 'Get-AzRoleAssignment, module-qualified'; text = 'Az.Resources\Get-AzRoleAssignment -Scope $scope' }
    ) {
        (Get-RoleAssignmentFinding -Text $text).Cmdlets.Count | Should -Be 1
    }

    It 'does not flag a comment or a string that names the cmdlets' {
        $text = "# Get-AzRoleAssignment calls Microsoft Graph`nWrite-Host 'New-AzRoleAssignment is not used'"
        (Get-RoleAssignmentFinding -Text $text).Cmdlets | Should -BeNullOrEmpty
    }

    It 'flags a role assignment read silenced with <form>' -ForEach @(
        @{ form = '-ErrorAction SilentlyContinue'; text = 'Get-LabArmRoleAssignment -Scope $s -ErrorAction SilentlyContinue' }
        @{ form = '-ErrorAction:Ignore'; text = 'Get-LabArmRoleAssignment -Scope $s -ErrorAction:Ignore' }
        @{ form = '-ea SilentlyContinue'; text = 'Get-LabArmRoleAssignment -Scope $s -ea SilentlyContinue' }
    ) {
        (Get-RoleAssignmentFinding -Text $text).Silenced.Count | Should -Be 1
    }

    It 'does not flag a read that lets its error through' {
        (Get-RoleAssignmentFinding -Text 'Get-LabArmRoleAssignment -Scope $s -PrincipalId $p').Silenced | Should -BeNullOrEmpty
    }

    It 'finds a guide''s PowerShell block that calls a role cmdlet, and sees whether the file names the error' {
        $fence = '```'
        $block = "Text`r`n`r`n$($fence)powershell`r`nGet-AzRoleAssignment -Scope `$scope`r`n$fence`r`n"
        $finding = Get-RoleCmdletDocFinding -Text $block
        $finding.Blocks | Should -Be 1
        $finding.NamesError | Should -BeFalse
        (Get-RoleCmdletDocFinding -Text "$block`r`nIf it fails with ``MicrosoftGraphEndpointResourceId``, see TROUBLESHOOTING.md.").NamesError | Should -BeTrue
    }

    It 'does not count a role cmdlet named in prose or in a Bash block' {
        $fence = '```'
        $text = "Get-AzRoleAssignment calls Microsoft Graph.`n`n$($fence)bash`naz role assignment list # not Get-AzRoleAssignment`n$fence`n"
        (Get-RoleCmdletDocFinding -Text $text).Blocks | Should -Be 0
    }
}

Describe 'Role assignments without Microsoft Graph - every lab script and tool (#397)' {

    It 'finds lab scripts and tools to check' -TestCases @(@{ count = @($script:Files).Count }) {
        $count | Should -BeGreaterThan 20 -Because 'finding none means the scan is broken'
    }

    It 'finds the ARM role assignment helpers in use' -TestCases @(@{ files = $script:Files }) {
        $calls = 0
        foreach ($entry in $files) {
            $calls += (Get-RoleAssignmentFinding -Text (Get-Content -Raw -LiteralPath $entry.path)).HelperCalls
        }
        $calls | Should -BeGreaterThan 5 -Because 'Labs 1.2, 1.3, 4.4 and 5.2 read role assignments through Get-LabArmRoleAssignment'
    }

    It '<file> calls no Az role assignment cmdlet and silences no role assignment read' -ForEach $script:Files {
        $finding = Get-RoleAssignmentFinding -Text (Get-Content -Raw -LiteralPath $path)
        $finding.ParseErrors | Should -Be 0
        $finding.Cmdlets | Should -BeNullOrEmpty -Because 'Get-/New-/Remove-AzRoleAssignment call Microsoft Graph; use Get-/New-/Remove-LabArmRoleAssignment from tools/LabCommon.psm1 (issue #397)'
        $finding.Silenced | Should -BeNullOrEmpty -Because 'a failed role assignment read is a failure, never "no assignment" (issue #397)'
    }
}

Describe 'Role assignments without Microsoft Graph - the guides and checklists a learner types from (#397)' {

    It 'finds lab guides and checklists, and role cmdlet blocks among them, to check' -TestCases @(@{ docs = $script:Docs }) {
        @($docs).Count | Should -BeGreaterThan 20 -Because 'finding none means the scan is broken'
        $blocks = 0
        foreach ($entry in $docs) { $blocks += (Get-RoleCmdletDocFinding -Text (Get-Content -Raw -LiteralPath $entry.path)).Blocks }
        $blocks | Should -BeGreaterThan 0 -Because 'Lab 1.2''s checklist and Lab 1.3''s guide teach the role cmdlets'
    }

    It '<file> names MicrosoftGraphEndpointResourceId where a learner types a role cmdlet' -ForEach $script:Docs {
        $finding = Get-RoleCmdletDocFinding -Text (Get-Content -Raw -LiteralPath $path)
        if ($finding.Blocks -eq 0) { return }
        $finding.NamesError | Should -BeTrue -Because "$($finding.Blocks) PowerShell block(s) call Get-/New-/Remove-AzRoleAssignment, which fail without a Microsoft Graph token; name the error and point to TROUBLESHOOTING.md (issue #397)"
    }
}

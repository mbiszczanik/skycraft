<#
.SYNOPSIS
    Pester 5 test: a lab guide step that names a Portal blade from a collapsed menu group also
    names the group.

.DESCRIPTION
    Today's Portal folds most resource menu items into collapsed groups (Settings, Monitoring,
    Data management, ...). A step that says "click **Peerings**" names an item the learner cannot
    see until the group is expanded (issue #346, check 5 of #363). The guides name the group as
    "under **Settings** (expand it if it is collapsed), click **Peerings**".

    The test reads every list step (a numbered or bulleted line) of every tracked lab guide
    (module-*/*/lab-guide-*.md). A step that clicks, selects, opens or navigates to one of the
    blades in $Blades, as a bold name, shall carry the name of one of that blade's groups
    on the same line. The list holds only blades whose group is documented (Microsoft Learn or a
    Portal pass of #329); where one name sits in different groups on different resources (Budgets,
    Access keys), every group is accepted. It grows from the Portal passes.

    The test fails when it finds no guide or no step that names a group, so a broken scan cannot
    pass as a green check, and fixtures prove the rule catches what it is meant to catch.

.EXAMPLE
    Invoke-Pester -Path .\tests\Guide-Menu-Groups.Tests.ps1

.NOTES
    Project: SkyCraft
    Issue: #346
#>

#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeDiscovery {
    $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    # Tracked files only: a worktree under a tool folder or a scratch file is not the repository.
    $script:Guides = foreach ($relative in @(git -C $repoRoot ls-files -- 'module-*')) {
        if ($relative -notmatch '^module-[^/]+/[^/]+/lab-guide-[^/]+\.md$') { continue }
        @{ file = $relative; path = (Join-Path $repoRoot $relative) }
    }
}

BeforeAll {
    # Blade -> the groups it sits in on the resources the guides use.
    $script:Blades = [ordered]@{
        'Peerings'                   = @('Settings')
        'Inbound security rules'     = @('Settings')
        'Outbound security rules'    = @('Settings')
        'Subnets'                    = @('Settings')
        'Backend pools'              = @('Settings')
        'Health probes'              = @('Settings')
        'Load balancing rules'       = @('Settings')
        'Locks'                      = @('Settings')
        'Usage + quotas'             = @('Settings')
        'Extensions + applications'  = @('Settings')
        'Instances'                  = @('Settings')
        'Virtual Network Links'      = @('DNS Management')
        'Backup items'               = @('Protected items')
        'Backup jobs'                = @('Monitoring')
        'Backup policies'            = @('Manage', 'Settings')
        'Diagnostic settings'        = @('Monitoring')
        'Topology'                   = @('Monitoring')
        'Connection monitor'         = @('Monitoring')
        'Lifecycle management'       = @('Data management')
        'Data protection'            = @('Data management')
        'Access keys'                = @('Settings', 'Security + networking')
        'Encryption'                 = @('Settings', 'Security + networking')
        'Budgets'                    = @('Monitoring', 'Cost Management')
        'Cost analysis'              = @('Cost Management')
        'Assignments'                = @('Authoring')
    }

    # The steps of a guide's text that click a listed blade without naming one of its groups, as
    # 'line: text' strings, and the number of steps that do name it.
    function Get-MenuGroupFinding {
        param([string]$Text)

        $lineNumber = 0
        foreach ($line in ($Text -split "`r?`n")) {
            $lineNumber++
            if ($line -notmatch '^\s*(?:\d+\.|[-*])\s') { continue }
            foreach ($blade in $script:Blades.Keys) {
                $click = '(?i)(?:click|select|open|choose|→|>|go to|navigate to|in the left menu,?)\s*\*\*' + [regex]::Escape($blade) + '\*\*'
                if ($line -notmatch $click) { continue }
                $named = @($script:Blades[$blade] | Where-Object { $line -match [regex]::Escape($_) }).Count
                [pscustomobject]@{ Line = $lineNumber; Blade = $blade; Named = [bool]$named; Text = $line.Trim() }
            }
        }
    }
}

Describe 'Menu groups in lab guides - the rule catches what it should (#346)' {

    It 'flags <case>' -ForEach @(
        @{ case = 'a click with no group'; text = '1. In the left menu, click **Peerings**.' }
        @{ case = 'an arrow path'; text = '3. Navigate to **dev-skycraft-swc-vnet** → **Subnets** → **DatabaseSubnet**' }
        @{ case = 'a bulleted step'; text = '- Open the VM → **Extensions + applications**.' }
        @{ case = 'a group named only in another step'; text = "1. Under **Settings**, click **Backend pools**.`n2. Click **Backend pools** → **+ Add**." }
    ) {
        @(Get-MenuGroupFinding -Text $text | Where-Object { -not $_.Named }).Count | Should -BeGreaterThan 0
    }

    It 'does not flag <case>' -ForEach @(
        @{ case = 'a click that names the group'; text = '1. In the left menu, under **Settings** (expand it if it is collapsed), click **Peerings**.' }
        @{ case = 'a group path with an arrow'; text = '3. Navigate to **dev-skycraft-swc-vnet** → **Settings** (expand it if it is collapsed) → **Subnets**' }
        @{ case = 'a blade of another group name that the list accepts'; text = '3. In the left menu, under **Cost Management** (expand it if it is collapsed), click **Budgets**' }
        @{ case = 'a blade that is not in the list'; text = '1. Click **Overview**.' }
        @{ case = 'a line that is not a list step'; text = 'The **Peerings** blade shows the state of each link.' }
        @{ case = 'a blade that is only named in bold without a click'; text = '1. The **Locks** blade lists the locks.' }
    ) {
        @(Get-MenuGroupFinding -Text $text | Where-Object { -not $_.Named }) | Should -BeNullOrEmpty
    }

    It 'gives the line of the step' {
        $finding = @(Get-MenuGroupFinding -Text "Text`n`n1. Click **Peerings**." | Where-Object { -not $_.Named })
        $finding[0].Line | Should -Be 3
    }
}

Describe 'Menu groups in lab guides - every lab guide (#346)' {

    It 'finds the guides to check' -TestCases @(@{ count = @($script:Guides).Count }) {
        $count | Should -BeGreaterThan 10 -Because 'finding none means the scan is broken'
    }

    It 'finds steps that name a group' -TestCases @(@{ guides = $script:Guides }) {
        $named = 0
        foreach ($guide in $guides) {
            $named += @(Get-MenuGroupFinding -Text (Get-Content -Raw -LiteralPath $guide.path) | Where-Object { $_.Named }).Count
        }
        $named | Should -BeGreaterThan 30 -Because 'the guides name the group of most of these steps; finding none means the scan is broken'
    }

    It '<file> names the group of every blade it clicks' -ForEach @($script:Guides) {
        $findings = @(Get-MenuGroupFinding -Text (Get-Content -Raw -LiteralPath $path) | Where-Object { -not $_.Named } |
                ForEach-Object { "$($_.Line): [$($_.Blade)] $($_.Text)" })
        $findings | Should -BeNullOrEmpty -Because "a collapsed menu group hides the item until it is expanded (#346); write 'under **Group** (expand it if it is collapsed), click **Item**'. Found:`n$($findings -join "`n")"
    }
}

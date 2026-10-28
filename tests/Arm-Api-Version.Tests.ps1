<#
.SYNOPSIS
    Pester 5 test: no lab script, tool, guide or checklist reads or writes an ARM resource by id
    without an explicit -ApiVersion.

.DESCRIPTION
    Az.Resources asks the resource provider for its newest listed version whenever a call reads,
    writes or deletes one resource by id without -ApiVersion. On 2026-10-28 the provider listed 2026-07-01 for
    Microsoft.Network/networkWatchers/connectionMonitors before Sweden Central served it, so every
    lookup of Lab 5.3's connection monitor failed and seven checks reported a monitor that existed
    as missing (issue #452). The same call works or fails depending on what Azure has rolled out
    that day.

    The test parses every tracked PowerShell file under module-*/*/scripts/ and tools/, and every
    PowerShell block in the lab guides and checklists (module-*/*.md and module-*/*/*.md), and
    fails on:
    - New-AzResource, Set-AzResource or Remove-AzResource without -ApiVersion;
    - Get-AzResource with -ResourceId, or with -Name, -ResourceGroupName and -ResourceType (the
      cmdlet builds the id and reads it by id), without -ApiVersion;
    - Get-AzResource -ExpandProperties on a listing, with or without -ApiVersion. The cmdlet reads
      every listed resource by id at the provider's newest version, and an -ApiVersion it is given
      also goes to the listing itself, a Microsoft.Resources call. List without -ExpandProperties
      and read each resource with -ResourceId and -ApiVersion instead.
    A call that splats its arguments cannot be checked and counts as a finding.

    Modules 1 to 3 are pinned by the running course (issue #300), so their calls are listed in
    $AllowedCalls with the number of calls allowed per file. The list is exact: a new call in a
    listed file fails, and so does an entry that no longer matches a call, so the list can only
    shrink. Module 4, Module 5 and tools/ have no entry and may have none.

    Lab tests/ folders are not scanned; their stubs name the cmdlets on purpose. The test fails
    when it finds no file, no versioned call in Module 5 or no guide block, so a broken scan cannot
    pass as a green check, and fixtures prove the rule catches what it is meant to catch.

.EXAMPLE
    Invoke-Pester -Path .\tests\Arm-Api-Version.Tests.ps1

.NOTES
    Project: SkyCraft
    Issue: #452
#>

#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeDiscovery {
    $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path

    # Owed for Modules 1 to 3 (pinned, #300): file -> number of unversioned calls it holds today.
    $script:AllowedCalls = @{
        'module-2-networking/2.1-virtual-networks/scripts/Remove-LabResource.ps1' = 1
        'module-3-compute/3.2-virtual-machines/scripts/Deploy-Bicep.ps1'          = 1
        'module-3-compute/3.2-virtual-machines/scripts/Remove-LabResource.ps1'    = 2
        'module-3-compute/3.3-containers/scripts/Deploy-Bicep.ps1'                = 2
        'module-3-compute/3.3-containers/scripts/Remove-LabResource.ps1'          = 9
        'module-3-compute/3.3-containers/scripts/Test-Lab.ps1'                    = 2
        'module-3-compute/3.3-containers/lab-checklist-3.3.md'                    = 1
        'module-3-compute/3.3-containers/lab-guide-3.3.md'                        = 1
        'module-3-compute/3.4-app-service/scripts/Deploy-Bicep.ps1'               = 1
        'module-3-compute/3.4-app-service/scripts/Test-Lab.ps1'                   = 2
    }

    # Tracked files only: a worktree under .claude/ or a scratch file is not the repository.
    $tracked = @(git -C $repoRoot ls-files -- 'module-*' 'tools')
    $script:Files = foreach ($relative in $tracked) {
        if ($relative -notmatch '^(module-[^/]+/[^/]+/scripts/[^/]+|tools/.+)\.(ps1|psm1)$') { continue }
        @{ file = $relative; path = (Join-Path $repoRoot $relative); kind = 'script'; allowed = [int]$script:AllowedCalls[$relative] }
    }
    $script:Docs = foreach ($relative in $tracked) {
        if ($relative -notmatch '^module-[^/]+/([^/]+/)?[^/]+\.md$') { continue }
        @{ file = $relative; path = (Join-Path $repoRoot $relative); kind = 'doc'; allowed = [int]$script:AllowedCalls[$relative] }
    }
    $script:Allowed = $script:AllowedCalls
}

BeforeAll {
    $script:ArmCmdlets = 'Get-AzResource', 'New-AzResource', 'Set-AzResource', 'Remove-AzResource'

    # The calls in PowerShell text that read or write a resource by id without -ApiVersion, as
    # 'line: text' strings. Line numbers start at $FirstLine.
    function Get-UnversionedArmCall {
        param([string]$Text, [int]$FirstLine = 1)

        $tokens = $null
        $errors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseInput($Text, [ref]$tokens, [ref]$errors)
        $commands = $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] }, $true)
        foreach ($command in $commands) {
            $name = "$($command.GetCommandName())" -replace '^Az\.Resources\\', ''
            if ($name -notin $script:ArmCmdlets) { continue }
            $parameters = @($command.CommandElements | Where-Object { $_ -is [System.Management.Automation.Language.CommandParameterAst] })
            $hasSplat = [bool]($command.CommandElements | Where-Object { $_ -is [System.Management.Automation.Language.VariableExpressionAst] -and $_.Splatted })
            $has = { param($p) [bool]@($parameters | Where-Object { $_.ParameterName.Length -ge 3 -and $p.StartsWith($_.ParameterName, [System.StringComparison]::OrdinalIgnoreCase) }).Count }
            $finding = "$($command.Extent.StartLineNumber + $FirstLine - 1): $($command.Extent.Text -replace '\s+', ' ')"
            if ($hasSplat) { $finding; continue }
            if ($name -eq 'Get-AzResource') {
                $byId = (& $has 'ResourceId') -or ((& $has 'Name') -and (& $has 'ResourceGroupName') -and (& $has 'ResourceType'))
                # A listing with -ExpandProperties reads each resource at the provider's newest version.
                if (-not $byId -and (& $has 'ExpandProperties')) { $finding; continue }
                if (-not $byId) { continue }
            }
            if (-not (& $has 'ApiVersion')) { $finding }
        }
    }

    # The same for a Markdown file's PowerShell blocks.
    function Get-UnversionedArmDocCall {
        param([string]$Text)

        $blocks = [regex]::Matches($Text, '(?ms)^[ \t]*```(?:powershell|pwsh|ps1)[ \t]*\r?$(?<body>.*?)^[ \t]*```')
        foreach ($block in $blocks) {
            $bodyGroup = $block.Groups['body']
            $firstLine = ($Text.Substring(0, $bodyGroup.Index) -split "`n").Count
            Get-UnversionedArmCall -Text $bodyGroup.Value -FirstLine $firstLine
        }
    }

    function Get-VersionedArmCallCount {
        param([string]$Text)
        $tokens = $null
        $errors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseInput($Text, [ref]$tokens, [ref]$errors)
        @($ast.FindAll({
            param($n)
            $n -is [System.Management.Automation.Language.CommandAst] -and $n.GetCommandName() -in $script:ArmCmdlets -and
                @($n.CommandElements | Where-Object { $_ -is [System.Management.Automation.Language.CommandParameterAst] -and $_.ParameterName -eq 'ApiVersion' }).Count
        }, $true)).Count
    }
}

Describe 'ARM calls with an explicit api-version - the rule catches what it should (#452)' {

    It 'flags <case>' -ForEach @(
        @{ case = 'Get-AzResource -ResourceId'; text = 'Get-AzResource -ResourceId $id -ExpandProperties -ErrorAction Stop' }
        @{ case = 'Get-AzResource -ResourceId in a pipeline'; text = '(Get-AzResource -ResourceId $id -ErrorAction SilentlyContinue).Tags' }
        @{ case = 'Get-AzResource -ResourceId, module-qualified'; text = 'Az.Resources\Get-AzResource -ResourceId $id' }
        @{ case = 'New-AzResource'; text = 'New-AzResource -ResourceId $id -Location $l -Properties @{} -Force' }
        @{ case = 'New-AzResource over two lines'; text = "New-AzResource -ResourceId `$id -Location `$l ``n    -Properties @{} -Force" }
        @{ case = 'a splatted call'; text = 'Get-AzResource @arguments' }
        @{ case = 'a -ApiVersion that is only in a comment'; text = "Get-AzResource -ResourceId `$id # -ApiVersion 2024-05-01" }
        @{ case = 'Get-AzResource by name, group and type'; text = "Get-AzResource -ResourceGroupName `$rg -ResourceType 'Microsoft.App/containerApps' -Name `$n -ErrorAction Stop" }
        @{ case = 'a listing with -ExpandProperties'; text = "Get-AzResource -ResourceType 'Microsoft.OperationalInsights/workspaces' -ExpandProperties -ErrorAction Stop" }
        @{ case = 'a listing with -ExpandProperties and -ApiVersion'; text = "Get-AzResource -ResourceGroupName `$rg -ExpandProperties -ApiVersion 2023-09-01" }
        @{ case = 'Remove-AzResource'; text = 'Remove-AzResource -ResourceId $id -Force -ErrorAction Stop' }
        @{ case = 'Set-AzResource'; text = 'Set-AzResource -ResourceId $id -Tag @{} -Force' }
    ) {
        @(Get-UnversionedArmCall -Text $text).Count | Should -Be 1
    }

    It 'does not flag <case>' -ForEach @(
        @{ case = 'a versioned read'; text = "Get-AzResource -ResourceId `$id -ApiVersion '2024-05-01' -ExpandProperties -ErrorAction Stop" }
        @{ case = 'a versioned read with a variable'; text = 'Get-AzResource -ResourceId $id -ApiVersion $version' }
        @{ case = 'a versioned write'; text = "New-AzResource -ResourceId `$id -Location `$l -ApiVersion 2024-07-01 -Properties @{} -Force" }
        @{ case = 'a list by type'; text = "Get-AzResource -ResourceType 'Microsoft.RecoveryServices/vaults' -ErrorAction Stop" }
        @{ case = 'a list by group'; text = 'Get-AzResource -ResourceGroupName $rg -ErrorAction Stop' }
        @{ case = 'a list by group and type'; text = "Get-AzResource -ResourceGroupName `$rg -ResourceType 'Microsoft.Insights/dataCollectionRules'" }
        @{ case = 'a versioned read by name, group and type'; text = "Get-AzResource -ResourceGroupName `$rg -ResourceType `$t -Name `$n -ApiVersion 2023-03-11 -ExpandProperties" }
        @{ case = 'a versioned delete'; text = "Remove-AzResource -ResourceId `$id -ApiVersion '2023-03-11' -Force" }
        @{ case = 'another cmdlet that starts with the same name'; text = 'Remove-AzResourceGroup -Name $rg -Force' }
        @{ case = 'a comment or a string that names them'; text = "# Get-AzResource -ResourceId is not used`nWrite-Host 'New-AzResource -ResourceId x'" }
        @{ case = 'another cmdlet with a similar name'; text = 'New-AzResourceGroup -Name x -Location y' }
    ) {
        @(Get-UnversionedArmCall -Text $text) | Should -BeNullOrEmpty
    }

    It 'gives the line of the call' {
        $finding = @(Get-UnversionedArmCall -Text "`$a = 1`n`$b = Get-AzResource -ResourceId `$id")
        $finding[0] | Should -BeLike '2: *'
    }

    It 'finds an unversioned call in a guide''s PowerShell block and ignores other blocks' {
        $fence = '```'
        $text = "Text`n`n$($fence)powershell`nNew-AzResource -ResourceId `$id -Force`n$fence`n`n$($fence)bash`nNew-AzResource -ResourceId x`n$fence`n"
        $finding = @(Get-UnversionedArmDocCall -Text $text)
        $finding.Count | Should -Be 1
        $finding[0] | Should -BeLike '4: *'
    }
}

Describe 'ARM calls with an explicit api-version - every lab script, tool, guide and checklist (#452)' {

    It 'finds lab scripts and tools to check' -TestCases @(@{ count = @($script:Files).Count }) {
        $count | Should -BeGreaterThan 20 -Because 'finding none means the scan is broken'
    }

    It 'finds the guides and checklists to check' -TestCases @(@{ count = @($script:Docs).Count }) {
        $count | Should -BeGreaterThan 20 -Because 'finding none means the scan is broken'
    }

    It 'finds versioned ARM calls in Module 5' -TestCases @(@{ files = $script:Files }) {
        $calls = 0
        foreach ($entry in @($files | Where-Object { $_.file -like 'module-5-*' })) {
            $calls += Get-VersionedArmCallCount -Text (Get-Content -Raw -LiteralPath $entry.path)
        }
        $calls | Should -BeGreaterOrEqual 10 -Because 'Lab 5.1, 5.2 and 5.3 read and delete resources by id with an explicit -ApiVersion'
    }

    It '<file> has no ARM call without -ApiVersion beyond its allowance' -ForEach @(@($script:Files) + @($script:Docs)) {
        $text = Get-Content -Raw -LiteralPath $path
        $findings = @(if ($kind -eq 'doc') { Get-UnversionedArmDocCall -Text $text } else { Get-UnversionedArmCall -Text $text })
        $findings.Count | Should -Be $allowed -Because "an ARM call by id needs an explicit -ApiVersion that Sweden Central serves, and a listing must not use -ExpandProperties (#452). Found:`n$($findings -join "`n")"
    }

    It 'lists in the allowance only files that exist' -TestCases @(@{ allowed = $script:Allowed; files = @(@($script:Files) + @($script:Docs) | ForEach-Object { $_.file }) }) {
        $stale = @($allowed.Keys | Where-Object { $files -notcontains $_ })
        $stale | Should -BeNullOrEmpty -Because 'an allowance for a file that is gone hides nothing and should be removed'
    }

    It 'allows no call in Module 4, Module 5 or tools' -TestCases @(@{ allowed = $script:Allowed }) {
        $owed = @($allowed.Keys | Where-Object { $_ -notmatch '^module-[123]-' })
        $owed | Should -BeNullOrEmpty -Because 'only Modules 1 to 3 are pinned by the running course (#300)'
    }
}

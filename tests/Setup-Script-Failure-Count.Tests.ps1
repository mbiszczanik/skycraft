<#
.SYNOPSIS
    Pester 5 test: a lab setup script that printed an [ERROR] does not end with exit 0.

.DESCRIPTION
    Regression guard for issue #340. Four setup scripts printed [ERROR] (or skipped a required
    object), carried on and ended through Exit-Lab with a constant 0, so a failed step looked
    done to the learner and to anything that reads the exit code.

    Over the scripts listed in $Scripts, parsed rather than matched with a regex:
      - every Write-Host that prints [ERROR] sits in a block that counts it (a ++) or ends the
        script (Exit-Lab), so no failure is only printed;
      - an Exit-Lab call takes a count that is not the literal 0, so the end of the script can
        report what failed;
      - no [WARNING] ... Skipping line stands in for a required object that is missing.

    Offline only. The live run of a failing path is recorded on the pull request.

.EXAMPLE
    Invoke-Pester -Path .\tests\Setup-Script-Failure-Count.Tests.ps1

.NOTES
    Project: SkyCraft
#>

#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeDiscovery {
    $root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    $script:Cases = @(
        'module-1-identities-governance/1.1-entra-users-groups/scripts/New-LabUser.ps1'
        'module-1-identities-governance/1.2-rbac/scripts/New-LabRoleAssignment.ps1'
        'module-2-networking/2.1-virtual-networks/scripts/Deploy-Networking.ps1'
        'module-2-networking/2.3-name-resolution/scripts/Deploy-DNS.ps1'
    ) | ForEach-Object { @{ Relative = $_; Path = (Join-Path $root $_) } }
}

Describe '#340 setup scripts count their failures' -ForEach $script:Cases {

    BeforeAll {
        $text = Get-Content -LiteralPath $Path -Raw
        $script:ast = [System.Management.Automation.Language.Parser]::ParseInput($text, [ref]$null, [ref]$null)
        $script:errorPrints = @($script:ast.FindAll({
                    param($n)
                    $n -is [System.Management.Automation.Language.CommandAst] -and
                    $n.GetCommandName() -eq 'Write-Host' -and $n.Extent.Text -match '\[ERROR\]'
                }, $true))
        $script:exitLabCalls = @($script:ast.FindAll({
                    param($n)
                    $n -is [System.Management.Automation.Language.CommandAst] -and $n.GetCommandName() -eq 'Exit-Lab'
                }, $true))
    }

    It '<Relative> prints [ERROR] somewhere (the guard has something to check)' {
        $script:errorPrints.Count | Should -BeGreaterThan 0
    }

    It '<Relative> counts or ends on every [ERROR] it prints' {
        $uncounted = foreach ($print in $script:errorPrints) {
            $block = $print.Parent
            while ($block -and $block -isnot [System.Management.Automation.Language.StatementBlockAst] -and $block -isnot [System.Management.Automation.Language.NamedBlockAst]) {
                $block = $block.Parent
            }
            $blockText = if ($block) { $block.Extent.Text } else { '' }
            if ($blockText -notmatch '\+\+' -and $blockText -notmatch 'Exit-Lab') {
                "line $($print.Extent.StartLineNumber): $($print.Extent.Text.Trim())"
            }
        }
        @($uncounted) | Should -BeNullOrEmpty -Because 'an [ERROR] that is only printed leaves the run at exit 0'
    }

    It '<Relative> ends through an Exit-Lab call that takes a count, not the literal 0' {
        $counted = @($script:exitLabCalls | Where-Object {
                $argText = ($_.CommandElements | Select-Object -Skip 1 | ForEach-Object { $_.Extent.Text }) -join ' '
                $argText -match '-FailureCount\s+\S' -and $argText -notmatch '-FailureCount\s+(0|1)\b'
            })
        $counted.Count | Should -BeGreaterThan 0
    }

    It '<Relative> does not skip a missing required object with a [WARNING]' {
        $skips = @($script:ast.FindAll({
                    param($n)
                    $n -is [System.Management.Automation.Language.CommandAst] -and
                    $n.GetCommandName() -eq 'Write-Host' -and $n.Extent.Text -match '\[WARNING\].*Skipping'
                }, $true))
        $skips.Count | Should -Be 0
    }
}

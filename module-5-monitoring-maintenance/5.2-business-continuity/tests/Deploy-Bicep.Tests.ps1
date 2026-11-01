<#
.SYNOPSIS
    Pester 5 tests that Lab 5.2 - Business Continuity Deploy-Bicep.ps1 changes nothing under -WhatIf (#370).

.DESCRIPTION
    Every state-changing Az cmdlet call in the script must sit where -WhatIf cannot reach it:
    in the else of an if ($WhatIf), under -not $WhatIf, or after an if ($WhatIf) that leaves
    the loop or script. The script is read with the PowerShell parser, not run: the deployment
    cmdlets are aliases in Az.Resources, so a run whose guard regressed could reach Azure.

.NOTES
    Project: SkyCraft
    Lab: 5.2 - Business Continuity
#>

#Requires -Version 7.0
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    $script:ScriptPath = (Resolve-Path (Join-Path $PSScriptRoot '..' 'scripts' 'Deploy-Bicep.ps1')).Path
    $parseErrors = $null
    $script:Ast = [System.Management.Automation.Language.Parser]::ParseFile($script:ScriptPath, [ref]$null, [ref]$parseErrors)
    if ($parseErrors) { throw "$($script:ScriptPath) does not parse: $($parseErrors[0].Message)" }

    $script:IfAst = [System.Management.Automation.Language.IfStatementAst]
    $script:Mutating = '^(New|Set|Register|Update|Remove|Add|Install|Enable|Disable|Start|Stop|Invoke)-Az'

    function script:Test-WhatIfCondition {
        param($Condition)
        $Condition.Extent.Text -match '^\$WhatIf$'
    }

    function script:Test-NotReachableUnderWhatIf {
        param($Node)
        $child = $Node
        $parent = $Node.Parent
        while ($parent) {
            if ($parent -is $script:IfAst) {
                for ($i = 0; $i -lt $parent.Clauses.Count; $i++) {
                    $clause = $parent.Clauses[$i]
                    if (-not $clause.Item2.Extent.Text.Contains($child.Extent.Text)) { continue }
                    if ($clause.Item1.Extent.Text -match '-not\s+\$WhatIf') { return $true }
                    for ($j = 0; $j -lt $i; $j++) {
                        if (script:Test-WhatIfCondition $parent.Clauses[$j].Item1) { return $true }
                    }
                }
                if ($parent.ElseClause -and $parent.ElseClause.Extent.StartOffset -le $child.Extent.StartOffset -and
                    $child.Extent.EndOffset -le $parent.ElseClause.Extent.EndOffset -and
                    (script:Test-WhatIfCondition $parent.Clauses[0].Item1)) { return $true }
            }
            if ($parent -is [System.Management.Automation.Language.StatementBlockAst] -or
                $parent -is [System.Management.Automation.Language.NamedBlockAst]) {
                foreach ($stmt in $parent.Statements) {
                    if ($stmt.Extent.StartOffset -ge $child.Extent.StartOffset) { break }
                    if ($stmt -is $script:IfAst -and (script:Test-WhatIfCondition $stmt.Clauses[0].Item1) -and
                        $stmt.Clauses[0].Item2.Extent.Text -match '\b(continue|exit|return|Exit-Lab)\b') { return $true }
                }
            }
            $child = $parent
            $parent = $parent.Parent
        }
        $false
    }

    $script:Calls = @($script:Ast.FindAll({
                param($n)
                $n -is [System.Management.Automation.Language.CommandAst] -and $n.GetCommandName() -match $script:Mutating
            }, $true))
}

Describe 'Lab 5.2 - Business Continuity Deploy-Bicep.ps1 under -WhatIf (#370)' {
    It 'declares the -WhatIf switch' {
        $script:Ast.ParamBlock.Parameters.Name.VariablePath.UserPath | Should -Contain 'WhatIf'
    }

    It 'finds the state-changing calls it is meant to guard' {
        $script:Calls.Count | Should -BeGreaterThan 0
    }

    It 'guards the resource provider registration' {
        $reg = @($script:Calls | Where-Object { $_.GetCommandName() -eq 'Register-AzResourceProvider' })
        $reg.Count | Should -BeGreaterThan 0
        foreach ($c in $reg) { script:Test-NotReachableUnderWhatIf $c | Should -BeTrue }
    }

    It 'keeps every state-changing call out of the -WhatIf path' {
        $exposed = @($script:Calls | Where-Object { -not (script:Test-NotReachableUnderWhatIf $_) } |
                ForEach-Object { "$($_.GetCommandName()) at line $($_.Extent.StartLineNumber)" })
        $exposed | Should -BeNullOrEmpty -Because 'these calls run under -WhatIf'
    }
}

Describe 'Lab 5.2 - Business Continuity Deploy-Bicep.ps1 step 7 cannot end the script silently (#366)' {
    BeforeAll {
        $script:TryAst = [System.Management.Automation.Language.TryStatementAst]
        $script:VmLoop = $script:Ast.Find({
                param($n)
                $n -is [System.Management.Automation.Language.ForEachStatementAst] -and $n.Variable.VariablePath.UserPath -eq 'vmName'
            }, $true)
    }

    It 'finds the loop over the VMs' {
        $script:VmLoop | Should -Not -BeNullOrEmpty
    }

    It 'runs the loop inside a try whose finally fails the run with Exit-Lab when the loop did not finish' {
        $try = $script:VmLoop.Parent
        while ($try -and $try -isnot $script:TryAst) { $try = $try.Parent }
        $try | Should -Not -BeNullOrEmpty -Because 'a stopped pipeline throws past every catch, so only a finally still runs'
        $try.Finally | Should -Not -BeNullOrEmpty
        $try.Finally.Extent.Text | Should -Match 'Exit-Lab\s+-FailureCount\s+1'
        $try.Finally.Extent.Text | Should -Match '-not\s+\$vmStepsDone'
    }

    It 'sets the finished flag after the loop, inside the try' {
        $try = $script:VmLoop.Parent
        while ($try -and $try -isnot $script:TryAst) { $try = $try.Parent }
        $last = $try.Body.Statements[-1]
        $last.Extent.Text | Should -Match '^\$vmStepsDone\s*=\s*\$true$'
        $last.Extent.StartOffset | Should -BeGreaterThan $script:VmLoop.Extent.EndOffset
    }

    It 'collects the Az pipelines before taking the first element' {
        $names = 'Get-AzResourceProvider', 'Get-AzRecoveryServicesBackupJob'
        foreach ($name in $names) {
            $cmd = $script:Ast.Find({ param($n) $n -is [System.Management.Automation.Language.CommandAst] -and $n.GetCommandName() -eq $name }, $true)
            $cmd | Should -Not -BeNullOrEmpty
            $pipeline = $cmd.Parent
            $pipeline.PipelineElements.Count | Should -BeGreaterThan 0
            ($pipeline.PipelineElements | Where-Object { $_ -is [System.Management.Automation.Language.CommandAst] -and $_.GetCommandName() -in 'Select-Object', 'select' }) |
                Should -BeNullOrEmpty -Because "$name ran with -ErrorAction SilentlyContinue into Select-Object -First and ended the script silently"
        }
    }
}

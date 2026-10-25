<#
.SYNOPSIS
    Pester 5 test: the Module 2 PowerShell deploy scripts write the four canonical tags, as the
    Portal steps and the Bicep path do.

.DESCRIPTION
    Issue #274: Deploy-Networking.ps1, Deploy-DNS.ps1 and Deploy-LoadBalancer.ps1 wrote tags
    without Owner, so a re-run replaced the tags of a Portal-built load balancer and Lab 2.3's
    Test-Lab.ps1 failed on the missing Owner tag. Every hashtable literal that sets Project must
    also set Environment (or have it added before use), CostCenter and Owner.

.EXAMPLE
    Invoke-Pester -Path .\tests\Module2-Script-Tags.Tests.ps1

.NOTES
    Project: SkyCraft
    Issue:   #274
#>

#Requires -Version 7.0
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeDiscovery {
    $root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    $script:Scripts = Get-ChildItem -Path (Join-Path $root 'module-2-networking') -Recurse -Filter 'Deploy-*.ps1' |
        Where-Object Name -ne 'Deploy-Bicep.ps1' |
        ForEach-Object { @{ name = $_.Name; path = $_.FullName } }
}

Describe 'Module 2 deploy scripts - canonical tags' {

    It '<name> sets Owner and CostCenter wherever it sets Project' -ForEach $script:Scripts {
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$null, [ref]$null)
        $tables = $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.HashtableAst] }, $true) |
            Where-Object { $_.KeyValuePairs.Item1.Extent.Text -contains 'Project' }
        @($tables).Count | Should -BeGreaterThan 0 -Because "$name tags what it creates"
        foreach ($table in $tables) {
            $keys = $table.KeyValuePairs.Item1.Extent.Text
            $keys | Should -Contain 'Owner' -Because "line $($table.Extent.StartLineNumber) of $name must match the Portal and Bicep tags"
            $keys | Should -Contain 'CostCenter' -Because "line $($table.Extent.StartLineNumber) of $name must match the Portal and Bicep tags"
        }
    }
}

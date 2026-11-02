<#
.SYNOPSIS
    Pester 5 tests: Lab 5.1 Deploy-Bicep.ps1 retries a Failed DCR deployment (#473).

.DESCRIPTION
    A fresh workspace needs about a minute before its tables exist, so the DCR deployment can end
    Failed with InvalidPayload. The retry loop must cover a Failed deployment the cmdlet returns
    without throwing, not only a thrown error. Static checks on the script text; no subscription.

.NOTES
    Project: SkyCraft
    Lab: 5.1 - Azure Monitor
    Issue: #473
#>

#Requires -Version 7.0
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    $script:Text = Get-Content -LiteralPath (Join-Path $PSScriptRoot '..' 'scripts' 'Deploy-Bicep.ps1') -Raw
}

Describe 'Lab 5.1 Deploy-Bicep.ps1 retry' {
    It 'retries a returned Failed deployment whose operation error is a table-not-ready error' {
        $script:Text | Should -Match "ProvisioningState -eq 'Failed' -and \`$attempt -lt \`$maxAttempts"
        $script:Text | Should -Match 'Get-AzDeploymentOperation -DeploymentName'
        $script:Text | Should -Match "-match 'InvalidOutputTable\|not available for destination\|InvalidPayload'"
    }

    It 'uses the cmdlet, not its alias, so a test stub can replace it' {
        $script:Text | Should -Not -Match 'Get-AzSubscriptionDeploymentOperation'
    }

    It 'still reports a Failed state that is not a table-not-ready error' {
        $script:Text | Should -Match "Deployment finished with state: \`$\(\`$deployment.ProvisioningState\)"
    }
}

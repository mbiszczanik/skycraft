<#
.SYNOPSIS
    Pester 5 tests: Lab 3.4 plan SKU parameter and the stop on a throttled plan create (issue #439).

.DESCRIPTION
    On a Free Trial subscription Azure refused the App Service plan create with HTTP 429 and retried
    for 3.5 hours before it failed the deployment. These tests pin the fix:

      1. Get-LabThrottleMessage reads a throttling status message (string or object) and returns
         nothing for other failures, empty operations and null.
      2. Lab 3.4's main.bicep takes the plan SKU as parPlanSkuName, default P0v4, allowing only
         P0v4, P0v3 and S1, and does not hard-code the SKU on the plan.
      3. Deploy-Bicep.ps1 passes -PlanSku to the template, deploys as a job, and stops the
         deployment on a throttled or never-created plan.
      4. Test-Lab.ps1 accepts the fallback SKUs.

    Nothing reaches Azure.

.EXAMPLE
    Invoke-Pester -Path .\tests\Lab34-Plan-Sku-Throttle.Tests.ps1

.NOTES
    Project: SkyCraft
    Lab: 3.4 - App Service
    Issue: #439
#>

#Requires -Version 7.0
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    $script:LabRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' 'module-3-compute' '3.4-app-service')).Path
    Import-Module (Join-Path $PSScriptRoot '..' 'tools' 'LabCommon.psm1') -Force
    $script:Bicep = Get-Content -Raw -LiteralPath (Join-Path $script:LabRoot 'bicep' 'main.bicep')
    $script:Deploy = Get-Content -Raw -LiteralPath (Join-Path $script:LabRoot 'scripts' 'Deploy-Bicep.ps1')
    $script:TestLab = Get-Content -Raw -LiteralPath (Join-Path $script:LabRoot 'scripts' 'Test-Lab.ps1')
}

Describe 'Get-LabThrottleMessage' {
    It 'returns the message of a 429 operation given as a string' {
        $op = [pscustomobject]@{ StatusMessage = 'App Service Plan Create operation is throttled for subscription x. (Code: 429, ExtendedCode: 51025)' }
        Get-LabThrottleMessage -Operation $op | Should -Match 'throttled'
    }

    It 'returns the message of a 429 operation given as an object' {
        $op = [pscustomobject]@{ StatusMessage = [pscustomobject]@{ status = 'Failed'; error = [pscustomobject]@{ code = 'TooManyRequests'; message = 'Slow down' } } }
        Get-LabThrottleMessage -Operation $op | Should -Match 'TooManyRequests'
    }

    It 'finds the throttled one among several operations' {
        $ops = @(
            [pscustomobject]@{ StatusMessage = $null }
            [pscustomobject]@{ StatusMessage = 'Quota exceeded for P0v4' }
            [pscustomobject]@{ StatusMessage = 'throttled (Code: 429)' }
        )
        Get-LabThrottleMessage -Operation $ops | Should -Be 'throttled (Code: 429)'
    }

    It 'returns nothing for a quota error' {
        $op = [pscustomobject]@{ StatusMessage = 'Operation cannot be completed without additional quota. (Code: Unauthorized)' }
        Get-LabThrottleMessage -Operation $op | Should -BeNullOrEmpty
    }

    It 'returns nothing for no operations, null and an operation without a message' {
        Get-LabThrottleMessage -Operation @() | Should -BeNullOrEmpty
        Get-LabThrottleMessage -Operation $null | Should -BeNullOrEmpty
        Get-LabThrottleMessage -Operation ([pscustomobject]@{ StatusMessage = $null }) | Should -BeNullOrEmpty
    }
}

Describe 'Lab 3.4 main.bicep plan SKU' {
    It 'declares parPlanSkuName defaulting to P0v4 and allowing only P0v4, P0v3 and S1' {
        $script:Bicep | Should -Match "(?s)@allowed\(\['P0v4', 'P0v3', 'S1'\]\)\s*param parPlanSkuName string = 'P0v4'"
    }

    It 'gives the plan the parameter, not a literal SKU' {
        $script:Bicep | Should -Match 'skuName: parPlanSkuName'
        $script:Bicep | Should -Not -Match "skuName: 'P0v"
    }
}

Describe 'Lab 3.4 Deploy-Bicep.ps1' {
    It 'takes -PlanSku limited to the template''s SKUs and passes it on' {
        $script:Deploy | Should -Match "ValidateSet\('P0v4', 'P0v3', 'S1'\)\]\s*\[string\]\`$PlanSku = 'P0v4'"
        $script:Deploy | Should -Match 'parPlanSkuName\s*=\s*\$PlanSku'
    }

    It 'runs the deployment as a job and stops it on a throttle or a plan that is not created in time' {
        $script:Deploy | Should -Match 'New-AzSubscriptionDeployment @deployParams -AsJob'
        $script:Deploy | Should -Match 'Get-LabThrottleMessage'
        $script:Deploy | Should -Match 'Stop-AzSubscriptionDeployment'
        $script:Deploy | Should -Match '\$PlanWaitMinutes'
    }

    It 'names the way out when the plan SKU has no quota' {
        $script:Deploy | Should -Match '(?s)catch \{.*?additional quota.*?-PlanSku P0v3 or -PlanSku S1.*?Exit-Lab -FailureCount 1'
    }

    It 'exits 1 after stopping' {
        $script:Deploy | Should -Match '(?s)Stop-AzSubscriptionDeployment.*?Exit-Lab -FailureCount 1'
    }
}

Describe 'Lab 3.4 Test-Lab.ps1' {
    It 'accepts the fallback SKUs' {
        $script:TestLab | Should -Match '\$asp\.Sku\.Name -in @\("P0v4", "P0v3", "S1"\)'
    }
}

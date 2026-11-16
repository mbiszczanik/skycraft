<#
.SYNOPSIS
    Pester 5 tests for the offline lab cost estimate and its comparison with a guide's stated cost.

.DESCRIPTION
    Fixture price and resource lists live in this file. No test makes a network or Azure call, and
    the last test fails if the module names a command that would.

.EXAMPLE
    Invoke-Pester -Path .\tests\LabCostEstimate.Tests.ps1

.NOTES
    Project: SkyCraft
    Issue:   #528
#>

#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    $script:ModulePath = Join-Path $PSScriptRoot '../tools/LabCostEstimate.psm1'
    Import-Module $script:ModulePath -Force -Verbose:$false

    $script:Prices = @(
        [pscustomobject]@{ serviceName = 'Virtual Machines'; skuName = 'D2s v5'; armRegionName = 'swedencentral'; unitOfMeasure = '1 Hour'; retailPrice = 0.10 }
        [pscustomobject]@{ serviceName = 'Virtual Machines'; skuName = 'D2s v5'; armRegionName = 'westeurope'; unitOfMeasure = '1 Hour'; retailPrice = 0.50 }
        [pscustomobject]@{ serviceName = 'Storage'; skuName = 'Standard LRS'; armRegionName = 'swedencentral'; unitOfMeasure = '1 GB/Month'; retailPrice = 0.02 }
        [pscustomobject]@{ serviceName = 'Storage'; skuName = 'Standard LRS'; armRegionName = 'swedencentral'; unitOfMeasure = '10K'; retailPrice = 9.99 }
        [pscustomobject]@{ serviceName = 'Virtual Network'; skuName = 'Standard'; armRegionName = 'swedencentral'; unitOfMeasure = '1 Hour'; retailPrice = 0.005 }
        [pscustomobject]@{ serviceName = 'Virtual Network'; skuName = 'Standard'; armRegionName = 'swedencentral'; unitOfMeasure = '1 Hour'; retailPrice = 0.004 }
    )
    $script:Vm  = @{ Name = 'vm1'; Type = 'Microsoft.Compute/virtualMachines'; Sku = 'D2s v5'; Quantity = 2; Region = 'swedencentral' }
    $script:Vnet = @{ Name = 'vnet1'; Type = 'Microsoft.Network/virtualNetworks'; Sku = 'n/a'; Quantity = 1; Region = 'swedencentral' }
    $script:Ghost = @{ Name = 'odd1'; Type = 'Microsoft.Compute/virtualMachines'; Sku = 'M416'; Quantity = 1; Region = 'swedencentral' }
}

Describe 'Get-LabCostEstimate' {
    It 'returns one row per resource' {
        $rows = @(Get-LabCostEstimate -Resource @($script:Vm, $script:Vnet, $script:Ghost) -PriceList $script:Prices)
        $rows.Count | Should -Be 3
        $rows.Name | Should -Be @('vm1', 'vnet1', 'odd1')
    }

    It 'prices an hourly item at 730 hours times quantity in the resource region' {
        $row = Get-LabCostEstimate -Resource @($script:Vm) -PriceList $script:Prices
        $row.Status | Should -Be 'priced'
        $row.MonthlyCost | Should -Be 146.00
    }

    It 'takes a per-GB-month item as is and ignores a unit it cannot convert' {
        $storage = @{ Name = 'st1'; Type = 'Microsoft.Storage/storageAccounts'; Sku = 'Standard LRS'; Quantity = 100; Region = 'swedencentral' }
        $row = Get-LabCostEstimate -Resource @($storage) -PriceList $script:Prices
        $row.MonthlyCost | Should -Be 2.00
    }

    It 'takes the highest price when several items match' {
        $ip = @{ Name = 'ip1'; Type = 'Microsoft.Network/publicIPAddresses'; Sku = 'Standard'; Quantity = 1; Region = 'swedencentral' }
        $row = Get-LabCostEstimate -Resource @($ip) -PriceList $script:Prices
        $row.MonthlyCost.ToString('0.00', [cultureinfo]::InvariantCulture) | Should -Be '3.65'
    }

    It 'marks a resource with no matching price unknown, with no number' {
        $row = Get-LabCostEstimate -Resource @($script:Ghost) -PriceList $script:Prices
        $row.Status | Should -Be 'unknown'
        $row.MonthlyCost | Should -BeNullOrEmpty
    }

    It 'does not count an unknown row as zero in the total' {
        $rows = Get-LabCostEstimate -Resource @($script:Vm, $script:Ghost) -PriceList $script:Prices
        $result = Compare-LabCostEstimate -Estimate $rows -StatedCost 1000
        $result.KnownTotal | Should -Be 146.00
        $result.UnknownCount | Should -Be 1
    }

    It 'labels a type on the no-charge list' {
        $row = Get-LabCostEstimate -Resource @($script:Vnet) -PriceList $script:Prices
        $row.Status | Should -Be 'no charge'
        $row.MonthlyCost | Should -Be 0
    }

    It 'does not price a resource from another region' {
        $other = @{ Name = 'vm2'; Type = 'Microsoft.Compute/virtualMachines'; Sku = 'D2s v5'; Quantity = 1; Region = 'northeurope' }
        (Get-LabCostEstimate -Resource @($other) -PriceList $script:Prices).Status | Should -Be 'unknown'
    }

    It 'throws and names the resource list when it is empty' {
        { Get-LabCostEstimate -Resource @() -PriceList $script:Prices } | Should -Throw '*resource list is empty*'
    }

    It 'throws and names the price list when it is empty' {
        { Get-LabCostEstimate -Resource @($script:Vm) -PriceList @() } | Should -Throw '*price list is empty*'
    }
}

Describe 'Compare-LabCostEstimate' {
    BeforeAll {
        $script:Rows = @(Get-LabCostEstimate -Resource @($script:Vm) -PriceList $script:Prices)   # 146.00
    }

    It 'reports within when the total is under the stated cost' {
        $r = Compare-LabCostEstimate -Estimate $script:Rows -StatedCost 200
        $r.Verdict | Should -Be 'within'
        $r.Clean | Should -BeTrue
    }

    It 'reports within when the total equals the stated cost plus the margin' {
        # 146 = 116.8 * 1.25
        (Compare-LabCostEstimate -Estimate $script:Rows -StatedCost 116.8 -MarginPercent 25).Verdict | Should -Be 'within'
    }

    It 'reports exceeds when the total is above the stated cost plus the margin' {
        $r = Compare-LabCostEstimate -Estimate $script:Rows -StatedCost 100 -MarginPercent 25
        $r.Verdict | Should -Be 'exceeds'
        $r.Clean | Should -BeFalse
    }

    It 'uses a margin of 25 percent when none is given' {
        (Compare-LabCostEstimate -Estimate $script:Rows -StatedCost 116.8).Limit | Should -Be 146.00
    }

    It 'says next to the verdict that a price is missing and is not a clean pass' {
        $rows = @(Get-LabCostEstimate -Resource @($script:Vm, $script:Ghost) -PriceList $script:Prices)
        $r = Compare-LabCostEstimate -Estimate $rows -StatedCost 1000
        $r.Verdict | Should -Be 'within'
        $r.Clean | Should -BeFalse
        $r.Message | Should -Match '^within: .*1 resource\(s\) have no price'
    }

    It 'throws and names the estimate when it is empty' {
        { Compare-LabCostEstimate -Estimate @() -StatedCost 10 } | Should -Throw '*estimate is empty*'
    }

    It 'treats an all-unknown estimate as incomplete, not as free' {
        $rows = @(Get-LabCostEstimate -Resource @($script:Ghost) -PriceList $script:Prices)
        (Compare-LabCostEstimate -Estimate $rows -StatedCost 10).Clean | Should -BeFalse
    }
}

Describe 'Offline' {
    It 'names no command that reaches the network or Azure' {
        $tokens = $null; $errors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path $script:ModulePath).Path, [ref]$tokens, [ref]$errors)
        $errors | Should -BeNullOrEmpty
        $commands = $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] }, $true) |
            ForEach-Object { $_.GetCommandName() } | Where-Object { $_ }
        $commands | Where-Object { $_ -match '^(Invoke-RestMethod|Invoke-WebRequest|irm|iwr|curl|wget|az|.*-Az.*|Connect-.*)$' } |
            Should -BeNullOrEmpty
    }
}

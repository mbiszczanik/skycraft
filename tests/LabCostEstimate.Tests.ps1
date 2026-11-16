<#
.SYNOPSIS
    Pester 5 test: the lab cost estimate prices a resource list and compares it with the guide.

.DESCRIPTION
    Covers tools/LabCostEstimate.psm1 with a fixture price list and resource list held in this
    file. No network or Azure call: the price list is data.

.EXAMPLE
    Invoke-Pester -Path .\tests\LabCostEstimate.Tests.ps1

.NOTES
    Project: SkyCraft
#>

#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '../tools/LabCostEstimate.psm1') -Force -Verbose:$false

    # Retail prices API shape. The Standard_B2s hourly price is 0.05, so 2 VMs cost 73.00 a month.
    $script:Prices = @(
        [pscustomobject]@{ serviceName = 'Virtual Machines'; skuName = 'B2s'; armRegionName = 'swedencentral'; unitOfMeasure = '1 Hour'; retailPrice = 0.05 }
        [pscustomobject]@{ serviceName = 'Virtual Machines'; skuName = 'B2s'; armRegionName = 'westeurope'; unitOfMeasure = '1 Hour'; retailPrice = 0.5 }
        [pscustomobject]@{ serviceName = 'Storage'; skuName = 'Standard LRS'; armRegionName = 'swedencentral'; unitOfMeasure = '1 GB/Month'; retailPrice = 0.02 }
        [pscustomobject]@{ serviceName = 'Key Vault'; skuName = 'Standard'; armRegionName = 'swedencentral'; unitOfMeasure = '10K'; retailPrice = 0.03 }
    )

    $script:Vm = [pscustomobject]@{ Name = 'vm-a'; Type = 'Microsoft.Compute/virtualMachines'; Sku = 'B2s'; Quantity = 2; Region = 'swedencentral' }
    $script:Disk = [pscustomobject]@{ Name = 'disk-a'; Type = 'Microsoft.Storage/storageAccounts'; Sku = 'Standard LRS'; Quantity = 100; Region = 'swedencentral' }
    $script:Vnet = [pscustomobject]@{ Name = 'vnet-a'; Type = 'Microsoft.Network/virtualNetworks'; Sku = 'n/a'; Quantity = 1; Region = 'swedencentral' }
    $script:NoPrice = [pscustomobject]@{ Name = 'bastion-a'; Type = 'Microsoft.Network/bastionHosts'; Sku = 'Basic'; Quantity = 1; Region = 'swedencentral' }
}

Describe 'Get-LabCostEstimate' {

    It 'returns one row per resource with a monthly cost from the price list' {
        $rows = @(Get-LabCostEstimate -Resource @($script:Vm, $script:Disk) -PriceList $script:Prices)
        $rows.Count | Should -Be 2
        ($rows | Where-Object Name -eq 'vm-a').MonthlyCost | Should -Be 73.00
        ($rows | Where-Object Name -eq 'vm-a').Status | Should -Be 'estimated'
        ($rows | Where-Object Name -eq 'disk-a').MonthlyCost | Should -Be 2.00
    }

    It 'prices in the resource region, not another one' {
        $rows = @(Get-LabCostEstimate -Resource $script:Vm -PriceList $script:Prices)
        $rows[0].MonthlyCost | Should -Be 73.00
    }

    It 'accepts the API envelope with an Items property' {
        $rows = @(Get-LabCostEstimate -Resource $script:Vm -PriceList ([pscustomobject]@{ Items = $script:Prices }))
        $rows[0].MonthlyCost | Should -Be 73.00
    }

    It 'marks a resource with no matching price unknown, with no number' {
        $rows = @(Get-LabCostEstimate -Resource $script:NoPrice -PriceList $script:Prices)
        $rows[0].Status | Should -Be 'unknown'
        $rows[0].MonthlyCost | Should -BeNullOrEmpty
    }

    It 'marks a match in a unit it cannot convert unknown' {
        $kv = [pscustomobject]@{ Name = 'kv-a'; Type = 'Microsoft.KeyVault/vaults'; Sku = 'Standard'; Quantity = 1; Region = 'swedencentral' }
        $rows = @(Get-LabCostEstimate -Resource $kv -PriceList $script:Prices)
        $rows[0].Status | Should -Be 'unknown'
        $rows[0].MonthlyCost | Should -BeNullOrEmpty
    }

    It 'does not count an unknown row as zero in the total' {
        $rows = @(Get-LabCostEstimate -Resource @($script:Vm, $script:NoPrice) -PriceList $script:Prices)
        $result = Compare-LabCostEstimate -Estimate $rows -StatedCost 100
        $result.KnownTotal | Should -Be 73.00
        $result.UnknownCount | Should -Be 1
    }

    It 'labels a type on the no-charge list no charge, with no number' {
        $rows = @(Get-LabCostEstimate -Resource $script:Vnet -PriceList $script:Prices)
        $rows[0].Status | Should -Be 'no charge'
        $rows[0].MonthlyCost | Should -BeNullOrEmpty
    }

    It 'throws naming the resource list when it is empty' {
        { Get-LabCostEstimate -Resource @() -PriceList $script:Prices } | Should -Throw '*resource list is empty*'
    }

    It 'throws naming the price list when it is empty' {
        { Get-LabCostEstimate -Resource $script:Vm -PriceList @() } | Should -Throw '*price list is empty*'
    }
}

Describe 'Compare-LabCostEstimate' {

    BeforeAll {
        $script:Rows = @(Get-LabCostEstimate -Resource @($script:Vm, $script:Disk) -PriceList $script:Prices)
        # Known total 75.00.
    }

    It 'reports within when the known total is inside the margin' {
        $r = Compare-LabCostEstimate -Estimate $script:Rows -StatedCost 62 -MarginPercent 25
        $r.Verdict | Should -Be 'within'
        $r.CleanPass | Should -BeTrue
    }

    It 'reports within when the total equals the limit exactly' {
        $r = Compare-LabCostEstimate -Estimate $script:Rows -StatedCost 60 -MarginPercent 25
        $r.Verdict | Should -Be 'within'
    }

    It 'reports exceeds when the total is over the limit' {
        $r = Compare-LabCostEstimate -Estimate $script:Rows -StatedCost 50 -MarginPercent 25
        $r.Verdict | Should -Be 'exceeds'
        $r.CleanPass | Should -BeFalse
    }

    It 'uses a 25 percent margin by default' {
        (Compare-LabCostEstimate -Estimate $script:Rows -StatedCost 60).Verdict | Should -Be 'within'
        (Compare-LabCostEstimate -Estimate $script:Rows -StatedCost 59).Verdict | Should -Be 'exceeds'
    }

    It 'says unknown next to a within verdict and does not call it a clean pass' {
        $rows = @(Get-LabCostEstimate -Resource @($script:Vm, $script:NoPrice) -PriceList $script:Prices)
        $r = Compare-LabCostEstimate -Estimate $rows -StatedCost 100
        $r.Verdict | Should -Be 'within'
        $r.CleanPass | Should -BeFalse
        $r.UnknownResources | Should -Contain 'bastion-a'
        $r.Message | Should -Match 'unknown'
        $r.Message | Should -Match 'not a clean pass'
    }

    It 'throws naming the estimate when it is empty' {
        { Compare-LabCostEstimate -Estimate @() -StatedCost 10 } | Should -Throw '*estimate is empty*'
    }
}

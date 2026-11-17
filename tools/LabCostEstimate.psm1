<#
.SYNOPSIS
    Offline monthly cost estimate for a lab's resources, and its comparison with the cost a guide states.

.DESCRIPTION
    Both functions take their input as data and make no network or Azure call, so the check runs in
    CI without a login. The price list has the shape of the Azure retail prices API (items with
    serviceName, skuName, armRegionName, unitOfMeasure, retailPrice); the caller supplies it.

    A resource with no matching price is 'unknown' and carries no number: counting it as zero would
    let a lab whose prices were never found pass as cheap. A resource type on the no-charge list is
    labelled 'no charge' and counts as zero on purpose.

.EXAMPLE
    Import-Module ./tools/LabCostEstimate.psm1
    $rows = Get-LabCostEstimate -Resource $resources -PriceList $prices
    Compare-LabCostEstimate -Estimate $rows -StatedCost 40

.NOTES
    Project: SkyCraft
    Issue:   #528
    Assumptions: a month is 730 hours; when several price items match one resource the highest wins,
    so a margin check errs towards 'exceeds'; the default margin is 25 percent.
#>

#Requires -Version 7.0

$ErrorActionPreference = 'Stop'

$script:HoursPerMonth = 730
$script:DaysPerMonth  = 730 / 24

# Types that carry no charge of their own, lower-case.
$script:NoChargeTypes = @(
    'microsoft.resources/resourcegroups'
    'microsoft.network/virtualnetworks'
    'microsoft.network/virtualnetworks/subnets'
    'microsoft.network/networksecuritygroups'
    'microsoft.network/networkinterfaces'
    'microsoft.network/routetables'
    'microsoft.network/applicationsecuritygroups'
    'microsoft.authorization/roleassignments'
    'microsoft.authorization/policyassignments'
    'microsoft.authorization/locks'
    'microsoft.managedidentity/userassignedidentities'
)

# Price service for a type; a type not listed here is matched on SKU and region alone.
$script:ServiceByType = @{
    'microsoft.compute/virtualmachines' = 'Virtual Machines'
    'microsoft.compute/disks'           = 'Storage'
    'microsoft.storage/storageaccounts' = 'Storage'
    'microsoft.network/publicipaddresses' = 'Virtual Network'
    'microsoft.network/natgateways'       = 'Virtual Network'
    'microsoft.keyvault/vaults'           = 'Key Vault'
    'microsoft.web/serverfarms'           = 'Azure App Service'
}

function ConvertTo-MonthlyFactor {
    <#
    .SYNOPSIS
        Months-per-price-unit factor for a retail price unit, or $null when the unit is not time based.

    .DESCRIPTION
        '1 Hour' becomes 730, '1 Day' about 30.42, and '1/Month', '1 GB/Month' and '1 Month' become 1.
        Any other unit ('10K', '1 GB') returns $null so the row is
        reported unknown instead of being priced on a guess.

    .EXAMPLE
        ConvertTo-MonthlyFactor -UnitOfMeasure '1 Hour'
    #>
    [CmdletBinding()]
    [OutputType([object])]
    param([Parameter(Mandatory)][AllowEmptyString()][string]$UnitOfMeasure)

    switch -Regex ($UnitOfMeasure.Trim()) {
        '^1 Hour$'            { return $script:HoursPerMonth }
        '^1 Day$'             { return $script:DaysPerMonth }
        '^1( GB)?[ /]Month$'  { return 1 }
    }
    return $null
}

function Get-LabCostEstimate {
    <#
    .SYNOPSIS
        Returns one row per resource with an approximate monthly cost.

    .DESCRIPTION
        Each resource needs Name, Type, Sku, Quantity and Region. A price item matches on skuName and
        armRegionName (case-insensitive), and on serviceName too where the resource type has a known
        service. A row is 'priced' with a number, 'no charge' with zero, or 'unknown' with $null.
        Throws, naming the input, when the resource list or the price list is empty.

    .PARAMETER Resource
        Resources to estimate: objects or hashtables with Name, Type, Sku, Quantity, Region.

    .PARAMETER PriceList
        Items in the shape of the Azure retail prices API.

    .EXAMPLE
        Get-LabCostEstimate -Resource $resources -PriceList $prices
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Resource,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$PriceList
    )

    if (-not $Resource -or $Resource.Count -eq 0) { throw 'Get-LabCostEstimate: the resource list is empty.' }
    if (-not $PriceList -or $PriceList.Count -eq 0) { throw 'Get-LabCostEstimate: the price list is empty.' }

    foreach ($item in $Resource) {
        $type = [string]$item.Type
        $qty  = if ($null -ne $item.Quantity) { [decimal]$item.Quantity } else { [decimal]1 }
        if ($qty -lt 0) { throw "Get-LabCostEstimate: resource '$($item.Name)' has a negative quantity." }
        $row  = [ordered]@{
            Name = $item.Name; Type = $type; Sku = $item.Sku; Quantity = $qty
            Region = $item.Region; Status = 'unknown'; MonthlyCost = $null; UnpricedMeters = 0
        }

        if ($script:NoChargeTypes -contains $type.ToLowerInvariant()) {
            $row.Status = 'no charge'; $row.MonthlyCost = [decimal]0
            [pscustomobject]$row
            continue
        }

        $service = $script:ServiceByType[$type.ToLowerInvariant()]
        $best = $null
        $skipped = 0
        foreach ($price in $PriceList) {
            if ([string]$price.skuName -ne [string]$item.Sku) { continue }
            if ([string]$price.armRegionName -ne [string]$item.Region) { continue }
            if ($service -and [string]$price.serviceName -ne $service) { continue }
            # A missing, non-numeric or negative amount is no price (never zero); both that and a unit
            # the estimate cannot convert leave a matching meter unpriced, which is counted below.
            $amount = [decimal]0
            $numeric = [decimal]::TryParse([string]$price.retailPrice, [System.Globalization.NumberStyles]::Float,
                [cultureinfo]::InvariantCulture, [ref]$amount)
            $factor = ConvertTo-MonthlyFactor -UnitOfMeasure ([string]$price.unitOfMeasure)
            if (-not $numeric -or $amount -lt 0 -or $null -eq $factor) { $skipped++; continue }
            $monthly = $amount * [decimal]$factor
            if ($null -eq $best -or $monthly -gt $best) { $best = $monthly }
        }

        if ($null -ne $best) {
            $row.Status = 'priced'
            $row.MonthlyCost = [math]::Round($best * $qty, 2)
            # Matching meters it could not price: no valid amount, or a unit it cannot convert (per 10K, per GB).
            $row.UnpricedMeters = $skipped
        }
        [pscustomobject]$row
    }
}

function Compare-LabCostEstimate {
    <#
    .SYNOPSIS
        Compares an estimate with the cost a guide states and reports 'within' or 'exceeds'.

    .DESCRIPTION
        The known total adds the rows that carry a number. The verdict is 'within' when that total
        does not exceed StatedCost by more than MarginPercent, otherwise 'exceeds'. When any row is
        unknown the message says so next to the verdict and Clean is $false, so 'within' is never a
        clean pass on prices that were not found. Throws, naming the input, on an empty estimate.

    .PARAMETER Estimate
        Rows returned by Get-LabCostEstimate.

    .PARAMETER StatedCost
        The monthly cost the guide states.

    .PARAMETER MarginPercent
        Allowed excess over StatedCost, in percent. Default 25.

    .EXAMPLE
        Compare-LabCostEstimate -Estimate $rows -StatedCost 40 -MarginPercent 10
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Estimate,
        [Parameter(Mandatory)][ValidateRange(0, [double]::MaxValue)][decimal]$StatedCost,
        [ValidateRange(0, [double]::MaxValue)][decimal]$MarginPercent = 25
    )

    if (-not $Estimate -or $Estimate.Count -eq 0) { throw 'Compare-LabCostEstimate: the estimate is empty.' }

    $known = [decimal]0
    $unknown = 0
    $partial = 0
    foreach ($row in $Estimate) {
        if ($null -eq $row.MonthlyCost) { $unknown++ } else { $known += [decimal]$row.MonthlyCost }
        if ($row.PSObject.Properties['UnpricedMeters'] -and [int]$row.UnpricedMeters -gt 0) { $partial++ }
    }

    # Cents: a double literal bound to [decimal] carries float noise that would flip an exact boundary.
    $limit = [math]::Round($StatedCost * (1 + $MarginPercent / 100), 2)
    $verdict = if ($known -le $limit) { 'within' } else { 'exceeds' }
    $message = "$verdict`: known total $known against stated $StatedCost (limit $limit)"
    if ($unknown -gt 0) { $message += "; $unknown resource(s) have no price, so the total is incomplete" }
    if ($partial -gt 0) { $message += "; $partial resource(s) have a meter the estimate could not price (no valid amount or an unsupported unit), so the total is incomplete" }

    [pscustomobject]@{
        Verdict      = $verdict
        KnownTotal   = $known
        StatedCost   = $StatedCost
        Limit        = $limit
        UnknownCount = $unknown
        PartialCount = $partial
        Clean        = ($verdict -eq 'within' -and $unknown -eq 0 -and $partial -eq 0)
        Message      = $message
    }
}

Export-ModuleMember -Function Get-LabCostEstimate, Compare-LabCostEstimate

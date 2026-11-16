<#
.SYNOPSIS
    Offline monthly cost estimate for a lab's resource list, and its comparison with the guide.

.DESCRIPTION
    Get-LabCostEstimate prices a resource list against a price list passed in, in the shape of the
    Azure retail prices API. Compare-LabCostEstimate checks the known total against the cost a
    guide states. Neither function calls the network or Azure: the caller supplies the price list.

    A resource with no matching price is `unknown` and carries no number, so it never counts as
    zero. A resource type on the no-charge list is `no charge`. An empty input throws, because a
    total of zero over nothing would read as a passed check.

    Reading the resources out of a lab's Bicep and fetching the live price list are not done here.

.EXAMPLE
    Import-Module ./tools/LabCostEstimate.psm1
    $rows = Get-LabCostEstimate -Resource $resources -PriceList $prices
    Compare-LabCostEstimate -Estimate $rows -StatedCost 20

.NOTES
    Project: SkyCraft
#>

#Requires -Version 7.0

$ErrorActionPreference = 'Stop'

# Azure bills hourly prices over 730 hours a month.
$script:HoursPerMonth = 730

# Types that have no charge of their own.
$script:DefaultNoChargeType = @(
    'Microsoft.Resources/resourceGroups'
    'Microsoft.Network/virtualNetworks'
    'Microsoft.Network/virtualNetworks/subnets'
    'Microsoft.Network/networkSecurityGroups'
    'Microsoft.Network/applicationSecurityGroups'
    'Microsoft.Network/networkInterfaces'
    'Microsoft.Network/routeTables'
    'Microsoft.Authorization/roleAssignments'
    'Microsoft.Authorization/policyAssignments'
    'Microsoft.Authorization/policyDefinitions'
    'Microsoft.Authorization/locks'
    'Microsoft.ManagedIdentity/userAssignedIdentities'
)

# Resource type to the serviceName the retail prices API uses.
$script:ServiceNameByType = @{
    'Microsoft.Compute/virtualMachines'            = 'Virtual Machines'
    'Microsoft.Compute/disks'                      = 'Storage'
    'Microsoft.Storage/storageAccounts'            = 'Storage'
    'Microsoft.Web/serverfarms'                    = 'Azure App Service'
    'Microsoft.Network/publicIPAddresses'          = 'Virtual Network'
    'Microsoft.Network/loadBalancers'              = 'Load Balancer'
    'Microsoft.Network/azureFirewalls'             = 'Azure Firewall'
    'Microsoft.Network/bastionHosts'               = 'Azure Bastion'
    'Microsoft.Network/virtualNetworkGateways'     = 'VPN Gateway'
    'Microsoft.KeyVault/vaults'                    = 'Key Vault'
    'Microsoft.RecoveryServices/vaults'            = 'Backup'
    'Microsoft.OperationalInsights/workspaces'     = 'Log Analytics'
}

function Get-LabCostEstimate {
    <#
    .SYNOPSIS
        Returns one row per resource with an approximate monthly cost.

    .DESCRIPTION
        A price item matches a resource when serviceName, skuName and armRegionName are equal
        (case-insensitive). The serviceName comes from the resource's ServiceName property, or
        from the built-in type map. Among matches with a supported unit the lowest retailPrice
        wins, so the result does not depend on the order of the price list.

        Units: '1 Hour' is priced as price x 730 x quantity; '1/Month' and '1 GB/Month' as
        price x quantity. A match in any other unit, or no match, is `unknown`.

        Each row has Name, Type, Sku, Quantity, Region, Status (`estimated`, `unknown` or
        `no charge`) and MonthlyCost (a number only for `estimated`, otherwise $null).

    .PARAMETER Resource
        Objects with Name, Type, Sku, Quantity (default 1) and Region. ServiceName is optional.

    .PARAMETER PriceList
        Price items, or an object with an Items property as the retail prices API returns.

    .PARAMETER NoChargeType
        Resource types that cost nothing. Defaults to the built-in list.

    .EXAMPLE
        Get-LabCostEstimate -Resource $resources -PriceList $prices

    .NOTES
        Project: SkyCraft
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [AllowNull()]
        $Resource,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [AllowNull()]
        $PriceList,

        [string[]]$NoChargeType = $script:DefaultNoChargeType
    )

    $resources = @($Resource | Where-Object { $null -ne $_ })
    if ($resources.Count -eq 0) {
        throw 'The resource list is empty: there is nothing to estimate.'
    }

    $items = if ($PriceList -and $PriceList.PSObject.Properties['Items']) { $PriceList.Items } else { $PriceList }
    $items = @($items | Where-Object { $null -ne $_ })
    if ($items.Count -eq 0) {
        throw 'The price list is empty: no resource can be priced.'
    }

    foreach ($res in $resources) {
        $quantity = if ($null -ne $res.PSObject.Properties['Quantity'] -and $null -ne $res.Quantity) { [double]$res.Quantity } else { 1.0 }
        $row = [pscustomobject]@{
            Name        = $res.Name
            Type        = $res.Type
            Sku         = $res.Sku
            Quantity    = $quantity
            Region      = $res.Region
            Status      = 'unknown'
            MonthlyCost = $null
        }

        if ($NoChargeType -contains $res.Type) {
            $row.Status = 'no charge'
            $row
            continue
        }

        $service = if ($res.PSObject.Properties['ServiceName'] -and $res.ServiceName) { $res.ServiceName } else { $script:ServiceNameByType[[string]$res.Type] }
        if ($service) {
            $match = $items |
                Where-Object {
                    $_.serviceName -eq $service -and $_.skuName -eq $res.Sku -and
                    $_.armRegionName -eq $res.Region -and $_.unitOfMeasure -in '1 Hour', '1/Month', '1 GB/Month'
                } |
                Sort-Object { [double]$_.retailPrice } |
                Select-Object -First 1

            if ($match) {
                $monthly = if ($match.unitOfMeasure -eq '1 Hour') { [double]$match.retailPrice * $script:HoursPerMonth * $quantity } else { [double]$match.retailPrice * $quantity }
                $row.Status = 'estimated'
                $row.MonthlyCost = [math]::Round($monthly, 2)
            }
        }
        $row
    }
}

function Compare-LabCostEstimate {
    <#
    .SYNOPSIS
        Compares the known total of an estimate with the cost a guide states.

    .DESCRIPTION
        Verdict is `within` when the known total does not exceed the stated cost by more than the
        margin, `exceeds` otherwise. The known total sums only `estimated` rows. When any row is
        `unknown` the Message says so and CleanPass is $false, so `within` is not a clean pass.

    .PARAMETER Estimate
        Rows returned by Get-LabCostEstimate.

    .PARAMETER StatedCost
        The monthly cost the guide states.

    .PARAMETER MarginPercent
        Allowed excess over the stated cost, in percent. Default 25.

    .EXAMPLE
        Compare-LabCostEstimate -Estimate $rows -StatedCost 20 -MarginPercent 10

    .NOTES
        Project: SkyCraft
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [AllowNull()]
        $Estimate,

        [Parameter(Mandatory)]
        [double]$StatedCost,

        [ValidateRange(0, [double]::MaxValue)]
        [double]$MarginPercent = 25
    )

    $rows = @($Estimate | Where-Object { $null -ne $_ })
    if ($rows.Count -eq 0) {
        throw 'The estimate is empty: there is nothing to compare.'
    }

    $known = [double](($rows | Where-Object { $_.Status -eq 'estimated' } | Measure-Object -Property MonthlyCost -Sum).Sum)
    $unknown = @($rows | Where-Object { $_.Status -eq 'unknown' })
    $limit = $StatedCost * (1 + $MarginPercent / 100)
    $verdict = if ($known -gt $limit) { 'exceeds' } else { 'within' }

    $message = "$verdict`: known total $([math]::Round($known, 2)) against stated $StatedCost with a $MarginPercent percent margin (limit $([math]::Round($limit, 2)))"
    if ($unknown.Count -gt 0) {
        $message += "; $($unknown.Count) resource(s) unknown and not counted: $(($unknown.Name) -join ', '). This is not a clean pass"
    }

    [pscustomobject]@{
        Verdict          = $verdict
        KnownTotal       = [math]::Round($known, 2)
        StatedCost       = $StatedCost
        MarginPercent    = $MarginPercent
        Limit            = [math]::Round($limit, 2)
        UnknownCount     = $unknown.Count
        UnknownResources = @($unknown.Name)
        CleanPass        = ($verdict -eq 'within' -and $unknown.Count -eq 0)
        Message          = $message
    }
}

Export-ModuleMember -Function Get-LabCostEstimate, Compare-LabCostEstimate

<#
.SYNOPSIS
    Pester 5 tests for the private DNS link helpers in tools/LabCommon.psm1 (issue #444).

.DESCRIPTION
    A private DNS zone link keeps the identity of the VNet it was made for. When that VNet is
    deleted and created again, the link still reads as Succeeded and Completed, no longer serves
    the new VNet, and Lab 2.3 cannot deploy until it is deleted. Measured on 2026-10-28: the link
    is older than the VNet it points at, and Azure queues its own delete of it minutes later. These
    tests pin that:

      1. Get-LabDnsLink calls a link stale when its VNet was created after it, and only then.
      2. A link Azure has already deleted, but the resource list still shows, is skipped.
      3. A listing that fails throws rather than reading as "no links".
      4. Remove-LabDnsLink returns once the link answers 404, waits for a delete Azure has already
         queued, and throws when the delete is refused or the link outlives the wait.

    Nothing reaches Azure: Invoke-AzRestMethod is mocked inside the module.

.EXAMPLE
    Invoke-Pester -Path .\tests\LabCommon-DnsLink.Tests.ps1

.NOTES
    Project: SkyCraft
    Issue: #444
#>

#Requires -Version 7.0
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..' 'tools' 'LabCommon.psm1') -Force

    $script:Sub     = '/subscriptions/sub'
    $script:DevVnet = "$script:Sub/resourceGroups/dev-skycraft-swc-rg/providers/Microsoft.Network/virtualNetworks/dev-skycraft-swc-vnet"
    $script:Link    = "$script:Sub/resourceGroups/platform-skycraft-swc-rg/providers/Microsoft.Network/privateDnsZones/skycraft.internal/virtualNetworkLinks/dev-vnet-link"

    function Get-ArmReply {
        param([int]$Status = 200, $Body)
        [pscustomobject]@{ StatusCode = $Status; Content = ($Body | ConvertTo-Json -Depth 6 -Compress) }
    }
}

Describe 'Get-LabDnsLink (#444)' {

    BeforeEach {
        $script:VnetCreated = '2026-10-28T09:22:06Z'
        $script:LinkGone    = $false
        Mock -ModuleName LabCommon Invoke-AzRestMethod {
            if ($Path -match 'privateDnsZones%2FvirtualNetworkLinks') {
                return Get-ArmReply -Body @{ value = @(@{ id = $script:Link; name = 'skycraft.internal/dev-vnet-link'; createdTime = '2026-10-28T09:21:21Z' }) }
            }
            if ($Path -match 'Microsoft.Network%2FvirtualNetworks%27') {
                return Get-ArmReply -Body @{ value = @(@{ id = $script:DevVnet; name = 'dev-skycraft-swc-vnet'; createdTime = $script:VnetCreated }) }
            }
            if ($script:LinkGone) { return Get-ArmReply -Status 404 -Body @{ error = @{ code = 'NotFound'; message = 'gone' } } }
            Get-ArmReply -Body @{ id = $script:Link; properties = @{ virtualNetwork = @{ id = $script:DevVnet } } }
        }
    }

    It 'calls a link stale when its VNet was created after it' {
        $link = @(Get-LabDnsLink -SubscriptionId 'sub')
        $link.Count | Should -Be 1
        $link[0].Name | Should -Be 'skycraft.internal/dev-vnet-link'
        $link[0].VirtualNetworkId | Should -Be $script:DevVnet
        $link[0].VirtualNetworkExists | Should -BeTrue
        $link[0].Stale | Should -BeTrue
    }

    It 'does not call a link stale when its VNet is older' {
        $script:VnetCreated = '2026-10-28T09:20:00Z'
        (Get-LabDnsLink -SubscriptionId 'sub').Stale | Should -BeFalse
    }

    It 'does not call a link stale when its VNet no longer exists' {
        $script:DevVnet = "$script:Sub/resourceGroups/dev-skycraft-swc-rg/providers/Microsoft.Network/virtualNetworks/gone-vnet"
        Mock -ModuleName LabCommon Invoke-AzRestMethod {
            if ($Path -match 'privateDnsZones%2FvirtualNetworkLinks') { return Get-ArmReply -Body @{ value = @(@{ id = $script:Link; name = 'skycraft.internal/dev-vnet-link'; createdTime = '2026-10-28T09:21:21Z' }) } }
            if ($Path -match 'Microsoft.Network%2FvirtualNetworks%27') { return Get-ArmReply -Body @{ value = @() } }
            Get-ArmReply -Body @{ id = $script:Link; properties = @{ virtualNetwork = @{ id = $script:DevVnet } } }
        }
        $link = Get-LabDnsLink -SubscriptionId 'sub'
        $link.VirtualNetworkExists | Should -BeFalse
        $link.Stale | Should -BeFalse
    }

    It 'skips a link the resource list still shows after Azure deleted it' {
        $script:LinkGone = $true
        @(Get-LabDnsLink -SubscriptionId 'sub').Count | Should -Be 0
    }

    It 'lists the links of one group when asked' {
        Get-LabDnsLink -SubscriptionId 'sub' -ResourceGroupName 'platform-skycraft-swc-rg' | Out-Null
        Should -Invoke -ModuleName LabCommon Invoke-AzRestMethod -Times 1 -Exactly -ParameterFilter {
            $Path -like '/subscriptions/sub/resourceGroups/platform-skycraft-swc-rg/resources?*privateDnsZones%2FvirtualNetworkLinks*createdTime*'
        }
    }

    It 'throws when the listing fails, rather than reading it as no links' {
        Mock -ModuleName LabCommon Invoke-AzRestMethod { Get-ArmReply -Status 403 -Body @{ error = @{ code = 'AuthorizationFailed'; message = 'no' } } }
        { Get-LabDnsLink -SubscriptionId 'sub' } | Should -Throw '*AuthorizationFailed*'
    }
}

Describe 'Lab 2.3 deploy scripts delete a stale link before linking (#444)' {

    It '<Script> looks the links up, deletes the stale ones, and stops with Exit-Lab 1 when it cannot' -ForEach @(
        @{ Script = 'Deploy-Bicep.ps1' }
        @{ Script = 'Deploy-DNS.ps1' }
    ) {
        $path = Join-Path $PSScriptRoot '..' 'module-2-networking' '2.3-name-resolution' 'scripts' $Script
        $source = Get-Content -Raw -LiteralPath $path
        $source | Should -Match 'Get-LabDnsLink -ResourceGroupName [^\r\n]*Where-Object \{ \$_\.Stale'
        $source | Should -Match 'Remove-LabDnsLink -Id \$staleLink\.Id'
        $source | Should -Match '(?s)catch \{\s+Write-Host [^\r\n]*\[ERROR\][^\r\n]*stale[^\r\n]*\s+Exit-Lab -FailureCount 1' -Because 'a check or delete that fails must stop the deploy'
    }

    It 'Deploy-Bicep.ps1 deletes the stale links before it deploys' {
        $source = Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot '..' 'module-2-networking' '2.3-name-resolution' 'scripts' 'Deploy-Bicep.ps1')
        $source.IndexOf('Remove-LabDnsLink') | Should -BeLessThan $source.IndexOf('New-AzDeployment')
    }
}

Describe 'Remove-LabDnsLink (#444)' {

    BeforeEach {
        Mock -ModuleName LabCommon Start-Sleep { }
    }

    It 'deletes the link and returns once it answers 404' {
        Mock -ModuleName LabCommon Invoke-AzRestMethod {
            if ($Method -eq 'DELETE') { return Get-ArmReply -Status 202 -Body $null }
            Get-ArmReply -Status 404 -Body @{ error = @{ code = 'NotFound'; message = 'gone' } }
        }
        { Remove-LabDnsLink -Id $script:Link -Confirm:$false } | Should -Not -Throw
        Should -Invoke -ModuleName LabCommon Invoke-AzRestMethod -Times 1 -Exactly -ParameterFilter { $Method -eq 'DELETE' }
    }

    It 'returns when the link is already gone' {
        Mock -ModuleName LabCommon Invoke-AzRestMethod { Get-ArmReply -Status 404 -Body @{ error = @{ code = 'NotFound'; message = 'gone' } } }
        { Remove-LabDnsLink -Id $script:Link -Confirm:$false } | Should -Not -Throw
    }

    It 'waits for a delete Azure has already queued instead of failing on it' {
        $script:Gets = 0
        Mock -ModuleName LabCommon Invoke-AzRestMethod {
            if ($Method -eq 'DELETE') { return Get-ArmReply -Status 409 -Body @{ code = 'Conflict'; message = "Another operation is pending. Operation group already has 1 operations like '/operations/type/DeleteVirtualNetworkLink/id/x' queued." } }
            $script:Gets++
            if ($script:Gets -lt 3) { return Get-ArmReply -Body @{ id = $script:Link } }
            Get-ArmReply -Status 404 -Body @{ error = @{ code = 'NotFound'; message = 'gone' } }
        }
        { Remove-LabDnsLink -Id $script:Link -Confirm:$false -PollSeconds 0 } | Should -Not -Throw
        $script:Gets | Should -Be 3
    }

    It 'throws when the delete is refused' {
        Mock -ModuleName LabCommon Invoke-AzRestMethod { Get-ArmReply -Status 403 -Body @{ error = @{ code = 'AuthorizationFailed'; message = 'no' } } }
        { Remove-LabDnsLink -Id $script:Link -Confirm:$false } | Should -Throw '*AuthorizationFailed*'
    }

    It 'throws when the link outlives the wait' {
        Mock -ModuleName LabCommon Invoke-AzRestMethod {
            if ($Method -eq 'DELETE') { return Get-ArmReply -Status 202 -Body $null }
            Get-ArmReply -Body @{ id = $script:Link }
        }
        { Remove-LabDnsLink -Id $script:Link -Confirm:$false -TimeoutSeconds 0 -PollSeconds 0 } | Should -Throw '*still there*'
    }

    It 'deletes nothing under -WhatIf' {
        Mock -ModuleName LabCommon Invoke-AzRestMethod { throw 'must not be called' }
        { Remove-LabDnsLink -Id $script:Link -WhatIf } | Should -Not -Throw
        Should -Invoke -ModuleName LabCommon Invoke-AzRestMethod -Times 0 -Exactly
    }
}

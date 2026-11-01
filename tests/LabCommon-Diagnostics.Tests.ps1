Import-Module (Join-Path $PSScriptRoot '../tools/LabCommon.psm1') -Force

Describe 'Shared diagnostic cleanup' {
    InModuleScope LabCommon {
        BeforeAll {
            function Get-AzResource {
                [CmdletBinding()]
                param([string]$ResourceGroupName)
                if ($script:DiscoveryError) { throw $script:DiscoveryError }
                $script:Resources
            }
            function Get-AzDiagnosticSetting {
                [CmdletBinding()]
                param([string]$ResourceId)
                if ($script:ReadError) { throw $script:ReadError }
                [pscustomobject]@{ Name = 'first' }
                [pscustomobject]@{ Name = 'second' }
            }
            function Remove-AzDiagnosticSetting {
                [CmdletBinding()]
                param([string]$ResourceId, [string]$Name)
                $script:Removed.Add("$ResourceId/$Name")
            }
        }
        BeforeEach {
            $script:DiscoveryError = $null
            $script:ReadError = $null
            $script:Resources = @()
            $script:Removed = [System.Collections.Generic.List[string]]::new()
        }
        AfterAll {
            Remove-Item Function:\Get-AzResource, Function:\Get-AzDiagnosticSetting, Function:\Remove-AzDiagnosticSetting -ErrorAction SilentlyContinue
        }
        It 'treats a missing resource group as no diagnostic targets' {
            $script:DiscoveryError = 'ResourceGroupNotFound'
            @(Get-LabDiagnosticResourceId -ResourceGroupName 'fixture-rg') | Should -BeNullOrEmpty
        }
        It 'does not treat a missing subscription as an absent diagnostic target' {
            $script:ReadError = 'SubscriptionNotFound: Status: 404 (Not Found)'
            Remove-LabResourceDiagnosticSetting -ResourceId '/fixture' -Confirm:$false | Should -Be 1
            $script:Removed.Count | Should -Be 0
        }
        It 'treats a genuine target 404 as no settings' {
            $script:ReadError = 'ResourceNotFound: Status: 404 (Not Found)'
            Remove-LabResourceDiagnosticSetting -ResourceId '/fixture' -Confirm:$false | Should -Be 0
            $script:Removed.Count | Should -Be 0
        }
        It 'rejects a target returned from outside the requested resource group' {
            $script:Resources = @(@{ ResourceId = '/subscriptions/fixture/resourceGroups/other/providers/Microsoft.KeyVault/vaults/fixture'; ResourceType = 'Microsoft.KeyVault/vaults' })
            { Get-LabDiagnosticResourceId -ResourceGroupName 'fixture-rg' } | Should -Throw '*outside*'
        }
        It 'removes all setting names once per target and honors WhatIf' {
            Remove-LabResourceDiagnosticSetting -ResourceId '/fixture', '/fixture' -Confirm:$false | Should -Be 0
            $script:Removed.ToArray() | Should -Be @('/fixture/first', '/fixture/second')
            $script:Removed.Clear()
            Remove-LabResourceDiagnosticSetting -ResourceId '/fixture' -WhatIf | Should -Be 0
            $script:Removed.Count | Should -Be 0
        }
    }
}

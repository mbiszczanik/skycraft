<#
.SYNOPSIS
    Pester 5 tests for Write-LabDeploymentOutput in tools/LabCommon.psm1 (issue #354).

.DESCRIPTION
    Issue #354, step 3.1.19: Lab 3.1's Deploy-Bicep.ps1 piped $deployment.Outputs to
    Format-Table. Each entry of that dictionary is a DeploymentVariable whose value sits in .Value,
    so Format-Table printed the output names with the type name (or nothing) in place of the
    values. Labs 1.3, 2.1, 2.2 and 3.3 had the same line. These tests pin that:

      1. Write-LabDeploymentOutput prints one line per output, sorted by name, with its value.
      2. It prints nothing for a deployment without outputs.
      3. No Deploy-Bicep.ps1 under module-* pipes a deployment's Outputs to Format-Table.

    Nothing reaches Azure: the outputs are a dictionary of the same shape.

.EXAMPLE
    Invoke-Pester -Path .\tests\LabCommon-DeploymentOutput.Tests.ps1

.NOTES
    Project: SkyCraft
    Issue: #354
#>

#Requires -Version 7.0
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeDiscovery {
    $root = Join-Path $PSScriptRoot '..'
    $script:DeployScripts = foreach ($dir in Get-ChildItem -LiteralPath $root -Directory -Filter 'module-*') {
        Get-ChildItem -LiteralPath $dir.FullName -Recurse -File -Filter 'Deploy-Bicep.ps1' |
            ForEach-Object { @{ Path = $_.FullName; Name = [System.IO.Path]::GetRelativePath($root, $_.FullName) } }
    }
    if (-not $script:DeployScripts) { throw 'No Deploy-Bicep.ps1 found under module-*.' }
}

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..' 'tools' 'LabCommon.psm1') -Force

    # The shape New-AzSubscriptionDeployment returns: name -> DeploymentVariable (Type, Value).
    function Get-StubOutputDictionary {
        $outputs = [System.Collections.Generic.Dictionary[string, object]]::new()
        $outputs['outDevVnetId']               = [pscustomobject]@{ Type = 'String'; Value = '/subscriptions/stub/resourceGroups/dev-skycraft-swc-rg/providers/Microsoft.Network/virtualNetworks/dev-skycraft-swc-vnet' }
        $outputs['outDevLoadBalancerPublicIp'] = [pscustomobject]@{ Type = 'String'; Value = '203.0.113.10' }
        $outputs['outDevVnetDeployed']         = [pscustomobject]@{ Type = 'Bool'; Value = $false }
        $outputs
    }

    function Get-PrintedLine {
        param($Outputs)
        @(Write-LabDeploymentOutput -Outputs $Outputs 6>&1 | ForEach-Object { "$_" })
    }
}

Describe 'Write-LabDeploymentOutput (#354)' {

    It 'prints every output with its value, sorted by name' {
        $lines = Get-PrintedLine -Outputs (Get-StubOutputDictionary)
        $lines.Count | Should -Be 3
        $lines[0] | Should -Match '^\s+outDevLoadBalancerPublicIp\s+203\.0\.113\.10$'
        $lines[1] | Should -Match '^\s+outDevVnetDeployed\s+False$' -Because 'false is a value, not a blank'
        $lines[2] | Should -Match '^\s+outDevVnetId\s+/subscriptions/.+/virtualNetworks/dev-skycraft-swc-vnet$'
    }

    It 'prints nothing for a deployment without outputs' {
        (Get-PrintedLine -Outputs $null).Count | Should -Be 0
        (Get-PrintedLine -Outputs @{}).Count | Should -Be 0
    }
}

Describe 'Deploy-Bicep.ps1 deployment outputs printout' {

    It '<Name> does not format the outputs dictionary' -ForEach $script:DeployScripts {
        @(Select-String -LiteralPath $Path -Pattern '\.Outputs\s*\|\s*Format-(Table|List)' | ForEach-Object { "$($_.LineNumber): $($_.Line.Trim())" }) |
            Should -BeNullOrEmpty -Because 'Format-Table on the dictionary prints the names without their values; use Write-LabDeploymentOutput'
    }
}

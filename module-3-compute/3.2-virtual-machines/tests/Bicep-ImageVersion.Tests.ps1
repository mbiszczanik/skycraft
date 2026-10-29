<#
.SYNOPSIS
    Pester 5 tests: Lab 3.2's main.bicep pins the Ubuntu image version both VMs boot from.

.DESCRIPTION
    Issue #366 (decision 2026-10-28): 'latest' booted kernel 6.8.0-1065-azure and Lab 5.2's Site
    Recovery replication failed with ASRMobilityServiceKernelNotSupportedV2. Image version
    22.04.202506200 boots 6.8.0-1030-azure (Canonical manifest of release 20250620), which every
    Site Recovery agent version lists. The suite compiles main.bicep with the standalone Bicep CLI
    and asserts that the image reference is that version, never 'latest', and that both VMs use it.
    No Azure sign-in is needed.

.EXAMPLE
    Invoke-Pester -Path .\Bicep-ImageVersion.Tests.ps1

.NOTES
    Project: SkyCraft
    Lab: 3.2 - Virtual Machines
    Issue: #366
#>

#Requires -Version 7.0
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    $script:LabRoot  = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    $script:RepoRoot = (Resolve-Path (Join-Path $script:LabRoot '..' '..')).Path
    Import-Module (Join-Path $script:RepoRoot 'tools' 'BicepCli.psm1') -Force
    $script:Bicep   = Get-BicepCliPath
    $script:WorkDir = Join-Path ([System.IO.Path]::GetTempPath()) ('skycraft-32-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $script:WorkDir -Force | Out-Null

    $out = Join-Path $script:WorkDir 'lab32.json'
    $null = & $script:Bicep build (Join-Path $script:LabRoot 'bicep' 'main.bicep') --outfile $out 2>&1
    $script:BuildExit = $LASTEXITCODE
    $script:Template = if ($script:BuildExit -eq 0) { Get-Content -Raw -LiteralPath $out | ConvertFrom-Json -AsHashtable } else { $null }
}

AfterAll {
    if ($script:WorkDir) { Remove-Item -LiteralPath $script:WorkDir -Recurse -Force -ErrorAction SilentlyContinue }
}

Describe 'Lab 3.2 main.bicep - pinned Ubuntu image (#366)' {

    It 'compiles' {
        $script:BuildExit | Should -Be 0
    }

    It 'pins Canonical Ubuntu 22.04 Gen2 to image version 22.04.202506200, not latest' {
        $image = $script:Template.variables.varImageReference
        $image.publisher | Should -Be 'Canonical'
        $image.offer | Should -Be '0001-com-ubuntu-server-jammy'
        $image.sku | Should -Be '22_04-lts-gen2'
        $image.version | Should -Be '22.04.202506200'
    }

    It 'gives both VM modules that image reference' {
        $resources = if ($script:Template.resources -is [System.Collections.IDictionary]) { $script:Template.resources.Values } else { $script:Template.resources }
        foreach ($name in @('auth-vm-deployment', 'world-vm-deployment')) {
            $vm = $resources | Where-Object { $_.name -eq $name } | Select-Object -First 1
            $vm | Should -Not -BeNullOrEmpty -Because $name
            $vm.properties.parameters.imageReference.value | Should -Be "[variables('varImageReference')]" -Because $name
        }
    }
}

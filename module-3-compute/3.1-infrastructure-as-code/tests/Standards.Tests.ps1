<#
.SYNOPSIS
    Pester 5 tests verifying Lab 3.1 Bicep files conform to SkyCraft Bicep standards.

.DESCRIPTION
    Checks the five Bicep files in Lab 3.1 against docs/bicep-standards.md:
      - Header block (SUMMARY / DESCRIPTION / AUTHOR / VERSION / DEPLOYMENT)
      - Hungarian notation for param / resource / module / output
      - Resource API versions pinned to 2023-11-01 (network stack) or 2023-07-01 (RG)
      - No preview API versions
      - CostCenter tag present in main.bicep
      - Compiles successfully via 'bicep build' (resolved by tools/BicepCli.psm1)
      - The guide's verification steps (3.1.21, 3.1.22) expect what main.bicep deploys (#263)

.EXAMPLE
    Invoke-Pester -Path .\Standards.Tests.ps1

.NOTES
    Project: SkyCraft
    Lab: 3.1 - Infrastructure as Code
#>

#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

# Discovery-phase data: -ForEach evaluates here, not in BeforeAll.
$BicepRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\bicep')).Path
$MainFile  = Join-Path $BicepRoot 'main.bicep'
$ModFiles  = Get-ChildItem -Path (Join-Path $BicepRoot 'modules') -Filter '*.bicep' -File

$AllCases = @(@{ file = 'main.bicep'; path = $MainFile }) +
            ($ModFiles | ForEach-Object { @{ file = $_.Name; path = $_.FullName } })
$ModCases = $ModFiles | ForEach-Object { @{ file = $_.Name; path = $_.FullName } }

Describe 'Lab 3.1 Bicep - file header' {
    It "'<file>' has the standard SUMMARY header" -ForEach $AllCases {
        $head = (Get-Content -LiteralPath $path -TotalCount 8) -join "`n"
        $head | Should -Match 'SUMMARY:'
        $head | Should -Match 'DESCRIPTION:'
        $head | Should -Match 'AUTHOR/S:'
        $head | Should -Match 'VERSION:'
    }
}

Describe 'Lab 3.1 Bicep - Hungarian notation' {
    It "'<file>' uses par<Name> for every declared parameter" -ForEach $AllCases {
        $text = Get-Content -Raw -LiteralPath $path
        $bad = [regex]::Matches($text, '(?m)^param\s+(\w+)') |
               Where-Object { $_.Groups[1].Value -notmatch '^par[A-Z]' } |
               ForEach-Object { $_.Groups[1].Value }
        $bad | Should -BeNullOrEmpty -Because "parameters must start with 'par'; offenders: $($bad -join ', ')"
    }

    It "'<file>' uses res<Name> for every resource symbol" -ForEach $AllCases {
        $text = Get-Content -Raw -LiteralPath $path
        $bad = [regex]::Matches($text, "(?m)^resource\s+(\w+)\s+'") |
               Where-Object { $_.Groups[1].Value -notmatch '^res[A-Z]' } |
               ForEach-Object { $_.Groups[1].Value }
        $bad | Should -BeNullOrEmpty -Because "resources must start with 'res'; offenders: $($bad -join ', ')"
    }

    It "'<file>' uses mod<Name> for every module symbol" -ForEach $AllCases {
        $text = Get-Content -Raw -LiteralPath $path
        $bad = [regex]::Matches($text, "(?m)^module\s+(\w+)\s+'") |
               Where-Object { $_.Groups[1].Value -notmatch '^mod[A-Z]' } |
               ForEach-Object { $_.Groups[1].Value }
        $bad | Should -BeNullOrEmpty -Because "modules must start with 'mod'; offenders: $($bad -join ', ')"
    }

    It "'<file>' uses out<Name> for every output symbol" -ForEach $AllCases {
        $text = Get-Content -Raw -LiteralPath $path
        $bad = [regex]::Matches($text, '(?m)^output\s+(\w+)\s') |
               Where-Object { $_.Groups[1].Value -notmatch '^out[A-Z]' } |
               ForEach-Object { $_.Groups[1].Value }
        $bad | Should -BeNullOrEmpty -Because "outputs must start with 'out'; offenders: $($bad -join ', ')"
    }
}

Describe 'Lab 3.1 Bicep - API versions' {
    It "'<file>' pins resource APIs to 2023-11-01 and uses no preview versions" -ForEach $ModCases {
        $text = Get-Content -Raw -LiteralPath $path
        $apis = [regex]::Matches($text, "'Microsoft\.[A-Za-z]+/[A-Za-z]+@([0-9-]+(?:-preview)?)'") |
                ForEach-Object { $_.Groups[1].Value } |
                Sort-Object -Unique
        $apis | Should -Not -BeNullOrEmpty
        foreach ($api in $apis) {
            $api | Should -Not -Match 'preview' -Because "preview APIs violate bicep-standards.md §2 in '$file'"
            $api | Should -Be '2023-11-01' -Because "Lab 2 gold standard is 2023-11-01 in '$file'"
        }
    }
}

Describe 'Lab 3.1 Bicep - CostCenter tag coverage' {
    BeforeAll {
        $script:MainFile = (Resolve-Path (Join-Path $PSScriptRoot '..\bicep\main.bicep')).Path
    }

    It 'main.bicep defines CostCenter in varCommonTags' {
        Get-Content -Raw -LiteralPath $script:MainFile | Should -Match 'CostCenter'
    }

    It 'main.bicep is not relying on ManagedBy instead of CostCenter' {
        $text = Get-Content -Raw -LiteralPath $script:MainFile
        if ($text -match 'ManagedBy') {
            $text | Should -Match 'CostCenter' -Because 'ManagedBy is OK as extra metadata, but CostCenter must also be present'
        }
    }
}

Describe 'Lab 3.1 Bicep - compilation' {
    BeforeAll {
        # The same compiler the deploy scripts use - see tools/BicepCli.psm1 (#144).
        Import-Module (Join-Path $PSScriptRoot '..' '..' '..' 'tools' 'BicepCli.psm1') -Force
        $script:Bicep = Get-BicepCliPath
    }

    It "'<file>' compiles via 'bicep build'" -ForEach $AllCases {
        $null = & $script:Bicep build $path --stdout 2>&1
        $LASTEXITCODE | Should -Be 0 -Because "'$file' must compile without errors"
    }
}

Describe 'Lab 3.1 guide - verification steps match main.bicep' {
    BeforeAll {
        $script:Main  = Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot '..' 'bicep' 'main.bicep')
        $guide        = Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot '..' 'lab-guide-3.1.md')
        $script:Step21 = [regex]::Match($guide, '(?s)### Step 3\.1\.21:.*?### Step 3\.1\.22:').Value
        $script:Step22 = [regex]::Match($guide, '(?s)### Step 3\.1\.22:.*?### Step 3\.1\.23:').Value
        $script:Outputs = @([regex]::Matches($script:Main, '(?m)^output\s+(\w+)') | ForEach-Object { $_.Groups[1].Value })
    }

    It 'step 3.1.21 expects as many dev subnets as the dev VNet module declares' {
        $block = [regex]::Match($script:Main, '(?s)module modDevVnet .*?parSubnets: \[(.*?)parTags:').Groups[1].Value
        $declared = [regex]::Matches($block, "(?m)^\s+name: '").Count
        $declared | Should -BeGreaterThan 0
        $expected = [regex]::Match($script:Step21, 'dev-skycraft-swc-vnet\s+10\.1\.0\.0/16\s+(\d+)')
        $expected.Success | Should -BeTrue -Because 'step 3.1.21 shows the dev VNet with its subnet count'
        [int]$expected.Groups[1].Value | Should -Be $declared
    }

    It "step 3.1.22 lists exactly the template's outputs" {
        $listed = @([regex]::Matches($script:Step22, '(?m)^# (out\w+)\s*$') | ForEach-Object { $_.Groups[1].Value })
        $listed.Count | Should -BeGreaterThan 0
        ($listed | Sort-Object) | Should -Be ($script:Outputs | Sort-Object)
    }

    It 'step 3.1.22 reads only outputs the template declares' {
        $read = @([regex]::Matches($script:Step22, "\`$outputs\['(\w+)'\]") | ForEach-Object { $_.Groups[1].Value })
        $read.Count | Should -BeGreaterThan 0
        foreach ($name in $read) { $script:Outputs | Should -Contain $name }
    }
}

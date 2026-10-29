<#
.SYNOPSIS
    Pester 5 tests for the storage account names of Labs 4.1-4.4 and 5.2-5.3 (issue #438).

.DESCRIPTION
    A storage account name is unique across Azure. The three names of Lab 4.1 were literals in the
    Deploy, Test and Remove scripts and the Bicep of Labs 4.1-4.4, and in the scripts of Labs 5.2
    and 5.3, so a name taken outside the subscription could not be replaced and the lab cycle could
    not pass another. These tests pin that:

      1. Every script keeps the default name it had, so the Portal guides and learners are unaffected.
      2. No script or Bicep file carries one of the names as a literal outside a parameter default.
      3. The Bicep templates take the names as parameters, and the Deploy scripts pass them.
      4. Each Deploy script asks Azure whether a name is free, and stops, before it deploys or
         previews anything, when it is not.

    The scripts are read from their syntax trees, never run: their Az commands cannot be shadowed
    by a function stub. The name check itself is tested in tests/LabCommon-GlobalName.Tests.ps1,
    and the cycle's wiring of the names in tests/LabCycle.Tests.ps1.

.EXAMPLE
    Invoke-Pester -Path .\tests\Storage-Account-Names.Tests.ps1

.NOTES
    Project: SkyCraft
    Issue: #438
#>

#Requires -Version 7.0
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeDiscovery {
    $root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    $m4 = 'module-4-storage'
    $m5 = 'module-5-monitoring-maintenance'
    $prod = "'prodskycraftswcsa'"
    $dev = "'devskycraftswcsa'"
    $platform = "'platformskycraftswcsa'"
    $perEnvironment = '"${Environment}skycraftswcsa"'

    # Script, parameter and the default it must keep.
    $script:ParameterCases = @(
        foreach ($script in 'Deploy-Bicep.ps1', 'Test-Lab.ps1', 'Remove-LabResource.ps1') {
            @{ Lab = '4.1'; Script = $script; Parameter = 'PlatformSaName'; Default = $platform; Path = "$root/$m4/4.1-storage-accounts/scripts/$script" }
            @{ Lab = '4.1'; Script = $script; Parameter = 'DevSaName'; Default = $dev; Path = "$root/$m4/4.1-storage-accounts/scripts/$script" }
            @{ Lab = '4.1'; Script = $script; Parameter = 'ProdSaName'; Default = $prod; Path = "$root/$m4/4.1-storage-accounts/scripts/$script" }
            @{ Lab = '4.2'; Script = $script; Parameter = 'ProdSaName'; Default = $prod; Path = "$root/$m4/4.2-blob-storage/scripts/$script" }
            @{ Lab = '4.2'; Script = $script; Parameter = 'DevSaName'; Default = $dev; Path = "$root/$m4/4.2-blob-storage/scripts/$script" }
            @{ Lab = '4.3'; Script = $script; Parameter = 'StorageAccountName'; Default = $perEnvironment; Path = "$root/$m4/4.3-azure-files/scripts/$script" }
            @{ Lab = '4.4'; Script = $script; Parameter = 'StorageAccountName'; Default = $perEnvironment; Path = "$root/$m4/4.4-storage-security/scripts/$script" }
        }
        foreach ($script in 'New-LabBlobBackup.ps1', 'Test-Lab.ps1', 'Remove-LabResource.ps1') {
            @{ Lab = '5.2'; Script = $script; Parameter = 'ProdSaName'; Default = $prod; Path = "$root/$m5/5.2-business-continuity/scripts/$script" }
        }
        @{ Lab = '5.3'; Script = 'Deploy-Bicep.ps1'; Parameter = 'PlatformSaName'; Default = $platform; Path = "$root/$m5/5.3-network-monitoring/scripts/Deploy-Bicep.ps1" }
    )

    # Bicep parameter and the default it must keep.
    $script:BicepCases = @(
        @{ Lab = '4.1'; Parameter = 'parPlatformSaName'; Default = 'platformskycraftswcsa'; Path = "$root/$m4/4.1-storage-accounts/bicep/main.bicep" }
        @{ Lab = '4.1'; Parameter = 'parDevSaName'; Default = 'devskycraftswcsa'; Path = "$root/$m4/4.1-storage-accounts/bicep/main.bicep" }
        @{ Lab = '4.1'; Parameter = 'parProdSaName'; Default = 'prodskycraftswcsa'; Path = "$root/$m4/4.1-storage-accounts/bicep/main.bicep" }
        @{ Lab = '4.2'; Parameter = 'parProdSaName'; Default = 'prodskycraftswcsa'; Path = "$root/$m4/4.2-blob-storage/bicep/main.bicep" }
        @{ Lab = '4.2'; Parameter = 'parDevSaName'; Default = 'devskycraftswcsa'; Path = "$root/$m4/4.2-blob-storage/bicep/main.bicep" }
        @{ Lab = '4.3'; Parameter = 'parStorageAccountName'; Default = '${parEnvironment}skycraftswcsa'; Path = "$root/$m4/4.3-azure-files/bicep/main.bicep" }
        @{ Lab = '4.4'; Parameter = 'parStorageAccountName'; Default = '${parEnvironment}skycraftswcsa'; Path = "$root/$m4/4.4-storage-security/bicep/main.bicep" }
    )

    # Deploy script, the template it deploys and the template parameters it must pass.
    $script:DeployCases = @(
        @{ Lab = '4.1'; Path = "$root/$m4/4.1-storage-accounts/scripts/Deploy-Bicep.ps1"; Bicep = "$root/$m4/4.1-storage-accounts/bicep/main.bicep"; Passes = @{ parPlatformSaName = 'PlatformSaName'; parDevSaName = 'DevSaName'; parProdSaName = 'ProdSaName' } }
        @{ Lab = '4.2'; Path = "$root/$m4/4.2-blob-storage/scripts/Deploy-Bicep.ps1"; Bicep = "$root/$m4/4.2-blob-storage/bicep/main.bicep"; Passes = @{ parProdSaName = 'ProdSaName'; parDevSaName = 'DevSaName' } }
        @{ Lab = '4.3'; Path = "$root/$m4/4.3-azure-files/scripts/Deploy-Bicep.ps1"; Bicep = "$root/$m4/4.3-azure-files/bicep/main.bicep"; Passes = @{ parStorageAccountName = 'StorageAccountName' } }
        @{ Lab = '4.4'; Path = "$root/$m4/4.4-storage-security/scripts/Deploy-Bicep.ps1"; Bicep = "$root/$m4/4.4-storage-security/bicep/main.bicep"; Passes = @{ parStorageAccountName = 'StorageAccountName' } }
    )

    # Every script of Modules 4 and 5, for the literal scan. Test-Lab etc. of other labs are read too.
    $script:AllScripts = @(
        foreach ($module in $m4, $m5) {
            Get-ChildItem -LiteralPath "$root/$module" -Recurse -File -Filter '*.ps1' |
                Where-Object { $_.FullName -match '[\\/]scripts[\\/]' } |
                ForEach-Object { @{ Name = $_.FullName.Substring($root.Length + 1).Replace('\', '/'); Path = $_.FullName } }
        }
    )
    $script:AllBicep = @(
        foreach ($module in $m4, $m5) {
            Get-ChildItem -LiteralPath "$root/$module" -Recurse -File -Filter '*.bicep' |
                ForEach-Object { @{ Name = $_.FullName.Substring($root.Length + 1).Replace('\', '/'); Path = $_.FullName } }
        }
    )
}

BeforeAll {
    function Get-Ast {
        param([string]$Path)
        [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$null, [ref]$null)
    }
}

Describe 'Storage account names keep their defaults (#438)' {

    It 'Lab <Lab> <Script> takes -<Parameter>, defaulting to <Default>' -ForEach $script:ParameterCases {
        $ast = Get-Ast -Path $Path
        $parameter = @($ast.ParamBlock.Parameters | Where-Object { $_.Name.VariablePath.UserPath -eq $Parameter })
        $parameter.Count | Should -Be 1
        $parameter[0].DefaultValue.Extent.Text | Should -BeExactly $Default
    }

    It 'Lab <Lab> <Script> accepts only a valid storage account name for -<Parameter>' -ForEach $script:ParameterCases {
        $ast = Get-Ast -Path $Path
        $parameter = @($ast.ParamBlock.Parameters | Where-Object { $_.Name.VariablePath.UserPath -eq $Parameter })[0]
        $pattern = @($parameter.Attributes | Where-Object { $_.TypeName.Name -eq 'ValidatePattern' })
        $pattern.Count | Should -Be 1
        'prodskycraftswcsaab' | Should -Match $pattern[0].PositionalArguments[0].Value
        'Prod-Name' | Should -Not -Match $pattern[0].PositionalArguments[0].Value
    }

    It 'Lab <Lab> main.bicep defaults <Parameter> to <Default>' -ForEach $script:BicepCases {
        $source = Get-Content -Raw -LiteralPath $Path
        $source | Should -Match ("(?m)^param $Parameter string = '" + [regex]::Escape($Default) + "'\s*$")
    }

    It 'Lab <Lab> main.bicep limits <Parameter> to 3-24 characters' -ForEach $script:BicepCases {
        $source = Get-Content -Raw -LiteralPath $Path
        $source | Should -Match "(?m)@minLength\(3\)\s+@maxLength\(24\)\s+param $Parameter "
    }
}

Describe 'No storage account name is left as a literal (#438)' {

    It '<Name> holds a name only as a parameter default' -ForEach $script:AllScripts {
        $ast = Get-Ast -Path $Path
        $strings = $ast.FindAll({
                param($node)
                ($node -is [System.Management.Automation.Language.StringConstantExpressionAst] -or
                $node -is [System.Management.Automation.Language.ExpandableStringExpressionAst]) -and
                $node.Value -match 'skycraftswcsa'
            }, $true)
        foreach ($string in $strings) {
            $parent = $string.Parent
            while ($parent -and $parent -isnot [System.Management.Automation.Language.ParameterAst]) { $parent = $parent.Parent }
            $parent | Should -Not -BeNullOrEmpty -Because "line $($string.Extent.StartLineNumber): $($string.Extent.Text) is not a parameter default"
        }
    }

    It '<Name> holds a name only as a parameter default' -ForEach $script:AllBicep {
        $lines = Get-Content -LiteralPath $Path
        foreach ($line in ($lines | Where-Object { $_ -match 'skycraftswcsa' -and $_ -notmatch '^\s*//' })) {
            $line | Should -Match '^param par\w+ string = ' -Because 'a storage account name is a parameter default'
        }
    }
}

Describe 'Deploy-Bicep.ps1 passes the names to its template (#438)' {

    It 'Lab <Lab> passes <Template> from -<Script>' -ForEach @(
        foreach ($case in $script:DeployCases) {
            foreach ($key in $case.Passes.Keys) {
                @{ Lab = $case.Lab; Path = $case.Path; Bicep = $case.Bicep; Template = $key; Script = $case.Passes[$key] }
            }
        }
    ) {
        $source = Get-Content -Raw -LiteralPath $Path
        $source | Should -Match ("\b$Template\s*=\s*\`$$Script\b")
        (Get-Content -Raw -LiteralPath $Bicep) | Should -Match "(?m)^param $Template string"
    }
}

Describe 'Deploy-Bicep.ps1 stops on a taken storage account name before it deploys (#438)' {

    It 'Lab <Lab> checks the name with Test-LabGlobalName -Kind StorageAccount and exits when it is taken' -ForEach $script:DeployCases {
        $ast = Get-Ast -Path $Path
        $calls = @($ast.FindAll({
                    param($node)
                    $node -is [System.Management.Automation.Language.CommandAst] -and $node.GetCommandName() -eq 'Test-LabGlobalName'
                }, $true))
        $calls.Count | Should -Be 1
        $calls[0].Extent.Text | Should -Match '-Kind StorageAccount\b'
        $calls[0].Extent.Text | Should -Match '-ParameterName'
        $calls[0].Extent.Text | Should -Match '-Owned'

        # Exit-Lab follows within the same block, so a taken name ends the script.
        $exits = @($ast.FindAll({
                    param($node)
                    $node -is [System.Management.Automation.Language.CommandAst] -and $node.GetCommandName() -eq 'Exit-Lab' -and
                    $node.Extent.StartOffset -gt $calls[0].Extent.EndOffset -and $node.Extent.StartOffset -lt ($calls[0].Extent.EndOffset + 250)
                }, $true))
        $exits.Count | Should -BeGreaterThan 0
        $exits[0].Extent.Text | Should -Match '-FailureCount (1|\$takenNames)\b'
    }

    It 'Lab <Lab> checks the name before it deploys or previews' -ForEach $script:DeployCases {
        $ast = Get-Ast -Path $Path
        $check = @($ast.FindAll({
                    param($node)
                    $node -is [System.Management.Automation.Language.CommandAst] -and $node.GetCommandName() -eq 'Test-LabGlobalName'
                }, $true))[0]
        $deploying = @($ast.FindAll({
                    param($node)
                    $node -is [System.Management.Automation.Language.CommandAst] -and
                    $node.GetCommandName() -in 'New-AzSubscriptionDeployment', 'Get-AzSubscriptionDeploymentWhatIfResult'
                }, $true))
        $deploying.Count | Should -BeGreaterThan 0
        foreach ($command in $deploying) {
            $check.Extent.StartOffset | Should -BeLessThan $command.Extent.StartOffset -Because "$($command.GetCommandName()) must not run before the name check"
        }
    }

    It 'Lab <Lab> lets a name the lab already owns through, as the cycle''s second run does' -ForEach $script:DeployCases {
        # An account that is already in the lab's resource group is not "taken": Azure reports its own
        # name as unavailable too, and a re-run of the deploy would otherwise stop on it.
        $ast = Get-Ast -Path $Path
        $check = @($ast.FindAll({
                    param($node)
                    $node -is [System.Management.Automation.Language.CommandAst] -and $node.GetCommandName() -eq 'Test-LabGlobalName'
                }, $true))[0]
        $check.Extent.Text | Should -Not -Match '-Owned \$(false|true)\b'
        $check.Extent.Text | Should -Match '-Owned (\(\$sa\.Name -in \$existingAccounts\)|\$owned|\$accountOwned)'
    }
}

<#
.SYNOPSIS
    Pester 5 test: every LabCommon function a lab script calls is exported by the module.

.DESCRIPTION
    A function defined in tools/LabCommon.psm1 but missing from Export-ModuleMember is invisible
    to the lab scripts that import the module: the call fails at run time with "The term ... is
    not recognized" (#368, Invoke-LabArmRequest in Deploy-Bicep.ps1), and the module's own
    callers hide it because they run inside the module scope.
#>

BeforeDiscovery {
    $script:RepoRoot = Split-Path -Parent $PSScriptRoot
    $script:ModuleText = Get-Content -LiteralPath (Join-Path $script:RepoRoot 'tools/LabCommon.psm1') -Raw
    $script:Defined = [regex]::Matches($script:ModuleText, '(?m)^function\s+([A-Za-z0-9-]+)') | ForEach-Object { $_.Groups[1].Value }
    $exportLine = [regex]::Match($script:ModuleText, '(?m)^Export-ModuleMember\s+-Function\s+(.+)$').Groups[1].Value
    $script:Exported = $exportLine -split '\s*,\s*' | ForEach-Object { $_.Trim() }

    $script:Scripts = foreach ($dir in Get-ChildItem -LiteralPath $script:RepoRoot -Directory -Filter 'module-*') {
        Get-ChildItem -LiteralPath $dir.FullName -Recurse -File -Filter '*.ps1' | Where-Object { $_.FullName -notmatch '[\/]tests[\/]' }
    }
    $script:Scripts = @($script:Scripts)
    $script:Cases = foreach ($s in $script:Scripts) {
        $text = Get-Content -LiteralPath $s.FullName -Raw
        foreach ($fn in $script:Defined) {
            if ($script:Exported -contains $fn) { continue }
            if ($text -match "(?<![A-Za-z0-9-])$([regex]::Escape($fn))(?![A-Za-z0-9-])") {
                @{ Script = $s.FullName.Substring($script:RepoRoot.Length + 1); Function = $fn }
            }
        }
    }
}

Describe 'LabCommon exports' {
    BeforeAll {
        $moduleText = Get-Content -LiteralPath (Join-Path (Split-Path -Parent $PSScriptRoot) 'tools/LabCommon.psm1') -Raw
        $script:DefinedCount = [regex]::Matches($moduleText, '(?m)^function\s+').Count
        $script:Exported = [regex]::Match($moduleText, '(?m)^Export-ModuleMember\s+-Function\s+(.+)$').Groups[1].Value -split '\s*,\s*'
        $script:ScriptCount = @(Get-ChildItem -LiteralPath (Split-Path -Parent $PSScriptRoot) -Directory -Filter 'module-*').Count
    }

    It 'finds the module functions and its export list' {
        $script:DefinedCount | Should -BeGreaterThan 0
        $script:Exported.Count | Should -BeGreaterThan 0
    }

    It 'finds the module folders to scan' {
        $script:ScriptCount | Should -BeGreaterThan 0
    }

    It 'exports <Function>, which <Script> calls' -ForEach @($script:Cases) {
        $script:Exported | Should -Contain $Function
    }
}

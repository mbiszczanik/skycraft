<#
.SYNOPSIS
    Pester 5 tests: AVM registry references are pinned and consistent repo-wide.

.DESCRIPTION
    docs/bicep-standards.md (AVM-first policy, issue #62 v2) requires:
      - every 'br/public:avm/...' reference pins an EXACT semver (x.y.z) —
        no floating tags, no partial versions
      - a given AVM module resolves to a SINGLE version across the whole
        repository (the version catalogue in docs/bicep-standards.md)
      - no registry aliases in bicepconfig.json — full br/public: paths only

    API-version policy for raw resource declarations lives in
    tests/Api-Version-Policy.Tests.ps1; AVM references carry no API version
    and are governed by this file instead.

.EXAMPLE
    Invoke-Pester -Path .\tests\Avm-Module-Pinning.Tests.ps1

.NOTES
    Project: SkyCraft
#>

#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

$RepoRoot   = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$BicepFiles = Get-ChildItem -Path $RepoRoot -Recurse -File -Filter '*.bicep'

# Every AVM registry reference across the repo from actual module declarations:
# module <symbolicName> 'br/public:<avm-path>:<version>' = {
$AvmRefPattern = "(?m)^\s*module\s+\S+\s+['`\"]br/public:(avm/[a-z0-9/-]+):([^'`\"]+)['`\"]"
$AllRefs = foreach ($f in $BicepFiles) {
    $text = Get-Content -Raw -LiteralPath $f.FullName
    foreach ($m in [regex]::Matches($text, $AvmRefPattern)) {
        [pscustomobject]@{
            File    = $f.FullName.Substring($RepoRoot.Length + 1)
            Module  = $m.Groups[1].Value
            Version = $m.Groups[2].Value
        }
    }
}

$RefCases = @($AllRefs | ForEach-Object {
    @{ file = $_.File; module = $_.Module; version = $_.Version }
})

$ModuleCases = @($AllRefs | Group-Object Module | ForEach-Object {
    @{
        module   = $_.Name
        versions = @($_.Group.Version | Sort-Object -Unique)
        files    = @($_.Group.File | Sort-Object -Unique)
    }
})

Describe 'AVM - every reference is pinned to an exact semver' {
    It "'<file>' pins '<module>' to an exact x.y.z version (got '<version>')" -ForEach $RefCases {
        $version | Should -Match '^\d+\.\d+\.\d+$' -Because "AVM references must pin an exact x.y.z version; '$module' in '$file' uses '$version'"
    }
}

Describe 'AVM - single version per module repo-wide' {
    It "'<module>' resolves to exactly one version across the repository" -ForEach $ModuleCases {
        $versions.Count | Should -Be 1 -Because "module '$module' is referenced with versions [$($versions -join ', ')] in: $($files -join '; ')"
    }
}

Describe 'AVM - no registry aliases' {
    It 'bicepconfig.json defines no moduleAliases' {
        $config = Get-Content -Raw -LiteralPath (Join-Path (Resolve-Path (Join-Path $PSScriptRoot '..')).Path 'bicepconfig.json') | ConvertFrom-Json
        $config.PSObject.Properties.Name | Should -Not -Contain 'moduleAliases' -Because 'AVM is consumed via full br/public: paths only'
    }
}

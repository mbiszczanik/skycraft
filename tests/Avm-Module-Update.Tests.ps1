<#
.SYNOPSIS
    Pester 5 tests: every AVM pin is published, and the repo knows how far behind it is.

.DESCRIPTION
    Issue #82 - AVM registry modules are invisible to Dependabot. A `br/public:avm/...`
    pin has no update signal of its own, so tools/AvmRegistry.psm1 asks the registry
    (mcr.microsoft.com, the `br/public` alias) which tags exist and compares them with
    the pins in the Bicep files. tools/Get-AvmModuleUpdate.ps1 prints that comparison
    and the quarterly workflow (.github/workflows/avm-module-update.yml) runs it.

    The first Describes pin the module's behaviour offline with an injected tag list:
      - the pin scan finds every module declaration and groups it by module
      - the tag list is read as semver, so 0.10.0 sorts after 0.9.0
      - a pin equal to the newest tag is Current, an older one is Behind, one the
        registry does not list is Unlisted, and an unreachable registry is Unknown

    The last Describe is the live check, and it is deliberately narrow: it asserts that
    every pinned version EXISTS in the registry, not that it is the newest. A newer AVM
    release is a review item, not a broken repository, and a gate that fails whenever
    Microsoft publishes would be switched off within a month. The latest version is
    carried in each test's name instead, so the run output IS the pins-vs-latest list.
    It skips itself when the registry cannot be reached, so the suite stays green offline.

.EXAMPLE
    Invoke-Pester -Path .\tests\Avm-Module-Update.Tests.ps1

.NOTES
    Project: SkyCraft
#>

#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
Import-Module (Join-Path $RepoRoot 'tools/AvmRegistry.psm1') -Force

# ---------------------------------------------------------------------------------------
# Live data, computed at discovery so the It names can carry the latest version.
# One probe decides whether the registry is reachable at all; a module whose own tag list
# fails after that is reported Unknown and skipped individually.
# ---------------------------------------------------------------------------------------

$RegistryReachable = Test-AvmRegistry
$LiveCases = @(
    if ($RegistryReachable) {
        Compare-AvmModulePin -Reference (Get-AvmModuleReference -RepoRoot $RepoRoot) | ForEach-Object {
            @{ module = $_.Module; pinned = $_.Pinned; latest = $_.Latest; status = $_.Status; files = $_.Files }
        }
    }
)

Describe 'AVM registry - Get-AvmModuleReference finds every pin' {

    BeforeAll {
        $root = Join-Path $TestDrive 'repo'
        New-Item -ItemType Directory -Path (Join-Path $root 'lab-a/bicep') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $root 'lab-b/bicep') -Force | Out-Null

        Set-Content -LiteralPath (Join-Path $root 'lab-a/bicep/main.bicep') -Value @'
module modRg 'br/public:avm/res/resources/resource-group:0.4.4' = {
  name: 'rg'
}
module modStorage 'br/public:avm/res/storage/storage-account:0.33.0' = [for env in envs: {
  name: 'st'
}]
// module modOld 'br/public:avm/res/storage/storage-account:0.1.0' = {}
'@
        Set-Content -LiteralPath (Join-Path $root 'lab-b/bicep/main.bicep') -Value @'
module modRg 'br/public:avm/res/resources/resource-group:0.4.4' = {
  name: 'rg'
}
'@
        $script:Refs = @(Get-AvmModuleReference -RepoRoot $root)
    }

    It 'returns one entry per distinct module' {
        $script:Refs.Count | Should -Be 2
        $script:Refs.Module | Should -Contain 'avm/res/resources/resource-group'
        $script:Refs.Module | Should -Contain 'avm/res/storage/storage-account'
    }

    It 'carries the pinned version' {
        ($script:Refs | Where-Object Module -eq 'avm/res/storage/storage-account').Pinned | Should -BeExactly '0.33.0'
    }

    It 'lists every file that references the module, repo-relative with forward slashes' {
        $files = ($script:Refs | Where-Object Module -eq 'avm/res/resources/resource-group').Files
        $files | Should -HaveCount 2
        $files | Should -Contain 'lab-a/bicep/main.bicep'
        $files | Should -Contain 'lab-b/bicep/main.bicep'
    }

    It 'ignores a commented-out declaration' {
        ($script:Refs | Where-Object Module -eq 'avm/res/storage/storage-account').Pinned | Should -Not -Be '0.1.0'
    }
}

Describe 'AVM registry - Get-AvmPublishedVersion reads the tag list as semver' {

    It 'sorts 0.10.0 after 0.9.0' {
        $provider = { param($Module) @('0.9.0', '0.10.0', '0.2.1') }
        $versions = @(Get-AvmPublishedVersion -Module 'avm/res/x/y' -TagListProvider $provider)
        $versions[-1].ToString() | Should -BeExactly '0.10.0'
        $versions[0].ToString()  | Should -BeExactly '0.2.1'
    }

    It 'drops tags that are not x.y.z' {
        $provider = { param($Module) @('0.1.0', 'latest', '0.2.0-preview', '1.0') }
        $versions = @(Get-AvmPublishedVersion -Module 'avm/res/x/y' -TagListProvider $provider)
        @($versions | ForEach-Object ToString) | Should -Be @('0.1.0')
    }

    It 'asks the provider for the module it was given' {
        $asked = [System.Collections.Generic.List[string]]::new()
        $provider = { param($Module) $asked.Add($Module); @('0.1.0') }.GetNewClosure()
        Get-AvmPublishedVersion -Module 'avm/res/network/virtual-network' -TagListProvider $provider | Out-Null
        $asked | Should -Be @('avm/res/network/virtual-network')
    }

    It 'builds the mcr.microsoft.com tag-list URL for br/public' {
        Get-AvmTagListUri -Module 'avm/res/network/virtual-network' |
            Should -BeExactly 'https://mcr.microsoft.com/v2/bicep/avm/res/network/virtual-network/tags/list'
    }
}

Describe 'AVM registry - Compare-AvmModulePin classifies every pin' {

    BeforeAll {
        $script:Refs = @(
            [pscustomobject]@{ Module = 'avm/res/a/current';  Pinned = '0.5.0';  Files = @('a.bicep') }
            [pscustomobject]@{ Module = 'avm/res/a/behind';   Pinned = '0.9.0';  Files = @('b.bicep') }
            [pscustomobject]@{ Module = 'avm/res/a/unlisted'; Pinned = '0.3.0';  Files = @('c.bicep') }
            [pscustomobject]@{ Module = 'avm/res/a/offline';  Pinned = '0.1.0';  Files = @('d.bicep') }
        )
        $script:Provider = {
            param($Module)
            switch ($Module) {
                'avm/res/a/current'  { @('0.4.0', '0.5.0') }
                'avm/res/a/behind'   { @('0.9.0', '0.10.0', '0.10.1') }
                'avm/res/a/unlisted' { @('0.4.0', '0.5.0') }
                'avm/res/a/offline'  { throw 'connection refused' }
            }
        }
        $script:Result = @(Compare-AvmModulePin -Reference $script:Refs -TagListProvider $script:Provider)
        $script:ByModule = @{}
        foreach ($r in $script:Result) { $script:ByModule[$r.Module] = $r }
    }

    It 'returns one result per reference, in the same order' {
        $script:Result.Module | Should -Be $script:Refs.Module
    }

    It 'marks a pin equal to the newest tag as Current' {
        $script:ByModule['avm/res/a/current'].Status | Should -BeExactly 'Current'
        $script:ByModule['avm/res/a/current'].Latest | Should -BeExactly '0.5.0'
    }

    It 'marks a pin older than the newest tag as Behind, with the newest tag' {
        $script:ByModule['avm/res/a/behind'].Status | Should -BeExactly 'Behind'
        $script:ByModule['avm/res/a/behind'].Latest | Should -BeExactly '0.10.1'
    }

    It 'marks a pin the registry does not list as Unlisted' {
        $script:ByModule['avm/res/a/unlisted'].Status | Should -BeExactly 'Unlisted'
    }

    It 'marks an unreachable module as Unknown and carries the error' {
        $script:ByModule['avm/res/a/offline'].Status | Should -BeExactly 'Unknown'
        $script:ByModule['avm/res/a/offline'].Latest | Should -BeNullOrEmpty
        $script:ByModule['avm/res/a/offline'].Error  | Should -Match 'connection refused'
    }

    It 'passes the files through' {
        $script:ByModule['avm/res/a/behind'].Files | Should -Be @('b.bicep')
    }
}

Describe 'AVM registry - the catalogue in docs/bicep-standards.md matches the pins' {

    # docs/bicep-standards.md section 4.4 asks for every reference and the catalogue row to
    # move in the same PR. tests/Avm-Module-Pinning.Tests.ps1 guards the references against
    # each other; this guards the table against them.
    BeforeAll {
        $root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
        $doc  = Get-Content -Raw -LiteralPath (Join-Path $root 'docs/bicep-standards.md')

        $script:Catalogue = @{}
        foreach ($m in [regex]::Matches($doc, '(?m)^\| `(?<module>avm/[a-z0-9/-]+)` \| `(?<version>\d+\.\d+\.\d+)` \|')) {
            $script:Catalogue[$m.Groups['module'].Value] = $m.Groups['version'].Value
        }

        $script:Pins = @{}
        foreach ($ref in Get-AvmModuleReference -RepoRoot $root) { $script:Pins[$ref.Module] = $ref.Pinned }
    }

    It 'found the catalogue table' {
        $script:Catalogue.Count | Should -BeGreaterThan 0
    }

    It 'lists exactly the modules the templates pin' {
        @($script:Catalogue.Keys | Sort-Object) | Should -Be @($script:Pins.Keys | Sort-Object)
    }

    It 'carries the pinned version of every module' {
        foreach ($module in $script:Pins.Keys) {
            $script:Catalogue[$module] | Should -BeExactly $script:Pins[$module] -Because "docs/bicep-standards.md section 4.4 lists '$module' at $($script:Catalogue[$module]) but the templates pin $($script:Pins[$module])"
        }
    }
}

Describe 'AVM registry - tools/Get-AvmModuleUpdate.ps1 reports and gates' {

    BeforeAll {
        # $PSScriptRoot rather than the file-level $RepoRoot: a BeforeAll does not see the
        # discovery run's file-level state.
        $script:Script = Join-Path (Resolve-Path (Join-Path $PSScriptRoot '..')).Path 'tools/Get-AvmModuleUpdate.ps1'
        $script:Pwsh   = (Get-Process -Id $PID).Path

        # A two-module repo: one current, one behind.
        $script:Root = Join-Path $TestDrive 'update-repo'
        New-Item -ItemType Directory -Path $script:Root -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $script:Root 'main.bicep') -Value @'
module modA 'br/public:avm/res/a/current:0.5.0' = {}
module modB 'br/public:avm/res/a/behind:0.9.0' = {}
'@
        # Written as text so the same provider can be handed to a child pwsh.
        $script:ProviderText = "{ param(`$Module) if (`$Module -eq 'avm/res/a/behind') { @('0.9.0', '0.10.0') } else { @('0.5.0') } }"
    }

    It 'writes one Markdown table row per module' {
        # A child process, like every other case here: the script's failure paths `exit`,
        # which in-process would end the Pester run itself.
        $output = & $script:Pwsh -NoProfile -Command "& '$($script:Script)' -RepoRoot '$($script:Root)' -Format Markdown -TagListProvider $($script:ProviderText)" | Out-String
        $output | Should -Match '(?m)^\| `avm/res/a/current` \| 0\.5\.0 \| 0\.5\.0 \| Current \|'
        $output | Should -Match '(?m)^\| `avm/res/a/behind` \| 0\.9\.0 \| 0\.10\.0 \| Behind \|'
    }

    It 'exits 0 by default even when a module is behind' {
        & $script:Pwsh -NoProfile -Command "& '$($script:Script)' -RepoRoot '$($script:Root)' -TagListProvider $($script:ProviderText) | Out-Null" | Out-Null
        $LASTEXITCODE | Should -Be 0
    }

    It 'exits non-zero with -FailOnBehind when a module is behind' {
        & $script:Pwsh -NoProfile -Command "& '$($script:Script)' -RepoRoot '$($script:Root)' -FailOnBehind -TagListProvider $($script:ProviderText) | Out-Null" | Out-Null
        $LASTEXITCODE | Should -Be 1
    }

    It 'exits non-zero when a pin is unlisted, whatever the switches' {
        $unlisted = "{ param(`$Module) @('0.1.0') }"
        & $script:Pwsh -NoProfile -Command "& '$($script:Script)' -RepoRoot '$($script:Root)' -TagListProvider $unlisted | Out-Null" | Out-Null
        $LASTEXITCODE | Should -Be 1
    }
}

Describe 'AVM registry - every pin in the repository is published on br/public' {

    It 'found the pins to check' -ForEach @(@{ count = $LiveCases.Count; reachable = $RegistryReachable }) {
        if (-not $reachable) { Set-ItResult -Skipped -Because 'mcr.microsoft.com is not reachable from this host' }
        $count | Should -BeGreaterThan 0 -Because 'an empty pin list would make this Describe pass by checking nothing'
    }

    It "'<module>' pin <pinned> is published (latest: <latest>)" -ForEach $LiveCases {
        if ($status -eq 'Unknown') { Set-ItResult -Skipped -Because 'the tag list for this module could not be read' }
        $status | Should -Not -Be 'Unlisted' -Because "'$module' is pinned to $pinned in $($files -join ', ') but br/public does not publish that tag"
    }
}

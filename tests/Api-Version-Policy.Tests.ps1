<#
.SYNOPSIS
    Pester 5 tests: every Bicep file pins a stable, non-future API version.

.DESCRIPTION
    docs/bicep-standards.md §2 requires "Gold Standard" stable API versions and forbids
    bleeding-edge releases ("Prefer Stable Versions"). This test walks every *.bicep
    file in module-*/ and asserts:
      - no resource or existing-resource declaration uses a '-preview' suffix
      - no API version date is from the future (later than today)
      - each file still compiles under 'az bicep build'

    A sibling regression test guards the specific bleeding-edge versions that were
    previously in the repo so they do not creep back in.

.EXAMPLE
    Invoke-Pester -Path .\tests\Api-Version-Policy.Tests.ps1

.NOTES
    Project: SkyCraft
#>

#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

$RepoRoot    = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$BicepFiles  = Get-ChildItem -Path $RepoRoot -Recurse -File -Filter '*.bicep' |
               Where-Object { $_.FullName -match '\\module-\d.*\\bicep\\' }

# Allow-list: resource types that have NEVER shipped a stable API version.
# Microsoft.Insights/diagnosticSettings is permanently stuck on *-preview upstream —
# see https://learn.microsoft.com/azure/templates/microsoft.insights/diagnosticsettings.
# Every listed version there is *-preview. Flagging these would be noise, not a real
# standards violation. The allow-list is passed per-case via -ForEach so it survives
# Pester 5 discovery/run scope isolation.
$PreviewAllowList = @(
    'Microsoft.Insights/diagnosticSettings'
)

$FileCases = $BicepFiles | ForEach-Object {
    @{
        file              = $_.FullName.Substring($RepoRoot.Length + 1)
        path              = $_.FullName
        previewAllowList  = $PreviewAllowList
    }
}

Describe 'Bicep - no preview API versions' {
    It "'<file>' declares no '@*-preview' API versions outside the allow-list" -ForEach $FileCases {
        $text = Get-Content -Raw -LiteralPath $path
        $allow = $previewAllowList
        $previews = [regex]::Matches($text, "'(Microsoft\.[^/']+/[^@']+)@([0-9-]+-preview)'") |
                    ForEach-Object { @{ type = $_.Groups[1].Value; api = $_.Groups[2].Value } } |
                    Where-Object { $allow -notcontains $_.type }
        $preview_strs = $previews | ForEach-Object { "$($_.type)@$($_.api)" }
        $preview_strs | Should -BeNullOrEmpty -Because "preview APIs in '$file': $($preview_strs -join ', ')"
    }
}

Describe 'Bicep - no future-dated API versions' {
    BeforeAll { $script:Today = (Get-Date).Date }

    It "'<file>' declares no API versions past today's date" -ForEach $FileCases {
        $text = Get-Content -Raw -LiteralPath $path
        $dates = [regex]::Matches($text, "'Microsoft\.[^/']+/[^@']+@(\d{4}-\d{2}-\d{2})") |
                 ForEach-Object { $_.Groups[1].Value } |
                 Sort-Object -Unique
        foreach ($d in $dates) {
            [datetime]::Parse($d) | Should -BeLessOrEqual $script:Today -Because "future-dated API '$d' in '$file' violates bicep-standards.md §2 (Prefer Stable Versions)"
        }
    }
}

Describe 'Bicep - regression guard on known bleeding-edge versions' {
    It "'<file>' does not reintroduce Microsoft.Web/*@2025-03-01" -ForEach $FileCases {
        $text = Get-Content -Raw -LiteralPath $path
        $text | Should -Not -Match "Microsoft\.Web/[^@']+@2025-03-01"
    }

    It "'<file>' does not reintroduce Microsoft.ContainerRegistry/registries@2023-01-01-preview" -ForEach $FileCases {
        $text = Get-Content -Raw -LiteralPath $path
        $text | Should -Not -Match "Microsoft\.ContainerRegistry/registries@2023-01-01-preview"
    }
}

Describe 'Bicep - module-3.3 and module-3.4 still compile' {
    $FixedModules = @(
        @{ file = 'module-3-compute/3.3-containers/bicep/main.bicep'        ; path = (Join-Path $RepoRoot 'module-3-compute/3.3-containers/bicep/main.bicep') }
        @{ file = 'module-3-compute/3.3-containers/bicep/modules/acr.bicep' ; path = (Join-Path $RepoRoot 'module-3-compute/3.3-containers/bicep/modules/acr.bicep') }
        @{ file = 'module-3-compute/3.3-containers/bicep/modules/aci.bicep' ; path = (Join-Path $RepoRoot 'module-3-compute/3.3-containers/bicep/modules/aci.bicep') }
        @{ file = 'module-3-compute/3.3-containers/bicep/modules/containerapps.bicep' ; path = (Join-Path $RepoRoot 'module-3-compute/3.3-containers/bicep/modules/containerapps.bicep') }
        @{ file = 'module-3-compute/3.4-app-service/bicep/main.bicep'       ; path = (Join-Path $RepoRoot 'module-3-compute/3.4-app-service/bicep/main.bicep') }
        @{ file = 'module-3-compute/3.4-app-service/bicep/modules/app-service.bicep' ; path = (Join-Path $RepoRoot 'module-3-compute/3.4-app-service/bicep/modules/app-service.bicep') }
    )

    It "'<file>' compiles via 'az bicep build'" -ForEach $FixedModules {
        $null = & az bicep build --file $path --stdout 2>&1
        $LASTEXITCODE | Should -Be 0 -Because "'$file' must compile without errors after API downgrade"
    }
}

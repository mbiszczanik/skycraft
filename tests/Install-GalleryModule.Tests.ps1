<#
.SYNOPSIS
    Pester 5 tests: tools/Install-GalleryModule.ps1 retries a failed Gallery install, and the workflows use it (#440).

.DESCRIPTION
    A PowerShell Gallery hiccup failed a PR check three times in two days with no code change. The
    cases run the script with Install-Module and Start-Sleep mocked, so they need neither the Gallery
    nor real waits:
      - a first-try success installs once and does not wait;
      - two failures then a success install three times, waiting 15 and 30 seconds;
      - failures on every try throw, after exactly -MaxAttempts calls, naming the module and the cause;
      - the version bounds reach Install-Module;
    and a text guard: no workflow calls Install-Module bare.

.EXAMPLE
    Invoke-Pester -Path .\tests\Install-GalleryModule.Tests.ps1

.NOTES
    Project: SkyCraft
    Issue: #440
#>

#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    $script:Script   = Join-Path $script:RepoRoot 'tools' 'Install-GalleryModule.ps1'
    # PowerShellGet is on every runner; the stub only covers a machine without it.
    if (-not (Get-Command Install-Module -ErrorAction SilentlyContinue)) {
        function global:Install-Module { param($Name, $MinimumVersion, $MaximumVersion, [switch]$Force, $Scope) }
    }
}

Describe 'Install-GalleryModule.ps1 (#440)' {

    BeforeEach {
        $global:GalleryInstallCalls = 0
        Mock Start-Sleep { }
    }

    It 'installs once and does not wait when the first try works' {
        Mock Install-Module { }
        & $script:Script -Name Pester
        Should -Invoke Install-Module -Times 1 -Exactly
        Should -Invoke Start-Sleep -Times 0 -Exactly
    }

    It 'tries again after a failure and waits longer each time' {
        Mock Install-Module { $global:GalleryInstallCalls++; if ($global:GalleryInstallCalls -le 2) { throw 'Package failed to download' } }
        & $script:Script -Name Pester
        Should -Invoke Install-Module -Times 3 -Exactly
        Should -Invoke Start-Sleep -Times 1 -Exactly -ParameterFilter { $Seconds -eq 15 }
        Should -Invoke Start-Sleep -Times 1 -Exactly -ParameterFilter { $Seconds -eq 30 }
    }

    It 'throws after the last try, naming the module, the number of tries and the cause' {
        Mock Install-Module { throw 'No match was found for the specified search criteria' }
        { & $script:Script -Name PSScriptAnalyzer -MaxAttempts 3 } |
            Should -Throw -ExpectedMessage '*Install-Module PSScriptAnalyzer failed after 3 attempt(s): No match was found for the specified search criteria*'
        Should -Invoke Install-Module -Times 3 -Exactly
    }

    It 'passes the version bounds to Install-Module' {
        Mock Install-Module { }
        & $script:Script -Name Pester -MinimumVersion 5.5 -MaximumVersion 5.99
        Should -Invoke Install-Module -Times 1 -Exactly -ParameterFilter { $Name -eq 'Pester' -and $MinimumVersion -eq '5.5' -and $MaximumVersion -eq '5.99' }
    }
}

Describe 'Workflows install Gallery modules through the retry script (#440)' {

    It 'finds the workflow files to read' {
        @(git -C $script:RepoRoot ls-files '.github/workflows/*.yml').Count | Should -BeGreaterThan 0
    }

    It 'has no workflow line that calls Install-Module itself' {
        $bare = foreach ($file in @(git -C $script:RepoRoot ls-files '.github/workflows/*.yml')) {
            $lines = Get-Content -LiteralPath (Join-Path $script:RepoRoot $file)
            for ($i = 0; $i -lt $lines.Count; $i++) {
                $isComment = $lines[$i].TrimStart().StartsWith('#')
                if (-not $isComment -and $lines[$i] -match '\bInstall-Module\s+\S' -and $lines[$i] -notmatch 'Install-GalleryModule') { "${file}:$($i + 1)" }
            }
        }
        $bare | Should -BeNullOrEmpty
    }

    It 'installs PSScriptAnalyzer and Pester through the script in lint.yml' {
        $text = Get-Content -Raw -LiteralPath (Join-Path $script:RepoRoot '.github/workflows/lint.yml')
        $text | Should -Match 'Install-GalleryModule\.ps1 -Name PSScriptAnalyzer'
        $text | Should -Match 'Install-GalleryModule\.ps1 -Name Pester -MinimumVersion 5\.5 -MaximumVersion 5\.99'
    }
}

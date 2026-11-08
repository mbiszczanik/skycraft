<#
.SYNOPSIS
    Pester 5 tests: the target text of a -WhatIf line carries no subscription id (#393).

.DESCRIPTION
    ShouldProcess prints "What if: Performing the operation ... on target ..." straight to the host,
    so the Write-Host redaction never sees it. A target that holds a scope or a resource id goes
    through Protect-LabText first. These cases run the real helper with -WhatIf and scan the lab
    scripts for a ShouldProcess target that names a scope without the helper.

.EXAMPLE
    Invoke-Pester -Path .\tests\LabCommon-ShouldProcess.Tests.ps1

.NOTES
    Project: SkyCraft
    Issue: #393
#>

#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    Import-Module (Join-Path $script:RepoRoot 'tools' 'LabCommon.psm1') -Force -Verbose:$false
    Import-Module (Join-Path $PSScriptRoot 'Support' 'RepoFiles.psm1') -Force -Verbose:$false
    $script:SubId = '11111111-2222-3333-4444-555555555555'
}

Describe 'ShouldProcess targets of LabCommon helpers (#393)' {

    It 'prints a -WhatIf role assignment removal without the subscription id' {
        $id = "/subscriptions/$($script:SubId)/providers/Microsoft.Authorization/roleAssignments/aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
        # The -WhatIf line goes to the host, not to a stream: capture it from a child process.
        $module = Join-Path $script:RepoRoot 'tools' 'LabCommon.psm1'
        $shown = (& pwsh -NoProfile -Command "Import-Module '$module' -Force -Verbose:`$false; Remove-LabArmRoleAssignment -Id '$id' -WhatIf" 2>&1 | Out-String)
        $shown | Should -Match 'What if'
        $shown | Should -Not -Match $script:SubId
        $shown | Should -Match '/subscriptions/<id>/'
    }
}

Describe 'ShouldProcess targets in lab scripts (#393)' {

    It 'wraps a target that names a scope or a full resource id in Protect-LabText' {
        $risky = '\$subscriptionScope|\$scopePath|\$\(\$budget\.Scope\)|\$roleLabel|^\s*\$id\s*$|^\s*\$Id\s*$'
        $files = @(Get-RepoFile -Root $script:RepoRoot -Filter '*.ps1' | Where-Object { $_.FullName -match '[\\/]module-[^\\/]+[\\/][^\\/]+[\\/]scripts[\\/]' }) +
            @(Get-Item (Join-Path $script:RepoRoot 'tools' 'LabCommon.psm1'))
        $offenders = foreach ($file in $files) {
            $lineNo = 0
            foreach ($line in (Get-Content -LiteralPath $file.FullName)) {
                $lineNo++
                if ($line -match 'ShouldProcess\((?<target>[^,]+),') {
                    $target = $Matches.target
                    if ($target -match $risky -and $target -notmatch 'Protect-LabText') { "$($file.Name):$lineNo $($line.Trim())" }
                }
            }
        }
        @($offenders) | Should -BeNullOrEmpty -Because "a target with a scope prints the subscription id in a -WhatIf run:`n$(@($offenders) -join "`n")"
    }
}

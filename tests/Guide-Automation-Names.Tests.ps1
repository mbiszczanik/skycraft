#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }
<#
.SYNOPSIS
    Pester 5 test: every resource name a lab's Test-Lab.ps1 asserts is named in that lab's
    guide or checklist.

.DESCRIPTION
    Issue #79 found labs whose validation script asserts resources the student-facing text never
    mentions - Lab 5.3's flow log and connection monitor were 16 of its 19 assertions and appeared
    only in a Bicep snippet; Lab 3.3's guide kept portal-era names the template had already
    replaced. A learner who follows the guide and then runs Test-Lab.ps1 sees failures for things
    the guide never told them to create.

    This test reads each lab's scripts/Test-Lab.ps1 and collects the literal resource names it
    binds to a *Name variable, e.g.

        $flowLogName = 'prod-skycraft-swc-vnet-flowlog'
        $caeName     = "dev-skycraft-swc-cae-02"

    and every literal passed to a -Name parameter, e.g.

        Get-AzDiagnosticSetting -ResourceId $id -Name 'skycraft-storage-diag'

    Names composed at run time ("$Environment-skycraft-swc-rg") carry a '$' and are skipped: the
    guide cannot be expected to spell a name the script itself does not. Each collected literal
    must appear verbatim in the prose of lab-guide-X.Y.md or lab-checklist-X.Y.md. Fenced code
    blocks are stripped first: a name that only occurs in a "Preview - the AVM module call" Bicep
    snippet or a CLI validation command is not an instruction to create anything.

.EXAMPLE
    Invoke-Pester -Path .\tests\Guide-Automation-Names.Tests.ps1

.NOTES
    Project: SkyCraft
#>

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path

# A literal is a single- or double-quoted string with no '$' (no interpolation) and no quote.
$LiteralPattern = '(?:''(?<lit>[^''$]+)''|"(?<lit>[^"$]+)")'
$AssignmentRegex = [regex]"^\s*\`$\w*Name\w*\s*=\s*$LiteralPattern\s*$"
$NameArgRegex    = [regex]"-Name\s+$LiteralPattern"

function Get-AssertedName {
    param([string]$ScriptPath)
    $names = [System.Collections.Generic.HashSet[string]]::new()
    foreach ($line in Get-Content -LiteralPath $ScriptPath) {
        $code = $line -replace '#.*$', ''      # strip trailing comments
        $m = $AssignmentRegex.Match($code)
        if ($m.Success) { [void]$names.Add($m.Groups['lit'].Value) }
        foreach ($m in $NameArgRegex.Matches($code)) { [void]$names.Add($m.Groups['lit'].Value) }
    }
    return $names
}

# Computed at discovery, as the other tests in this directory do, so the It block needs nothing
# from the file scope.
$LabCases = Get-ChildItem -Path $RepoRoot -Directory -Filter 'module-*' |
    Get-ChildItem -Directory |
    Where-Object { $_.Name -match '^\d+\.\d+-' -and (Test-Path (Join-Path $_.FullName 'scripts\Test-Lab.ps1')) } |
    ForEach-Object {
        $num  = [regex]::Match($_.Name, '^\d+\.\d+').Value
        $root = $_.FullName
        $docs = @((Join-Path $root "lab-guide-$num.md"), (Join-Path $root "lab-checklist-$num.md")) |
                Where-Object { Test-Path -LiteralPath $_ }
        $docText  = ($docs | ForEach-Object { Get-Content -Raw -LiteralPath $_ }) -join "`n"
        $docText  = [regex]::Replace($docText, '(?ms)^[ \t]*(`{3,}|~{3,}).*?^[ \t]*\1[ \t]*\r?$', '')   # CRLF-safe
        $asserted = Get-AssertedName -ScriptPath (Join-Path $root 'scripts\Test-Lab.ps1')
        @{
            lab     = $_.Name
            missing = @($asserted | Where-Object { -not $docText.Contains($_) } | Sort-Object)
        }
    }

Describe 'Test-Lab.ps1 resource names are documented' {
    It "'<lab>' guide or checklist names every resource its Test-Lab.ps1 asserts" -ForEach $LabCases {
        $missing | Should -BeNullOrEmpty -Because "a learner following '$lab' cannot create what the guide never names: $($missing -join ', ')"
    }
}

<#
.SYNOPSIS
    Pester 5 test: no lab script pipes an Az cmdlet that runs with -ErrorAction SilentlyContinue
    into Select-Object -First.

.DESCRIPTION
    An Az cmdlet that catches the exception Select-Object -First uses to stop its input, and
    reports it with WriteError, ends in PipelineStoppedException when it runs with
    -ErrorAction SilentlyContinue (or Continue). No try/catch sees that exception: the script just
    stops, with exit code 0. Lab 5.2's Deploy-Bicep.ps1 did it on a rerun while a backup job was in
    progress: Get-AzRecoveryServicesBackupJob -ErrorAction SilentlyContinue | Where-Object |
    Select-Object -First 1 ended the script after the first VM, skipped the second VM, Site
    Recovery and the closing lines, and exited 0 (issue #366).

    The fix is to collect first and then take the element: @(Get-AzX ...)[0], or
    @(Get-AzX ...) | Select-Object -First 1. A Sort-Object (or any other command that reads all of
    its input) between the cmdlet and Select-Object -First has the same effect, since the cmdlet is
    then never asked to stop. -ErrorAction Stop on the cmdlet is not affected.

    The test parses every tracked PowerShell script under module-*/*/scripts/ and tools/ and fails
    on a pipeline that starts with an Az cmdlet carrying -ErrorAction SilentlyContinue, Continue or
    Ignore (or -EA) and reaches Select-Object -First or -Index with nothing in between that reads
    all of its input. $Owed lists the findings that belong to another branch, as an upper bound per
    file: a file may hold fewer, never more. Fixtures prove the rule catches what it is meant to
    catch, and the first test fails when the scan finds no script, so a broken scan cannot pass.

    One test runs a stand-in cmdlet with the same behaviour in a child pwsh process, so the claim
    above is checked on this machine's PowerShell instead of being taken on trust.

.EXAMPLE
    Invoke-Pester -Path .\tests\Select-First-Pipeline.Tests.ps1

.NOTES
    Project: SkyCraft
    Issue: #366
#>

#Requires -Version 7.0
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeDiscovery {
    $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path

    # Owed by other branches: Lab 5.1's scripts (the Lab 5.1 fix branch). An upper bound per file.
    $script:Owed = @{
        'module-5-monitoring-maintenance/5.1-azure-monitor/scripts/Deploy-Bicep.ps1' = 1
        'module-5-monitoring-maintenance/5.1-azure-monitor/scripts/Test-Lab.ps1'     = 2
    }

    $tracked = @(git -C $repoRoot ls-files -- 'module-*' 'tools')
    $script:Scripts = foreach ($relative in $tracked) {
        if ($relative -notmatch '^(module-[^/]+/[^/]+/scripts/[^/]+|tools/.+)\.(ps1|psm1)$') { continue }
        @{ file = $relative; path = (Join-Path $repoRoot $relative); owed = [int]$script:Owed[$relative] }
    }
}

BeforeAll {
    # Commands that read all of their input before they pass anything on.
    $script:Blocking = 'Sort-Object', 'Group-Object', 'Measure-Object', 'Out-String', 'ConvertTo-Json', 'ConvertTo-Csv'

    # The findings in PowerShell text, as 'line: text' strings.
    function Get-SelectFirstFinding {
        param([string]$Text)

        $ast = [System.Management.Automation.Language.Parser]::ParseInput($Text, [ref]$null, [ref]$null)
        $pipelines = $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.PipelineAst] -and $n.PipelineElements.Count -gt 1 }, $true)
        foreach ($pipeline in $pipelines) {
            $elements = @($pipeline.PipelineElements)
            $first = $elements[0]
            if ($first -isnot [System.Management.Automation.Language.CommandAst]) { continue }
            if ("$($first.GetCommandName())" -notmatch '^[A-Za-z]+-Az') { continue }
            # -ErrorAction / -EA with a value other than Stop (an unset one means the preference,
            # which the lab scripts set to Stop, so only an explicit weaker value counts).
            $weak = $false
            $words = @($first.CommandElements)
            for ($i = 0; $i -lt $words.Count - 1; $i++) {
                if ($words[$i] -isnot [System.Management.Automation.Language.CommandParameterAst]) { continue }
                $name = $words[$i].ParameterName
                if ($name -ieq 'EA' -or ($name.Length -ge 6 -and 'ErrorAction'.StartsWith($name, [System.StringComparison]::OrdinalIgnoreCase))) {
                    if ("$($words[$i + 1].Extent.Text)" -match '^[''"]?(SilentlyContinue|Continue|Ignore)[''"]?$') { $weak = $true }
                }
            }
            if (-not $weak) { continue }
            for ($j = 1; $j -lt $elements.Count; $j++) {
                $command = $elements[$j]
                if ($command -isnot [System.Management.Automation.Language.CommandAst]) { continue }
                $commandName = "$($command.GetCommandName())"
                if ($commandName -in $script:Blocking) { break }
                if ($commandName -in 'Select-Object', 'select' -and $command.Extent.Text -match '(?i)-(First|Index)\b') {
                    "$($pipeline.Extent.StartLineNumber): $($first.GetCommandName()) ... $($command.Extent.Text)"
                    break
                }
            }
        }
    }
}

Describe 'Select-Object -First after an Az cmdlet with -ErrorAction SilentlyContinue (#366)' {

    It 'scans the lab scripts and tools' -ForEach @(@{ count = @($script:Scripts).Count }) {
        $count | Should -BeGreaterThan 20 -Because 'a scan that finds no script cannot fail'
    }

    It "'<file>' has no more of them than it owes (<owed>)" -ForEach $script:Scripts {
        $found = @(Get-SelectFirstFinding -Text (Get-Content -Raw -LiteralPath $path))
        $found.Count | Should -BeLessOrEqual $owed -Because "collect first: @(Get-AzX ... -ErrorAction SilentlyContinue)[0]. Found:`n$($found -join "`n")"
    }
}

BeforeDiscovery {
    $script:MultiLine = @'
$job = Get-AzFoo `
    -Name x `
    -ErrorAction SilentlyContinue |
    Where-Object { $_ } |
    Select-Object -First 1
'@
}

Describe 'Select-Object -First rule: fixtures' {

    It 'flags <name>' -ForEach @(
        @{ name = 'an Az cmdlet with SilentlyContinue';                text = 'Get-AzFoo -Name x -ErrorAction SilentlyContinue | Select-Object -First 1' }
        @{ name = 'the -EA alias with Ignore, through Where-Object';   text = 'Get-AzFoo -EA Ignore | Where-Object { $_ } | select -First 1' }
        @{ name = 'a multi-line pipeline';                             text = $script:MultiLine }
        @{ name = 'a pipeline inside a subexpression';                 text = '$x = (Get-AzFoo -ErrorAction SilentlyContinue | Select-Object -First 2)' }
        @{ name = '-Index';                                            text = 'Get-AzFoo -ErrorAction Continue | Select-Object -Index 0' }
    ) {
        @(Get-SelectFirstFinding -Text $text).Count | Should -Be 1
    }

    It 'passes <name>' -ForEach @(
        @{ name = 'a collected result, indexed';          text = '$x = @(Get-AzFoo -ErrorAction SilentlyContinue)[0]' }
        @{ name = 'a collected result, piped';            text = '$x = @(Get-AzFoo -ErrorAction SilentlyContinue) | Select-Object -First 1' }
        @{ name = '-ErrorAction Stop';                    text = 'Get-AzFoo -ErrorAction Stop | Select-Object -First 1' }
        @{ name = 'no -ErrorAction';                      text = 'Get-AzFoo | Select-Object -First 1' }
        @{ name = 'a Sort-Object in between';             text = 'Get-AzFoo -ErrorAction SilentlyContinue | Sort-Object Name | Select-Object -First 1' }
        @{ name = 'a command that is not an Az cmdlet';   text = 'Get-Command foo -ErrorAction SilentlyContinue | Select-Object -First 1' }
        @{ name = 'a variable as the first element';      text = '$all | Where-Object { $_ } | Select-Object -First 1' }
    ) {
        @(Get-SelectFirstFinding -Text $text).Count | Should -Be 0
    }
}

Describe 'Select-Object -First after a cmdlet that reports the stop as an error: the behaviour itself' {

    BeforeAll {
        # A stand-in for the Az cmdlets in question: it catches what WriteObject throws once the
        # downstream Select-Object -First has stopped it, and reports that with WriteError.
        $script:Prelude = @'
Add-Type -TypeDefinition @"
using System;
using System.Management.Automation;
[Cmdlet("Get", "FakeJob")]
public class GetFakeJob : PSCmdlet {
    protected override void ProcessRecord() {
        try { for (int i = 0; i < 3; i++) WriteObject(i); }
        catch (Exception e) { WriteError(new ErrorRecord(e, "x", ErrorCategory.NotSpecified, null)); }
    }
}
"@ -PassThru | ForEach-Object { Import-Module -Assembly $_.Assembly }
$ErrorActionPreference = 'Stop'
'@

        function script:Invoke-Child {
            param([string]$Body)
            $path = Join-Path $TestDrive "child-$([guid]::NewGuid().ToString('N')).ps1"
            Set-Content -LiteralPath $path -Value ($script:Prelude + "`n" + $Body)
            $output = & (Get-Process -Id $PID).Path -NoProfile -NonInteractive -File $path 2>&1
            [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = (($output | ForEach-Object { "$_" }) -join "`n") }
        }
    }

    It 'ends the script silently with exit 0 when the cmdlet runs with -ErrorAction SilentlyContinue' {
        $run = script:Invoke-Child -Body @'
try {
    $x = Get-FakeJob -ErrorAction SilentlyContinue | Select-Object -First 1
    'after the pipeline'
} catch { 'caught' }
'script went on'
'@
        $run.ExitCode | Should -Be 0
        $run.Output | Should -Not -Match 'after the pipeline|caught|script went on' -Because 'the script ends inside the pipeline, with no error for a catch'
    }

    It 'goes on when the result is collected first' {
        $run = script:Invoke-Child -Body @'
$x = @(Get-FakeJob -ErrorAction SilentlyContinue)[0]
$y = @(Get-FakeJob -ErrorAction SilentlyContinue | Where-Object { $true }) | Select-Object -First 1
"x=$x y=$y"
'@
        $run.ExitCode | Should -Be 0
        $run.Output | Should -Match 'x=0 y=0'
    }

    It 'goes on with -ErrorAction Stop on the cmdlet' {
        $run = script:Invoke-Child -Body @'
$x = Get-FakeJob -ErrorAction Stop | Select-Object -First 1
"x=$x"
'@
        $run.Output | Should -Match 'x=0'
    }
}

<#
.SYNOPSIS
    Pester 5 tests for tools/Get-LabCycleVerdict.ps1.

.DESCRIPTION
    Runs the script as a child process against fixture JSON lines written to a temporary folder,
    so the exit code asserted is the process's own. No Azure call, no credential, no network.

.EXAMPLE
    Invoke-Pester -Path .\tests\LabCycle-Verdict.Tests.ps1 -CI

.NOTES
    Project: SkyCraft
    Issue: #527
#>

#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    $script:ScriptPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'tools/Get-LabCycleVerdict.ps1'
    $script:Pwsh = (Get-Process -Id $PID).Path
    $script:Dir = Join-Path ([System.IO.Path]::GetTempPath()) ("verdict-" + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $script:Dir | Out-Null

    function script:New-ResultsFile {
        param([string]$Name, [string[]]$Lines)
        $path = Join-Path $script:Dir $Name
        Set-Content -LiteralPath $path -Value $Lines
        $path
    }

    function script:Rec {
        param([string]$Id, [string]$Status)
        (@{ RunId = 'r'; Id = $Id; Lab = "module/$Id"; Status = $Status; ExitCode = 0; Cause = 'SECRET TRANSCRIPT TEXT' } | ConvertTo-Json -Compress)
    }

    # Returns the process exit code, stdout lines and stderr text.
    function script:Invoke-Verdict {
        param([string[]]$Arguments)
        $out = Join-Path $script:Dir ([guid]::NewGuid().ToString('N') + '.out')
        $err = Join-Path $script:Dir ([guid]::NewGuid().ToString('N') + '.err')
        $proc = Start-Process -FilePath $script:Pwsh -ArgumentList ((@('-NoProfile', '-File', $script:ScriptPath) + $Arguments) | ForEach-Object { '"' + $_ + '"' }) `
            -NoNewWindow -Wait -PassThru -RedirectStandardOutput $out -RedirectStandardError $err
        $stdout = @(Get-Content -LiteralPath $out | Where-Object { $_.Trim() })
        [pscustomobject]@{
            ExitCode = $proc.ExitCode
            Lines    = $stdout
            Json     = if ($stdout.Count -eq 1) { try { $stdout[0] | ConvertFrom-Json } catch { $null } } else { $null }
            Stderr   = (Get-Content -LiteralPath $err -Raw)
        }
    }
}

AfterAll {
    if ($script:Dir -and (Test-Path -LiteralPath $script:Dir)) { Remove-Item -LiteralPath $script:Dir -Recurse -Force }
}

Describe 'Get-LabCycleVerdict' {
    Context 'passed' {
        It 'reports passed and exits 0 when every expected lab succeeded and the exit code is 0' {
            $f = New-ResultsFile 'pass.jsonl' @((Rec '1.2' 'Succeeded'), (Rec '2.1' 'Succeeded'))
            $r = Invoke-Verdict @('-ResultsPath', $f, '-ExpectedLab', '1.2,2.1', '-CycleExitCode', '0', '-RunId', 'run-42')
            $r.ExitCode | Should -Be 0
            $r.Lines.Count | Should -Be 1
            $r.Json.verdict | Should -Be 'passed'
            $r.Json.ran | Should -Be @('1.2', '2.1')
            @($r.Json.failed).Count | Should -Be 0
            foreach ($key in 'verdict', 'ran', 'failed', 'reason', 'issueTitle', 'issueBody') {
                $r.Json.PSObject.Properties.Name | Should -Contain $key
            }
        }
    }

    Context 'failed' {
        It 'reports failed, exits 1 and names the lab for a Failed record' {
            $f = New-ResultsFile 'fail.jsonl' @((Rec '1.2' 'Succeeded'), (Rec '2.1' 'Failed(Test)'))
            $r = Invoke-Verdict @('-ResultsPath', $f, '-ExpectedLab', '1.2,2.1', '-CycleExitCode', '1', '-RunId', 'r1')
            $r.ExitCode | Should -Be 1
            $r.Json.verdict | Should -Be 'failed'
            @($r.Json.failed) | Should -Be @('2.1')
            $r.Json.reason | Should -Match '2\.1'
        }

        It 'reports failed on a non-zero exit code even when every record succeeded' {
            $f = New-ResultsFile 'exit.jsonl' @((Rec '1.2' 'Succeeded'))
            $r = Invoke-Verdict @('-ResultsPath', $f, '-ExpectedLab', '1.2', '-CycleExitCode', '4', '-RunId', 'r1')
            $r.ExitCode | Should -Be 1
            $r.Json.verdict | Should -Be 'failed'
            $r.Json.reason | Should -Match '4'
        }

        It 'reports failed and names an expected lab that has no record while others ran' {
            $f = New-ResultsFile 'missing.jsonl' @((Rec '1.2' 'Succeeded'))
            $r = Invoke-Verdict @('-ResultsPath', $f, '-ExpectedLab', '1.2,2.1', '-CycleExitCode', '0', '-RunId', 'r1')
            $r.ExitCode | Should -Be 1
            $r.Json.verdict | Should -Be 'failed'
            @($r.Json.failed) | Should -Be @('2.1')
        }

        It 'does not count a Skipped record as a failure of its own' {
            $f = New-ResultsFile 'skip.jsonl' @((Rec '1.2' 'Failed'), (Rec '1.3' 'Skipped'))
            $r = Invoke-Verdict @('-ResultsPath', $f, '-ExpectedLab', '1.2', '-CycleExitCode', '1', '-RunId', 'r1')
            $r.Json.verdict | Should -Be 'failed'
            @($r.Json.failed) | Should -Be @('1.2')
        }
    }

    Context 'not-executed' {
        It 'reports not-executed and exits 3 when the results file is missing' {
            $r = Invoke-Verdict @('-ResultsPath', (Join-Path $script:Dir 'absent.jsonl'), '-ExpectedLab', '1.2', '-CycleExitCode', '0', '-RunId', 'r1')
            $r.ExitCode | Should -Be 3
            $r.Json.verdict | Should -Be 'not-executed'
            $r.Json.reason | Should -Not -BeNullOrEmpty
        }

        It 'reports not-executed when the results file is empty' {
            $f = Join-Path $script:Dir 'empty.jsonl'
            New-Item -ItemType File -Path $f | Out-Null
            $r = Invoke-Verdict @('-ResultsPath', $f, '-ExpectedLab', '1.2', '-CycleExitCode', '0', '-RunId', 'r1')
            $r.ExitCode | Should -Be 3
            $r.Json.verdict | Should -Be 'not-executed'
        }

        It 'reports not-executed when no record is Succeeded or Failed' {
            $f = New-ResultsFile 'noexec.jsonl' @((Rec '1.2' 'Skipped'), (Rec '2.1' 'DryRun'))
            $r = Invoke-Verdict @('-ResultsPath', $f, '-ExpectedLab', '1.2,2.1', '-CycleExitCode', '0', '-RunId', 'r1')
            $r.ExitCode | Should -Be 3
            $r.Json.verdict | Should -Be 'not-executed'
        }

        It 'reports not-executed with -AuthFailed even when the file holds a success' {
            $f = New-ResultsFile 'auth.jsonl' @((Rec '1.2' 'Succeeded'))
            $r = Invoke-Verdict @('-ResultsPath', $f, '-ExpectedLab', '1.2', '-CycleExitCode', '0', '-RunId', 'r1', '-AuthFailed')
            $r.ExitCode | Should -Be 3
            $r.Json.verdict | Should -Be 'not-executed'
            $r.Json.reason | Should -Match 'authenticate'
        }
    }

    Context 'records that did not run in this cycle' {
        It 'does not count DryRun as run, so the lab is missing and the verdict is failed' {
            $f = New-ResultsFile 'dry.jsonl' @((Rec '1.2' 'Succeeded'), (Rec '2.1' 'DryRun'))
            $r = Invoke-Verdict @('-ResultsPath', $f, '-ExpectedLab', '1.2,2.1', '-CycleExitCode', '0', '-RunId', 'r1')
            $r.Json.verdict | Should -Be 'failed'
            @($r.Json.ran) | Should -Be @('1.2')
            @($r.Json.failed) | Should -Be @('2.1')
        }

        It 'does not count Succeeded(Resumed) as run' {
            $f = New-ResultsFile 'resumed.jsonl' @((Rec '1.2' 'Succeeded'), (Rec '2.1' 'Succeeded(Resumed)'))
            $r = Invoke-Verdict @('-ResultsPath', $f, '-ExpectedLab', '1.2,2.1', '-CycleExitCode', '0', '-RunId', 'r1')
            $r.Json.verdict | Should -Be 'failed'
            @($r.Json.ran) | Should -Be @('1.2')
        }

        It 'reports not-executed, never passed, when every record is Succeeded(Resumed)' {
            $f = New-ResultsFile 'allresumed.jsonl' @((Rec '1.2' 'Succeeded(Resumed)'))
            $r = Invoke-Verdict @('-ResultsPath', $f, '-ExpectedLab', '1.2', '-CycleExitCode', '0', '-RunId', 'r1')
            $r.ExitCode | Should -Be 3
            $r.Json.verdict | Should -Be 'not-executed'
        }
    }

    Context 'issue text' {
        It 'uses one constant issueTitle for every verdict' {
            $ok = New-ResultsFile 'title-ok.jsonl' @((Rec '1.2' 'Succeeded'))
            $bad = New-ResultsFile 'title-bad.jsonl' @((Rec '1.2' 'Failed'))
            $titles = @(
                (Invoke-Verdict @('-ResultsPath', $ok, '-ExpectedLab', '1.2', '-CycleExitCode', '0', '-RunId', 'a')).Json.issueTitle
                (Invoke-Verdict @('-ResultsPath', $bad, '-ExpectedLab', '1.2', '-CycleExitCode', '1', '-RunId', 'b')).Json.issueTitle
                (Invoke-Verdict @('-ResultsPath', $ok, '-ExpectedLab', '1.2', '-CycleExitCode', '0', '-RunId', 'c', '-AuthFailed')).Json.issueTitle
            )
            ($titles | Select-Object -Unique).Count | Should -Be 1
            $titles[0] | Should -Not -BeNullOrEmpty
        }

        It 'puts the run id, exit code and lab ids in issueBody and no transcript text' {
            $f = New-ResultsFile 'body.jsonl' @((Rec '1.2' 'Succeeded'), (Rec '2.1' 'Failed(Test)'))
            $r = Invoke-Verdict @('-ResultsPath', $f, '-ExpectedLab', '1.2,2.1', '-CycleExitCode', '1', '-RunId', 'run-777')
            $r.Json.issueBody | Should -Match 'run-777'
            $r.Json.issueBody | Should -Match 'Exit code: 1'
            $r.Json.issueBody | Should -Match '2\.1'
            $r.Json.issueBody | Should -Not -Match 'TRANSCRIPT'
            $r.Json.reason | Should -Not -Match 'TRANSCRIPT'
        }
    }

    Context 'bad input' {
        It 'exits 2 and names the parameter when a mandatory parameter is missing' -ForEach @(
            @{ Missing = '-ResultsPath'; Params = @('-ExpectedLab', '1.2', '-CycleExitCode', '0', '-RunId', 'r') }
            @{ Missing = '-ExpectedLab'; Params = @('-ResultsPath', 'x.jsonl', '-CycleExitCode', '0', '-RunId', 'r') }
            @{ Missing = '-CycleExitCode'; Params = @('-ResultsPath', 'x.jsonl', '-ExpectedLab', '1.2', '-RunId', 'r') }
            @{ Missing = '-RunId'; Params = @('-ResultsPath', 'x.jsonl', '-ExpectedLab', '1.2', '-CycleExitCode', '0') }
        ) {
            $r = Invoke-Verdict $Params
            $r.ExitCode | Should -Be 2
            $r.Stderr | Should -Match ([regex]::Escape($Missing))
            $r.Lines.Count | Should -Be 0
        }

        It 'exits 2 and names the line when the results file is not valid JSON lines' {
            $f = New-ResultsFile 'badjson.jsonl' @((Rec '1.2' 'Succeeded'), 'this is not json')
            $r = Invoke-Verdict @('-ResultsPath', $f, '-ExpectedLab', '1.2', '-CycleExitCode', '0', '-RunId', 'r1')
            $r.ExitCode | Should -Be 2
            $r.Stderr | Should -Match 'line 2'
            $r.Stderr | Should -Match 'not valid JSON'
        }
    }

    Context 'offline guarantee' {
        It 'calls no Azure command' {
            $text = Get-Content -LiteralPath $script:ScriptPath -Raw
            $text | Should -Not -Match '\b(Connect-AzAccount|Invoke-AzRestMethod|Get-Az\w+|New-Az\w+|az\s+(login|account|rest))\b'
        }
    }
}

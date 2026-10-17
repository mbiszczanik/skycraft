<#
.SYNOPSIS
    Pester 5 test: every `az policy assignment create` in the repository passes --policy the full
    definition path.

.DESCRIPTION
    With a bare built-in definition id (`--policy ea3f2387-...`) the current Azure CLI fails with
    PolicyDefinitionNotFound and a Python traceback, although `az policy definition show` finds
    the same definition (issue #350, seen live on 2026-10-16). The guides, the scripts and the
    architecture diagrams therefore pass the full path,
    /providers/Microsoft.Authorization/policyDefinitions/<id> (or a definition path under a
    subscription or management group).

    The test reads every tracked Markdown, PowerShell, shell and Python file, and the text
    elements of every Excalidraw diagram (the SVG exports are rendered from them). Each
    `az policy assignment create` command is read to its end - continuation lines ending in a
    backslash or a backtick included - and its --policy value must start with `/`. A command
    that uses --policy-set-definition instead is not checked here. The test fails when it finds
    no command at all, so a broken file scan cannot pass as a green check.

.EXAMPLE
    Invoke-Pester -Path .\tests\Az-Policy-Assignment-Cli.Tests.ps1

.NOTES
    Project: SkyCraft
#>

#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeDiscovery {
    $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    $textExtensions = @('.md', '.ps1', '.psm1', '.psd1', '.sh', '.py')

    # Tracked files only: a worktree under .claude/ or a scratch file is not the repository.
    $tracked = @(git -C $repoRoot ls-files)

    # The text a file holds, as lines. An Excalidraw diagram is JSON; its commands live in the
    # text elements, whose line breaks are escaped in the file.
    function Get-ScannedLine {
        param([string]$Path)
        if ([System.IO.Path]::GetExtension($Path) -ieq '.excalidraw') {
            $drawing = Get-Content -Raw -Encoding utf8 -LiteralPath $Path | ConvertFrom-Json
            foreach ($element in @($drawing.elements)) {
                if ($element.type -eq 'text' -and $element.text) { $element.text -split "`r?`n" }
            }
            return
        }
        Get-Content -Encoding utf8 -LiteralPath $Path
    }

    $script:Commands = foreach ($relative in $tracked) {
        $extension = [System.IO.Path]::GetExtension($relative)
        if ($extension -notin $textExtensions -and $extension -ine '.excalidraw') { continue }
        # This test names the command in its own text.
        if ($relative -eq 'tests/Az-Policy-Assignment-Cli.Tests.ps1') { continue }
        $path = Join-Path $repoRoot $relative
        if (-not (Test-Path -LiteralPath $path)) { continue }

        $lines = @(Get-ScannedLine -Path $path)
        for ($i = 0; $i -lt $lines.Count; $i++) {
            if ($lines[$i] -notmatch '\baz\s+policy\s+assignment\s+create\b') { continue }
            $command = $lines[$i]
            $j = $i
            while ($lines[$j] -match '[\\`]\s*$' -and $j + 1 -lt $lines.Count) {
                $j++
                $command += "`n" + $lines[$j]
            }
            @{ file = $relative; line = $i + 1; command = $command }
        }
    }
}

Describe 'az policy assignment create - the definition is passed by its full path (#350)' {
    It 'finds at least one az policy assignment create to check' -TestCases @(@{ count = @($script:Commands).Count }) {
        $count | Should -BeGreaterThan 0 -Because 'the guides and diagrams use the command; finding none means the scan is broken'
    }

    It '<file>:<line> passes --policy a full definition path' -ForEach $script:Commands {
        $match = [regex]::Match($command, '--policy(?:\s+|=)["'']?(?<value>[^\s"''\\`]+)')
        if (-not $match.Success) {
            # --policy-set-definition, or the definition is given another way: not this rule.
            $command | Should -Not -Match '--policy(?:\s|=)' -Because 'a --policy value must be readable'
            return
        }
        $match.Groups['value'].Value | Should -Match '^/(providers|subscriptions)/.+/policyDefinitions/[^/]+$' -Because "a bare definition id fails with PolicyDefinitionNotFound in the current Azure CLI ($file, line $line)"
    }
}

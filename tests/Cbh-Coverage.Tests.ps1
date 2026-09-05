<#
.SYNOPSIS
    Pester 5 test: every PowerShell script in the repo ships Comment-Based Help.

.DESCRIPTION
    docs/powershell-standards.md §1 requires every *.ps1 under module-*/**/scripts/, the repo-root
    scripts/ and tools/ to carry a Comment-Based Help block with .SYNOPSIS, .DESCRIPTION, and
    .NOTES. This test finds every such script and asserts those three tags are present inside the
    help block itself.

    THE WINDOW IS THE BLOCK, NOT A LINE COUNT (#124). This test used to read the first 60 lines,
    which is a proxy for 'inside the help block' and only holds while every block is short. Both
    lab cycle orchestrators carry a long .DESCRIPTION and a dozen-plus .PARAMETER entries, so
    their .NOTES sits past line 165 - correctly - and the proxy reported two false positives
    against files that comply. Reading the block itself drops the arbitrary limit and is stricter
    at the other end: a .NOTES written in a comment below the header no longer counts.

.EXAMPLE
    Invoke-Pester -Path .\tests\Cbh-Coverage.Tests.ps1

.NOTES
    Project: SkyCraft
#>

#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

# ---------------------------------------------------------------------------------------------
# Discovery-time state. Pester 5 runs this file once to discover tests and again to run them, and
# a -ForEach case list has to be built during discovery. A function defined here is not in scope
# when the It bodies run, so everything a case asserts on is computed now, not in the assertion.
# ---------------------------------------------------------------------------------------------

$RepoRoot   = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
# Repo-root scripts/ is included alongside the per-lab ones (issue #116).
$PsScripts  = Get-ChildItem -Path $RepoRoot -Recurse -File -Filter '*.ps1' |
              Where-Object { (($_.FullName.Substring($RepoRoot.Length + 1)) -replace '\\', '/') -match '^(module-\d.*/)?(scripts|tools)/' }

# The leading Comment-Based Help block, or '' when the script has none. Read from the token stream
# rather than matched with a regex, so that a '#>' inside a string cannot end the block early and
# so that the '#Requires' lines - comments to the tokenizer - are skipped rather than mistaken for
# the header.
function Get-HelpBlock {
    param([string]$Text)

    $tokens = $null
    $null = [System.Management.Automation.Language.Parser]::ParseInput($Text, [ref]$tokens, [ref]$null)

    foreach ($token in $tokens) {
        if ($token.Kind -eq 'NewLine') { continue }
        if ($token.Kind -eq 'Comment') {
            if ($token.Text.StartsWith('<#')) { return $token.Text }
            continue
        }
        # Code before any block comment: the script has no help header to read.
        break
    }

    return ''
}

$ScriptCases = $PsScripts | ForEach-Object {
    @{
        file = $_.FullName.Substring($RepoRoot.Length + 1)
        help = Get-HelpBlock -Text (Get-Content -Raw -LiteralPath $_.FullName)
    }
}

# Fixtures for the rule itself, held as text so they need no files on disk. The first is the shape
# that produced the false positives in #124: a block far longer than any line window.
$LongHelpBlock = @(
    '<#'
    '.SYNOPSIS'
    '    A help block long enough to push .NOTES well past the sixtieth line.'
    '.DESCRIPTION'
    (1..80 | ForEach-Object { "    line $_ of a long description" })
    '.NOTES'
    '    Project: SkyCraft'
    '#>'
    '#Requires -Version 7.0'
    'exit 0'
) -join "`n"

$HelpBlockWithoutNotes = @(
    '<#'
    '.SYNOPSIS'
    '    A block with no notes tag at all.'
    '.DESCRIPTION'
    '    Short, and still non-compliant.'
    '#>'
    '#Requires -Version 7.0'
    'exit 0'
) -join "`n"

$NotesBelowTheBlock = @(
    '<#'
    '.SYNOPSIS'
    '    A block with no notes tag at all.'
    '.DESCRIPTION'
    '    The tag below is a line comment in the body, not help.'
    '#>'
    '#Requires -Version 7.0'
    '# .NOTES this is not comment-based help'
    'exit 0'
) -join "`n"

$RequiresBeforeTheBlock = @(
    '#Requires -Version 7.0'
    '<#'
    '.SYNOPSIS'
    '    A script that declares its requirements above the help block.'
    '.DESCRIPTION'
    '    Get-HelpBlock has to skip the line comment and keep looking.'
    '.NOTES'
    '    Project: SkyCraft'
    '#>'
    'exit 0'
) -join "`n"

$HelpBlockCases = @(
    @{
        name     = 'finds a .NOTES that sits past the sixtieth line of a long help block'
        found    = [bool]((Get-HelpBlock -Text $LongHelpBlock) -match '\.NOTES')
        expected = $true
    }
    @{
        name     = 'still reports a help block that omits .NOTES'
        found    = [bool]((Get-HelpBlock -Text $HelpBlockWithoutNotes) -match '\.NOTES')
        expected = $false
    }
    @{
        name     = 'does not accept a .NOTES written below the help block'
        found    = [bool]((Get-HelpBlock -Text $NotesBelowTheBlock) -match '\.NOTES')
        expected = $false
    }
    @{
        name     = "reads the block when a '#Requires' line comes before it"
        found    = [bool]((Get-HelpBlock -Text $RequiresBeforeTheBlock) -match '\.SYNOPSIS')
        expected = $true
    }
)

Describe 'SkyCraft PowerShell - CBH coverage' {

    It 'has scripts in scope to check' -ForEach @(@{ count = @($ScriptCases).Count }) {
        # A filter that matches nothing produces a Describe that passes by asserting nothing.
        $count | Should -BeGreaterThan 0
    }

    It "'<file>' declares .SYNOPSIS in its comment-based help block" -ForEach $ScriptCases {
        $help | Should -Match '\.SYNOPSIS' -Because 'docs/powershell-standards.md §1 requires it'
    }

    It "'<file>' declares .DESCRIPTION in its comment-based help block" -ForEach $ScriptCases {
        $help | Should -Match '\.DESCRIPTION' -Because 'docs/powershell-standards.md §1 requires it'
    }

    It "'<file>' declares .NOTES in its comment-based help block" -ForEach $ScriptCases {
        $help | Should -Match '\.NOTES' -Because 'docs/powershell-standards.md §1 requires it'
    }
}

Describe 'SkyCraft PowerShell - the CBH rule reads the help block, not a line window' {

    # The rule was narrowed in #124; these hold it to reading the block, and to still failing the
    # scripts it is there to fail.
    It '<name>' -ForEach $HelpBlockCases {
        $found | Should -Be $expected
    }
}

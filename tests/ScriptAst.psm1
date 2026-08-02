<#
.SYNOPSIS
    Shared helper: parses a PowerShell script and walks its abstract syntax tree.

.DESCRIPTION
    The automation-contract and overlay-policy suites both lint scripts by reading their AST
    rather than by matching text. Both need the same two primitives, so they live here once.

    Get-ScriptAst throws on a parse error rather than returning a partial tree. That behaviour
    is the reason this is shared rather than copied: a second copy that quietly lost the throw
    would let a suite report PASS on a file it never parsed, which is the failure shape these
    suites exist to remove.

    Find-AstNode is the single walk. `exit` is an ExitStatementAst rather than a CommandAst, and
    parameters and assignments are different node types again, so a command-only helper would
    have forced each rule to hand-roll its own FindAll predicate.

    Rule-specific predicates are deliberately NOT here. They encode what a particular contract
    means and have one consumer each, so they stay beside the rule that uses them.

.EXAMPLE
    Import-Module ./tests/ScriptAst.psm1
    $ast = Get-ScriptAst -Path ./module-3-compute/3.3-containers/scripts/Deploy-Bicep.ps1
    Find-AstNode -Ast $ast -Type ([System.Management.Automation.Language.AssignmentStatementAst])

.NOTES
    Project: SkyCraft
#>

#Requires -Version 7.0

$ErrorActionPreference = 'Stop'

function Get-ScriptAst {
    <#
    .SYNOPSIS
        Parses a script file and returns its ScriptBlockAst.

    .DESCRIPTION
        Throws on a parse error rather than returning a partial tree, so a malformed script
        fails loudly instead of silently satisfying every rule that walks it.

    .PARAMETER Path
        Path to the .ps1 file to parse.

    .NOTES
        Project: SkyCraft
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    $tokens = $null
    $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$tokens, [ref]$errors)
    if ($errors.Count -gt 0) { throw "Parse error in '$Path': $($errors[0].Message)" }
    $ast
}

function Find-AstNode {
    <#
    .SYNOPSIS
        Returns every node of a given type, optionally narrowed by a predicate.

    .DESCRIPTION
        One walk, shared by every rule in every suite. The predicate is closed over its captured
        variables so it resolves them in the scope it was written in rather than wherever
        FindAll happens to invoke it.

    .PARAMETER Ast
        The AST to search. Any node works, not only a script root, so a rule can scope a search
        to one block.

    .PARAMETER Type
        The AST node type to match, e.g. [System.Management.Automation.Language.CommandAst].

    .PARAMETER Where
        Optional extra predicate, invoked with the candidate node.

    .NOTES
        Project: SkyCraft
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'Type', Justification = 'False positive: read inside the GetNewClosure predicate handed to FindAll.')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'Where', Justification = 'False positive: read inside the GetNewClosure predicate handed to FindAll.')]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Ast,

        [Parameter(Mandatory)]
        [type]$Type,

        [Parameter()]
        [scriptblock]$Where
    )

    $predicate = {
        param($node)
        $node -is $Type -and (-not $Where -or (& $Where $node))
    }.GetNewClosure()
    @($Ast.FindAll($predicate, $true))
}

Export-ModuleMember -Function Get-ScriptAst, Find-AstNode

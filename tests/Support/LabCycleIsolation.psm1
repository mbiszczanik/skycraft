<#
.SYNOPSIS
    Lists what tests/LabCycle.Tests.ps1 has to poison so that it can never reach Azure.

.DESCRIPTION
    tests/LabCycle.Tests.ps1 runs tools/Invoke-LabCycle.ps1 and tools/Remove-LabCycle.ps1
    in-process with '&'. Every Azure touchpoint in them is an injectable [scriptblock]
    parameter, and every call in the suite overrides them, but the DEFAULTS are the real thing:
    Remove-AzResourceGroup -Force, Get-AzContext, and runners that start the real lab scripts
    in a child pwsh. Issue #152: nothing asserted that a call had not forgotten one, and
    tools/Invoke-DryRun.ps1 -Check Pester runs the suite on a signed-in developer box.

    The suite poisons two things, and this module is where it learns what they are:

      Get-LabCycleScriptblockParameter - every [scriptblock] parameter the orchestrators declare,
      including those with no default in the param block because the script body fills them in
      (TeardownRunner, PhaseRunner). The suite gives each one a poisoned default through
      $PSDefaultParameterValues.

      Get-LabCycleAzCommand - every '<Verb>-Az<Noun>' command named anywhere in the given files,
      in a default or in a function body. The suite shadows each one with a global function.

    Both read the parser's AST, never a hand-kept list, so a probe or an Az call added to the
    orchestrators later is poisoned without anyone having to remember the test file.

.EXAMPLE
    Import-Module ./tests/Support/LabCycleIsolation.psm1

    Get-LabCycleScriptblockParameter -Path ./tools/Remove-LabCycle.ps1
    Get-LabCycleAzCommand -Path ./tools/Remove-LabCycle.ps1, ./tools/LabCycle.psm1

.NOTES
    Project: SkyCraft
    Issue: #152
#>

#Requires -Version 7.0

$ErrorActionPreference = 'Stop'

function Get-LabCycleScriptblockParameter {
    <#
    .SYNOPSIS
        Returns every [scriptblock] parameter a script declares, as Script/Parameter/Key objects.

    .DESCRIPTION
        Key is '<file name>:<parameter>', the form $PSDefaultParameterValues matches a script
        invoked by path against. Typed parameters are matched on the parser's StaticType, so a
        parameter declared as [ScriptBlock] or [System.Management.Automation.ScriptBlock] counts
        the same as [scriptblock].

    .PARAMETER Path
        The scripts to read. Parsed, never executed.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [string[]]$Path
    )

    foreach ($file in $Path) {
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($file, [ref]$null, [ref]$null)
        if (-not $ast.ParamBlock) { continue }
        $leaf = Split-Path -Leaf $file

        foreach ($parameter in $ast.ParamBlock.Parameters) {
            if ($parameter.StaticType -ne [scriptblock]) { continue }
            $name = $parameter.Name.VariablePath.UserPath
            [pscustomobject]@{ Script = $leaf; Parameter = $name; Key = "${leaf}:$name" }
        }
    }
}

function Get-LabCycleAzCommand {
    <#
    .SYNOPSIS
        Returns the distinct '<Verb>-Az<Noun>' commands named in the given files, sorted.

    .DESCRIPTION
        Every CommandAst in the file counts, wherever it sits: in a parameter default, in a
        function body, in a closure. A name inside a comment or a string is not a command and is
        not returned.

    .PARAMETER Path
        The scripts and modules to read. Parsed, never executed.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string[]]$Path
    )

    $names = foreach ($file in $Path) {
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($file, [ref]$null, [ref]$null)
        $ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.CommandAst] }, $true) |
            ForEach-Object { $_.GetCommandName() } |
            Where-Object { $_ -cmatch '^[A-Z][a-z]+-Az[A-Z][A-Za-z]*$' }
    }
    @($names | Sort-Object -Unique)
}

Export-ModuleMember -Function Get-LabCycleScriptblockParameter, Get-LabCycleAzCommand

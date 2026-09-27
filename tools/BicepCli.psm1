<#
.SYNOPSIS
    Resolves the standalone Bicep CLI that the repository's offline tooling compiles with.

.DESCRIPTION
    The deploy scripts compile through the 'bicep' executable on PATH: New-AzSubscriptionDeployment
    and New-AzResourceGroupDeployment shell out to it. The Pester suites and tools/Invoke-DryRun.ps1 used to
    compile through 'az bicep' instead, which runs the copy the Azure CLI manages under
    ~/.azure/bin - a second toolchain that can be a different version, so "the gate built
    it" and "the deploy script built it" were not the same statement (issue #144). It also
    routes the compiled JSON through the CLI's bundled Python, whose 'build --stdout' dies
    with a UnicodeEncodeError on Windows as soon as a template pulls in an AVM module with
    non-ANSI metadata.

    Get-BicepCliPath returns the 'bicep' on PATH first, so offline builds use the compiler
    the deploys use. It falls back to the Azure-CLI-managed binary so a machine that only
    ever ran 'az bicep install' keeps working, and throws with an install hint when neither
    exists. The fallback invokes that binary directly, never through 'az', so the console
    encoding crash cannot come back through it.

.EXAMPLE
    Import-Module ./tools/BicepCli.psm1
    & (Get-BicepCliPath) build ./module-3-compute/3.1-infrastructure-as-code/bicep/main.bicep --stdout

.NOTES
    Project: SkyCraft
#>

#Requires -Version 7.0

$ErrorActionPreference = 'Stop'

function Get-AzCliBicepPath {
    <#
    .SYNOPSIS
        Returns where 'az bicep install' puts the Bicep binary, whether or not it exists.

    .DESCRIPTION
        The Azure CLI keeps its managed Bicep under <config dir>/bin, where the config dir
        is $env:AZURE_CONFIG_DIR when set and ~/.azure otherwise.

    .NOTES
        Project: SkyCraft
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    $configDir = if ($env:AZURE_CONFIG_DIR) { $env:AZURE_CONFIG_DIR } else { Join-Path $HOME '.azure' }
    $fileName  = if ($IsWindows) { 'bicep.exe' } else { 'bicep' }

    return (Join-Path $configDir 'bin' $fileName)
}

function Get-BicepCliPath {
    <#
    .SYNOPSIS
        Returns the full path of the Bicep CLI to compile with.

    .DESCRIPTION
        Resolution order:
          1. 'bicep' on PATH - the binary the Az PowerShell deployment cmdlets use.
          2. The Azure-CLI-managed copy (see Get-AzCliBicepPath).
        Throws when neither exists, naming both ways to install it.

    .OUTPUTS
        [string] full path of the executable.

    .NOTES
        Project: SkyCraft
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    $onPath = Get-Command -Name 'bicep' -CommandType Application -ErrorAction SilentlyContinue |
              Select-Object -First 1
    if ($onPath) {
        return $onPath.Source
    }

    $azManaged = Get-AzCliBicepPath
    if (Test-Path -LiteralPath $azManaged -PathType Leaf) {
        return $azManaged
    }

    throw ("The Bicep CLI was not found: no 'bicep' on PATH and no Azure-CLI-managed copy at '$azManaged'. " +
           'Install the standalone CLI (https://aka.ms/bicep-install) or run: az bicep install')
}

Export-ModuleMember -Function Get-BicepCliPath, Get-AzCliBicepPath

<#
.SYNOPSIS
    Runs a lab script in a child pwsh with its Az commands replaced by a generated stub module.

.DESCRIPTION
    The one supported way for a Pester suite to execute a real lab script (Remove-LabResource.ps1
    and friends) without reaching Azure. Written for issue #112, lifted from the Lab 5.2 suite
    that found the problem (#105), and required by tests/Lab-Script-Harness-Guard.Tests.ps1 for
    every suite that launches pwsh at a lab script.

    Two PowerShell behaviours make the obvious approaches fail silently, and a silent failure
    here is a real teardown on whatever subscription Get-AzContext returns:

      1. PSModulePath is not an isolation mechanism. pwsh 7 prepends the CurrentUser and AllUsers
         module directories to any inherited PSModulePath, so a stub directory placed first by the
         parent is not first in the child, and an installed Az always wins command resolution.

      2. Importing a stub module before the script is not enough either. The script's
         '#Requires -Modules Az.*' line imports the real modules after the stub, and among
         same-kind commands the later import wins. Az modules that export cmdlets stay shadowed
         (a function outranks a cmdlet), but autorest-generated modules such as Az.DataProtection
         export functions, so theirs replace the stub's. The session is half real.

    Invoke-LabScriptWithStub therefore does, inside the child and in this order:

      - import every real module the script requires, so '#Requires' finds them loaded and does
        not re-import them on top of the stub;
      - import the stub module last, so its functions outrank both cmdlets and functions;
      - assert that every stubbed command resolves to the stub module, and exit 99 without running
        the script if any does not - the suite fails instead of touching real resources;
      - run the script and hand its exit code back.

    Initialize-LabScriptStub writes the stub module and, next to it, manifest-only placeholders
    for the required modules. The placeholders export nothing and can never win resolution; they
    exist so '#Requires -Modules' is satisfiable on a runner with no Az installed (CI does not
    install it). The placeholder directory is put on PSModulePath only for the child launch.

.EXAMPLE
    Import-Module ./tests/Support/LabScriptStub.psm1

    $stub = Initialize-LabScriptStub -Name 'SkyCraftAzStub' `
        -Command 'Get-AzContext', 'Remove-AzResourceGroup' `
        -RequiredModule 'Az.Accounts', 'Az.Resources' `
        -Body @'
function Get-AzContext { [pscustomobject]@{ Name = 'stub-context' } }
function Remove-AzResourceGroup { param($Name, [switch]$Force) }
'@
    $run = Invoke-LabScriptWithStub -Stub $stub -ScriptPath $scriptPath -ArgumentList '-Force'
    $run.Refused  | Should -BeFalse
    $run.ExitCode | Should -Be 0

.NOTES
    Project: SkyCraft
    Issue: #112
#>

#Requires -Version 7.0

$ErrorActionPreference = 'Stop'

# The child exits with this code when the stub is not in effect. Distinctive on purpose: a lab
# script's own contract is 0 or 1, so a 99 can only mean the harness refused to run.
$script:RefusedExitCode = 99

function Initialize-LabScriptStub {
    <#
    .SYNOPSIS
        Writes a stub module and the placeholder modules a lab script's '#Requires' line needs.

    .DESCRIPTION
        Creates a throwaway directory under the temp path holding:

          <Name>.psm1               the stub body, verbatim
          <Name>.psd1               a manifest exporting exactly -Command
          modules/<Required>/1.0.0  a manifest-only placeholder per required module

        -Command is exported explicitly rather than through FunctionsToExport = '*': that leaves
        the export list to the module analyser, which infers it with a lightweight scan and can
        stop partway through. Every name in -Command must be defined in -Body; a name that is not
        cannot resolve to the stub, and Invoke-LabScriptWithStub will refuse to run.

        The caller owns the directory and removes it (Remove-Item -Recurse on .Directory) in
        AfterAll.

    .PARAMETER Name
        Module name of the stub. It is what every stubbed command's Source is checked against.

    .PARAMETER Command
        The command names the stub defines and exports - every Az command the script calls, plus
        any built-in it shadows (for example Get-Module).

    .PARAMETER Body
        The .psm1 content: one function per name in -Command.

    .PARAMETER RequiredModule
        The module names from the script's '#Requires -Modules' line, exactly. They are imported
        for real (when installed) before the stub, and a placeholder is written for each so the
        script parses on a runner without them.

    .OUTPUTS
        PSCustomObject with Name, Directory, Manifest, PlaceholderPath, Commands, RequiredModules.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string[]]$Command,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Body,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string[]]$RequiredModule
    )

    $directory = Join-Path ([System.IO.Path]::GetTempPath()) ('skycraft-stub-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $directory -Force | Out-Null

    Set-Content -LiteralPath (Join-Path $directory "$Name.psm1") -Value $Body -Encoding utf8
    $manifest = Join-Path $directory "$Name.psd1"
    New-ModuleManifest -Path $manifest `
        -RootModule "$Name.psm1" `
        -ModuleVersion '1.0.0' `
        -FunctionsToExport $Command

    $placeholderPath = Join-Path $directory 'modules'
    foreach ($required in $RequiredModule) {
        $requiredDir = Join-Path $placeholderPath $required '1.0.0'
        New-Item -ItemType Directory -Path $requiredDir -Force | Out-Null
        New-ModuleManifest -Path (Join-Path $requiredDir "$required.psd1") `
            -ModuleVersion '1.0.0' `
            -FunctionsToExport @()
    }

    [pscustomobject]@{
        Name            = $Name
        Directory       = $directory
        Manifest        = $manifest
        PlaceholderPath = $placeholderPath
        Commands        = [string[]]$Command
        RequiredModules = [string[]]$RequiredModule
    }
}

function Invoke-LabScriptWithStub {
    <#
    .SYNOPSIS
        Runs a script in a child pwsh with the stub shadowing its Az commands, or refuses.

    .DESCRIPTION
        Launches 'pwsh -NoProfile -NonInteractive -Command' with a preamble that imports the
        required modules, imports the stub last, verifies every stubbed command resolves to the
        stub, and only then runs the script. See the module description for why that order is
        the only one that works.

        The child is launched with -Command rather than -File on purpose: a script that declares
        '#Requires -Modules' loses its exit code through 'pwsh -File' (issue #104), and this
        helper is about what the script returns, not about that propagation.

    .PARAMETER Stub
        The object Initialize-LabScriptStub returned.

    .PARAMETER ScriptPath
        Full path of the script to run.

    .PARAMETER ArgumentList
        Arguments appended verbatim to the invocation, for example '-Force'. Quote values that
        need it; they are spliced into the child's command text as written.

    .PARAMETER Environment
        Environment variables to set for the child (name -> value) and restore afterwards. This is
        how a stub body is usually parameterised per scenario: one generated module, behaviour
        chosen by variables.

    .OUTPUTS
        PSCustomObject with ExitCode, Output (the child's combined output as one string) and
        Refused ($true when the child exited 99 because the stub was not in effect).
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$Stub,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$ScriptPath,

        [Parameter()]
        [string[]]$ArgumentList = @(),

        [Parameter()]
        [hashtable]$Environment = @{}
    )

    $required  = "'" + ($Stub.RequiredModules -join "','") + "'"
    $shadowed  = "'" + ($Stub.Commands -join "','") + "'"
    $arguments = if ($ArgumentList.Count -gt 0) { ' ' + ($ArgumentList -join ' ') } else { '' }

    $childCommand = @"
foreach (`$m in @($required)) { Import-Module `$m -ErrorAction SilentlyContinue }
Import-Module '$($Stub.Manifest)' -Force
`$notShadowed = @($shadowed) | Where-Object { (Get-Command `$_ -ErrorAction SilentlyContinue).Source -ne '$($Stub.Name)' }
if (`$notShadowed) {
    Write-Host "[HARNESS] Az stubs are not in effect for: `$(`$notShadowed -join ', ') - refusing to run."
    exit $script:RefusedExitCode
}
`$global:LASTEXITCODE = 0
& '$ScriptPath'$arguments
exit `$LASTEXITCODE
"@

    $savedEnvironment = @{}
    foreach ($key in $Environment.Keys) {
        $savedEnvironment[$key] = [System.Environment]::GetEnvironmentVariable($key)
    }
    $savedModulePath = $env:PSModulePath

    try {
        foreach ($key in $Environment.Keys) {
            [System.Environment]::SetEnvironmentVariable($key, [string]$Environment[$key])
        }
        # Only so the placeholder modules are discoverable when no real module is installed. This
        # is not the shadowing mechanism - the child prepends its own directories ahead of it.
        $env:PSModulePath = $Stub.PlaceholderPath + [System.IO.Path]::PathSeparator + $env:PSModulePath

        $output = & pwsh -NoProfile -NonInteractive -Command $childCommand 2>&1
        $code   = $LASTEXITCODE
    } finally {
        foreach ($key in $savedEnvironment.Keys) {
            [System.Environment]::SetEnvironmentVariable($key, $savedEnvironment[$key])
        }
        $env:PSModulePath = $savedModulePath
    }

    [pscustomobject]@{
        ExitCode = $code
        Output   = ($output | Out-String)
        Refused  = ($code -eq $script:RefusedExitCode)
    }
}

function Test-LabScriptHarnessText {
    <#
    .SYNOPSIS
        Classifies a Pester suite's text against the child-process harness rule.

    .DESCRIPTION
        The rule tests/Lab-Script-Harness-Guard.Tests.ps1 enforces, kept next to the helper it
        is about so the two cannot drift: a suite that names a lab script and either launches
        pwsh itself or uses this module is a harness, and a harness is guarded when it goes
        through this module or carries the same Source assertion and 'exit 99' inline.

        Launch forms only ('& pwsh', '& $Pwsh', 'Start-Process pwsh'): the word 'pwsh' in a
        comment or an It name is not a launch, and Invoke-LabScriptProcess (tools/LabCycle.psm1)
        is the orchestrators' shim, exercised by tests/LabCycle.Tests.ps1 against fixtures.

    .PARAMETER Text
        The suite's full text.

    .OUTPUTS
        PSCustomObject with LaunchesChild, NamesLabScript, UsesHelper, HasInlineGuard, IsHarness
        and Guarded.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Text
    )

    $launchesChild  = $Text -match '(?im)(^|[\s(;{])&\s+(pwsh|\$(script:)?\w*pwsh\w*)\b|Start-Process\b[^\r\n]*\bpwsh'
    $namesLabScript = $Text -match '(?i)\b(Remove-LabResource|Deploy-Bicep|Test-Lab|New-LabUser)\.ps1\b'
    $usesHelper     = $Text -match '(?i)LabScriptStub\.psm1'
    $hasInlineGuard = ($Text -match '(?i)\.Source\s+-ne\s+') -and ($Text -match '\bexit\s+99\b')

    [pscustomobject]@{
        LaunchesChild  = $launchesChild
        NamesLabScript = $namesLabScript
        UsesHelper     = $usesHelper
        HasInlineGuard = $hasInlineGuard
        IsHarness      = $namesLabScript -and ($launchesChild -or $usesHelper)
        Guarded        = $usesHelper -or $hasInlineGuard
    }
}

Export-ModuleMember -Function Initialize-LabScriptStub, Invoke-LabScriptWithStub, Test-LabScriptHarnessText

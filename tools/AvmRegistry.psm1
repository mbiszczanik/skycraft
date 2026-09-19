<#
.SYNOPSIS
    Compares the repository's AVM pins with what the public Bicep registry publishes.

.DESCRIPTION
    Dependabot does not read Bicep registry references, so a 'br/public:avm/res/...:x.y.z'
    pin has no update signal of its own (issue #82). This module supplies one: it scans
    the Bicep files for every AVM module declaration, asks mcr.microsoft.com - the registry
    behind the br/public alias - for each module's tag list, and classifies every pin as
    Current, Behind, Unlisted or Unknown.

    Held in a module so tools/Get-AvmModuleUpdate.ps1 and tests/Avm-Module-Update.Tests.ps1
    call the same scan and the same comparison. The registry call is injectable with a
    real default, so the classification is tested offline while the shipped path stays
    the tested path.

.EXAMPLE
    Import-Module ./tools/AvmRegistry.psm1
    Compare-AvmModulePin -Reference (Get-AvmModuleReference -RepoRoot .) | Format-Table

.NOTES
    Project: SkyCraft
#>

#Requires -Version 7.0

$ErrorActionPreference = 'Stop'

# The same declaration shape tests/Avm-Module-Pinning.Tests.ps1 matches:
#   module <symbolicName> 'br/public:<avm-path>:<version>' = ...
# Anchored to the line start so a commented-out declaration ('// module ...') is not a pin.
$script:AvmRefPattern = "(?m)^\s*module\s+\S+\s+'br/public:(avm/[a-z0-9/-]+):([^']+)'"

function Get-AvmModuleReference {
    <#
    .SYNOPSIS
        Returns every distinct AVM module the repository pins, with its version and files.

    .PARAMETER RepoRoot
        The directory to scan for *.bicep files.

    .OUTPUTS
        [pscustomobject] per module: Module, Pinned, Files (repo-relative, forward slashes).
        A module pinned to more than one version returns one object per version;
        tests/Avm-Module-Pinning.Tests.ps1 is what forbids that state.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$RepoRoot
    )

    $root  = (Resolve-Path -LiteralPath $RepoRoot).Path
    $files = Get-ChildItem -Path $root -Recurse -File -Filter '*.bicep'

    $refs = foreach ($f in $files) {
        $text = Get-Content -Raw -LiteralPath $f.FullName
        foreach ($m in [regex]::Matches($text, $script:AvmRefPattern)) {
            [pscustomobject]@{
                File    = ($f.FullName.Substring($root.Length + 1) -replace '\\', '/')
                Module  = $m.Groups[1].Value
                Version = $m.Groups[2].Value
            }
        }
    }

    $refs | Group-Object Module, Version | Sort-Object Name | ForEach-Object {
        [pscustomobject]@{
            Module = $_.Group[0].Module
            Pinned = $_.Group[0].Version
            Files  = @($_.Group.File | Sort-Object -Unique)
        }
    }
}

function Get-AvmTagListUri {
    <#
    .SYNOPSIS
        The OCI tag-list endpoint for an AVM module on the public registry.

    .DESCRIPTION
        'br/public' is Bicep's alias for mcr.microsoft.com/bicep, so a module published as
        'br/public:avm/res/x/y' lives at repository 'bicep/avm/res/x/y' and its tags are
        listed by the standard OCI distribution endpoint '/v2/<repository>/tags/list'.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidatePattern('^avm/[a-z0-9/-]+$')]
        [string]$Module
    )

    "https://mcr.microsoft.com/v2/bicep/$Module/tags/list"
}

function Invoke-AvmTagList {
    <#
    .SYNOPSIS
        The real registry probe: returns the raw tag names for one module.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param([Parameter(Mandatory = $true)][string]$Module)

    $response = Invoke-RestMethod -Uri (Get-AvmTagListUri -Module $Module) -Method Get -TimeoutSec 30
    [string[]]@($response.tags)
}

function Test-AvmRegistry {
    <#
    .SYNOPSIS
        True when mcr.microsoft.com answers a tag-list request; false when it cannot be reached.

    .DESCRIPTION
        One cheap probe so a caller can decide up front whether to run a live comparison
        at all, instead of discovering the network is missing thirty modules later.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $false)]
        [string]$Module = 'avm/res/resources/resource-group'
    )

    try {
        $null = Invoke-RestMethod -Uri (Get-AvmTagListUri -Module $Module) -Method Get -TimeoutSec 15
        $true
    }
    catch {
        $false
    }
}

function Get-AvmPublishedVersion {
    <#
    .SYNOPSIS
        Returns the published x.y.z versions of an AVM module, ascending.

    .DESCRIPTION
        Only exact x.y.z tags count; 'latest', pre-release and partial tags are dropped,
        matching the pin format the repository allows. Sorted as [version], not as text,
        so 0.10.0 is newer than 0.9.0.

    .PARAMETER Module
        The AVM module path, e.g. 'avm/res/network/virtual-network'.

    .PARAMETER TagListProvider
        A script block that takes the module path and returns its raw tag names.
        Defaults to the real registry.
    #>
    [CmdletBinding()]
    [OutputType([version[]])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Module,

        [Parameter(Mandatory = $false)]
        [scriptblock]$TagListProvider = { param($Module) Invoke-AvmTagList -Module $Module }
    )

    $tags = @(& $TagListProvider $Module)
    [version[]]@($tags | Where-Object { $_ -match '^\d+\.\d+\.\d+$' } | ForEach-Object { [version]$_ } | Sort-Object)
}

function Compare-AvmModulePin {
    <#
    .SYNOPSIS
        Classifies each pinned AVM module against the registry's newest version.

    .DESCRIPTION
        Status per module:
          Current   the pin is the newest x.y.z tag the registry lists
          Behind    the registry lists a newer x.y.z tag (Latest names it)
          Unlisted  the registry does not list the pinned tag at all - the pin cannot
                    resolve, which is a broken template, not a review item
          Unknown   the tag list could not be read (Error carries why)

    .PARAMETER Reference
        The objects Get-AvmModuleReference returns.

    .PARAMETER TagListProvider
        Passed through to Get-AvmPublishedVersion; defaults to the real registry.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [pscustomobject[]]$Reference,

        [Parameter(Mandatory = $false)]
        [scriptblock]$TagListProvider = { param($Module) Invoke-AvmTagList -Module $Module }
    )

    foreach ($ref in $Reference) {

        $latest = $null
        $status = 'Unknown'
        $reason = $null

        try {
            $published = @(Get-AvmPublishedVersion -Module $ref.Module -TagListProvider $TagListProvider)
            $pinned    = [version]$ref.Pinned

            if ($published.Count -gt 0) { $latest = $published[-1].ToString() }

            $status = if ($published -notcontains $pinned) { 'Unlisted' }
                      elseif ($pinned -lt $published[-1])  { 'Behind' }
                      else                                  { 'Current' }
        }
        catch {
            $reason = $_.Exception.Message
        }

        [pscustomobject]@{
            Module = $ref.Module
            Pinned = $ref.Pinned
            Latest = $latest
            Status = $status
            Files  = $ref.Files
            Error  = $reason
        }
    }
}

Export-ModuleMember -Function Get-AvmModuleReference, Get-AvmTagListUri, Test-AvmRegistry, Get-AvmPublishedVersion, Compare-AvmModulePin

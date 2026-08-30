<#
.SYNOPSIS
    Reports Azure resources tagged for this project that no lab source accounts for.

.DESCRIPTION
    Lists every resource carrying the project tag and flags the ones whose name
    the repository cannot produce. It reports only - nothing is deleted - because
    a false positive must never tear down live lab state.

    The check is not a literal name grep. Roughly half of all SkyCraft resource
    names are composed at deploy time from an environment parameter and a suffix
    ('${varNamePrefix}-kv', "$Environment-skycraft-swc-vnet") and never appear in
    the sources as literals, so absence of a literal is not evidence of drift:
    grepping for the literal name flags prod-skycraft-swc-kv, -asp and -app01 -
    all legitimate, actively deployed resources - as loudly as it flags a genuine
    orphan.

    Instead the audit rebuilds the set of names the repository can produce. It
    reads the deployment sources, keeps the names spelled literally, and expands
    the composed ones over the environment domain. A resource is drift when its
    name is not in that set - the discriminator is the suffix, which for real lab
    resources is always one some template emits.

    Test fixtures under tests/ are not deployment sources and are not read.

.PARAMETER RepoRoot
    Repository root to read the deployment sources from. Defaults to the parent
    of the directory holding this script.

.PARAMETER ProjectTag
    Value of the Project tag identifying lab resources. Defaults to SkyCraft.

.PARAMETER EnvironmentPrefix
    Environment name segments a resource name may start with. Defaults to the
    domain the bicep templates declare in @allowed(['dev', 'prod', 'platform']).

.PARAMETER PassThru
    Emit the flagged resources as objects instead of only printing the report.

.EXAMPLE
    .\scripts\Invoke-ResourceAudit.ps1
    Reports every tagged resource the repository does not account for.

.EXAMPLE
    .\scripts\Invoke-ResourceAudit.ps1 -PassThru | Format-Table Name, ResourceType
    Reports drift and emits it for further processing.

.NOTES
    Project: SkyCraft
    Issue: 116 - nothing detects a lab resource that no template deploys and no teardown deletes
    Author: Marcin Biszczanik
    Version: 1.0.0
#>

#Requires -Version 7.0
#Requires -Modules Az.Accounts, Az.Resources

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path,

    [Parameter(Mandatory = $false)]
    [string]$ProjectTag = 'SkyCraft',

    [Parameter(Mandatory = $false)]
    [string[]]$EnvironmentPrefix = @('dev', 'prod', 'platform'),

    [Parameter(Mandatory = $false)]
    [switch]$PassThru
)

$ErrorActionPreference = 'Stop'

function Get-KnownResourceName {
    <#
    .SYNOPSIS
        Builds the set of resource names the repository can produce.
    .DESCRIPTION
        Reads every deployment source under RepoRoot and returns the names it can
        emit: those spelled literally, plus the prefix-and-suffix templates
        expanded over the environment domain.
    .NOTES
        Project: SkyCraft
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepoRoot,

        [Parameter(Mandatory = $false)]
        [string]$ProjectToken = 'skycraft',

        [Parameter(Mandatory = $false)]
        [string[]]$EnvironmentPrefix = @('dev', 'prod', 'platform')
    )

    $known = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)

    # tests/ holds fixtures, not deployment sources - reading it would teach the
    # audit the very names its regression guards expect it not to know.
    $sources = Get-ChildItem -Path $RepoRoot -Recurse -File -Include '*.bicep', '*.bicepparam', '*.ps1' |
        Where-Object { ($_.FullName -replace '\\', '/') -notmatch '/(\.git|tests|docs)/' }

    $texts = foreach ($source in $sources) { Get-Content -Raw -LiteralPath $source.FullName }

    $singleQuoted = [regex]"'([^'\r\n]{3,160})'"
    $doubleQuoted = [regex]'"([^"\r\n]{3,160})"'

    # A name declaration need not mention the project: Lab 5.3 names the Network
    # Watcher 'NetworkWatcher_${parLocation}'. Matching the declaration itself
    # catches those; matching the project token catches the rest.
    $nameDeclaration = [regex]@'
(?:var\s+\w*Name|\$\w*Name\w*)\s*=\s*['"]([^'"\r\n]{3,160})['"]
'@

    # The values a placeholder can take. Every domain a template constrains with
    # @allowed is one the audit can expand over - environments, locations, and
    # the short codes the sources declare outright.
    $domain = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($environment in $EnvironmentPrefix) { [void]$domain.Add($environment) }
    foreach ($text in $texts) {
        foreach ($allowed in [regex]::Matches($text, '@allowed\(\s*\[([^\]]*)\]', 'IgnoreCase')) {
            foreach ($value in $singleQuoted.Matches($allowed.Groups[1].Value)) {
                [void]$domain.Add($value.Groups[1].Value)
            }
        }
        foreach ($match in [regex]::Matches($text, 'LocationShortCode\s*=\s*[''"](\w+)[''"]', 'IgnoreCase')) {
            [void]$domain.Add($match.Groups[1].Value)
        }
    }

    # Pass 1 - literals that name something, expanded over the domain.
    # Descriptions and resource-ID templates mention the project too, and would be
    # expanded and counted alongside the real names; Azure cannot name a resource
    # with whitespace or a path separator, and 90 is the longest name it accepts.
    $isPlausibleName = {
        param([string]$Value)
        $Value -notmatch '[\s/\\:]' -and $Value.Length -le 90
    }

    $candidate = [System.Collections.Generic.List[string]]::new()
    foreach ($text in $texts) {
        foreach ($pattern in @($singleQuoted, $doubleQuoted)) {
            foreach ($match in $pattern.Matches($text)) {
                if ($match.Groups[1].Value -match $ProjectToken -and
                    (& $isPlausibleName $match.Groups[1].Value)) { $candidate.Add($match.Groups[1].Value) }
            }
        }
        foreach ($match in $nameDeclaration.Matches($text)) {
            if (& $isPlausibleName $match.Groups[1].Value) { $candidate.Add($match.Groups[1].Value) }
        }
    }

    foreach ($value in $candidate) {
        # Every interpolation form collapses to one placeholder.
        $normalised = $value -replace '\$\{[^}]+\}', '<X>' -replace '\$\([^)]*\)', '<X>' -replace '\$\w+', '<X>'

        if ($normalised -notmatch '<X>') {
            [void]$known.Add($normalised)
            continue
        }

        # A template with no literal run of its own - a bare '${parEnvironment}' -
        # would expand to the domain values themselves and match far too much.
        if (($normalised -replace '<X>', '') -notmatch '[A-Za-z0-9]{3}') { continue }

        $placeholder = $normalised.Split('<X>').Count - 1
        if ($placeholder -gt 2) { continue }

        $pending = @($normalised)
        for ($round = 0; $round -lt $placeholder; $round++) {
            $next = [System.Collections.Generic.List[string]]::new()
            foreach ($partial in $pending) {
                foreach ($value in $domain) { $next.Add(([regex]'<X>').Replace($partial, $value, 1)) }
            }
            $pending = $next
        }
        foreach ($expanded in $pending) {
            if ($expanded -notmatch '<X>') { [void]$known.Add($expanded) }
        }
    }

    # Pass 2 - '<prefix>-suffix' templates, whose literal text never names the project.
    $suffixes = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($text in $texts) {
        foreach ($match in [regex]::Matches($text, '\$\{?\w*prefix\}?(-[a-z0-9][a-z0-9-]*)', 'IgnoreCase')) {
            [void]$suffixes.Add($match.Groups[1].Value)
        }
    }

    # The location short code is declared outright in some sources and implied by
    # the literal names in others; both are used so neither alone has to be present.
    $shortCodes = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($text in $texts) {
        foreach ($match in [regex]::Matches($text, 'LocationShortCode\s*=\s*[''"](\w+)[''"]', 'IgnoreCase')) {
            [void]$shortCodes.Add($match.Groups[1].Value)
        }
    }
    $environmentAlternation = ($EnvironmentPrefix | ForEach-Object { [regex]::Escape($_) }) -join '|'
    foreach ($name in @($known)) {
        $match = [regex]::Match($name, "^(?:$environmentAlternation)-$ProjectToken-([a-z0-9]{2,5})-", 'IgnoreCase')
        if ($match.Success) { [void]$shortCodes.Add($match.Groups[1].Value) }
    }

    foreach ($environment in $EnvironmentPrefix) {
        foreach ($shortCode in $shortCodes) {
            foreach ($suffix in $suffixes) {
                [void]$known.Add("$environment-$ProjectToken-$shortCode$suffix")
            }
        }
    }

    return @($known)
}

function Test-LabResourceKnown {
    <#
    .SYNOPSIS
        Reports whether a resource name is one the repository can produce.
    .DESCRIPTION
        Returns true when the name is in the set built by Get-KnownResourceName.
        Matching is case-insensitive, because Azure resource names are.
    .NOTES
        Project: SkyCraft
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [string[]]$KnownName
    )

    return [bool]($KnownName -contains $Name)
}

function Select-UnreferencedResource {
    <#
    .SYNOPSIS
        Selects the resources whose names the repository cannot produce.
    .DESCRIPTION
        Filters a resource list down to the drift. Returns them; deletes nothing.
    .NOTES
        Project: SkyCraft
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]]$Resource,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [string[]]$KnownName
    )

    return @($Resource | Where-Object { -not (Test-LabResourceKnown -Name $_.Name -KnownName $KnownName) })
}

Write-Host "=== SkyCraft - Resource Audit ===" -ForegroundColor Cyan -BackgroundColor Black

$context = Get-AzContext
if (-not $context) {
    Write-Host "Not logged in. Please run Connect-AzAccount" -ForegroundColor Red
    $Host.SetShouldExit(1)
    exit 1
}

Write-Host "`nSubscription : $($context.Subscription.Name) ($($context.Subscription.Id))" -ForegroundColor Gray
Write-Host "Repository   : $RepoRoot" -ForegroundColor Gray

$knownName = Get-KnownResourceName -RepoRoot $RepoRoot -ProjectToken $ProjectTag.ToLowerInvariant() -EnvironmentPrefix $EnvironmentPrefix
Write-Host "Known names  : $($knownName.Count)" -ForegroundColor Gray

Write-Host "`nReading resources tagged Project=$ProjectTag..." -ForegroundColor Cyan
$tagged = @(Get-AzResource -TagName 'Project' -TagValue $ProjectTag)
$taggedGroup = @(Get-AzResourceGroup -Tag @{ Project = $ProjectTag } |
    Select-Object -Property @{ n = 'Name'; e = { $_.ResourceGroupName } },
                            @{ n = 'ResourceType'; e = { 'Microsoft.Resources/resourceGroups' } },
                            @{ n = 'ResourceGroupName'; e = { $_.ResourceGroupName } },
                            ResourceId)

$all = @($tagged) + @($taggedGroup)
Write-Host "  -> $($all.Count) tagged resource(s) found" -ForegroundColor Gray

$drift = @(Select-UnreferencedResource -Resource $all -KnownName $knownName)

if ($drift.Count -eq 0) {
    Write-Host "`n[OK] Every tagged resource is accounted for by a lab source." -ForegroundColor Green
    if ($PassThru) { @() }
    exit 0
}

Write-Host "`n[DRIFT] $($drift.Count) tagged resource(s) that no lab source accounts for:" -ForegroundColor Yellow
foreach ($item in $drift) {
    Write-Host "  - $($item.Name)" -ForegroundColor Yellow
    Write-Host "      type : $($item.ResourceType)" -ForegroundColor Gray
    Write-Host "      group: $($item.ResourceGroupName)" -ForegroundColor Gray
}
Write-Host "`nReview each one before acting. This audit reports; it deletes nothing." -ForegroundColor Cyan

if ($PassThru) { $drift }

$Host.SetShouldExit(1)
exit 1

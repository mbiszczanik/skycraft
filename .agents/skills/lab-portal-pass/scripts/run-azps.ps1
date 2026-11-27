<#
.SYNOPSIS
    Runs a lab script (Test-Lab.ps1, Deploy-Bicep.ps1 -WhatIf) against one subscription with a
    process-scoped Az context built from the az CLI token. No saved Az context is read or written.

.EXAMPLE
    pwsh -NoProfile -NonInteractive -File run-azps.ps1 -SubscriptionId <sub-id> -Script <lab>/scripts/Test-Lab.ps1
    pwsh -NoProfile -NonInteractive -File run-azps.ps1 -SubscriptionId <sub-id> -Script <lab>/scripts/Deploy-Bicep.ps1 -WhatIf
    pwsh -NoProfile -NonInteractive -File run-azps.ps1 -SubscriptionId <sub-id> -Script <5.1>/scripts/Deploy-Bicep.ps1 -WhatIf -Param OpsEmail=ops@example.com

.NOTES
    Exit code: the script's own, or 99 when the script threw (message and line printed as CRASH).
    -WhatIf is passed through only to Deploy-Bicep.ps1; this wrapper never deploys.
#>
param(
    [Parameter(Mandatory)][string]$SubscriptionId,
    [Parameter(Mandatory)][string]$Script,
    [switch]$WhatIf,
    # Extra script parameters as Name=Value (e.g. -Param OpsEmail=ops@example.com); a bare Name is a switch
    [string[]]$Param = @()
)
$ErrorActionPreference = 'Stop'

$Script = (Resolve-Path -LiteralPath $Script).Path
$leaf = Split-Path $Script -Leaf
if ($leaf -notin 'Test-Lab.ps1', 'Deploy-Bicep.ps1') { throw "Only Test-Lab.ps1 or Deploy-Bicep.ps1 run here, not $leaf." }
$isDeploy = $leaf -eq 'Deploy-Bicep.ps1'
if ($isDeploy -and -not $WhatIf) {
    throw 'Deploy-Bicep.ps1 runs here only with -WhatIf; a real deploy is a separate, approved step.'
}

$splat = @{}
foreach ($p in $Param) {
    $name = ($p -split '=', 2)[0]
    # Binding accepts prefixes and the aliases wi/cf, so block those too.
    if ($name -in 'wi', 'cf' -or 'whatif'.StartsWith($name.ToLower()) -or 'confirm'.StartsWith($name.ToLower())) {
        throw "-Param may not set WhatIf or Confirm ($p)."
    }
    if ($p -match '^([A-Za-z][A-Za-z0-9]*)=(.*)$') { $splat[$Matches[1]] = $Matches[2] } else { $splat[$p] = $true }
}
if ($isDeploy) { $splat['WhatIf'] = $true }

$tok = az account get-access-token --subscription $SubscriptionId --resource https://management.azure.com/ --query accessToken -o tsv
$acct = az account show --subscription $SubscriptionId --query user.name -o tsv
if (-not $tok -or -not $acct) { throw 'No az CLI token for this subscription (sign in again; MFA is the user''s).' }
Connect-AzAccount -AccessToken $tok -AccountId $acct -Subscription $SubscriptionId -Scope Process | Out-Null
if ((Get-AzContext).Subscription.Id -ne $SubscriptionId) { throw 'Az context is on the wrong subscription.' }

try {
    & $Script @splat
    exit $LASTEXITCODE
} catch {
    Write-Host "CRASH: $($_.Exception.Message) at line $($_.InvocationInfo.ScriptLineNumber)"
    exit 99
}

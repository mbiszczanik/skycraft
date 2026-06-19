# SkyCraft PowerShell Standards

> **Source of Truth** for automation and deployment script development.

This document outlines the strict coding conventions for PowerShell scripts in the SkyCraft project. All automation must adhere to these standards to ensure readability, consistent user experience, and robust error handling.

> [!NOTE]
> These standards follow the official [PowerShell cmdlet development guidelines](https://learn.microsoft.com/powershell/scripting/developer/cmdlet/strongly-encouraged-development-guidelines) with a small number of **conscious divergences** documented in [Section 7](#7-conscious-divergences-from-microsoft-guidance).

---

## 1. File Structure & Header (Comment-Based Help)

Every PowerShell script must start with a standardized **Comment-Based Help (CBH)** block. This enables the use of `Get-Help` and provides immediate context.

Directly after the CBH block, declare requirements with `#Requires` statements so the script fails fast on an unsupported host:

```powershell
<#
.SYNOPSIS
    [Short Description of the script's purpose]

.DESCRIPTION
    [Detailed explanation of what the script does and any side effects]

.PARAMETER [ParameterName]
    [Description of what the parameter does and its default value if applicable]

.EXAMPLE
    .\Script-Name.ps1 -ParameterValue "Example"
    [Explanation of what this example does]

.NOTES
    Project: SkyCraft
    Author: [Name]
    Date: [YYYY-MM-DD]
#>

#Requires -Version 7.0
#Requires -Modules Az.Accounts

[CmdletBinding()]
param(...)
```

- `#Requires -Version 7.0` is mandatory in every script.
- Add `#Requires -Modules <Name>` for each Az module the script imports (e.g., `Az.Accounts`, `Az.Network`). Scripts that only shell out to the `az` CLI omit the module requirement.

## 2. Naming Conventions

Consistency in naming helps distinguish between external inputs and internal logic. We enforce the **Verb-Noun** pattern for all scripts.

| Object Type         | Convention             | Allowed Verbs | Examples                                           |
| :------------------ | :--------------------- | :------------ | :------------------------------------------------- |
| **Creation Script** | `New-Lab[Noun].ps1`    | `New`         | `New-LabUser.ps1`<br>`New-LabResourceGroup.ps1`    |
| **Cleanup Script**  | `Remove-Lab[Noun].ps1` | `Remove`      | `Remove-LabResource.ps1`<br>`Remove-LabPolicy.ps1` |
| **Test Script**     | `Test-Lab.ps1`         | `Test`        | `Test-Lab.ps1` (Standard validation script)        |
| **Action Script**   | `Invoke-Lab[Noun].ps1` | `Invoke`      | `Invoke-LabGovernance.ps1`                         |
| **Deployment**      | `Deploy-[Noun].ps1`    | `Deploy`      | `Deploy-Bicep.ps1`<br>`Deploy-Networking.ps1`      |

### Internal Objects

| Object Type    | Convention   | Example                                  |
| :------------- | :----------- | :--------------------------------------- |
| **Parameters** | `PascalCase` | `$ResourceGroupName`, `$Location`        |
| **Variables**  | `camelCase`  | `$vnet`, `$nsgProd`, `$retries`          |
| **Functions**  | `Verb-Noun`  | `Get-ProjectStatus`, `Test-AzConnection` |

### Language Rules

- **No aliases in scripts**: Always use full cmdlet and parameter names (`Get-ChildItem`, not `gci`/`ls`; `Where-Object`, not `?`; `ForEach-Object`, not `%`). Aliases are for the interactive prompt only. Enforced by the `PSAvoidUsingCmdletAliases` analyzer rule.
- **Approved verbs only**: Script and function verbs must come from `Get-Verb` (enforced by `PSUseApprovedVerbs`).

### Parameter Validation

Constrain parameters declaratively instead of validating them in the body. This gives the caller an immediate, well-formatted error and self-documents the contract:

```powershell
param(
    [Parameter(Mandatory = $false)]
    [ValidateSet('swedencentral', 'westeurope', 'northeurope')]
    [string]$Location = 'swedencentral',

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$ResourceGroupName,

    [Parameter(Mandatory = $false)]
    [ValidateRange(1, 3)]
    [int]$VmCount = 1
)
```

## 3. User Interface & Output

We use a standardized color scheme for `Write-Host` to provide a premium and consistent CLI experience.

> [!NOTE]
> Microsoft guidance discourages `Write-Host` in favour of `Write-Information`/`Write-Verbose`. We deliberately diverge for these learner-facing lab scripts — see [Section 7.1](#71-write-host-for-learner-facing-output).

| Output Type         | Color Style | Purpose                                  |
| :------------------ | :---------- | :--------------------------------------- |
| **Section Header**  | `Cyan`      | Main tasks or module headers             |
| **Action/Progress** | `Yellow`    | Current operation or "Wait" messages     |
| **Success**         | `Green`     | Completed tasks or positive validation   |
| **Error**           | `Red`       | Failures or exceptions                   |
| **Warning**         | `Yellow`    | Potential issues or safety confirmations |
| **Information**     | `Gray`      | Background details or skipping messages  |

### Example Implementation

```powershell
Write-Host "=== Task 1: Starting Deployment ===" -ForegroundColor Cyan
Write-Host "Creating resource..." -ForegroundColor Yellow
Write-Host "  -> Resource created successfully" -ForegroundColor Green
```

## 4. Robust Error Handling

Scripts interacting with Azure **must** use `try...catch` blocks to handle API failures gracefully.

### Mandatory Pattern

1. Set `$ErrorActionPreference = 'Stop'` at the top of every script (right after the `param` block), so unhandled errors terminate instead of silently continuing.
2. Use `try...catch` for all Azure cmdlets.
3. Use `-ErrorAction SilentlyContinue` if manually checking existence.
4. Use `-ErrorAction Stop` when a failure should trigger the `catch` block for retries or termination.

```powershell
$ErrorActionPreference = 'Stop'

try {
    Remove-AzResource -Name "Example" -Force -ErrorAction Stop
}
catch {
    Write-Host "  -> [ERROR] Failed to remove resource" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
}
```

## 5. Best Practices

- **`SupportsShouldProcess` for destructive scripts**: Every `Remove-Lab*` script (and any `Invoke-Lab*` script that changes state irreversibly) must declare `[CmdletBinding(SupportsShouldProcess)]` and wrap each destructive operation in `$PSCmdlet.ShouldProcess()`. This provides `-WhatIf` and `-Confirm` for free — do not reimplement them with manual `Read-Host` prompts:

  ```powershell
  [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
  param(
      [Parameter(Mandatory = $true)]
      [string]$ResourceGroupName,

      [switch]$Force
  )

  $ErrorActionPreference = 'Stop'
  if ($Force) { $ConfirmPreference = 'None' }

  if ($PSCmdlet.ShouldProcess($ResourceGroupName, 'Remove resource group')) {
      Remove-AzResourceGroup -Name $ResourceGroupName -Force
  }
  ```

  Callers skip the confirmation prompt with `-Confirm:$false`. SkyCraft `Remove-Lab*` scripts additionally retain a `-Force` switch — the backward-compatible, learner-facing equivalent that sets `$ConfirmPreference = 'None'` so existing `-Force` usage keeps working without a manual `Read-Host`. Keeping `-Force` is a conscious divergence — see [§7.4](#74--force-switch-on-destructive-scripts).

- **Secrets handling**: Never accept or store credentials as plain `[string]`. Use `[SecureString]` / `[PSCredential]` parameters (`Get-Credential`), and never echo secret values with `Write-Host`. Generated passwords go to Key Vault, not to the console or a file.

- **Az PowerShell vs. `az` CLI**: Prefer **Az PowerShell cmdlets** (`Get-AzContext`, `New-AzSubscriptionDeployment`, ...) as the default in scripts — they return objects, not text. Dropping to the **`az` CLI** is acceptable where its coverage is better (e.g., `az backup`, `az bicep`), but never mix both for the *same* resource within one script, and always follow the `--output json` rule below.

- **Retry Logic**: Implement retry loops for "stubborn" Azure resources (like NSGs) that suffer from eventual consistency delays.

- **Dependencies First**: Dissociate resources (e.g., NSG from Subnet) before attempting deletion.

- **No Hardcoding**: Default parameter values are acceptable, but hardcoded strings inside logic are discouraged.

- **Always Specify `--output json` for `az` → `ConvertFrom-Json` Pipelines**: The Azure CLI defaults to table/text output based on the user's local config (`AZURE_DEFAULTS_OUTPUT`). When using `az` output with `ConvertFrom-Json`, **always** explicitly pass `--output json`. Without it, the command will produce a `Conversion from JSON failed` error for any user whose default output format is not `json`.

  ```powershell
  # ❌ WRONG — breaks if user's default output format is 'table' or 'tsv'
  $account = az account show 2>$null | ConvertFrom-Json

  # ✅ CORRECT — always works regardless of az CLI configuration
  $account = az account show --output json 2>$null | ConvertFrom-Json
  ```

- **WhatIf Deployment Pattern**: Build separate args arrays for what-if vs real deployment rather than mutating indices. This avoids brittle index-based overwrites and makes intent clear:

  ```powershell
  # ❌ WRONG — index mutation is fragile
  $deployArgs[2] = 'what-if'

  # ✅ CORRECT — build two clean arrays
  if ($WhatIf) {
      $deployArgs = @('deployment', 'sub', 'what-if') + $commonParams
  } else {
      $deployArgs = @('deployment', 'sub', 'create') + $commonParams + @('--output', 'json')
  }
  ```

## 6. Static Analysis & Testing

### PSScriptAnalyzer

All scripts must pass **PSScriptAnalyzer** using the repo-root [`PSScriptAnalyzerSettings.psd1`](../PSScriptAnalyzerSettings.psd1):

```powershell
Invoke-ScriptAnalyzer -Path . -Recurse -Settings .\PSScriptAnalyzerSettings.psd1
```

- `Error`-severity findings block merge (enforced in CI).
- `Warning`-severity findings should be fixed or justified in the PR description.
- The settings file excludes `PSAvoidUsingWriteHost` (see [Section 7.1](#71-write-host-for-learner-facing-output)) — do not suppress other rules inline without a comment explaining why.

### Pester (Repository Standards Tests)

Repo-wide conventions are enforced by **Pester 5** tests in [`tests/`](../tests/) (API version policy, CBH coverage, README casing, etc.). Run them before pushing:

```powershell
Invoke-Pester -Path .\tests
```

New repo-wide rules should be added as Pester tests, not as manual checklist items. Lab-level `Test-Lab.ps1` scripts intentionally remain procedural — see [Section 7.2](#72-procedural-test-labps1-scripts).

## 7. Conscious Divergences from Microsoft Guidance

These are deliberate decisions where SkyCraft departs from the official Microsoft gold path, trading production-grade convention for the learning experience. **Do not "fix" these in code review** — if you want to change one, update this document first.

### 7.1 `Write-Host` for Learner-Facing Output

- **Microsoft says**: Avoid `Write-Host`; use `Write-Output` for data, `Write-Verbose`/`Write-Information` for status (analyzer rule `PSAvoidUsingWriteHost`).
- **We do**: Color-coded `Write-Host` throughout ([Section 3](#3-user-interface--output)).
- **Why**: Lab scripts are interactive teaching tools, not pipeline building blocks. The fixed color scheme (Cyan/Yellow/Green/Red/Gray) is part of the curriculum's UX and must render identically for every student regardless of preference variables. `PSAvoidUsingWriteHost` is excluded in `PSScriptAnalyzerSettings.psd1` for this reason.

### 7.2 Procedural `Test-Lab.ps1` Scripts

- **Microsoft says**: Infrastructure validation belongs in a test framework (Pester).
- **We do**: Procedural `Test-Lab.ps1` scripts with color-coded pass/fail output; Pester is reserved for repo-standards tests in `tests/`.
- **Why**: Students run `Test-Lab.ps1` *before* the testing module is taught; the linear, narrated output doubles as a learning aid showing *what* is being verified and *how* (which cmdlets query which resources).

### 7.3 Duplicated Connection Checks per Lab

- **Microsoft says**: Don't repeat yourself; factor shared setup (the `Get-AzContext` / `Connect-AzAccount` / `az account show` connection check) into a single shared module dot-sourced by every script.
- **We do**: Each lab's scripts carry their own self-contained connection-check block.
- **Why**: Every lab folder must be runnable in isolation and readable end-to-end without chasing a shared helper up the tree. The connection step is itself part of the lesson — students should see *how* a script verifies it is authenticated before acting. A shared `Common.ps1` would couple labs together and hide a teaching moment behind an abstraction.

### 7.4 `-Force` Switch on Destructive Scripts

- **Microsoft says**: `SupportsShouldProcess` already provides `-Confirm:$false`; a custom `-Force` switch is redundant and should not be reintroduced.
- **We do**: Every `Remove-Lab*` script keeps a `[switch]$Force` that sets `$ConfirmPreference = 'None'` (alongside full `SupportsShouldProcess` support, so `-WhatIf` / `-Confirm:$false` also work).
- **Why**: `-Force` shipped in earlier lab guides, READMEs, and student muscle memory. Removing it would be a breaking change to the documented learner interface for no functional gain. Retaining it as a thin alias over `$ConfirmPreference` keeps the scripts backward compatible while still routing every deletion through `$PSCmdlet.ShouldProcess()` (no manual `Read-Host`). `PSReviewUnusedParameter` may flag `-Force` where a script reads it only via the preference assignment — suppress with a justification rather than deleting the switch.

## 8. Script Boilerplate

```powershell
<#
.SYNOPSIS
    [Summary]
.DESCRIPTION
    [Detailed Description]
.PARAMETER Location
    Azure region for all resources. Defaults to 'swedencentral'.
.EXAMPLE
    .\Script-Name.ps1 -Location swedencentral
.NOTES
    Project: SkyCraft
    Date: [Current Date]
#>

#Requires -Version 7.0
#Requires -Modules Az.Accounts

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$Location = 'swedencentral'
)

$ErrorActionPreference = 'Stop'

Write-Host "=== Script Title ===" -ForegroundColor Cyan

# 1. Verify Connection
$context = Get-AzContext
if (-not $context) {
    Write-Host "Not logged in." -ForegroundColor Red; exit 1
}

# 2. Logic with Error Handling
try {
    Write-Host "Performing action..." -ForegroundColor Yellow
    # Action here
    Write-Host "Success!" -ForegroundColor Green
}
catch {
    Write-Host "Failed!" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    exit 1
}
```

### Destructive Script Boilerplate (`Remove-Lab*.ps1`)

```powershell
<#
.SYNOPSIS
    Removes [Lab Resources].
.DESCRIPTION
    [Detailed Description]
.PARAMETER ResourceGroupName
    Name of the resource group to remove.
.EXAMPLE
    .\Remove-LabExample.ps1 -ResourceGroupName 'dev-skycraft-swc-rg' -WhatIf
    Previews the removal without deleting anything.
.NOTES
    Project: SkyCraft
    Date: [Current Date]
#>

#Requires -Version 7.0
#Requires -Modules Az.Accounts, Az.Resources

[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$ResourceGroupName
)

$ErrorActionPreference = 'Stop'

Write-Host "=== Cleanup: $ResourceGroupName ===" -ForegroundColor Cyan

try {
    if ($PSCmdlet.ShouldProcess($ResourceGroupName, 'Remove resource group')) {
        Write-Host "Removing resource group..." -ForegroundColor Yellow
        Remove-AzResourceGroup -Name $ResourceGroupName -Force
        Write-Host "  -> Removed" -ForegroundColor Green
    }
}
catch {
    Write-Host "  -> [ERROR] $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
```

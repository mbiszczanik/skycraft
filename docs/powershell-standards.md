# SkyCraft PowerShell Standards

> **Source of Truth** for automation and deployment script development.

This document outlines the strict coding conventions for PowerShell scripts in the SkyCraft project. All automation must adhere to these standards to ensure readability, consistent user experience, and robust error handling.

---

## 1. File Structure & Header (Comment-Based Help)

Every PowerShell script must start with a standardized **Comment-Based Help (CBH)** block. This enables the use of `Get-Help` and provides immediate context.

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

[CmdletBinding()]
param(...)
```

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

## 3. User Interface & Output

We use a standardized color scheme for `Write-Host` to provide a premium and consistent CLI experience.

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

1. Use `try...catch` for all Azure cmdlets.
2. Use `-ErrorAction SilentlyContinue` if manually checking existence.
3. Use `-ErrorAction Stop` when a failure should trigger the `catch` block for retries or termination.

```powershell
try {
    Remove-AzResource -Name "Example" -Force -ErrorAction Stop
}
catch {
    Write-Host "  -> [ERROR] Failed to remove resource" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
}
```

## 5. Best Practices

- **Interactive Prompts**: Always use a confirmation prompt for destructive actions (Cleanup) unless the `-Force` switch is used.
- **Retry Logic**: Implement retry loops for "stubborn" Azure resources (like NSGs) that suffer from eventual consistency delays.
- **Dependencies First**: Dissociate resources (e.g., NSG from Subnet) before attempting deletion.
- **No Hardcoding**: Default parameter values are acceptable, but hardcoded strings inside logic are discouraged.

---

## 6. Script Boilerplate

```powershell
<#
.SYNOPSIS
    [Summary]
.DESCRIPTION
    [Detailed Description]
.NOTES
    Project: SkyCraft
    Date: [Current Date]
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$Location = 'swedencentral'
)

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
}
```

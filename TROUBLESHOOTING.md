# Troubleshooting Guide

This guide addresses common issues encountered while setting up or running the SkyCraft labs.

## 🔑 Identity & Authorization Issues

### "Tenant Mismatch" Error

**Symptoms**: You receive a `Status: 400 (BadRequest)` when attempting to assign roles (e.g., in Lab 1.2 scripts).
**Cause**: The Azure Subscription you are using is linked to a different Microsoft Entra ID tenant than the one where your User identities reside.
**Solution**:

1.  **Verify Tenants**: Run `Get-AzContext` to see your current TenantId. Run `Get-MgContext` to see your Graph TenantId. They must match.
2.  **Switch Context**: Use `Connect-AzAccount -TenantId <TargetTenantId>` to switch your subscription context if possible.
3.  **Cross-Tenant Setup**: If using a separate subscription (e.g., MSDN) and a separate Entra ID (e.g., Developer Program), you must add the "Service Principal" or "User" as a B2B Guest in the subscription's tenant to verify role assignments.

### "Insufficient Privileges" for Graph

**Symptoms**: Scripts dealing with Entra ID Users/Groups fail with "Insufficient privileges to complete the operation".
**Solution**:

1.  Ensure you have the **User Administrator** or **Global Administrator** role in Entra ID.
2.  Ensure you have granted consent to the Microsoft Graph PowerShell application.

## 💻 Environment Issues

### "The term 'az' is not recognized" or "The term 'bicep' is not recognized"

**Cause**: Azure CLI or Bicep is not installed or not in your system PATH.
**Solution**:

1.  Install the latest **Azure CLI** (v2.40+ recommended).
2.  Install **Bicep CLI**.
3.  Restart your terminal/VS Code reliability.

## ☁️ Deployment Errors

### "QuotaExceeded"

**Symptoms**: Deployment fails stating you have exceeded the quota for vCPUs or Public IPs.
**Solution**:

1.  Check your usage in the "Usage + quotas" blade of your Subscription.
2.  Request a quota increase or delete unused resources from other projects.
3.  Note: Free Trial subscriptions have strict limits (often 4 vCPUs) which may limit simultaneous lab deployments.

### "Public IP Address is not available"

**Cause**: Specific regions (like Sweden Central) may have temporary capacity issues for Standard Public IPs.
**Solution**:

1.  Try deploying to a different region (update your local parameter file).
2.  Wait and retry later.

/*=====================================================
SUMMARY: Key Vault Module
DESCRIPTION: Deploys Azure Key Vault for disk encryption keys
AUTHOR/S: Marcin Biszczanik
VERSION: 1.0.0
DEPLOYMENT: Internal use via Orchestrator
======================================================*/

// ============================================================================
// PARAMETERS
// ============================================================================

@description('Name of the Key Vault (must be globally unique)')
@minLength(3)
@maxLength(24)
param parKeyVaultName string

@description('Azure region for deployment')
param parLocation string = resourceGroup().location

@description('Enable Key Vault for Azure Disk Encryption')
param parEnabledForDiskEncryption bool = true

@description('Enable Key Vault for VM deployment (secrets retrieval)')
param parEnabledForDeployment bool = true

@description('Enable Key Vault for template deployment')
param parEnabledForTemplateDeployment bool = true

@description('Key Vault SKU')
@allowed(['standard', 'premium'])
param parSku string = 'standard'

@description('Enable soft delete for Key Vault')
param parEnableSoftDelete bool = true

@description('Soft delete retention period in days')
@minValue(7)
@maxValue(90)
param parSoftDeleteRetentionInDays int = 90

@description('Enable purge protection (prevents permanent deletion)')
param parEnablePurgeProtection bool = true

@description('Resource tags')
param parTags object

// ============================================================================
// VARIABLES
// ============================================================================

var varTenantId = subscription().tenantId

// ============================================================================
// RESOURCES
// ============================================================================

resource resKeyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: parKeyVaultName
  location: parLocation
  tags: parTags
  properties: {
    tenantId: varTenantId
    sku: {
      family: 'A'
      name: parSku
    }
    enabledForDeployment: parEnabledForDeployment
    enabledForDiskEncryption: parEnabledForDiskEncryption
    enabledForTemplateDeployment: parEnabledForTemplateDeployment
    enableSoftDelete: parEnableSoftDelete
    softDeleteRetentionInDays: parSoftDeleteRetentionInDays
    enablePurgeProtection: parEnablePurgeProtection
    enableRbacAuthorization: true
    publicNetworkAccess: 'Enabled'
    networkAcls: {
      defaultAction: 'Allow'
      bypass: 'AzureServices'
    }
  }
}

// ============================================================================
// OUTPUTS
// ============================================================================

output outKeyVaultId string = resKeyVault.id
output outKeyVaultName string = resKeyVault.name
output outKeyVaultUri string = resKeyVault.properties.vaultUri

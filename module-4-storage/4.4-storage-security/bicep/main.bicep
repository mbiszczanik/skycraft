/*=====================================================
SUMMARY: Lab 4.4 - Storage Security - Orchestrator
DESCRIPTION: Locks a SkyCraft storage account down via the Azure Verified Module for storage accounts - firewall default action Deny, a virtual network rule for the lab subnet, an optional client IP rule, and the dev-assets container used for SAS and RBAC testing
EXAMPLE: .\scripts\Deploy-Bicep.ps1 -Environment prod
AUTHOR/S: Marcin Biszczanik
VERSION: 2.0.0
DEPLOYMENT: .\scripts\Deploy-Bicep.ps1
======================================================*/

targetScope = 'subscription'

/*******************
*    Parameters    *
*******************/

@description('Location for all resources')
@allowed(['swedencentral', 'northeurope'])
param parLocation string = 'swedencentral'

// platform is deliberately excluded: this lab allows a workload subnet through the storage
// firewall, and the hub VNet has only AzureBastionSubnet and GatewaySubnet.
@description('Target environment')
@allowed(['dev', 'prod'])
param parEnvironment string = 'prod'

@description('Resource owner tag value')
@minLength(1)
param parOwner string = 'mbiszczanik'

@description('Subnet allowed through the storage firewall (must carry the Microsoft.Storage service endpoint from Lab 2.2)')
@minLength(1)
@maxLength(80)
param parSubnetName string = 'WorldSubnet'

@description('Client IP address allowed through the storage firewall. Leave empty to add no IP rule.')
param parClientIp string = ''

@description('Blob soft delete retention days (baseline from Lab 4.1)')
@minValue(1)
@maxValue(365)
param parBlobSoftDeleteDays int = 7

@description('Container soft delete retention days (baseline from Lab 4.1)')
@minValue(1)
@maxValue(365)
param parContainerSoftDeleteDays int = 7

/*******************
*    Variables     *
*******************/

var varEnvironmentTags = {
  dev: 'Development'
  prod: 'Production'
}

var varCommonTags = {
  Project: 'SkyCraft'
  Environment: varEnvironmentTags[parEnvironment]
  CostCenter: 'MSDN'
  Owner: parOwner
}

var varSkuNames = {
  dev: 'Standard_LRS'
  prod: 'Standard_GRS'
}

var varResourceGroupName = '${parEnvironment}-skycraft-swc-rg'

// This lab has to pass blobServices to create dev-assets, and a non-empty blobServices replaces
// the whole blob service configuration - so it restates what Labs 4.1 and 4.2 set for this
// environment (standards section 4.5 note on cumulative labs).
var varVersioningEnabled = {
  dev: false
  prod: true
}

var varContainersByEnvironment = {
  dev: [
    { name: 'public-demo', publicAccess: 'None' }
  ]
  prod: [
    { name: 'game-assets', publicAccess: 'None' }
    { name: 'player-backups', publicAccess: 'None' }
    { name: 'server-config', publicAccess: 'None' }
    { name: 'game-logs', publicAccess: 'None' }
  ]
}

// dev-assets is this lab's own container - the target for the SAS and RBAC exercises
var varContainers = concat(varContainersByEnvironment[parEnvironment], [
  { name: 'dev-assets', publicAccess: 'None' }
])

/*******************
*     Existing     *
*******************/

resource resVnet 'Microsoft.Network/virtualNetworks@2024-05-01' existing = {
  name: '${parEnvironment}-skycraft-swc-vnet'
  scope: resourceGroup(varResourceGroupName)

  resource resSubnet 'subnets' existing = {
    name: parSubnetName
  }
}

/*******************
*     Modules      *
*******************/

module modStorage 'br/public:avm/res/storage/storage-account:0.33.0' = {
  name: 'sa-deployment-security'
  scope: resourceGroup(varResourceGroupName)
  params: {
    name: '${parEnvironment}skycraftswcsa'
    location: parLocation
    tags: varCommonTags
    skuName: varSkuNames[parEnvironment]
    kind: 'StorageV2'
    accessTier: 'Hot'
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
    allowBlobPublicAccess: false
    allowSharedKeyAccess: true
    publicNetworkAccess: 'Enabled'
    requireInfrastructureEncryption: false
    // This is the lab that locks the account down - the one place where Deny is intentional
    networkAcls: {
      bypass: 'AzureServices'
      defaultAction: 'Deny'
      virtualNetworkRules: [
        {
          id: resVnet::resSubnet.id
          action: 'Allow'
        }
      ]
      ipRules: empty(parClientIp) ? [] : [
        {
          value: parClientIp
          action: 'Allow'
        }
      ]
    }
    blobServices: {
      deleteRetentionPolicyEnabled: true
      deleteRetentionPolicyDays: parBlobSoftDeleteDays
      containerDeleteRetentionPolicyEnabled: true
      containerDeleteRetentionPolicyDays: parContainerSoftDeleteDays
      isVersioningEnabled: varVersioningEnabled[parEnvironment]
      changeFeedEnabled: false
      containers: varContainers
    }
  }
}

/******************
*     Outputs     *
******************/

@description('Resource ID of the secured storage account')
output outStorageAccountId string = modStorage.outputs.resourceId

@description('Container created for the SAS and RBAC exercises')
output outContainerName string = 'dev-assets'

@description('Firewall default action applied by this lab')
output outFirewallDefaultAction string = 'Deny'

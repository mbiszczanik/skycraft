/*=====================================================
SUMMARY: Module 4.4 - Storage Security
DESCRIPTION: Configures storage account network security (firewall, VNet rules,
             service endpoint) and creates the dev-assets container
             for SAS and RBAC testing.
AUTHOR/S: SkyCraft
VERSION: 1.0.0
DEPLOYMENT: [Internal use via Orchestrator]
======================================================*/

/*******************
*    Parameters    *
*******************/
@description('Location for resources')
param parLocation string



@description('Tags to apply to resources')
param parTags object

@description('Name of the existing storage account to secure')
param parStorageAccountName string

@description('VNet name for service endpoint integration')
param parVnetName string

@description('Subnet name to allow through the firewall')
param parSubnetName string = 'WorldSubnet'

@description('Client IP address to allow through the firewall (CIDR notation)')
param parClientIp string = ''

/*******************
*    Variables     *
*******************/
var varContainerName = 'dev-assets'

/*******************
*    Resources     *
*******************/

// Reference existing storage account
resource resStorageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' existing = {
  name: parStorageAccountName
}

// Reference existing VNet and Subnet
resource resVnet 'Microsoft.Network/virtualNetworks@2023-11-01' existing = {
  name: parVnetName
}

resource resSubnet 'Microsoft.Network/virtualNetworks/subnets@2023-11-01' existing = {
  parent: resVnet
  name: parSubnetName
}

// Configure storage account networking (firewall + VNet rule)
resource resStorageNetworkRules 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: resStorageAccount.name
  location: parLocation
  tags: parTags
  kind: 'StorageV2'
  sku: {
    name: 'Standard_GRS'
  }
  properties: {
    networkAcls: {
      bypass: 'AzureServices'
      defaultAction: 'Deny'
      virtualNetworkRules: [
        {
          id: resSubnet.id
          action: 'Allow'
        }
      ]
      ipRules: parClientIp != '' ? [
        {
          value: parClientIp
          action: 'Allow'
        }
      ] : []
    }
  }
}

// Create blob service and dev-assets container
resource resBlobService 'Microsoft.Storage/storageAccounts/blobServices@2023-01-01' existing = {
  parent: resStorageAccount
  name: 'default'
}

resource resDevAssetsContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = {
  parent: resBlobService
  name: varContainerName
  properties: {
    publicAccess: 'None'
  }
}

/******************
*     Outputs     *
******************/
output outStorageAccountId string = resStorageAccount.id
output outContainerName string = resDevAssetsContainer.name
output outFirewallDefaultAction string = 'Deny'

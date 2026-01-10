/*=====================================================
SUMMARY: Lab 3.1 - Compute Infrastructure
DESCRIPTION: Orchestrates the deployment of SkyCraft Linux VMs.
EXAMPLE: az deployment sub create --location swedencentral --template-file main.bicep
AUTHOR/S: Marcin Biszczanik
VERSION: 0.1.0
======================================================*/

targetScope = 'subscription'

/*******************
*    Parameters    *
*******************/
@description('Location for all resources')
param parLocation string = 'swedencentral'

@description('Production Resource Group Name')
param parResourceGroupNameProd string = 'prod-skycraft-swc-rg'

@description('Admin Username for all VMs')
param parAdminUsername string = 'skycraftadmin'

@description('SSH Public Key for all VMs')
@secure()
param parAdminPublicKey string

@description('VM Size for all VMs')
param parVmSize string = 'Standard_B2s'

/*******************
*    Variables     *
*******************/
var varVnetProdName = 'prod-skycraft-swc-vnet'
var varAuthVmName = 'auth-skycraft-swc-vm'
var varWorldVmName = 'world-skycraft-swc-vm'

/*******************
*    Resources     *
*******************/

// Reference Existing Prod VNet to get Subnet IDs
resource resRgProd 'Microsoft.Resources/resourceGroups@2024-03-01' existing = {
  name: parResourceGroupNameProd
}

module modVnetProd 'modules/existing-vnet.bicep' = {
  name: 'get-existing-vnet'
  scope: resRgProd
  params: {
    parVnetName: varVnetProdName
  }
}

// Deploy Auth Server (Zone 1)
module modAuthServer 'modules/vm-linux.bicep' = {
  name: 'deploy-auth-server'
  scope: resRgProd
  params: {
    parLocation: parLocation
    parVmName: varAuthVmName
    parVmSize: parVmSize
    parAdminUsername: parAdminUsername
    parAdminPublicKey: parAdminPublicKey
    parSubnetId: modVnetProd.outputs.outAuthSubnetIdSafe
    parAvailabilityZone: '1'
    parTags: {
      Project: 'SkyCraft'
      Environment: 'Production'
      Tier: 'Auth'
      CostCenter: 'MSDN'
    }
  }
}

// Deploy World Server (Zone 2)
module modWorldServer 'modules/vm-linux.bicep' = {
  name: 'deploy-world-server'
  scope: resRgProd
  params: {
    parLocation: parLocation
    parVmName: varWorldVmName
    parVmSize: parVmSize
    parAdminUsername: parAdminUsername
    parAdminPublicKey: parAdminPublicKey
    parSubnetId: modVnetProd.outputs.outWorldSubnetIdSafe
    parAvailabilityZone: '2'
    parTags: {
      Project: 'SkyCraft'
      Environment: 'Production'
      Tier: 'World'
      CostCenter: 'MSDN'
    }
  }
}

/******************
*     Outputs     *
******************/
output outAuthVmPrivateIp string = modAuthServer.outputs.outPrivateIp
output outWorldVmPrivateIp string = modWorldServer.outputs.outPrivateIp

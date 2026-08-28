/*=====================================================
SUMMARY: Lab 3.1 - Infrastructure as Code Orchestrator
DESCRIPTION: Orchestrates SkyCraft Lab 3.1 (resource groups, hub and dev VNets, NSGs, public IP, load balancer) with hand-written local modules - writing them is this lab's learning objective (docs/bicep-standards.md section 8.2)
EXAMPLE: az deployment sub create --location swedencentral --template-file main.bicep --parameters parameters/dev.bicepparam
AUTHOR/S: Marcin Biszczanik
VERSION: 1.1.0
DEPLOYMENT: .\scripts\Deploy-Bicep.ps1
======================================================*/

targetScope = 'subscription'

/*******************
*    Parameters    *
*******************/

@description('Azure region for resource deployment')
@allowed(['swedencentral', 'northeurope'])
param parLocation string = 'swedencentral'

@description('Environment selected by the parameter file (the lab builds the dev spoke; prod receives only its resource group)')
@allowed(['dev', 'prod'])
param parEnvironment string

@description('Project name used in resource names (lowercase)')
@minLength(2)
@maxLength(12)
param parProject string = 'skycraft'

@description('Resource owner tag value')
@minLength(1)
param parOwner string = 'mbiszczanik'

@description('Hub VNet address space')
param parHubVnetAddressPrefix string = '10.0.0.0/16'

@description('Dev VNet address space')
param parDevVnetAddressPrefix string = '10.1.0.0/16'

@description('Prod VNet address space (reserved here; the prod spoke is built in Lab 2.1)')
param parProdVnetAddressPrefix string = '10.2.0.0/16'

/*******************
*    Variables     *
*******************/

var varLocationShortCode = 'swc' // Sweden Central

// Canonical tag set (docs/bicep-standards.md section 5); Environment is added per resource group.
var varCommonTags = {
  Project: 'SkyCraft'
  CostCenter: 'MSDN'
  Owner: parOwner
}
var varTagsPlatform = union(varCommonTags, { Environment: 'Platform' })
var varTagsDev = union(varCommonTags, { Environment: 'Development' })
var varTagsProd = union(varCommonTags, { Environment: 'Production' })

// Resource group and name prefixes
var varPlatformRgName = 'platform-${parProject}-${varLocationShortCode}-rg'
var varDevRgName = 'dev-${parProject}-${varLocationShortCode}-rg'
var varProdRgName = 'prod-${parProject}-${varLocationShortCode}-rg'
var varPlatformPrefix = 'platform-${parProject}-${varLocationShortCode}'
var varDevPrefix = 'dev-${parProject}-${varLocationShortCode}'

/*******************
*    Resources     *
*******************/

// Resource groups are raw resources here on purpose: Lab 3.1 teaches what a module contains.
resource resPlatformRg 'Microsoft.Resources/resourceGroups@2023-07-01' = {
  name: varPlatformRgName
  location: parLocation
  tags: varTagsPlatform
}

resource resDevRg 'Microsoft.Resources/resourceGroups@2023-07-01' = {
  name: varDevRgName
  location: parLocation
  tags: varTagsDev
}

resource resProdRg 'Microsoft.Resources/resourceGroups@2023-07-01' = {
  name: varProdRgName
  location: parLocation
  tags: varTagsProd
}

/*******************
*     Modules      *
*******************/

// Network security groups (dev environment)
module modDevAuthNsg 'modules/nsg.bicep' = {
  name: 'devAuthNsgDeployment'
  scope: resDevRg
  params: {
    parNsgName: 'auth-nsg'
    parLocation: parLocation
    parTags: varTagsDev
    parSecurityRules: [
      {
        name: 'AllowBastionSSH'
        protocol: 'Tcp'
        sourcePortRange: '*'
        destinationPortRange: '22'
        sourceAddressPrefix: '10.0.0.0/26'
        destinationAddressPrefix: '*'
        access: 'Allow'
        priority: 100
        direction: 'Inbound'
      }
      {
        name: 'AllowAuthPort'
        protocol: 'Tcp'
        sourcePortRange: '*'
        destinationPortRange: '3724'
        sourceAddressPrefix: '*'
        destinationAddressPrefix: '*'
        access: 'Allow'
        priority: 110
        direction: 'Inbound'
      }
    ]
  }
}

module modDevWorldNsg 'modules/nsg.bicep' = {
  name: 'devWorldNsgDeployment'
  scope: resDevRg
  params: {
    parNsgName: 'world-nsg'
    parLocation: parLocation
    parTags: varTagsDev
    parSecurityRules: [
      {
        name: 'AllowBastionSSH'
        protocol: 'Tcp'
        sourcePortRange: '*'
        destinationPortRange: '22'
        sourceAddressPrefix: '10.0.0.0/26'
        destinationAddressPrefix: '*'
        access: 'Allow'
        priority: 100
        direction: 'Inbound'
      }
      {
        name: 'AllowWorldPort'
        protocol: 'Tcp'
        sourcePortRange: '*'
        destinationPortRange: '8085'
        sourceAddressPrefix: '*'
        destinationAddressPrefix: '*'
        access: 'Allow'
        priority: 110
        direction: 'Inbound'
      }
    ]
  }
}

// Virtual networks
module modHubVnet 'modules/network.bicep' = {
  name: 'hubVnetDeployment'
  scope: resPlatformRg
  params: {
    parNamePrefix: varPlatformPrefix
    parLocation: parLocation
    parVnetAddressPrefix: parHubVnetAddressPrefix
    // Same subnet layout as the Lab 2.1 hub, so re-running this lab after Module 2 changes nothing.
    parSubnets: [
      {
        name: 'AzureBastionSubnet'
        addressPrefix: '10.0.0.0/26'
      }
      {
        name: 'GatewaySubnet'
        addressPrefix: '10.0.1.0/27'
      }
    ]
    parTags: varTagsPlatform
  }
}

module modDevVnet 'modules/network.bicep' = {
  name: 'devVnetDeployment'
  scope: resDevRg
  params: {
    parNamePrefix: varDevPrefix
    parLocation: parLocation
    parVnetAddressPrefix: parDevVnetAddressPrefix
    parSubnets: [
      {
        name: 'AuthSubnet'
        addressPrefix: '10.1.1.0/24'
        nsgId: modDevAuthNsg.outputs.outNsgId
      }
      {
        name: 'WorldSubnet'
        addressPrefix: '10.1.2.0/24'
        nsgId: modDevWorldNsg.outputs.outNsgId
      }
      {
        name: 'DatabaseSubnet'
        addressPrefix: '10.1.3.0/24'
      }
      {
        // Kept in sync with Lab 2.1's dev VNet so re-deploying 3.1 does not drop
        // the App Service delegated subnet that Lab 3.4 integrates with.
        name: 'AppServiceSubnet'
        addressPrefix: '10.1.4.0/24'
        delegation: 'Microsoft.Web/serverFarms'
      }
    ]
    parTags: varTagsDev
  }
}

// Public IP address
module modDevLbPublicIp 'modules/publicip.bicep' = {
  name: 'devLbPublicIpDeployment'
  scope: resDevRg
  params: {
    parPublicIpName: '${varDevPrefix}-lb-pip'
    parLocation: parLocation
    parSku: 'Standard'
    parAllocationMethod: 'Static'
    parTags: varTagsDev
  }
}

// Load balancer
module modDevLoadBalancer 'modules/loadbalancer.bicep' = {
  name: 'devLoadBalancerDeployment'
  scope: resDevRg
  params: {
    parNamePrefix: varDevPrefix
    parLocation: parLocation
    parPublicIpId: modDevLbPublicIp.outputs.outPublicIpId
    parBackendPools: [
      { name: '${varDevPrefix}-lb-be-world' }
      { name: '${varDevPrefix}-lb-be-auth' }
    ]
    parHealthProbes: [
      {
        name: '${varDevPrefix}-lb-probe-world'
        protocol: 'Tcp'
        port: 8085
        intervalInSeconds: 15
        numberOfProbes: 2
      }
      {
        name: '${varDevPrefix}-lb-probe-auth'
        protocol: 'Tcp'
        port: 3724
        intervalInSeconds: 15
        numberOfProbes: 2
      }
    ]
    parLbRules: [
      {
        name: '${varDevPrefix}-lb-rule-world'
        protocol: 'Tcp'
        frontendPort: 8085
        backendPort: 8085
        backendPoolName: '${varDevPrefix}-lb-be-world'
        probeName: '${varDevPrefix}-lb-probe-world'
      }
      {
        name: '${varDevPrefix}-lb-rule-auth'
        protocol: 'Tcp'
        frontendPort: 3724
        backendPort: 3724
        backendPoolName: '${varDevPrefix}-lb-be-auth'
        probeName: '${varDevPrefix}-lb-probe-auth'
      }
    ]
    parTags: varTagsDev
  }
}

/******************
*     Outputs     *
******************/

output outPlatformResourceGroupName string = resPlatformRg.name
output outDevResourceGroupName string = resDevRg.name
output outProdResourceGroupName string = resProdRg.name

output outHubVnetId string = modHubVnet.outputs.outVnetId
output outDevVnetId string = modDevVnet.outputs.outVnetId

output outDevLoadBalancerId string = modDevLoadBalancer.outputs.outLoadBalancerId
output outDevLoadBalancerPublicIp string = modDevLbPublicIp.outputs.outIpAddress

// Configuration echo (also keeps the parameter-file-only inputs referenced; no-unused-params is an error)
output outConfigProdVnetPrefix string = parProdVnetAddressPrefix
output outConfigEnvironment string = parEnvironment

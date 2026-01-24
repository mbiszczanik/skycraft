/*=====================================================
SUMMARY: Lab 3.1 - Infrastructure as Code Orchestrator
DESCRIPTION: Orchestrates deployment for SkyCraft Lab 3.1 (VNets, NSGs, LBs)
EXAMPLE: az deployment sub create --location swedencentral --template-file main.bicep
AUTHOR/S: Marcin Biszczanik
VERSION: 1.0.0
DEPLOYMENT: .\scripts\Deploy-Bicep.ps1
======================================================*/

targetScope = 'subscription'

// ============================================================================
// PARAMETERS
// ============================================================================

@description('Azure region for resource deployment')
@allowed(['swedencentral', 'westeurope', 'northeurope'])
param parLocation string = 'swedencentral'

@description('Environment name')
@allowed(['dev', 'prod'])
param parEnvironment string

@description('Project name for resource naming')
param parProject string = 'skycraft'

@description('Service/workload name')
param parService string = 'swc'

@description('Cost center for billing')
param parCostCenter string = 'MSDN'

@description('Hub VNet address space')
param parHubVnetAddressPrefix string = '10.0.0.0/16'

@description('Dev VNet address space')
param parDevVnetAddressPrefix string = '10.1.0.0/16'

@description('Prod VNet address space')
param parProdVnetAddressPrefix string = '10.2.0.0/16'


@description('Deployment date string (auto-generated)')
param parCurrentDate string = utcNow('yyyy-MM-dd')

// ============================================================================
// VARIABLES
// ============================================================================

var varLocationShortCode = 'swc'  // Sweden Central
var varCommonTags = {
  Project: parProject
  Service: parService
  CostCenter: parCostCenter
  ManagedBy: 'Bicep'
  DeploymentDate: parCurrentDate
}

// Resource group names
var varPlatformRgName = 'platform-${parProject}-${varLocationShortCode}-rg'
var varDevRgName = 'dev-${parProject}-${varLocationShortCode}-rg'
var varProdRgName = 'prod-${parProject}-${varLocationShortCode}-rg'

// ============================================================================
// RESOURCE GROUPS
// ============================================================================

resource resPlatformRg 'Microsoft.Resources/resourceGroups@2023-07-01' = {
  name: varPlatformRgName
  location: parLocation
  tags: union(varCommonTags, {
    Environment: 'Platform'
  })
}

resource resDevRg 'Microsoft.Resources/resourceGroups@2023-07-01' = {
  name: varDevRgName
  location: parLocation
  tags: union(varCommonTags, {
    Environment: 'Development'
  })
}

resource resProdRg 'Microsoft.Resources/resourceGroups@2023-07-01' = {
  name: varProdRgName
  location: parLocation
  tags: union(varCommonTags, {
    Environment: 'Production'
  })
}

// ============================================================================
// NETWORK SECURITY GROUPS (Dev Environment)
// ============================================================================

module modDevAuthNsg 'modules/nsg.bicep' = {
  name: 'devAuthNsgDeployment'
  scope: resDevRg
  params: {
    nsgName: 'auth-nsg'
    location: parLocation
    tags: union(varCommonTags, { Environment: 'Development', Purpose: 'AuthServers' })
    securityRules: [
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
    nsgName: 'world-nsg'
    location: parLocation
    tags: union(varCommonTags, { Environment: 'Development', Purpose: 'WorldServers' })
    securityRules: [
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

// ============================================================================
// VIRTUAL NETWORKS
// ============================================================================

module modHubVnet 'modules/network.bicep' = {
  name: 'hubVnetDeployment'
  scope: resPlatformRg
  params: {
    namePrefix: 'platform-${parProject}-${varLocationShortCode}'
    location: parLocation
    environment: 'platform'
    vnetAddressPrefix: parHubVnetAddressPrefix
    subnets: [
      {
        name: 'AzureBastionSubnet'
        addressPrefix: '10.0.0.0/26'
      }
    ]
    tags: union(varCommonTags, { Environment: 'Platform', Purpose: 'HubNetwork' })
  }
}

module modDevVnet 'modules/network.bicep' = {
  name: 'devVnetDeployment'
  scope: resDevRg
  // dependencies inferred by Bicep from output references
  params: {
    namePrefix: 'dev-${parProject}-${varLocationShortCode}'
    location: parLocation
    environment: 'dev'
    vnetAddressPrefix: parDevVnetAddressPrefix
    subnets: [
      {
        name: 'AuthSubnet'
        addressPrefix: '10.1.1.0/24'
        nsgId: modDevAuthNsg.outputs.nsgId
      }
      {
        name: 'WorldSubnet'
        addressPrefix: '10.1.2.0/24'
        nsgId: modDevWorldNsg.outputs.nsgId
      }
      {
        name: 'DatabaseSubnet'
        addressPrefix: '10.1.3.0/24'
      }
    ]
    tags: union(varCommonTags, { Environment: 'Development' })
  }
}

// ============================================================================
// PUBLIC IP ADDRESSES
// ============================================================================

module modDevLbPublicIp 'modules/publicip.bicep' = {
  name: 'devLbPublicIpDeployment'
  scope: resDevRg
  params: {
    publicIpName: 'dev-${parProject}-${varLocationShortCode}-lb-pip'
    location: parLocation
    sku: 'Standard'
    allocationMethod: 'Static'
    tags: union(varCommonTags, { Environment: 'Development', Purpose: 'LoadBalancer' })
  }
}

// ============================================================================
// LOAD BALANCERS
// ============================================================================

module modDevLoadBalancer 'modules/loadbalancer.bicep' = {
  name: 'devLoadBalancerDeployment'
  scope: resDevRg
  params: {
    namePrefix: 'dev-${parProject}-${varLocationShortCode}'
    location: parLocation
    publicIpId: modDevLbPublicIp.outputs.publicIpId
    backendPools: [
      { name: 'dev-${parProject}-${varLocationShortCode}-lb-be-world' }
      { name: 'dev-${parProject}-${varLocationShortCode}-lb-be-auth' }
    ]
    healthProbes: [
      {
        name: 'dev-${parProject}-${varLocationShortCode}-lb-probe-world'
        protocol: 'Tcp'
        port: 8085
        intervalInSeconds: 15
        numberOfProbes: 2
      }
      {
        name: 'dev-${parProject}-${varLocationShortCode}-lb-probe-auth'
        protocol: 'Tcp'
        port: 3724
        intervalInSeconds: 15
        numberOfProbes: 2
      }
    ]
    lbRules: [
      {
        name: 'dev-${parProject}-${varLocationShortCode}-lb-rule-world'
        protocol: 'Tcp'
        frontendPort: 8085
        backendPort: 8085
        backendPoolName: 'dev-${parProject}-${varLocationShortCode}-lb-be-world'
        probeName: 'dev-${parProject}-${varLocationShortCode}-lb-probe-world'
      }
      {
        name: 'dev-${parProject}-${varLocationShortCode}-lb-rule-auth'
        protocol: 'Tcp'
        frontendPort: 3724
        backendPort: 3724
        backendPoolName: 'dev-${parProject}-${varLocationShortCode}-lb-be-auth'
        probeName: 'dev-${parProject}-${varLocationShortCode}-lb-probe-auth'
      }
    ]
    tags: union(varCommonTags, { Environment: 'Development' })
  }
}

// ============================================================================
// OUTPUTS
// ============================================================================

output outPlatformResourceGroupName string = resPlatformRg.name
output outDevResourceGroupName string = resDevRg.name
output outProdResourceGroupName string = resProdRg.name

output outHubVnetId string = modHubVnet.outputs.vnetId
output outDevVnetId string = modDevVnet.outputs.vnetId

output outDevLoadBalancerId string = modDevLoadBalancer.outputs.loadBalancerId
output outDevLoadBalancerPublicIp string = modDevLbPublicIp.outputs.ipAddress

// Outputs to silence "Unused Parameter" warnings and expose config
// output configVmSize string - Removed
output outConfigProdVnetPrefix string = parProdVnetAddressPrefix
output outConfigEnvironment string = parEnvironment

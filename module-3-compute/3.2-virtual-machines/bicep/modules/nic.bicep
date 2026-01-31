/*=====================================================
SUMMARY: Network Interface Module
DESCRIPTION: Deploys Azure Network Interfaces for VMs
AUTHOR/S: Marcin Biszczanik
VERSION: 1.0.0
DEPLOYMENT: Internal use via Orchestrator
======================================================*/

// ============================================================================
// PARAMETERS
// ============================================================================

@description('Name of the Network Interface')
param parNicName string

@description('Azure region for deployment')
param parLocation string = resourceGroup().location

@description('Subnet resource ID for NIC placement')
param parSubnetId string

@description('Enable accelerated networking (requires compatible VM size)')
param parEnableAcceleratedNetworking bool = false

@description('Load Balancer backend pool IDs to associate (optional)')
param parLoadBalancerBackendPoolIds array = []

@description('Resource tags')
param parTags object

// ============================================================================
// RESOURCES
// ============================================================================

resource resNic 'Microsoft.Network/networkInterfaces@2023-05-01' = {
  name: parNicName
  location: parLocation
  tags: parTags
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          subnet: {
            id: parSubnetId
          }
          loadBalancerBackendAddressPools: [for poolId in parLoadBalancerBackendPoolIds: {
            id: poolId
          }]
        }
      }
    ]
    enableAcceleratedNetworking: parEnableAcceleratedNetworking
  }
}

// ============================================================================
// OUTPUTS
// ============================================================================

output outNicId string = resNic.id
output outNicName string = resNic.name
output outPrivateIpAddress string = resNic.properties.ipConfigurations[0].properties.privateIPAddress

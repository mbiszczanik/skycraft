// modules/loadbalancer.bicep
// Azure Load Balancer module for high availability

@description('Name prefix for load balancer resources')
param namePrefix string

@description('Azure region for deployment')
param location string = resourceGroup().location

@description('Public IP address resource ID')
param publicIpId string

@description('Backend pool configurations')
param backendPools array

@description('Health probe configurations')
param healthProbes array

@description('Load balancing rule configurations')
param lbRules array

@description('Resource tags')
param tags object

// Load Balancer
resource loadBalancer 'Microsoft.Network/loadBalancers@2023-05-01' = {
  name: '${namePrefix}-lb'
  location: location
  tags: tags
  sku: {
    name: 'Standard'
    tier: 'Regional'
  }
  properties: {
    frontendIPConfigurations: [
      {
        name: '${namePrefix}-lb-frontend'
        properties: {
          publicIPAddress: {
            id: publicIpId
          }
        }
      }
    ]
    backendAddressPools: [for pool in backendPools: {
      name: pool.name
    }]
    probes: [for probe in healthProbes: {
      name: probe.name
      properties: {
        protocol: probe.protocol
        port: probe.port
        intervalInSeconds: probe.intervalInSeconds
        numberOfProbes: probe.numberOfProbes
      }
    }]
    loadBalancingRules: [for (rule, i) in lbRules: {
      name: rule.name
      properties: {
        frontendIPConfiguration: {
          id: resourceId('Microsoft.Network/loadBalancers/frontendIPConfigurations', '${namePrefix}-lb', '${namePrefix}-lb-frontend')
        }
        backendAddressPool: {
          id: resourceId('Microsoft.Network/loadBalancers/backendAddressPools', '${namePrefix}-lb', rule.backendPoolName)
        }
        probe: {
          id: resourceId('Microsoft.Network/loadBalancers/probes', '${namePrefix}-lb', rule.probeName)
        }
        protocol: rule.protocol
        frontendPort: rule.frontendPort
        backendPort: rule.backendPort
        enableFloatingIP: false
        idleTimeoutInMinutes: 4
        loadDistribution: 'Default'
      }
    }]
  }
}

// Outputs
output loadBalancerId string = loadBalancer.id
output loadBalancerName string = loadBalancer.name
output backendPoolIds array = [for (pool, i) in backendPools: {
  name: pool.name
  id: loadBalancer.properties.backendAddressPools[i].id
}]

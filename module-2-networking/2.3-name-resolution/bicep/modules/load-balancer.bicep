/*=====================================================
SUMMARY: Standard Load Balancer Module
DESCRIPTION: Deploys a Standard Public LB with Backend Pools, Probes, and Rules.
AUTHOR/S: Marcin Biszczanik
VERSION: 0.1.0
DEPLOYMENT: Internal Module
=====================================================*/

// ===================================
// Parameters
// ===================================

@description('The name of the Load Balancer.')
param parLbName string

@description('The location for the Load Balancer.')
param parLocation string

@description('The tags for the Load Balancer.')
param parTags object = {}

@description('The name of the existing Public IP address.')
param parPublicIpName string

// ===================================
// Variables
// ===================================

var varFrontendName = '${parLbName}-frontend'
var varBackendPoolWorldName = '${parLbName}-be-world'
var varBackendPoolAuthName = '${parLbName}-be-auth'
var varProbeWorldName = '${parLbName}-probe-world'
var varProbeAuthName = '${parLbName}-probe-auth'
var varRuleWorldName = '${parLbName}-rule-world'
var varRuleAuthName = '${parLbName}-rule-auth'

// ===================================
// Resources
// ===================================

resource resLoadBalancer 'Microsoft.Network/loadBalancers@2023-04-01' = {
  name: parLbName
  location: parLocation
  tags: parTags
  sku: {
    name: 'Standard'
    tier: 'Regional'
  }
  properties: {
    frontendIPConfigurations: [
      {
        name: varFrontendName
        properties: {
          publicIPAddress: {
            id: resourceId('Microsoft.Network/publicIPAddresses', parPublicIpName)
          }
        }
      }
    ]
    backendAddressPools: [
      {
        name: varBackendPoolWorldName
      }
      {
        name: varBackendPoolAuthName
      }
    ]
    probes: [
      {
        name: varProbeWorldName
        properties: {
          protocol: 'Tcp'
          port: 8085
          intervalInSeconds: 15
          numberOfProbes: 2
        }
      }
      {
        name: varProbeAuthName
        properties: {
          protocol: 'Tcp'
          port: 3724
          intervalInSeconds: 15
          numberOfProbes: 2
        }
      }
    ]
    loadBalancingRules: [
      {
        name: varRuleWorldName
        properties: {
          frontendIPConfiguration: {
            id: resourceId('Microsoft.Network/loadBalancers/frontendIPConfigurations', parLbName, varFrontendName)
          }
          backendAddressPool: {
            id: resourceId('Microsoft.Network/loadBalancers/backendAddressPools', parLbName, varBackendPoolWorldName)
          }
          probe: {
            id: resourceId('Microsoft.Network/loadBalancers/probes', parLbName, varProbeWorldName)
          }
          protocol: 'Tcp'
          frontendPort: 8085
          backendPort: 8085
          idleTimeoutInMinutes: 4
          enableTcpReset: true
          loadDistribution: 'Default'
        }
      }
      {
        name: varRuleAuthName
        properties: {
          frontendIPConfiguration: {
            id: resourceId('Microsoft.Network/loadBalancers/frontendIPConfigurations', parLbName, varFrontendName)
          }
          backendAddressPool: {
            id: resourceId('Microsoft.Network/loadBalancers/backendAddressPools', parLbName, varBackendPoolAuthName)
          }
          probe: {
            id: resourceId('Microsoft.Network/loadBalancers/probes', parLbName, varProbeAuthName)
          }
          protocol: 'Tcp'
          frontendPort: 3724
          backendPort: 3724
          idleTimeoutInMinutes: 4
          enableTcpReset: true
          loadDistribution: 'Default'
        }
      }
    ]
  }
}

// ===================================
// Outputs
// ===================================

output outLbId string = resLoadBalancer.id
output outFrontendIpName string = varFrontendName
output outBackendPoolWorldName string = varBackendPoolWorldName
output outBackendPoolAuthName string = varBackendPoolAuthName

/*=====================================================
SUMMARY: Lab 3.1 - Load Balancer Module
DESCRIPTION: Deploys a Standard Azure Load Balancer with configurable backend pools, health probes, and LB rules for SkyCraft Lab 3.1.
AUTHOR/S: Marcin Biszczanik
VERSION: 1.1.0
DEPLOYMENT: [Internal use via Orchestrator]
======================================================*/

/*******************
*    Parameters    *
*******************/
@description('Name prefix for load balancer resources (e.g., dev-skycraft-swc)')
param parNamePrefix string

@description('Azure region for deployment')
param parLocation string = resourceGroup().location

@description('Public IP address resource ID for the frontend')
param parPublicIpId string

@description('Backend pool configurations: [{ name }]')
param parBackendPools array

@description('Health probe configurations: [{ name, protocol, port, intervalInSeconds, numberOfProbes }]')
param parHealthProbes array

@description('Load balancing rule configurations: [{ name, protocol, frontendPort, backendPort, backendPoolName, probeName }]')
param parLbRules array

@description('Resource tags (must include Project, Environment, CostCenter)')
param parTags object

/*******************
*    Variables     *
*******************/
var varLbName = '${parNamePrefix}-lb'
var varFrontendName = '${parNamePrefix}-lb-frontend'

/*******************
*    Resources     *
*******************/
resource resLoadBalancer 'Microsoft.Network/loadBalancers@2023-11-01' = {
  name: varLbName
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
            id: parPublicIpId
          }
        }
      }
    ]
    backendAddressPools: [for pool in parBackendPools: {
      name: pool.name
    }]
    probes: [for probe in parHealthProbes: {
      name: probe.name
      properties: {
        protocol: probe.protocol
        port: probe.port
        intervalInSeconds: probe.intervalInSeconds
        numberOfProbes: probe.numberOfProbes
      }
    }]
    loadBalancingRules: [for rule in parLbRules: {
      name: rule.name
      properties: {
        frontendIPConfiguration: {
          id: resourceId('Microsoft.Network/loadBalancers/frontendIPConfigurations', varLbName, varFrontendName)
        }
        backendAddressPool: {
          id: resourceId('Microsoft.Network/loadBalancers/backendAddressPools', varLbName, rule.backendPoolName)
        }
        probe: {
          id: resourceId('Microsoft.Network/loadBalancers/probes', varLbName, rule.probeName)
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

/******************
*     Outputs     *
******************/
output outLoadBalancerId string = resLoadBalancer.id
output outLoadBalancerName string = resLoadBalancer.name
output outBackendPoolIds array = [for (pool, i) in parBackendPools: {
  name: pool.name
  id: resLoadBalancer.properties.backendAddressPools[i].id
}]

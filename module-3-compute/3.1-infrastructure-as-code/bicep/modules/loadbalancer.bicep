/*=====================================================
SUMMARY: Lab 3.1 - Load Balancer Module
DESCRIPTION: Deploys a Standard Azure Load Balancer with typed backend pools, health probes and load-balancing rules for SkyCraft Lab 3.1.
AUTHOR/S: Marcin Biszczanik
VERSION: 1.2.0
DEPLOYMENT: [Internal use via Orchestrator]
======================================================*/

/*******************
*      Types       *
*******************/

@description('Backend pool definition')
type backendPoolConfig = {
  @description('Backend pool name')
  name: string
}

@description('Health probe definition')
type healthProbeConfig = {
  @description('Probe name')
  name: string

  @description('Probe protocol')
  protocol: 'Tcp' | 'Http' | 'Https'

  @description('Probe port')
  @minValue(1)
  @maxValue(65535)
  port: int

  @description('Seconds between probes')
  @minValue(5)
  @maxValue(2147483646)
  intervalInSeconds: int

  @description('Consecutive failures before the endpoint is marked unhealthy')
  @minValue(1)
  numberOfProbes: int
}

@description('Load-balancing rule definition')
type lbRuleConfig = {
  @description('Rule name')
  name: string

  @description('Transport protocol')
  protocol: 'Tcp' | 'Udp' | 'All'

  @description('Frontend port')
  @minValue(0)
  @maxValue(65534)
  frontendPort: int

  @description('Backend port')
  @minValue(0)
  @maxValue(65535)
  backendPort: int

  @description('Name of the backend pool the rule targets (must exist in parBackendPools)')
  backendPoolName: string

  @description('Name of the health probe the rule uses (must exist in parHealthProbes)')
  probeName: string
}

/*******************
*    Parameters    *
*******************/

@description('Name prefix for load balancer resources (e.g., dev-skycraft-swc)')
@minLength(1)
@maxLength(40)
param parNamePrefix string

@description('Azure region for deployment')
param parLocation string = resourceGroup().location

@description('Public IP address resource ID for the frontend')
param parPublicIpId string

@description('Backend pool configurations')
param parBackendPools backendPoolConfig[]

@description('Health probe configurations')
param parHealthProbes healthProbeConfig[]

@description('Load balancing rule configurations')
param parLbRules lbRuleConfig[]

@description('Resource tags (canonical set: Project, Environment, CostCenter, Owner)')
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
        // Explicit for parity with the Lab 2.3 AVM definition of this load balancer (standards section 4.5):
        // the Module 3 VMs rely on the implicit outbound SNAT through the frontend IP.
        disableOutboundSnat: false
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

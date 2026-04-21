/*=====================================================
SUMMARY: Lab 3.1 - Network Security Group Module
DESCRIPTION: Deploys a Network Security Group with a configurable set of security rules for SkyCraft Lab 3.1.
AUTHOR/S: Marcin Biszczanik
VERSION: 1.1.0
DEPLOYMENT: [Internal use via Orchestrator]
======================================================*/

/*******************
*    Parameters    *
*******************/
@description('Name of the Network Security Group')
param parNsgName string

@description('Azure region for deployment')
param parLocation string = resourceGroup().location

@description('Security rules configuration')
param parSecurityRules array = []

@description('Resource tags (must include Project, Environment, CostCenter)')
param parTags object

/*******************
*    Resources     *
*******************/
resource resNsg 'Microsoft.Network/networkSecurityGroups@2023-11-01' = {
  name: parNsgName
  location: parLocation
  tags: parTags
  properties: {
    securityRules: [for rule in parSecurityRules: {
      name: rule.name
      properties: {
        protocol: rule.protocol
        sourcePortRange: rule.sourcePortRange
        destinationPortRange: rule.destinationPortRange
        sourceAddressPrefix: contains(rule, 'sourceAddressPrefix') ? rule.sourceAddressPrefix : '*'
        destinationAddressPrefix: contains(rule, 'destinationAddressPrefix') ? rule.destinationAddressPrefix : '*'
        access: rule.access
        priority: rule.priority
        direction: rule.direction
      }
    }]
  }
}

/******************
*     Outputs     *
******************/
output outNsgId string = resNsg.id
output outNsgName string = resNsg.name

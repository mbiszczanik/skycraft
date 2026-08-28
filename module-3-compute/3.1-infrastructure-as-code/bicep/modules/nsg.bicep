/*=====================================================
SUMMARY: Lab 3.1 - Network Security Group Module
DESCRIPTION: Deploys a Network Security Group with a typed set of security rules for SkyCraft Lab 3.1.
AUTHOR/S: Marcin Biszczanik
VERSION: 1.2.0
DEPLOYMENT: [Internal use via Orchestrator]
======================================================*/

/*******************
*      Types       *
*******************/

@description('Security rule definition consumed by the NSG resource')
type securityRuleConfig = {
  @description('Rule name')
  name: string

  @description('Network protocol')
  protocol: 'Tcp' | 'Udp' | 'Icmp' | '*'

  @description('Source port or range')
  sourcePortRange: string

  @description('Destination port or range')
  destinationPortRange: string

  @description('Source address prefix (defaults to *)')
  sourceAddressPrefix: string?

  @description('Destination address prefix (defaults to *)')
  destinationAddressPrefix: string?

  @description('Allow or deny')
  access: 'Allow' | 'Deny'

  @description('Rule priority (100-4096, lower is evaluated first)')
  @minValue(100)
  @maxValue(4096)
  priority: int

  @description('Traffic direction')
  direction: 'Inbound' | 'Outbound'
}

/*******************
*    Parameters    *
*******************/

@description('Name of the Network Security Group')
@minLength(1)
@maxLength(80)
param parNsgName string

@description('Azure region for deployment')
param parLocation string = resourceGroup().location

@description('Security rules configuration')
param parSecurityRules securityRuleConfig[] = []

@description('Resource tags (canonical set: Project, Environment, CostCenter, Owner)')
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
        sourceAddressPrefix: rule.?sourceAddressPrefix ?? '*'
        destinationAddressPrefix: rule.?destinationAddressPrefix ?? '*'
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

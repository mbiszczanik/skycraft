// modules/nsg.bicep
// Network Security Group module with configurable rules

@description('Name of the Network Security Group')
param nsgName string

@description('Azure region for deployment')
param location string = resourceGroup().location

@description('Security rules configuration')
param securityRules array = []

@description('Resource tags')
param tags object

// Network Security Group
resource nsg 'Microsoft.Network/networkSecurityGroups@2023-05-01' = {
  name: nsgName
  location: location
  tags: tags
  properties: {
    securityRules: [for rule in securityRules: {
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

// Outputs
output nsgId string = nsg.id
output nsgName string = nsg.name

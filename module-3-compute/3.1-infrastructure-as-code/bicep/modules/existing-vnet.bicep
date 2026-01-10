/*=====================================================
SUMMARY: Helper Module - Get Existing VNet Details
DESCRIPTION: Retrieves Subnet IDs from an existing VNet.
AUTHOR/S: Marcin Biszczanik
VERSION: 0.1.0
======================================================*/

param parVnetName string

resource resVnet 'Microsoft.Network/virtualNetworks@2023-11-01' existing = {
  name: parVnetName
}

output outVnetId string = resVnet.id
output outAuthSubnetId string = resVnet.properties.subnets[0].id // Assuming order or filtering by name would be safer but keeping simple for now. 
// Safer approach: reference subnets directly
resource resSubnetAuth 'Microsoft.Network/virtualNetworks/subnets@2023-11-01' existing = {
  parent: resVnet
  name: 'AuthSubnet'
}

resource resSubnetWorld 'Microsoft.Network/virtualNetworks/subnets@2023-11-01' existing = {
  parent: resVnet
  name: 'WorldSubnet'
}

output outAuthSubnetIdSafe string = resSubnetAuth.id
output outWorldSubnetIdSafe string = resSubnetWorld.id

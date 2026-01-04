/*=====================================================
SUMMARY: Lab 2.1 - VNet Peering
DESCRIPTION: Configures bi-directional peering between two VNets.
AUTHOR/S: Marcin Biszczanik
VERSION: 0.1.0
======================================================*/

/*******************
*    Parameters    *
*******************/
@description('Name of the Source Virtual Network')
param parSourceVnetName string

@description('ID of the Target Virtual Network')
param parTargetVnetId string

@description('Name of the Peering Connection')
param parPeeringName string

/*******************
*    Resources     *
*******************/

resource resPeering 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2023-11-01' = {
  name: '${parSourceVnetName}/${parPeeringName}'
  properties: {
    remoteVirtualNetwork: {
      id: parTargetVnetId
    }
    allowVirtualNetworkAccess: true
    allowForwardedTraffic: true
    allowGatewayTransit: false
    useRemoteGateways: false
  }
}

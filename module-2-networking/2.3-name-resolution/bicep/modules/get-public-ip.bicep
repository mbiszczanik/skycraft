/*=====================================================
SUMMARY: Public IP Lookup Helper
DESCRIPTION: Returns properties of an existing Public IP.
AUTHOR/S: Marcin Biszczanik
VERSION: 0.1.0
DEPLOYMENT: Internal Module
=====================================================*/

@description('The name of the existing Public IP.')
param parPublicIpName string

resource resPublicIp 'Microsoft.Network/publicIPAddresses@2023-04-01' existing = {
  name: parPublicIpName
}

output outIpAddress string = resPublicIp.properties.ipAddress
output outId string = resPublicIp.id

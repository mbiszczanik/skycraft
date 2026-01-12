/*=====================================================
SUMMARY: Lab 2.3 - Public IP Lookup Module
DESCRIPTION: Returns properties of an existing Public IP.
AUTHOR/S: Marcin Biszczanik
VERSION: 0.2.0
DEPRECATED: False
======================================================*/

@description('The name of the existing Public IP.')
param parPublicIpName string

resource resPublicIp 'Microsoft.Network/publicIPAddresses@2023-04-01' existing = {
  name: parPublicIpName
}

output outIpAddress string = resPublicIp.properties.ipAddress
output outId string = resPublicIp.id

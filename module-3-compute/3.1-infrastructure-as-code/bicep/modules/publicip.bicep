// modules/publicip.bicep
// Public IP address module

@description('Name of the public IP address')
param publicIpName string

@description('Azure region for deployment')
param location string = resourceGroup().location

@description('Public IP SKU')
@allowed(['Basic', 'Standard'])
param sku string = 'Standard'

@description('IP allocation method')
@allowed(['Static', 'Dynamic'])
param allocationMethod string = 'Static'

@description('DNS label (optional)')
param dnsLabel string = ''

@description('Resource tags')
param tags object

// Public IP Address
resource publicIp 'Microsoft.Network/publicIPAddresses@2023-05-01' = {
  name: publicIpName
  location: location
  tags: tags
  sku: {
    name: sku
    tier: 'Regional'
  }
  properties: {
    publicIPAllocationMethod: allocationMethod
    publicIPAddressVersion: 'IPv4'
    dnsSettings: !empty(dnsLabel) ? {
      domainNameLabel: dnsLabel
    } : null
  }
}

// Outputs
output publicIpId string = publicIp.id
output publicIpName string = publicIp.name
output ipAddress string = publicIp.properties.ipAddress

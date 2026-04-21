/*=====================================================
SUMMARY: Lab 3.1 - Public IP Address Module
DESCRIPTION: Deploys a Standard / Static Public IP Address for load balancers or gateways in SkyCraft Lab 3.1.
AUTHOR/S: Marcin Biszczanik
VERSION: 1.1.0
DEPLOYMENT: [Internal use via Orchestrator]
======================================================*/

/*******************
*    Parameters    *
*******************/
@description('Name of the public IP address')
param parPublicIpName string

@description('Azure region for deployment')
param parLocation string = resourceGroup().location

@description('Public IP SKU')
@allowed(['Basic', 'Standard'])
param parSku string = 'Standard'

@description('IP allocation method')
@allowed(['Static', 'Dynamic'])
param parAllocationMethod string = 'Static'

@description('Optional DNS label (leave empty to skip DNS settings)')
param parDnsLabel string = ''

@description('Resource tags (must include Project, Environment, CostCenter)')
param parTags object

/*******************
*    Resources     *
*******************/
resource resPublicIp 'Microsoft.Network/publicIPAddresses@2023-11-01' = {
  name: parPublicIpName
  location: parLocation
  tags: parTags
  sku: {
    name: parSku
    tier: 'Regional'
  }
  properties: {
    publicIPAllocationMethod: parAllocationMethod
    publicIPAddressVersion: 'IPv4'
    dnsSettings: !empty(parDnsLabel) ? {
      domainNameLabel: parDnsLabel
    } : null
  }
}

/******************
*     Outputs     *
******************/
output outPublicIpId string = resPublicIp.id
output outPublicIpName string = resPublicIp.name
output outIpAddress string = resPublicIp.properties.ipAddress

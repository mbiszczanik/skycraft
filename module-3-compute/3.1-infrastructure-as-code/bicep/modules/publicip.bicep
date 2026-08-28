/*=====================================================
SUMMARY: Lab 3.1 - Public IP Address Module
DESCRIPTION: Deploys a Standard / Static, zone-redundant Public IP Address for load balancers or gateways in SkyCraft Lab 3.1.
AUTHOR/S: Marcin Biszczanik
VERSION: 1.2.0
DEPLOYMENT: [Internal use via Orchestrator]
======================================================*/

/*******************
*    Parameters    *
*******************/

@description('Name of the public IP address')
@minLength(1)
@maxLength(80)
param parPublicIpName string

@description('Azure region for deployment')
param parLocation string = resourceGroup().location

@description('Public IP SKU')
@allowed(['Basic', 'Standard'])
param parSku string = 'Standard'

@description('IP allocation method')
@allowed(['Static', 'Dynamic'])
param parAllocationMethod string = 'Static'

@description('Availability zones. Zone-redundant by default, like the Lab 2.1 public IPs: zones are immutable on a public IP, so both labs must agree.')
param parAvailabilityZones string[] = ['1', '2', '3']

@description('Optional DNS label (leave empty to skip DNS settings)')
param parDnsLabel string = ''

@description('Resource tags (canonical set: Project, Environment, CostCenter, Owner)')
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
  zones: parAvailabilityZones
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

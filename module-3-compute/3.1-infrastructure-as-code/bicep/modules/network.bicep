/*=====================================================
SUMMARY: Lab 3.1 - Virtual Network Module
DESCRIPTION: Deploys a Virtual Network with typed subnet definitions (optional NSG association and delegation) for SkyCraft Lab 3.1.
AUTHOR/S: Marcin Biszczanik
VERSION: 1.2.0
DEPLOYMENT: [Internal use via Orchestrator]
======================================================*/

/*******************
*      Types       *
*******************/

@description('Subnet definition consumed by the VNet resource')
type subnetConfig = {
  @description('Subnet name')
  name: string

  @description('Subnet address prefix (CIDR)')
  addressPrefix: string

  @description('Optional resource ID of the NSG to associate')
  nsgId: string?

  @description('Optional delegation service name (e.g. Microsoft.Web/serverFarms)')
  delegation: string?
}

/*******************
*    Parameters    *
*******************/

@description('Name prefix for network resources (e.g., dev-skycraft-swc)')
@minLength(1)
@maxLength(40)
param parNamePrefix string

@description('Azure region for deployment')
param parLocation string = resourceGroup().location

@description('VNet address space')
param parVnetAddressPrefix string

@description('Subnet configurations')
param parSubnets subnetConfig[]

@description('Resource tags (canonical set: Project, Environment, CostCenter, Owner)')
param parTags object

/*******************
*    Resources     *
*******************/

resource resVnet 'Microsoft.Network/virtualNetworks@2023-11-01' = {
  name: '${parNamePrefix}-vnet'
  location: parLocation
  tags: parTags
  properties: {
    addressSpace: {
      addressPrefixes: [parVnetAddressPrefix]
    }
    subnets: [for subnet in parSubnets: {
      name: subnet.name
      properties: {
        addressPrefix: subnet.addressPrefix
        networkSecurityGroup: empty(subnet.?nsgId) ? null : {
          id: subnet.nsgId!
        }
        // The delegation is named after its service, exactly as the AVM subnet module used in
        // Lab 2.1 records it, so both labs describe the same subnet without a rename.
        delegations: empty(subnet.?delegation) ? null : [
          {
            name: subnet.delegation!
            properties: {
              serviceName: subnet.delegation!
            }
          }
        ]
      }
    }]
  }
}

/******************
*     Outputs     *
******************/

output outVnetId string = resVnet.id
output outVnetName string = resVnet.name
output outSubnets array = [for (subnet, i) in parSubnets: {
  name: subnet.name
  id: resVnet.properties.subnets[i].id
}]

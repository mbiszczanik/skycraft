/*=====================================================
SUMMARY: Container Instance Module
DESCRIPTION: Deploys Azure Container Instance (ACI) for SkyCraft
AUTHOR/S: Antigravity
VERSION: 0.1.0
DEPLOYMENT: [Internal use via Orchestrator]
======================================================*/

/*******************
*    Parameters    *
*******************/
@description('Location for resources')
param parLocation string

@description('Environment tag value')
param parEnvironment string = 'dev'

@description('Name of the Container Registry to pull from')
param parAcrName string

@description('Name of the Container Instance')
param parAciName string

@description('Container Image to deploy (e.g., repository:tag)')
param parImage string

/*******************
*    Variables     *
*******************/
var varCommonTags = {
  Project: 'SkyCraft'
  Environment: parEnvironment
  CostCenter: 'MSDN'
}

// Generate unique DNS label
var varDnsLabel = toLower('${parAciName}-${uniqueString(resourceGroup().id)}')

/*******************
*    Resources     *
*******************/

// Reference existing ACR to get credentials
resource resAcr 'Microsoft.ContainerRegistry/registries@2023-01-01-preview' existing = {
  name: parAcrName
}

resource resAci 'Microsoft.ContainerInstance/containerGroups@2023-05-01' = {
  name: parAciName
  location: parLocation
  tags: varCommonTags
  properties: {
    containers: [
      {
        name: parAciName
        properties: {
          image: '${resAcr.properties.loginServer}/${parImage}'
          ports: [
            {
              port: 80
              protocol: 'TCP'
            }
          ]
          resources: {
            requests: {
              cpu: 1
              memoryInGB: 1 // Default small size
              // Lab says 0.5 CPU, 0.5 GB
            }
          }
        }
      }
    ]
    osType: 'Linux'
    ipAddress: {
      type: 'Public'
      ports: [
        {
          protocol: 'TCP'
          port: 80
        }
      ]
      dnsNameLabel: varDnsLabel
    }
    imageRegistryCredentials: [
      {
        server: resAcr.properties.loginServer
        username: resAcr.listCredentials().username
        password: resAcr.listCredentials().passwords[0].value
      }
    ]
  }
}

/******************
*     Outputs     *
******************/
@description('The FQDN of the container instance')
output outAciFqdn string = resAci.properties.ipAddress.fqdn

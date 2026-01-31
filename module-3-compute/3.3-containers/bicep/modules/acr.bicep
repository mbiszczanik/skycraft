/*=====================================================
SUMMARY: Container Registry Module
DESCRIPTION: Deploys Azure Container Registry (ACR) for SkyCraft
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

@description('Name of the Container Registry')
param parAcrName string

/*******************
*    Variables     *
*******************/
var varCommonTags = {
  Project: 'SkyCraft'
  Environment: parEnvironment
  CostCenter: 'MSDN'
}
// Force Lowercase just in case
var varAcrNameStart = toLower(parAcrName)

/*******************
*    Resources     *
*******************/

// ACR - Standard SKU with Admin enabled
resource resAcr 'Microsoft.ContainerRegistry/registries@2023-01-01-preview' = {
  name: varAcrNameStart
  location: parLocation
  tags: varCommonTags
  sku: {
    name: 'Standard'
  }
  properties: {
    adminUserEnabled: true
  }
}

/******************
*     Outputs     *
******************/
@description('The resource ID of the container registry')
output outAcrId string = resAcr.id

@description('The name of the container registry')
output outAcrName string = resAcr.name

@description('The login server of the container registry')
output outAcrLoginServer string = resAcr.properties.loginServer

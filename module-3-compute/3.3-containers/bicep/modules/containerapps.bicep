/*=====================================================
SUMMARY: Azure Container Apps Module
DESCRIPTION: Deploys Container Apps Environment (CAE) and Container App (ACA) for SkyCraft
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

@description('Acr Name')
param parAcrName string

@description('Name of the Container Apps Environment')
param parCaeName string

@description('Name of the Container App')
param parAcaName string

@description('Container Image to deploy')
param parImage string

/*******************
*    Variables     *
*******************/
var varCommonTags = {
  Project: 'SkyCraft'
  Environment: parEnvironment
  CostCenter: 'MSDN'
}

/*******************
*    Resources     *
*******************/

// ACR Reference for Credentials
resource resAcr 'Microsoft.ContainerRegistry/registries@2023-01-01-preview' existing = {
  name: parAcrName
}

// Container Apps Environment
resource resCae 'Microsoft.App/managedEnvironments@2023-05-01' = {
  name: parCaeName
  location: parLocation
  tags: varCommonTags
  properties: {
    appLogsConfiguration: {
      destination: 'azure-monitor'
    }
    zoneRedundant: false
    // Workload profiles if needed, using Consumption by default which is implicitly supported
  }
}

// Container App
resource resAca 'Microsoft.App/containerApps@2023-05-01' = {
  name: parAcaName
  location: parLocation
  tags: varCommonTags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    managedEnvironmentId: resCae.id
    configuration: {
      ingress: {
        external: true
        targetPort: 80
        transport: 'auto'
      }
      secrets: [
        {
          name: 'acr-password'
          value: resAcr.listCredentials().passwords[0].value
        }
      ]
      registries: [
        {
          server: resAcr.properties.loginServer
          username: resAcr.listCredentials().username
          passwordSecretRef: 'acr-password'
        }
      ]
    }
    template: {
      containers: [
        {
          name: 'worldserver'
          image: '${resAcr.properties.loginServer}/${parImage}'
          resources: {
            cpu: json('0.25')
            memory: '0.5Gi'
          }
        }
      ]
      scale: {
        minReplicas: 1
        maxReplicas: 3
        rules: [
          {
            name: 'http-load'
            http: {
              metadata: {
                concurrentRequests: '10'
              }
            }
          }
        ]
      }
    }
  }
}

/******************
*     Outputs     *
******************/
@description('The FQDN of the Container App')
output outAcaFqdn string = resAca.properties.configuration.ingress.fqdn

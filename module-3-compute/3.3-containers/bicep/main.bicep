/*=====================================================
SUMMARY: Lab 3.3 - Containers Orchestrator
DESCRIPTION: Deploys the Container Registry, a Container Instance and a Container Apps environment with one app for SkyCraft Lab 3.3 via Azure Verified Modules (the image must already exist in the registry - Deploy-Bicep.ps1 bootstraps it with acr.bicep first)
EXAMPLE: az deployment sub create --location swedencentral --template-file main.bicep
AUTHOR/S: Marcin Biszczanik
VERSION: 0.2.0
DEPLOYMENT: .\scripts\Deploy-Bicep.ps1
======================================================*/

targetScope = 'subscription'

/*******************
*    Parameters    *
*******************/

@description('Location for all resources')
@allowed(['swedencentral', 'northeurope'])
param parLocation string = 'swedencentral'

@description('Environment (maps to the canonical Environment tag value)')
@allowed(['dev', 'prod', 'platform'])
param parEnvironment string = 'dev'

@description('Resource owner tag value')
@minLength(1)
param parOwner string = 'mbiszczanik'

@description('Resource Group Name')
@minLength(1)
@maxLength(90)
param parResourceGroupName string = 'dev-skycraft-swc-rg'

@description('Name of the Container Registry (alphanumeric, globally unique)')
@minLength(5)
@maxLength(50)
param parAcrName string = 'devskycraftswcacr01'

@description('Name of the Container Instance')
@minLength(1)
@maxLength(63)
param parAciName string = 'dev-skycraft-swc-aci-auth'

@description('Name of the Container Apps Environment')
@minLength(1)
@maxLength(60)
param parCaeName string = 'dev-skycraft-swc-cae-02'

@description('Name of the Container App')
@minLength(1)
@maxLength(32)
param parAcaName string = 'dev-skycraft-swc-aca-world-02'

@description('Image repository and tag to run (must exist in the registry)')
@minLength(3)
param parImage string = 'skycraft-auth:v1'

/*******************
*    Variables     *
*******************/

var varEnvironmentTags = {
  dev: 'Development'
  prod: 'Production'
  platform: 'Platform'
}
var varCommonTags = {
  Project: 'SkyCraft'
  Environment: varEnvironmentTags[parEnvironment]
  CostCenter: 'MSDN'
  Owner: parOwner
}

var varAcrName = toLower(parAcrName)
// Same seed as the previous module-level uniqueString(resourceGroup().id), so the FQDN is unchanged
var varAciDnsLabel = toLower('${parAciName}-${uniqueString(resRg.id)}')

/*******************
*     Existing     *
*******************/

resource resRg 'Microsoft.Resources/resourceGroups@2023-07-01' existing = {
  name: parResourceGroupName
}

// Registry lookup for the admin credentials consumed by ACI and the Container App
resource resAcr 'Microsoft.ContainerRegistry/registries@2023-07-01' existing = {
  name: varAcrName
  scope: resRg
}

/*******************
*     Modules      *
*******************/

// Resource group (idempotent; re-applies the canonical tags)
module modResourceGroup 'br/public:avm/res/resources/resource-group:0.4.4' = {
  name: 'rg-deployment'
  params: {
    name: parResourceGroupName
    location: parLocation
    tags: varCommonTags
  }
}

// 1. Container Registry (Standard, admin user on - the lab's credential model)
module modAcr 'br/public:avm/res/container-registry/registry:0.13.0' = {
  name: 'acr-deployment'
  scope: resRg
  params: {
    name: varAcrName
    location: parLocation
    tags: varCommonTags
    acrSku: 'Standard'
    acrAdminUserEnabled: true
    publicNetworkAccess: 'Enabled'
    networkRuleSetDefaultAction: 'Allow' // AVM default 'Deny' would add a network rule set that blocks the lab
  }
  dependsOn: [
    modResourceGroup // RG must exist before RG-scoped modules; no symbolic reference available
  ]
}

// 2. Container Instance (public IP, port 80)
module modAci 'br/public:avm/res/container-instance/container-group:0.7.0' = {
  name: 'aci-deployment'
  scope: resRg
  params: {
    name: parAciName
    location: parLocation
    tags: varCommonTags
    availabilityZone: -1
    osType: 'Linux'
    containers: [
      {
        name: parAciName
        properties: {
          image: '${modAcr.outputs.loginServer}/${parImage}'
          ports: [
            {
              port: 80
              protocol: 'TCP'
            }
          ]
          resources: {
            requests: {
              cpu: 1
              memoryInGB: '1'
            }
          }
        }
      }
    ]
    ipAddress: {
      type: 'Public'
      dnsNameLabel: varAciDnsLabel
      ports: [
        {
          port: 80
          protocol: 'TCP'
        }
      ]
    }
    imageRegistryCredentials: [
      {
        server: modAcr.outputs.loginServer
        username: resAcr.listCredentials().username
        password: resAcr.listCredentials().passwords[0].value
      }
    ]
  }
}

// 3. Container Apps environment (consumption, Azure Monitor logs)
module modCae 'br/public:avm/res/app/managed-environment:0.15.0' = {
  name: 'cae-deployment'
  scope: resRg
  params: {
    name: parCaeName
    location: parLocation
    tags: varCommonTags
    appLogsConfiguration: {
      destination: 'azure-monitor'
    }
    // Lab-friction overrides (standards section 4.5): the AVM defaults (zone redundancy, which
    // needs an infrastructure subnet, and public network access disabled) would block the lab.
    zoneRedundant: false
    publicNetworkAccess: 'Enabled'
  }
  dependsOn: [
    modResourceGroup // RG must exist before RG-scoped modules; no symbolic reference available
  ]
}

// 4. Container App (external HTTP ingress, 1-3 replicas on HTTP concurrency)
module modAca 'br/public:avm/res/app/container-app:0.23.0' = {
  name: 'aca-deployment'
  scope: resRg
  params: {
    name: parAcaName
    location: parLocation
    tags: varCommonTags
    environmentResourceId: modCae.outputs.resourceId
    managedIdentities: {
      systemAssigned: true
    }
    ingressExternal: true
    ingressTargetPort: 80
    ingressTransport: 'auto'
    ingressAllowInsecure: false
    scaleSettings: {
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
    secrets: [
      {
        name: 'acr-password'
        value: resAcr.listCredentials().passwords[0].value
      }
    ]
    registries: [
      {
        server: modAcr.outputs.loginServer
        username: resAcr.listCredentials().username
        passwordSecretRef: 'acr-password'
      }
    ]
    containers: [
      {
        name: 'worldserver'
        image: '${modAcr.outputs.loginServer}/${parImage}'
        resources: {
          cpu: json('0.25')
          memory: '0.5Gi'
        }
      }
    ]
  }
}

/******************
*     Outputs     *
******************/

output outAcrLoginServer string = modAcr.outputs.loginServer
output outAciFqdn string = '${varAciDnsLabel}.${parLocation}.azurecontainer.io'
output outAcaFqdn string = modAca.outputs.fqdn

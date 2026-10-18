/*=====================================================
SUMMARY: Lab 3.3 - Containers Orchestrator
DESCRIPTION: Deploys the Container Registry, a Container Instance and a Container Apps environment with one app for SkyCraft Lab 3.3 via Azure Verified Modules (the image must already exist in the registry - Deploy-Bicep.ps1 bootstraps it with acr.bicep first)
EXAMPLE: .\scripts\Deploy-Bicep.ps1 (Phase 1 deploys acr.bicep and imports the image, Phase 2 runs: New-AzSubscriptionDeployment -Location swedencentral -TemplateFile main.bicep)
AUTHOR/S: Marcin Biszczanik
VERSION: 0.3.0
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

// Every name below takes its prefix from parEnvironment (#121), so `-Environment prod` deploys
// prod-named resources; the parameters stay overridable because the registry name is global.
@description('Resource Group Name')
@minLength(1)
@maxLength(90)
param parResourceGroupName string = '${parEnvironment}-skycraft-swc-rg'

@description('Name of the Container Registry (alphanumeric, globally unique)')
@minLength(5)
@maxLength(50)
param parAcrName string = '${parEnvironment}skycraftswcacr01'

@description('Name of the Container Instance')
@minLength(1)
@maxLength(63)
param parAciName string = '${parEnvironment}-skycraft-swc-aci-auth'

// The -02 suffix is load-bearing here: a Container Apps environment names its infrastructure
// resource group ME_<name> and that name is immutable (lab guide, "Why -02").
@description('Name of the Container Apps Environment')
@minLength(1)
@maxLength(60)
param parCaeName string = '${parEnvironment}-skycraft-swc-cae-02'

// No -02 on the app: nothing immutable hangs off its name, and with it the platform name
// would run to 34 characters against the 32 a Container App allows.
@description('Name of the Container App')
@minLength(1)
@maxLength(32)
param parAcaName string = '${parEnvironment}-skycraft-swc-aca-world'

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
// The DNS label is derived from the resource group's ARM id - the same input the pre-conversion
// template hashed through uniqueString(resourceGroup().id); confirm the FQDN on the first live deployment.
var varAciDnsLabel = toLower('${parAciName}-${uniqueString('/subscriptions/${subscription().subscriptionId}/resourceGroups/${parResourceGroupName}')}')

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
module modAcr 'br/public:avm/res/container-registry/registry:0.13.1' = {
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
    // AVM defaults this to 'disabled'; Azure's own default is 'enabled'. While disabled, ARM-audience tokens
    // cannot reach the registry data plane, so Get-AzContainerRegistryRepository (used by Test-Lab.ps1)
    // fails with 'Unauthorized' even though the image is present.
    azureADAuthenticationAsArmPolicyStatus: 'enabled'
  }
  dependsOn: [
    modResourceGroup // RG must exist before RG-scoped modules; no symbolic reference available
  ]
}

// 2. Container Instance (public IP, port 80). Every setting the Portal steps of the lab guide choose
// is spelled out here, so the three paths (Portal, Az PowerShell, Bicep) end in the same state (#228, #362).
module modAci 'br/public:avm/res/container-instance/container-group:0.7.1' = {
  name: 'aci-deployment'
  scope: resRg
  params: {
    name: parAciName
    location: parLocation
    tags: varCommonTags
    availabilityZone: -1
    osType: 'Linux'
    sku: 'Standard'
    restartPolicy: 'Always' // the Portal's Advanced tab sets the same (guide Step 3.3.4)
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
      // The guide sets "Any reuse (unsecure)" in the Portal, because New-AzContainerGroup has no scope
      // parameter and leaves this value; the FQDN output below depends on it (#229).
      autoGeneratedDomainNameLabelScope: 'Unsecure'
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

// 3. Container Apps environment (Consumption workload profile, Azure Monitor logs). The Portal creates
// only Workload profiles environments, so the template declares the Consumption profile the Portal
// adds. Logs go to Azure Monitor, which creates no Log Analytics workspace: the Portal's default
// creates one in the resource group that Module 5 wizards then offer as their default (#374).
module modCae 'br/public:avm/res/app/managed-environment:0.16.0' = {
  name: 'cae-deployment'
  scope: resRg
  params: {
    name: parCaeName
    location: parLocation
    tags: varCommonTags
    appLogsConfiguration: {
      destination: 'azure-monitor'
    }
    workloadProfiles: [
      {
        name: 'Consumption'
        workloadProfileType: 'Consumption'
      }
    ]
    // Lab-friction overrides (standards section 4.5): the AVM defaults (zone redundancy, which
    // needs an infrastructure subnet, and public network access disabled) would block the lab.
    zoneRedundant: false
    publicNetworkAccess: 'Enabled'
  }
  dependsOn: [
    modResourceGroup // RG must exist before RG-scoped modules; no symbolic reference available
  ]
}

// 4. Container App (external HTTP ingress, 1-3 replicas on HTTP concurrency). It pulls with the
// registry's admin credentials, the "Secret" authentication type of the guide's Step 3.3.7, and has no
// managed identity: the Portal's managed identity option would need a role assignment (#229).
module modAca 'br/public:avm/res/app/container-app:0.23.0' = {
  name: 'aca-deployment'
  scope: resRg
  params: {
    name: parAcaName
    location: parLocation
    tags: varCommonTags
    environmentResourceId: modCae.outputs.resourceId
    workloadProfileName: 'Consumption'
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
// container-group:0.7.1 outputs only the IPv4 address, so the FQDN is composed here. The composition
// holds for the Unsecure domain-name-label scope set above ({label}.{region}.azurecontainer.io); any
// other scope adds a hash segment. Test-Lab.ps1 prints the real one from Get-AzContainerGroup.
output outAciFqdn string = '${varAciDnsLabel}.${parLocation}.azurecontainer.io'
output outAcaFqdn string = modAca.outputs.fqdn

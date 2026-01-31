/*=====================================================
SUMMARY: App Service Module
DESCRIPTION: Deploys App Service Plan (P0V4), Web App (Node), Staging Slot, and Autoscale
AUTHOR/S: Antigravity
VERSION: 0.1.0
DEPLOYMENT: Internal via Orchestrator
======================================================*/

/*******************
*    Parameters    *
*******************/
@description('Location for resources')
param parLocation string

@description('Environment tag value')
param parEnvironment string

@description('Name of the App Service Plan')
param parAppServicePlanName string

@description('Name of the Web App (must be globally unique)')
param parAppName string

@description('Resource ID of the subnet for VNet Integration')
param parSubnetId string

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

resource resAppServicePlan 'Microsoft.Web/serverfarms@2025-03-01' = {
  name: parAppServicePlanName
  location: parLocation
  tags: varCommonTags
  sku: {
    name: 'P0v4'
    tier: 'PremiumV4'
    size: 'P0v4'
    family: 'Pv4'
    capacity: 1
  }
  kind: 'linux'
  properties: {
    reserved: true
  }
}

resource resWebApp 'Microsoft.Web/sites@2025-03-01' = {
  name: parAppName
  location: parLocation
  tags: varCommonTags
  kind: 'app,linux'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    serverFarmId: resAppServicePlan.id
    siteConfig: {
      linuxFxVersion: 'NODE|20-lts' // Node 24 not yet standard in Bicep alias, using 20 LTS
      vnetRouteAllEnabled: true
      minTlsVersion: '1.2'
    }
    virtualNetworkSubnetId: parSubnetId
    httpsOnly: true
  }
}

resource resStagingSlot 'Microsoft.Web/sites/slots@2022-09-01' = {
  parent: resWebApp
  name: 'staging'
  location: parLocation
  tags: varCommonTags
  kind: 'app,linux'
  properties: {
    serverFarmId: resAppServicePlan.id
    siteConfig: {
      linuxFxVersion: 'NODE|20-lts'
    }
  }
}

resource resAutoscale 'Microsoft.Insights/autoscalesettings@2022-10-01' = {
  name: '${parAppServicePlanName}-autoscale'
  location: parLocation
  tags: varCommonTags
  properties: {
    targetResourceUri: resAppServicePlan.id
    enabled: true
    profiles: [
      {
        name: 'AutoCreatedDefaultProfile'
        capacity: {
          minimum: '1'
          maximum: '3'
          default: '1'
        }
        rules: [
          {
            metricTrigger: {
              metricName: 'CpuPercentage'
              metricResourceUri: resAppServicePlan.id
              timeGrain: 'PT1M'
              statistic: 'Average'
              timeWindow: 'PT10M'
              timeAggregation: 'Average'
              operator: 'GreaterThan'
              threshold: 70
            }
            scaleAction: {
              direction: 'Increase'
              type: 'ChangeCount'
              value: '1'
              cooldown: 'PT5M'
            }
          }
          {
            metricTrigger: {
              metricName: 'CpuPercentage'
              metricResourceUri: resAppServicePlan.id
              timeGrain: 'PT1M'
              statistic: 'Average'
              timeWindow: 'PT10M'
              timeAggregation: 'Average'
              operator: 'LessThan'
              threshold: 30
            }
            scaleAction: {
              direction: 'Decrease'
              type: 'ChangeCount'
              value: '1'
              cooldown: 'PT5M'
            }
          }
        ]
      }
    ]
  }
}

/******************
*     Outputs     *
******************/
output outWebAppName string = resWebApp.name
output outAppServicePlanId string = resAppServicePlan.id


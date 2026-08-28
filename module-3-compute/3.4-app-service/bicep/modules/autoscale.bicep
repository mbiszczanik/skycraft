/*=====================================================
SUMMARY: Lab 3.4 - Autoscale Setting Module
DESCRIPTION: Deploys a CPU-based autoscale setting for an App Service Plan (local fallback: avm/res/insights/autoscale-setting is only Proposed in the AVM index)
AUTHOR/S: Marcin Biszczanik
VERSION: 0.2.0
DEPLOYMENT: [Internal use via Orchestrator]
======================================================*/

/*******************
*    Parameters    *
*******************/

@description('Name of the autoscale setting')
@minLength(1)
@maxLength(260)
param parAutoscaleName string

@description('Location for the autoscale setting')
param parLocation string = resourceGroup().location

@description('Environment tag value')
@allowed(['Platform', 'Development', 'Production'])
param parEnvironment string = 'Development'

@description('Resource owner tag value')
@minLength(1)
param parOwner string = 'mbiszczanik'

@description('Resource ID of the App Service Plan to scale')
param parTargetResourceId string

@description('Minimum instance count')
@minValue(1)
@maxValue(30)
param parMinimumCapacity int = 1

@description('Maximum instance count')
@minValue(1)
@maxValue(30)
param parMaximumCapacity int = 3

@description('Default instance count')
@minValue(1)
@maxValue(30)
param parDefaultCapacity int = 1

@description('Average CPU percentage above which one instance is added')
@minValue(1)
@maxValue(100)
param parScaleOutCpuThreshold int = 70

@description('Average CPU percentage below which one instance is removed')
@minValue(1)
@maxValue(100)
param parScaleInCpuThreshold int = 30

/*******************
*    Variables     *
*******************/

var varCommonTags = {
  Project: 'SkyCraft'
  Environment: parEnvironment
  CostCenter: 'MSDN'
  Owner: parOwner
}

/*******************
*    Resources     *
*******************/

resource resAutoscale 'Microsoft.Insights/autoscalesettings@2022-10-01' = {
  name: parAutoscaleName
  location: parLocation
  tags: varCommonTags
  properties: {
    targetResourceUri: parTargetResourceId
    enabled: true
    profiles: [
      {
        name: 'AutoCreatedDefaultProfile'
        capacity: {
          minimum: string(parMinimumCapacity)
          maximum: string(parMaximumCapacity)
          default: string(parDefaultCapacity)
        }
        rules: [
          {
            metricTrigger: {
              metricName: 'CpuPercentage'
              metricResourceUri: parTargetResourceId
              timeGrain: 'PT1M'
              statistic: 'Average'
              timeWindow: 'PT10M'
              timeAggregation: 'Average'
              operator: 'GreaterThan'
              threshold: parScaleOutCpuThreshold
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
              metricResourceUri: parTargetResourceId
              timeGrain: 'PT1M'
              statistic: 'Average'
              timeWindow: 'PT10M'
              timeAggregation: 'Average'
              operator: 'LessThan'
              threshold: parScaleInCpuThreshold
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

output outAutoscaleId string = resAutoscale.id
output outAutoscaleName string = resAutoscale.name

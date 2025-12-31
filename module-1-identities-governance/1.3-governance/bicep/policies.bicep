/*=====================================================
SUMMARY: Lab 1.3 - Azure Policy Assignments
DESCRIPTION: This template assigns governance policies at subscription scope
EXAMPLE:
AUTHOR/S: Marcin Biszczanik
VERSION: 0.1.0
======================================================*/

targetScope = 'subscription'

@description('Tag name to require on resource groups')
param parRequiredTagName string = 'Environment'

@description('Project tag value to enforce')
param parProjectTagValue string = 'SkyCraft'

@description('Allowed Azure regions')
param parAllowedLocations array = [
  'swedencentral'
  'northeurope'
]

// Policy 1: Require tag on resource groups
module modRequireTagPolicy 'br/public:avm/res/authorization/policy-assignment/sub-scope:0.1.0' = {
  params: {
    name: 'Require Environment Tag on Resource Groups'
    policyDefinitionId: '/providers/Microsoft.Authorization/policyDefinitions/96670d01-0a4d-4649-9c89-2d3abc0a5025'
    displayName: 'Require Environment Tag on Resource Groups'
    description: 'All resource groups must have an Environment tag'
    parameters: {
      tagName: {
        value: parRequiredTagName
      }
    }
    nonComplianceMessages: [
      {
        message: 'Resource group must have an Environment tag (Development, Production, or Shared)'
      }
    ]
  }
}

// Policy 2: Require tag and value on resources
module modEnforceProjectTagPolicy 'br/public:avm/res/authorization/policy-assignment/sub-scope:0.1.0' = {
  params: {
    name: 'Enforce-Project-Tag'
    policyDefinitionId: '/providers/Microsoft.Authorization/policyDefinitions/1e30110a-5ceb-460c-a204-c1c3969c6d62'
    displayName: 'Enforce Project Tag Value'
    description: 'All resources must have Project tag set to SkyCraft'
    parameters: {
      tagName: {
        value: 'Project'
      }
      tagValue: {
        value: parProjectTagValue
      }
    }
    nonComplianceMessages: [
      {
        message: 'All resources must be tagged with Project=${parProjectTagValue}'
      }
    ]
  }
}

// Policy 3: Allowed locations
module modAllowedLocationsPolicy 'br/public:avm/res/authorization/policy-assignment/sub-scope:0.1.0' = {
  params: {
    name: 'Restrict-Azure-Regions'
    policyDefinitionId: '/providers/Microsoft.Authorization/policyDefinitions/e56962a6-4747-49cd-b67b-bf8b01975c4c'
    displayName: 'Restrict to Allowed Regions'
    description: 'Resources can only be created in specified regions'
    parameters: {
      listOfAllowedLocations: {
        value: parAllowedLocations
      }
    }
    nonComplianceMessages: [
      {
        message: 'Resources must be deployed to approved regions only'
      }
    ]
  }
}

// Outputs
output policyAssignments array = [
  {
    name: modRequireTagPolicy.name
  }
  {
    name: modEnforceProjectTagPolicy.name
  }
  {
    name: modAllowedLocationsPolicy.name
  }
]

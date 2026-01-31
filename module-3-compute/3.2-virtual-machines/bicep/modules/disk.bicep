/*=====================================================
SUMMARY: Managed Data Disk Module
DESCRIPTION: Deploys Azure Managed Disks for VM data storage
AUTHOR/S: Marcin Biszczanik
VERSION: 1.0.0
DEPLOYMENT: Internal use via Orchestrator
======================================================*/

// ============================================================================
// PARAMETERS
// ============================================================================

@description('Name of the managed disk')
param parDiskName string

@description('Azure region for deployment')
param parLocation string = resourceGroup().location

@description('Disk size in GB')
@minValue(4)
@maxValue(32767)
param parDiskSizeGB int = 64

@description('Storage account type for the disk')
@allowed([
  'Standard_LRS'
  'StandardSSD_LRS'
  'Premium_LRS'
  'StandardSSD_ZRS'
  'Premium_ZRS'
])
param parDiskSku string = 'StandardSSD_LRS'

@description('Availability zone for the disk (1, 2, or 3)')
@allowed(['1', '2', '3'])
param parAvailabilityZone string = '1'

@description('Resource tags')
param parTags object

// ============================================================================
// RESOURCES
// ============================================================================

resource resDisk 'Microsoft.Compute/disks@2023-10-02' = {
  name: parDiskName
  location: parLocation
  tags: parTags
  sku: {
    name: parDiskSku
  }
  zones: [
    parAvailabilityZone
  ]
  properties: {
    creationData: {
      createOption: 'Empty'
    }
    diskSizeGB: parDiskSizeGB
    osType: 'Linux'
  }
}

// ============================================================================
// OUTPUTS
// ============================================================================

output outDiskId string = resDisk.id
output outDiskName string = resDisk.name

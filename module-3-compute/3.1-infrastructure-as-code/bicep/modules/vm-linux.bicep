/*=====================================================
SUMMARY: Generic Linux Virtual Machine Module
DESCRIPTION: Deploys a Linux VM with NIC, OS Disk, and SSH access.
AUTHOR/S: Marcin Biszczanik
VERSION: 0.1.0
======================================================*/

/*******************
*    Parameters    *
*******************/
@description('The name of the Virtual Machine.')
param parVmName string

@description('The location for the VM resources.')
param parLocation string

@description('The size of the Virtual Machine (e.g., Standard_B2s).')
param parVmSize string

@description('The resource ID of the Subnet where the VM NIC will be created.')
param parSubnetId string

@description('The Admin Username for the VM.')
param parAdminUsername string

@description('The SSH Public Key for the Admin User.')
@secure()
param parAdminPublicKey string

@description('Availability Zone (e.g., "1", "2", or "3"). Use empty string if regional.')
param parAvailabilityZone string = ''

@description('Tags to apply to the resources.')
param parTags object = {}

/*******************
*    Variables     *
*******************/
var varNicName = '${parVmName}-nic'
var varOsDiskName = '${parVmName}-osdisk'

/*******************
*    Resources     *
*******************/

// Network Interface
resource resNic 'Microsoft.Network/networkInterfaces@2023-11-01' = {
  name: varNicName
  location: parLocation
  tags: parTags
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          subnet: {
            id: parSubnetId
          }
        }
      }
    ]
  }
}

// Virtual Machine
resource resVm 'Microsoft.Compute/virtualMachines@2024-03-01' = {
  name: parVmName
  location: parLocation
  tags: parTags
  zones: empty(parAvailabilityZone) ? null : [
    parAvailabilityZone
  ]
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    hardwareProfile: {
      vmSize: parVmSize
    }
    osProfile: {
      computerName: parVmName
      adminUsername: parAdminUsername
      linuxConfiguration: {
        disablePasswordAuthentication: true
        ssh: {
          publicKeys: [
            {
              path: '/home/${parAdminUsername}/.ssh/authorized_keys'
              keyData: parAdminPublicKey
            }
          ]
        }
      }
    }
    storageProfile: {
      imageReference: {
        publisher: 'Canonical'
        offer: '0001-com-ubuntu-server-jammy'
        sku: '22_04-lts-gen2'
        version: 'latest'
      }
      osDisk: {
        name: varOsDiskName
        createOption: 'FromImage'
        caching: 'ReadWrite'
        managedDisk: {
          storageAccountType: 'StandardSSD_LRS'
        }
        deleteOption: 'Delete'
      }
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: resNic.id
          properties: {
            deleteOption: 'Delete'
          }
        }
      ]
    }
    diagnosticsProfile: {
      bootDiagnostics: {
        enabled: true
      }
    }
  }
}

/******************
*     Outputs     *
******************/
output outVmId string = resVm.id
output outVmName string = resVm.name
output outPrivateIp string = resNic.properties.ipConfigurations[0].properties.privateIPAddress
output outPrincipalId string = resVm.identity.principalId

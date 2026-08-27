/*=====================================================
SUMMARY: Lab 2.3 - Public IP Lookup
DESCRIPTION: Returns the address of an existing Public IP. Local fallback for a trivial 'existing' lookup (docs/bicep-standards.md, Section 4.3)
AUTHOR/S: Marcin Biszczanik
VERSION: 0.3.0
DEPLOYMENT: Internal use via Orchestrator
======================================================*/

/*******************
*    Parameters    *
*******************/

@description('Name of the existing Public IP')
@minLength(1)
@maxLength(80)
param parPublicIpName string

/*******************
*    Resources     *
*******************/

resource resPublicIp 'Microsoft.Network/publicIPAddresses@2023-11-01' existing = {
  name: parPublicIpName
}

/******************
*     Outputs     *
******************/

output outIpAddress string = resPublicIp.properties.ipAddress

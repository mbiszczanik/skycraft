/*=====================================================
SUMMARY: Lab 1.2 - Resource Groups Parameters
DESCRIPTION: Default parameter set for resource-groups.bicep. role-assignments.bicep has no parameter file: its four principal IDs are tenant-specific object IDs that scripts/Deploy-Bicep.ps1 -IncludeRoleAssignments resolves from Entra ID at run time and passes as overrides.
EXAMPLE: .\scripts\Deploy-Bicep.ps1
AUTHOR/S: Marcin Biszczanik
VERSION: 0.1.0
======================================================*/

using '../resource-groups.bicep'

param parLocation = 'swedencentral'

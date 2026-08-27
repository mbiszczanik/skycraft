/*=====================================================
SUMMARY: Lab 1.2 - Resource Groups Parameters
DESCRIPTION: Default parameter set for resource-groups.bicep. role-assignments.bicep has no parameter file: its principal IDs are resolved at runtime from Entra ID by scripts/New-LabRoleAssignment.ps1.
EXAMPLE: az deployment sub create --location swedencentral --template-file ../resource-groups.bicep --parameters resource-groups.bicepparam
AUTHOR/S: Marcin Biszczanik
VERSION: 0.1.0
======================================================*/

using '../resource-groups.bicep'

param parLocation = 'swedencentral'

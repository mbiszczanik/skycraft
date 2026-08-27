// Lab 1.2 - default parameter set for resource-groups.bicep.
// role-assignments.bicep has no parameter file: its principal IDs are resolved
// at runtime from Entra ID by scripts/New-LabRoleAssignment.ps1.
using '../resource-groups.bicep'

param parLocation = 'swedencentral'

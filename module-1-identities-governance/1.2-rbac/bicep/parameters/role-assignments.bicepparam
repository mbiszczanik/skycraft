/*=====================================================
SUMMARY: Lab 1.2 - Role Assignments Parameters
DESCRIPTION: Parameter values for the role-assignments.bicep entry point. Module 1 is
             non-environment (a single pass covers all resource groups), so this is a
             single parameter file. The four principal-ID parameters are required and
             have no template default; real Entra object IDs are resolved imperatively
             by scripts/New-LabRoleAssignment.ps1, so they carry empty-string
             placeholders here to satisfy 'bicep build-params' (BCP258). The three
             parResourceGroupName* parameters have defaults and are omitted.
EXAMPLE: .\scripts\New-LabRoleAssignment.ps1
         Deploy through the script, not 'az deployment' directly: this file leaves
         the four Entra principal IDs as empty placeholders, which exist only to keep
         'az bicep build-params' valid (BCP258). Passing it straight to the CLI
         submits those empty values.
AUTHOR/S: Marcin Biszczanik
VERSION: 1.0.0
======================================================*/

using '../role-assignments.bicep'

// Required principal IDs - supply real Entra object IDs at deploy time.
// Resolved imperatively by scripts/New-LabRoleAssignment.ps1; placeholders only.
param parAdminPrincipalId = ''           // overridden by scripts/New-LabRoleAssignment.ps1 at runtime
param parDeveloperGroupPrincipalId = ''  // overridden by scripts/New-LabRoleAssignment.ps1 at runtime
param parTesterGroupPrincipalId = ''     // overridden by scripts/New-LabRoleAssignment.ps1 at runtime
param parPartnerPrincipalId = ''         // overridden by scripts/New-LabRoleAssignment.ps1 at runtime

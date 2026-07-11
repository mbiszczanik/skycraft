/*=====================================================
SUMMARY: Lab 1.3 - Governance Parameters
DESCRIPTION: Parameter values for the main.bicep governance orchestrator. Module 1 is
             non-environment (a single pass applies tags, policies, and locks across all
             resource groups), so this is a single parameter file. Both template
             parameters (parLocation, parAdminEmail) have defaults, so no assignments are
             needed here; Deploy-Bicep.ps1 overlays the -Location and -AdminEmail script
             parameters on top of these values at runtime.
EXAMPLE: az deployment sub create --location swedencentral --template-file main.bicep --parameters parameters/main.bicepparam
AUTHOR/S: Marcin Biszczanik
VERSION: 1.0.0
======================================================*/

using '../main.bicep'

// No parameter assignments: parLocation and parAdminEmail both have defaults and are
// overlaid by Deploy-Bicep.ps1 from its -Location / -AdminEmail parameters at runtime.

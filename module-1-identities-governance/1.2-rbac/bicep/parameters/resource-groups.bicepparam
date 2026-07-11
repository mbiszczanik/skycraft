/*=====================================================
SUMMARY: Lab 1.2 - Resource Groups Parameters
DESCRIPTION: Parameter values for the resource-groups.bicep entry point. Module 1 is
             non-environment (a single pass deploys all three resource groups), so this
             is a single parameter file. Every template parameter (parLocation,
             parCommonTags, parOwnerEmail) has a default, so no assignments are needed
             here - the template defaults are used as-is.
EXAMPLE: az deployment sub create --location swedencentral --template-file resource-groups.bicep --parameters parameters/resource-groups.bicepparam
AUTHOR/S: Marcin Biszczanik
VERSION: 1.0.0
======================================================*/

using '../resource-groups.bicep'

// No parameter assignments: all parameters in resource-groups.bicep have defaults.

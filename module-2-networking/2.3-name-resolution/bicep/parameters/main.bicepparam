/*=====================================================
SUMMARY: Lab 2.3 - Name Resolution Parameters
DESCRIPTION: Parameter values for the Lab 2.3 DNS and load-balancer deployment.
             Every entry-point parameter in main.bicep has a default, so this file
             carries only the `using` link. Deploy-Bicep.ps1 passes this file
             directly (it supplies no per-template overrides of its own).
EXAMPLE: az deployment sub create --location swedencentral --template-file main.bicep --parameters parameters/main.bicepparam
AUTHOR/S: Marcin Biszczanik
VERSION: 1.0.0
======================================================*/

using '../main.bicep'

// All entry-point parameters use the template defaults.
// The only per-run value (parLocation) is a deployment-scope location, not a
// template parameter, so nothing needs to be overridden here.

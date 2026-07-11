/*=====================================================
SUMMARY: Lab 2.1 - Virtual Networks Parameters
DESCRIPTION: Parameter values for the Lab 2.1 Hub-and-Spoke networking deployment.
             Every entry-point parameter in main.bicep has a default, so this file
             carries only the `using` link. Runtime-computed and script-supplied
             values (location, resource-group names) are overlaid by
             Deploy-Bicep.ps1 at deployment time.
EXAMPLE: az deployment sub create --location swedencentral --template-file main.bicep --parameters parameters/main.bicepparam
AUTHOR/S: Marcin Biszczanik
VERSION: 1.0.0
======================================================*/

using '../main.bicep'

// All entry-point parameters use the template defaults.
// Values that differ per run (parLocation and the three RG-name params)
// are overlaid by Deploy-Bicep.ps1 at runtime.

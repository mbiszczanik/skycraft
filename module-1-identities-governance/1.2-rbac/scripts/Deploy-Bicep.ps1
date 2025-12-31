$location = 'swedencentral'

New-AzSubscriptionDeployment -Name "Lab-1.2-RBAC-RG" -TemplateFile ..\bicep\resource-groups.bicep -Location $location -Verbose

# Note: role-assignments.bicep requires parameters for Principal IDs
# New-AzSubscriptionDeployment -Name "Lab-1.2-RBAC-Roles" -TemplateFile ..\bicep\role-assignments.bicep -Location $location -Verbose
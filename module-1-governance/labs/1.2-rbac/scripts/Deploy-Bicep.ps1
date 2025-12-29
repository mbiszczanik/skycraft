$location = 'swedencentral'

New-AzSubscriptionDeployment -Name "Lab-1.2-RBAC-demo" -TemplateFile ..\bicep\main.bicep -Location $location -Verbose
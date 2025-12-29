$location = 'swedencentral'

# New-AzSubscriptionDeployment -Name "Lab-1.3-Governance-locks" -TemplateFile ..\bicep\locks.bicep -Location $location -Verbose

New-AzSubscriptionDeployment -Name "Lab-1.3-Governance-policies" -TemplateFile ..\bicep\policies.bicep -Location $location -Verbose

New-AzSubscriptionDeployment -Name "Lab-1.3-Governance-tags" -TemplateFile ..\bicep\tags.bicep -Location $location -Verbose
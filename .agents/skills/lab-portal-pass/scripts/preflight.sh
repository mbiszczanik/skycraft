#!/usr/bin/env bash
# Read-only inventory of a SkyCraft subscription before an agent Portal pass.
# Usage: preflight.sh <subscription-id> [name-filter (default: skycraft)]
# Prints resource groups (with tags), resources in matching groups, policy assignments at
# subscription scope, locks, budgets, action groups, activity-log alerts and recent
# subscription deployments. Every call names the subscription explicitly: the az CLI's
# default context drifts between tenants on this machine. Entra objects are not covered
# (Graph needs the Entra admin's sign-in): inventory them in the Portal.
set -u
export MSYS_NO_PATHCONV=1
S="${1:?usage: preflight.sh <subscription-id> [name-filter]}"
F="${2:-skycraft}"

ctx=$(az account show --subscription "$S" --query "{sub:id,tenant:tenantId,user:user.name}" -o tsv 2>&1) || { echo "Cannot reach subscription $S: $ctx"; exit 1; }
echo "== context: $ctx"
echo "== resource groups"
az group list --subscription "$S" --query "[].{name:name,location:location,tags:to_string(tags)}" -o table
echo "== resources in groups matching '$F'"
az resource list --subscription "$S" --query "[?contains(resourceGroup,'$F')].{rg:resourceGroup,type:type,name:name}" -o table
echo "== policy assignments (subscription scope)"
az policy assignment list --subscription "$S" --query "[].{name:name,display:displayName,mode:enforcementMode,created:systemData.createdAt}" -o table
echo "== locks"
az lock list --subscription "$S" --query "[].{name:name,level:level,rg:resourceGroup}" -o table
echo "== budgets (subscription)"
az consumption budget list --subscription "$S" --query "[].{name:name,amount:amount,grain:timeGrain}" -o table 2>/dev/null
for rg in $(az group list --subscription "$S" --query "[?contains(name,'$F')].name" -o tsv); do
  out=$(az consumption budget list --subscription "$S" -g "$rg" --query "[].name" -o tsv 2>/dev/null)
  [ -n "$out" ] && echo "== budgets in $rg: $out"
done
echo "== action groups"
az monitor action-group list --subscription "$S" --query "[].{name:name,rg:resourceGroup,location:location}" -o table 2>/dev/null
echo "== activity-log alerts"
az monitor activity-log alert list --subscription "$S" --query "[].{name:name,rg:resourceGroup}" -o table 2>/dev/null
echo "== recent subscription deployments"
az deployment sub list --subscription "$S" --query "sort_by([], &properties.timestamp)[-8:].{name:name,time:properties.timestamp,state:properties.provisioningState}" -o table

#!/bin/bash
# Lab 1.3 - Validation Script
# Validates governance configuration (tags, policies, locks)

set -e

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${BLUE}=== Lab 1.3 Governance Validation ===${NC}\n"

# Check if logged in
echo -e "${BLUE}Checking Azure CLI connection...${NC}"
if ! az account show &> /dev/null; then
    echo -e "${RED}Not logged in to Azure CLI${NC}"
    echo "Please run: az login"
    exit 1
fi
echo -e "${GREEN}Connected to Azure${NC}\n"

# Get subscription ID
SUB_ID=$(az account show --query id -o tsv)
echo -e "${BLUE}Using subscription: $SUB_ID${NC}\n"

# Validate tags
echo -e "${BLUE}=== Validating Resource Group Tags ===${NC}\n"

RGS=("dev-skycraft-swc-rg, prod-skycraft-swc-rg, platform-skycraft-swc-rg")

for rg in "${RGS[@]}"; do
    echo -e "${YELLOW}Checking $rg... ${NC}"

    if az group show --name "$rg" &> /dev/nyull; then
        TAG_COUNT=$(az group show --name "$rg" --query 'length(tags)' -o tsv)
        echo -e "${GREEN}Resource Group exists with $TAG_COUNT tags${NC}"

        # Display tags
        az group show --name "$rg" --query 'tags' -o json | jq -r 'to_entries[] | "\(.key): \(.value)"'
    else
        echo -e "${RED}Resource Group not found: $rg${NC}"
    fi
    echo ""
done

# Validate Azure Policies

echo -e "${BLUE}=== Validating Azure Policy Assignments ===${NC}\n"

for policy in "${POLICIES[@]}"; do
    if az policy assigment show --name "$policy" --scope "/subscrptions/$SUB_ID" &> /dev/null; then
        echo -e "${GREEN}Policy assigmed: $policy${NC}"
    else
        echo -e "${RED}Policy not found: $policy${NC}"
    fi
done

echo -e "\n${YELLOW}Policy Compliance Summary:${NC}"
az policy state summarize \
    --query "results[?policyAssignments[?policyAssignmentId!=null]] | [0].{Compliant:resourceDetails.complianceState}" \
    -o table 2>/dev/null || echo "Run compliance scan from Azure Portal"

# Validate Resource Locks
echo -e "\n${BLUE}=== Validating Resource Locks ===${NC}\n"

LOCK_RGS=("rg-skycraft-prod" "rg-skycraft-shared")

for rg in "${LOCK_RGS[@]}"; do
    LOCK_COUNT=$(az lock list --resource-group "$rg" --query 'length(@)' -o tsv)
    
    if [ "$LOCK_COUNT" -gt 0 ]; then
        echo -e "${GREEN}✓ Locks found on $rg: $LOCK_COUNT${NC}"
        az lock list --resource-group "$rg" --query "[].{Name:name,Level:level}" -o table
    else
        echo -e "${RED}✗ No locks found on $rg${NC}"
    fi
    echo ""
done

# Validate Budgets

echo -e "${BLUE}=== Budget Status ===${NC}\n"
echo -e "${YELLOW}Note: Budget validation requires Cost Management permissions${NC}"
echo -e "Please verify budgets manually in Azure Portal:"
echo -e "  • Cost Management + Billing > Budgets"
echo -e "  • Expected: SkyCraft-Monthly-Budget ($200/month)"
echo -e "  • Expected: SkyCraft-Prod-Monthly ($100/month)"

# Summary

echo -e "\n${BLUE}=== Validation Summary ===${NC}\n"
echo -e "${GREEN}Governance Configuration:${NC}"
echo -e "${GREEN}Lab 1.3 validation complete${NC}"
echo -e "\n${BLUE}Next Steps:${NC}"
echo "  1. Review Policy Compliance in Azure Portal"
echo "  2. Verify budget alerts are configured"
echo "  3. Check Azure Advisor recommendations"
echo "  4. Complete Lab 1.3 checklist"

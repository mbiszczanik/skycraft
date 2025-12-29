#!/bin/bash

# Lab 1.2 - Validation Script
# Validates Resource Groups and role assigments

set -e
export MSYS_NO_PATHCONV=1

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${BLUE}=== Lab 1.2 Validation Script===${NC}\n"

# Check if logged in
echo -e "${BLUE}Checking Azure CLI connection...${NC}"
if ! az account show &> /dev/null; then
    echo -e "${RED}Not logged in to Azure CLI${NC}"
    echo "Please run: az login"
    exit 1
fi
echo -e "${GREEN}Connected to Azure${NC}\n"

# Validate Resource Groups
echo -e "${BLUE}Validating Resource Groups...${NC}"
EXPECTED_RGS=("dev-skycraft-swc-rg" "prod-skycraft-swc-rg" "platform-skycraft-swc-rg")

for rg in "${EXPECTED_RGS[@]}"; do
    if az group show --name "$rg" &> /dev/null; then
        echo -e "${GREEN}Resource Group exists: $rg${NC}"
    else
        echo -e "${RED}Resource group missing: $rg${NC}"
    fi
done

echo ""

# List all role assignments
echo -e "${BLUE}Checking role assignments (including inherited)..${NC}"

# Get current subscription ID and strip potential carriage returns (common on Windows Bash)
SUB_ID=$(az account show --query id -o tsv | tr -d '\r')

if [ -z "$SUB_ID" ]; then
    echo -e "${RED}Error: Could not determine Subscription ID.${NC}"
    exit 1
fi

for rg in "${EXPECTED_RGS[@]}"; do
    echo -e "\n${YELLOW}--- $rg ---${NC}"
    az role assignment list --scope "/subscriptions/$SUB_ID/resourceGroups/$rg" \
        --query "[].{Principal:principalName || principalId, Role:roleDefinitionName, Scope:scope}" -o table
done

# Summary
echo -e "\n${BLUE}=== Validation Summary ===${NC}"
echo -e "${GREEN}Lab 1.2 validation complete${NC}"
#!/bin/bash

# Lab 1.2 - Validation Script
# Validates Resource Groups and role assigments

set -e 

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[1;33,'
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
EXPECTED_RGS=("dev-skycraft-swc-rg, prod-skycraft-swc-rg, platform-skycraft-swc-rg")

for rg in "${EXPECTED_RGS[@]}"; do
    if az group show --name "$rg" &> /dev/null; then
        echo -e "${GREEN}Resource Group exists: $rg${NC}"
    else
        echo -e "${RED}Resource group missing: $rg${NC}"
    fi
done

echo ""

# List all role assigments
echo -e "${BLUE}Checking role assigments..${NC}"

# Check dev RG
echo -e "\n${YELLOW}dev-skycraft-swc-rg:${NC}"
az role assigment list --resource-group dev-skycraft-swc-rg \
    --query "[].{Principal:principalName,Role:roleDefinitionName}" \

# Check prod RG
echo -e "\n${YELLOW}prod-skycraft-swc-rg:${NC}"
az role assigment list --resource-group prod-skycraft-swc-rg \
    --query "[].{Principal:principalName,Role:roleDefinitionName}" \

# Check platform RG
echo -e "\n${YELLOW}platform-skycraft-swc-rg:${NC}"
az role assigment list --resource-group platform-skycraft-swc-rg \
    --query "[].{Principal:principalName,Role:roleDefinitionName}" \

# Summary
echo -e "\n${BLUE}=== Validation Summary ===${NC}"
echo -e "${GREEN}Lab 1.2 validation complete${NC}"
echo -e "\nNext steps:"
echo "  1. Review the role assignments above"
echo "  2. Verify expected principals and roles"
echo "  3. Complete Lab 1.2 checklist"
echo "  4. Proceed to Lab 1.3"
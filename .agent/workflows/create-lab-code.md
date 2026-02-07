---
description: Phase 2 - Create Bicep IaC and PowerShell scripts based on corrected lab guide
---

# Create Lab Code (Phase 2)

Create all Infrastructure-as-Code and automation scripts based on the corrected lab guide from Phase 1.

## Prerequisites

- [ ] Phase 1 complete (`/create-lab`)
- [ ] Lab guide manually tested and corrected
- [ ] Azure feature dependencies validated

## 1. Analyze Corrected Guide

Review the lab guide for infrastructure requirements:

1. **Resources**: List all Azure resources to deploy
2. **Configuration**: Note specific SKUs, tiers, redundancy levels
3. **Dependencies**: Identify resources from previous labs (use `existing`)
4. **Scope**: New infrastructure vs. updates to existing

## 2. Design Bicep Architecture

```
bicep/
├── main.bicep          # Orchestrator (subscription scope)
└── modules/
    ├── network.bicep   # VNets, Subnets
    ├── storage.bicep   # Storage Accounts
    ├── compute.bicep   # VMs, Containers
    └── security.bicep  # NSGs, ASGs
```

## 3. Create Bicep Modules

For each module, follow `docs/BICEP_STANDARDS.md`:

1. **Header**: Standard metadata block
2. **Parameters**: Hungarian notation (`parLocation`, `parEnvironment`)
3. **Variables**: `varCommonTags` with Project, Environment, CostCenter
4. **Resources**: Stable API versions, apply tags
5. **Outputs**: Resource IDs needed by other modules

> **Match the guide exactly**: Configuration in Bicep must match documentation

## 4. Create Orchestrator

`main.bicep` at subscription scope:

1. **Reference existing RGs** or create new ones
2. **Call modules** with correct parameters
3. **Handle dependencies** (implicit via outputs)

## 5. Create PowerShell Scripts

### Deploy-Bicep.ps1

- Deploy Bicep to Azure
- Handle parameters, what-if mode
- Follow `docs/POWERSHELL_STANDARDS.md`

### Test-Lab.ps1

- Verify deployed resources
- Check configurations match expectations
- Return PASS/FAIL status

### Remove-LabResource.ps1

- Clean up lab resources
- Handle dependencies (NSG disassociation, etc.)
- Confirmation prompt unless `-Force`

## 6. Build Validation

```powershell
# Validate Bicep syntax
az bicep build --file bicep/main.bicep

# Lint for best practices
az bicep lint --file bicep/main.bicep
```

## Output

Phase 2 complete when:

- [ ] `bicep/main.bicep` + modules created
- [ ] `scripts/Deploy-Bicep.ps1` created
- [ ] `scripts/Test-Lab.ps1` created
- [ ] `scripts/Remove-LabResource.ps1` created
- [ ] Bicep builds without errors
- [ ] Ready for Phase 3: `/validate-lab`

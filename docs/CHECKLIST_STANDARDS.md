# SkyCraft Checklist Standards

> **Source of Truth** for Lab Completion Checklists

This document defines the structure, content, and purpose of lab checklist files (`lab-checklist-X.Y.md`). Checklists serve as **verification tools** to confirm successful lab completion, not as learning materials. They complement lab guides but must NOT duplicate content.

---

## 1. Purpose and Scope

### What Checklists ARE

- **Verification instruments**: Confirm all resources were created correctly
- **Configuration records**: Document actual deployed values (IPs, names, IDs)
- **Quality assurance**: Ensure naming conventions and tagging compliance
- **Assessment tools**: Allow instructors to verify student work
- **Troubleshooting aids**: Provide validation commands to diagnose issues

### What Checklists ARE NOT

- **Learning materials**: Explanations belong in lab guides, not checklists
- **Instruction manuals**: Step-by-step guidance belongs in lab guides
- **Knowledge tests**: Theoretical questions belong in lab guide Knowledge Checks
- **Duplicate content**: Never copy-paste sections from lab guides

---

## 2. File Structure (Required Sections)

Every checklist must follow this exact structure:

```markdown
# Lab X.Y Completion Checklist

## ✅ [Resource Category 1] Verification
[Checkboxes for configuration items]

## ✅ [Resource Category 2] Verification
[Checkboxes for configuration items]

## 🔍 Validation Commands
[Azure CLI/PowerShell commands to verify deployment]

## 📊 [Summary Table]
[Visual summary of deployed architecture]

## 📝 Reflection Questions
[Open-ended, experiential questions]

## ⏱️ Completion Tracking
[Time tracking and metadata]

## ✅ Final Lab X.Y Sign-off
[Final approval checklist]

## 🎉 Congratulations!
[Brief summary of accomplishments]

## 📌 Module Navigation
[Links to next lab]
```

---

## 3. Content Guidelines

### 3.1 Verification Checkboxes

**Format**: Each resource type gets its own subsection with specific configuration details to verify.

**DO**:
- ✅ List exact resource names following naming conventions
- ✅ Include specific configuration values (SKU, IP ranges, sizes)
- ✅ Reference tags that must be applied (Project, Environment, CostCenter)
- ✅ Verify relationships (peerings, associations, dependencies)

**DON'T**:
- ❌ Explain WHY something should be configured that way (belongs in lab guide)
- ❌ Provide step-by-step instructions (belongs in lab guide)
- ❌ Include screenshots (reference lab guide instead)

**Example (CORRECT)**:

```markdown
## ✅ Hub Virtual Network (platform-skycraft-swc-vnet)

### Network Configuration
- [ ] Virtual network name: `platform-skycraft-swc-vnet`
- [ ] Location: **Sweden Central**
- [ ] Resource group: `platform-skycraft-swc-rg`
- [ ] Address space: `10.0.0.0/16`
- [ ] DNS servers: Default (Azure-provided)

### Subnets
- [ ] **AzureBastionSubnet**
  - Name: `AzureBastionSubnet` (exact match, case-sensitive)
  - Address range: `10.0.0.0/26`
  - Available IPs: 59 (64 total - 5 reserved)
```

**Example (INCORRECT - too much explanation)**:

```markdown
## ✅ Hub Virtual Network

- [ ] Virtual network created
  - The hub VNet is the central point in our hub-spoke topology. It contains shared services like Azure Bastion which provides secure RDP/SSH access without exposing VMs to the internet. We chose a /16 address space because it provides 65,536 IP addresses which allows for future growth...
```

---

### 3.2 Validation Commands

**Purpose**: Provide copy-paste Azure CLI or PowerShell commands that students/instructors can run to verify deployment.

**Structure**:

```markdown
## 🔍 Validation Commands

Run these Azure CLI commands to validate your lab setup:

### Login and Set Context

```azurecli
# Login to Azure
az login

# Set subscription context
az account set --subscription "YOUR-SUBSCRIPTION-NAME"
```

### Verify [Resource Type]

```azurecli
# List all VNets
az network vnet list \
  --query "[].{Name:name,ResourceGroup:resourceGroup,AddressSpace:addressSpace.addressPrefixes[0]}" \
  --output table

# Expected output:
# Name                       ResourceGroup            AddressSpace
# ------------------------   ----------------------   -------------
# platform-skycraft-swc-vnet platform-skycraft-swc-rg 10.0.0.0/16
```
```

**Requirements**:
- Always include expected output
- Use `--query` to filter relevant fields only
- Use `--output table` for readability
- Group commands by resource type
- Include comments explaining what each command checks

---

### 3.3 Reflection Questions (CRITICAL DISTINCTION)

**Purpose**: Capture hands-on experience and practical application, NOT test theoretical knowledge.

**RULE**: If a question tests conceptual understanding with a provided answer, it belongs in the **Lab Guide Knowledge Check**, not here.

**Checklist Reflection Questions MUST**:
- ✅ Be open-ended (no provided answers)
- ✅ Require students to document what THEY built
- ✅ Capture experiential learning (challenges, solutions, observations)
- ✅ Allow instructor review and feedback
- ✅ Include space for student responses

**DO**:

```markdown
## 📝 Reflection Questions

### Question 1: IP Address Documentation
**Document the public IP addresses you created:**

| Resource | Public IP Address | Purpose |
|----------|-------------------|---------|
| platform-skycraft-swc-bas-pip | __________ | Azure Bastion |
| dev-skycraft-swc-lb-pip | __________ | Dev load balancer |

### Question 2: Troubleshooting Experience
**What was the most challenging part of this lab? How did you resolve it?**

_________________________________________________________________

_________________________________________________________________

### Question 3: Architecture Expansion
**If you added a staging environment, what address space would you use?**

- VNet name: __________________
- Address space: __________________
- Justification: _________________________________________________________________

**Instructor Review Date**: _________  
**Feedback**: _________________________________________________________________
```

**DON'T** (this belongs in Lab Guide Knowledge Check):

```markdown
### Question 1: Subnet Sizing
**What is the minimum subnet size for AzureBastionSubnet?**

<details>
  <summary>Click to see the answer</summary>
  Answer: /26 (64 IP addresses). Azure Bastion requires...
</details>
```

**Key Difference**:
- **Lab Guide Knowledge Check**: "What is...?" / "Why does...?" / "How does...?" with provided answers
- **Checklist Reflection**: "What did you...?" / "How did you...?" / "Document your..." with student fills in blanks

---

### 3.4 Summary Tables

**Purpose**: Provide a visual, at-a-glance view of the entire deployed architecture.

**Format**:

```markdown
## 📊 Network Architecture Summary

| Component | Name | Address Space | Subnets | Peerings | Status |
|-----------|------|---------------|---------|----------|--------|
| **Hub VNet** | platform-skycraft-swc-vnet | 10.0.0.0/16 | 2 | 2 | ✅ |
| └─ Bastion Subnet | AzureBastionSubnet | 10.0.0.0/26 | N/A | N/A | ✅ |
```

**Use Cases**:
- Network topology summaries
- Resource inventory tables
- Cost tracking tables
- Deployment status matrices

---

## 4. Emoji Usage (Standardized)

Use these emojis consistently across all checklists:

| Section Type | Emoji | Usage |
|--------------|-------|-------|
| **Verification** | ✅ | Resource configuration checklists |
| **Validation** | 🔍 | CLI/PowerShell command sections |
| **Summary** | 📊 | Architecture/resource summary tables |
| **Reflection** | 📝 | Open-ended student response questions |
| **Time Tracking** | ⏱️ | Lab duration and completion dates |
| **Sign-off** | ✅ | Final approval section |
| **Celebration** | 🎉 | Congratulations/completion message |
| **Navigation** | 📌 | Links to other labs |

---

## 5. Time Tracking Section

**Purpose**: Capture actual time spent vs. estimated time for course improvement.

**Required Format**:

```markdown
## ⏱️ Completion Tracking

- **Estimated Time**: 3 hours
- **Actual Time Spent**: _________ hours
- **Date Started**: _________
- **Date Completed**: _________

**Challenges Encountered** (optional):

_________________________________________________________________
```

---

## 6. Final Sign-off Section

**Purpose**: Formal verification that all lab objectives were met.

**Required Format**:

```markdown
## ✅ Final Lab X.Y Sign-off

**All Verification Items Complete**:
- [ ] All resources created with proper naming conventions
- [ ] All tags applied (Project, Environment, CostCenter)
- [ ] All validation commands executed successfully
- [ ] All reflection questions answered
- [ ] Ready to proceed to Lab X.Z

**Student Name**: _________________  
**Lab X.Y Completion Date**: _________________  
**Instructor Signature**: _________________
```

---

## 7. Anti-Patterns (What NOT to Do)

### ❌ Anti-Pattern 1: Duplicating Lab Guide Content

**WRONG**:

```markdown
## ✅ Create Hub Virtual Network

Follow these steps to create the hub VNet:

1. Navigate to Virtual Networks
2. Click + Create
3. Enter the name platform-skycraft-swc-vnet
4. Select Sweden Central region
...
```

**WHY**: Step-by-step instructions belong ONLY in lab guides, not checklists.

**RIGHT**:

```markdown
## ✅ Hub Virtual Network Verification

- [ ] Virtual network name: `platform-skycraft-swc-vnet`
- [ ] Location: **Sweden Central**
- [ ] Address space: `10.0.0.0/16`
```

---

### ❌ Anti-Pattern 2: Knowledge Checks with Provided Answers

**WRONG** (in checklist):

```markdown
### Question: What is VNet peering?

<details>
  <summary>Click for answer</summary>
  VNet peering connects two Azure virtual networks...
</details>
```

**WHY**: This tests conceptual knowledge and belongs in the Lab Guide Knowledge Check section.

**RIGHT** (in checklist):

```markdown
### Question: Document Your Peering Configuration

List the peering connections you created:

1. Peering name: __________ | Remote VNet: __________ | Status: __________
2. Peering name: __________ | Remote VNet: __________ | Status: __________
```

---

### ❌ Anti-Pattern 3: Generic Checkboxes

**WRONG**:

```markdown
- [ ] Virtual network created
- [ ] Subnets configured
- [ ] Everything looks good
```

**WHY**: Too vague, can't verify specific requirements.

**RIGHT**:

```markdown
- [ ] Virtual network name: `platform-skycraft-swc-vnet` (follows naming convention)
- [ ] Subnet: `AzureBastionSubnet` with address range `10.0.0.0/26`
- [ ] Tag: `Project` = `SkyCraft`
```

---

## 8. Checklist Boilerplate Template

Copy this template when creating a new checklist:

```markdown
# Lab X.Y Completion Checklist

## ✅ [Resource Type 1] Verification

### [Subcategory]
- [ ] Resource name: `[exact-name-from-standards]`
- [ ] Location: **Sweden Central**
- [ ] Resource group: `[rg-name]`
- [ ] [Specific configuration]: [expected value]

### Tags
- [ ] Tag: `Project` = `SkyCraft`
- [ ] Tag: `Environment` = `[Development|Production|Platform]`
- [ ] Tag: `CostCenter` = `MSDN`

---

## ✅ [Resource Type 2] Verification

[Repeat pattern]

---

## 🔍 Validation Commands

Run these Azure CLI commands to validate your lab setup:

### Verify [Resource Type]

```azurecli
# Command description
az [command] \
  --query "[].{Field:property}" \
  --output table

# Expected output:
# [Show expected table output]
```

---

## 📊 [Architecture/Resource] Summary

| Component | Name | [Property 1] | [Property 2] | Status |
|-----------|------|--------------|--------------|--------|
| [Type] | [name] | [value] | [value] | ✅ |

---

## 📝 Reflection Questions

### Question 1: [Open-ended Documentation Question]
**[Prompt requiring student to document what they built]**

_________________________________________________________________

### Question 2: [Experiential Learning Question]
**What challenges did you encounter? How did you resolve them?**

_________________________________________________________________

### Question 3: [Architecture Extension Question]
**How would you modify this for [scenario]?**

_________________________________________________________________

**Instructor Review Date**: _________  
**Feedback**: _________________________________________________________________

---

## ⏱️ Completion Tracking

- **Estimated Time**: X hours
- **Actual Time Spent**: _________ hours
- **Date Started**: _________
- **Date Completed**: _________

---

## ✅ Final Lab X.Y Sign-off

**All Verification Items Complete**:
- [ ] All resources created with proper naming conventions
- [ ] All tags applied correctly
- [ ] All validation commands executed successfully
- [ ] All reflection questions answered
- [ ] Ready to proceed to Lab X.Z

**Student Name**: _________________  
**Lab X.Y Completion Date**: _________________  
**Instructor Signature**: _________________

---

## 🎉 Congratulations!

You've successfully completed **Lab X.Y: [Title]**!

**What You Built**:
- ✅ [Key accomplishment 1]
- ✅ [Key accomplishment 2]
- ✅ [Key accomplishment 3]

**Next**: [Lab X.Z: Title →](../X.Z-lab-name/lab-guide-X.Z.md)

---

## 📌 Module Navigation

- [← Back to Module X Index](../README.md)
- [Lab X.Z: Next Lab →](../X.Z-lab-name/lab-guide-X.Z.md)
```

---

## 9. Quality Checklist for Checklist Authors

Before finalizing a checklist, verify:

- [ ] No step-by-step instructions included (those belong in lab guide)
- [ ] No Knowledge Check questions with provided answers (those belong in lab guide)
- [ ] All resource names follow STANDARDS.md naming conventions
- [ ] All tags reference match BICEP_STANDARDS.md requirements
- [ ] Validation commands include expected output
- [ ] Reflection Questions are open-ended and experiential
- [ ] Summary table provides at-a-glance architecture view
- [ ] Emojis follow DOCUMENTATION_STANDARDS.md guidelines
- [ ] Final sign-off section included
- [ ] Module navigation links work

---

## 10. Related Standards

This document complements:

- **DOCUMENTATION_STANDARDS.md**: Covers lab guide structure and markdown formatting
- **STANDARDS.md**: Defines resource naming conventions
- **BICEP_STANDARDS.md**: Specifies required tags and IaC patterns
- **POWERSHELL_STANDARDS.md**: PowerShell script conventions

**Rule of Thumb**: If it teaches a concept, it belongs in the lab guide. If it verifies correct implementation, it belongs in the checklist.

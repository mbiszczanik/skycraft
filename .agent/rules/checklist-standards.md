# SkyCraft Checklist Creation Standards

> **MEMORY FILE** for creating lab completion checklists (`lab-checklist-X.Y.md`).

---

## 1. Purpose

Checklists are **verification instruments** — they confirm resources were created correctly. They are NOT learning materials.

| Checklists ARE                       | Checklists ARE NOT                |
| ------------------------------------ | --------------------------------- |
| Verification of configurations       | Learning materials                |
| Documentation of deployed values     | Step-by-step instructions         |
| Quality assurance for naming/tagging | Knowledge tests                   |
| Assessment tools for instructors     | Duplicate content from lab guides |

---

## 2. Required Sections (In Order)

| Section               | Emoji | Purpose                                   |
| --------------------- | ----- | ----------------------------------------- |
| Title                 | n/a   | `# Lab X.Y Completion Checklist`          |
| Resource Verification | ✅    | Checkboxes for configuration items        |
| Validation Commands   | 🔍    | Azure CLI/PowerShell with expected output |
| Summary Table         | 📊    | At-a-glance architecture view             |
| Reflection Questions  | 📝    | Open-ended, experiential questions        |
| Completion Tracking   | ⏱️    | Time tracking and dates                   |
| Final Sign-off        | ✅    | Formal completion verification            |
| Congratulations       | 🎉    | Brief accomplishments summary             |
| Module Navigation     | 📌    | Links to next lab                         |

---

## 3. Verification Checkboxes Format

```markdown
## ✅ Hub Virtual Network (platform-skycraft-swc-vnet)

### Network Configuration

- [ ] Virtual network name: `platform-skycraft-swc-vnet`
- [ ] Location: **Sweden Central**
- [ ] Resource group: `platform-skycraft-swc-rg`
- [ ] Address space: `10.0.0.0/16`

### Tags

- [ ] Tag: `Project` = `SkyCraft`
- [ ] Tag: `Environment` = `Platform`
- [ ] Tag: `CostCenter` = `MSDN`
```

**Rules**:

- List **exact resource names** following STANDARDS.md
- Include specific values (SKU, IP ranges, sizes)
- NO explanations of WHY (belongs in lab guide)
- NO step-by-step instructions

---

## 4. Validation Commands Format

````markdown
## 🔍 Validation Commands

### Verify VNets

```azurecli
# List all VNets with address spaces
az network vnet list \
  --query "[].{Name:name,ResourceGroup:resourceGroup,AddressSpace:addressSpace.addressPrefixes[0]}" \
  --output table

# Expected output:
# Name                        ResourceGroup             AddressSpace
# ------------------------    ----------------------    -------------
# platform-skycraft-swc-vnet  platform-skycraft-swc-rg  10.0.0.0/16
```
````

````

**Requirements**:
- Always include **expected output**
- Use `--query` to filter relevant fields
- Use `--output table` for readability
- Group commands by resource type

---

## 5. Reflection Questions (CRITICAL)

> **RULE**: Checklist Reflection Questions are **OPEN-ENDED** with NO provided answers. This distinguishes them from Lab Guide Knowledge Checks.

| Type | Location | Answer Format |
|------|----------|---------------|
| "What is...?" / "Why does...?" | Lab Guide Knowledge Check | `<details>` with answer |
| "What did you...?" / "Document your..." | Checklist Reflection | Student fills in blanks |

**Correct Format**:

```markdown
## 📝 Reflection Questions

### Question 1: IP Address Documentation
**Document the public IP addresses you created:**

| Resource | Public IP Address | Purpose |
|----------|-------------------|---------|
| platform-skycraft-swc-bas-pip | __________ | Azure Bastion |

### Question 2: Troubleshooting Experience
**What was the most challenging part? How did you resolve it?**

_________________________________________________________________

**Instructor Review Date**: _________
**Feedback**: _________________________________________________________________
````

---

## 6. Final Sign-off Format

```markdown
## ✅ Final Lab X.Y Sign-off

**All Verification Items Complete**:

- [ ] All resources created with proper naming conventions
- [ ] All tags applied (Project, Environment, CostCenter)
- [ ] All validation commands executed successfully
- [ ] All reflection questions answered
- [ ] Ready to proceed to Lab X.Z

**Student Name**: ********\_********
**Lab X.Y Completion Date**: ********\_********
**Instructor Signature**: ********\_********
```

---

## 7. Anti-Patterns to AVOID

| ❌ Don't                                 | ✅ Do                                  |
| ---------------------------------------- | -------------------------------------- |
| Step-by-step instructions                | Verification checkboxes only           |
| Knowledge Check with `<details>` answers | Open-ended student fill-in questions   |
| Generic: "Virtual network created"       | Specific: `platform-skycraft-swc-vnet` |
| Explanations of WHY                      | Just the expected values               |
| Duplicate lab guide content              | Reference lab guide for details        |

---

## 8. Checklist Boilerplate

````markdown
# Lab X.Y Completion Checklist

## ✅ [Resource Type] Verification

### [Subcategory]

- [ ] Resource name: `[exact-name]`
- [ ] Location: **Sweden Central**
- [ ] Resource group: `[rg-name]`
- [ ] [Property]: [expected value]

### Tags

- [ ] Tag: `Project` = `SkyCraft`
- [ ] Tag: `Environment` = `[Development|Production|Platform]`
- [ ] Tag: `CostCenter` = `MSDN`

---

## 🔍 Validation Commands

```azurecli
# Verify [resource type]
az [command] \
  --query "[].{Field:property}" \
  --output table

# Expected output:
# [table output]
```
````

---

## 📊 [Architecture] Summary

| Component | Name   | Property | Status |
| --------- | ------ | -------- | ------ |
| [Type]    | [name] | [value]  | ✅     |

---

## 📝 Reflection Questions

### Question 1: [Documentation Question]

**[Prompt requiring student to document what they built]**

---

### Question 2: [Experiential Question]

**What challenges did you encounter? How did you resolve them?**

---

**Instructor Review Date**: ****\_****
**Feedback**: ********************************\_********************************

---

## ⏱️ Completion Tracking

- **Estimated Time**: X hours
- **Actual Time Spent**: ****\_**** hours
- **Date Started**: ****\_****
- **Date Completed**: ****\_****

---

## ✅ Final Lab X.Y Sign-off

- [ ] All resources created with proper naming conventions
- [ ] All tags applied correctly
- [ ] All validation commands executed successfully
- [ ] All reflection questions answered
- [ ] Ready to proceed to Lab X.Z

**Student Name**: ********\_********
**Lab X.Y Completion Date**: ********\_********
**Instructor Signature**: ********\_********

---

## 🎉 Congratulations!

You've completed **Lab X.Y: [Title]**!

**What You Built**:

- ✅ [Accomplishment 1]
- ✅ [Accomplishment 2]

**Next**: [Lab X.Z →](../X.Z-lab-name/lab-guide-X.Z.md)

---

## 📌 Module Navigation

- [← Back to Module X Index](../README.md)
- [Lab X.Z: Next Lab →](../X.Z-lab-name/lab-guide-X.Z.md)

```

---

## 9. Quality Checklist

Before finalizing any checklist, verify:

- [ ] **No step-by-step instructions** (belong in lab guide)
- [ ] **No Knowledge Check Q&A** with provided answers (belong in lab guide)
- [ ] All resource names follow STANDARDS.md
- [ ] All tags match BICEP_STANDARDS.md
- [ ] Validation commands include **expected output**
- [ ] Reflection Questions are **open-ended**
- [ ] Summary table provides at-a-glance view
- [ ] Final sign-off section included
- [ ] Module navigation links work

---

**Rule of Thumb**: If it **teaches a concept**, it belongs in the lab guide. If it **verifies correct implementation**, it belongs in the checklist.

```

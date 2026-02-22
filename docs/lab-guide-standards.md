# SkyCraft Lab Guide Standards

> **Source of Truth** for Lab Guide Creation

This document defines the structure, formatting rules, and content requirements for lab guide files (`lab-guide-X.Y.md`). Lab guides are **instructional materials** that teach concepts and walk students through Azure configuration. They complement checklists but must NOT duplicate verification content.

For the ready-to-copy skeleton with `[PLACEHOLDER]` markers, see `lab-guide-template.md`.

---

## 1. Purpose and Scope

### What Lab Guides ARE

- **Instructional materials**: Step-by-step guidance through Azure configuration
- **Concept explainers**: Deep dives into technology with comparison tables
- **Decision documentation**: SkyCraft Choice callouts explaining architectural decisions
- **Knowledge tests**: Conceptual questions with provided answers in `<details>` blocks
- **Multi-modal training**: Portal, CLI, and PowerShell methods for every step (AZ-104 alignment)

### What Lab Guides ARE NOT

- **Verification tools**: Resource validation belongs in checklists
- **Open-ended assessments**: Reflection questions belong in checklists
- **CLI-only scripts**: Validation commands belong in checklists
- **Duplicate content**: Never copy-paste verification items from checklists

---

## 2. Required Sections (In Order)

Every lab guide must include these sections with their emojis:

| Section               | Emoji | Purpose                                          |
| --------------------- | ----- | ------------------------------------------------ |
| Title                 | n/a   | `# Lab X.Y: [Title] ([Duration] hours)`          |
| Learning Objectives   | 🎯    | 5-7 measurable outcomes with AZ-104 action verbs |
| Architecture Overview | 🏗️    | **MANDATORY** Mermaid diagram                    |
| Real-World Scenario   | 📋    | Business context with SkyCraft deployment        |
| Estimated Time        | ⏱️    | Section-by-section breakdown (must sum to total) |
| Prerequisites         | ✅    | Dependencies, roles, verification CLI block      |
| Deep Dive (Concept)   | 📖    | Theory + comparison tables before configuration  |
| Configuration         | ⚙️    | Multi-modal step-by-step instructions            |
| Lab Checklist         | ✅    | Quick verification (link to detailed checklist)  |
| Troubleshooting       | 🔧    | 5-10 common issues with Root Cause analysis      |
| Knowledge Check       | 🎓    | 5-7 Q&A with `<details>` answers                 |
| Additional Resources  | 📚    | Microsoft Learn links only                       |
| Module Navigation     | 📌    | ← Back + ← Previous + Next →                     |
| Lab Summary           | 📝    | Accomplishments + Infrastructure Deployed table  |

---

## 3. Mermaid Diagram Requirements

**Color Scheme** (MANDATORY):

| Element       | Fill                                                               | Stroke    | Width |
| ------------- | ------------------------------------------------------------------ | --------- | ----- |
| Platform/Hub  | `#e1f5ff`                                                          | `#0078d4` | 3px   |
| Development   | `#fff4e1`                                                          | `#f39c12` | 2px   |
| Production    | `#ffe1e1`                                                          | `#e74c3c` | 2px   |
| Key resources | Accent colors: green `#4CAF50`, purple `#9C27B0`, orange `#FF9800` | —         | —     |

**Must Include**:

- Resource group boundaries (`subgraph`)
- Resource names following `project-standards.md`
- CIDR ranges for networks
- Relationship arrows with labels

---

## 4. Deep Dive & Decision Standards

Every lab **must** explain the _why_ before the _how_.

### 4.1 Deep Dive Concepts

- **Placement**: Before any configuration steps
- **Content**: Explain the core technology (e.g., "What is a Storage Account?")
- **Comparison**: Use tables to compare options (SKUs, Tiers, Redundancy)
- **Length**: 2-3 paragraphs max, then move to action

### 4.2 SkyCraft Choice Callouts

At least **one per lab**. Explicitly state **why** a specific configuration was chosen for SkyCraft.

**Format**:

```markdown
> **SkyCraft Choice**: We chose **[Option]** because [justification relating to cost, performance, or business requirement].
```

---

## 5. Multi-Modal Step Formatting

Labs must teach **Portal (GUI)**, **CLI**, and **PowerShell** methods for every step where applicable. This is critical for AZ-104 which tests all three methods.

### Structure

````markdown
### Step X.Y.Z: [Action Name]

#### Option 1: Azure Portal (GUI)

1. Navigate to **[Section]** → **[Sub-section]**
2. Fill in the details:

| Field | Value         |
| ----- | ------------- |
| Name  | `exact-value` |

#### Option 2: Azure CLI

​`bash
az [command] --name [value] --resource-group [rg] --output table
​`

#### Option 3: PowerShell

​`powershell
[Cmdlet] -ResourceGroupName [rg] -Name [value]
​`

**Expected Result**: [Specific success description]
````

### Rules

- **Bold** for Azure Portal UI elements
- `Code formatting` for values to enter/variables
- Tables for multi-field forms
- Always include **Expected Result** after step groups
- **Screenshots**: Place **after** Expected Result (Instructions → Result → Screenshot)

---

## 6. Knowledge Check Format

```markdown
1. **[Question about concept]?**

   <details>
     <summary>**Click to see the answer**</summary>

   **Answer**: [Detailed explanation with reasoning]
   </details>
```

> **CRITICAL**: Knowledge Checks have **PROVIDED ANSWERS** in `<details>` blocks. This distinguishes them from Checklist Reflection Questions (which are open-ended).

---

## 7. Troubleshooting Format

Every issue must follow the **Symptom → Root Cause → Solution** pattern:

```markdown
### Issue 1: [Problem]

**Symptom**: [Error message or observable behavior]

**Root Cause**: [Why this happened]

**Solution**:

- [Step to resolve]
```

Minimum **5 issues** per lab guide.

---

## 8. Writing Style

| Aspect         | ✅ Correct                 | ❌ Incorrect                        |
| -------------- | -------------------------- | ----------------------------------- |
| Voice          | Active: "Create a VNet"    | Passive: "A VNet should be created" |
| Address        | "You will configure..."    | "The student configures..."         |
| Instructions   | Imperative: "Click Create" | "You should click Create"           |
| Portal Name    | Azure Portal               | "portal", "azure portal"            |
| Region         | Sweden Central             | east us, myRegion                   |
| Resource Names | `prod-skycraft-swc-rg`     | "myResourceGroup"                   |

---

## 9. Time Guidelines

| Module  | Typical Duration   |
| ------- | ------------------ |
| Lab 1.x | 2-3 hours each     |
| Lab 2.x | 1.5-3 hours each   |
| Lab 3.x | 3-4 hours each     |
| Lab 4.x | 1.5-2.5 hours each |
| Lab 5.x | 2-3 hours each     |

Break into 15-30 minute sections. Include reading/understanding time.

---

## 10. Anti-Patterns to AVOID

| ❌ Don't                              | ✅ Do                                            |
| ------------------------------------- | ------------------------------------------------ |
| Long theory blocks (5+ paragraphs)    | Brief context (2-3 paragraphs), then action      |
| Vague results: "VNet will be created" | Specific: "VNet appears with status 'Available'" |
| Bare instructions without context     | Explain WHY: "Must be `/26` (64 IPs minimum)"    |
| Generic names: `myResourceGroup`      | Standard names: `platform-skycraft-swc-rg`       |
| No troubleshooting section            | 5-10 issues with symptoms and solutions          |
| Portal-only instructions              | Multi-modal: Portal + CLI + PowerShell           |
| Validation commands in lab guide      | Move validation to checklist                     |
| Open-ended reflection questions       | Move reflections to checklist                    |

---

## 11. Quality Checklist

Before finalizing any lab guide, verify:

- [ ] Title includes lab number and duration
- [ ] 5-7 clear learning objectives (AZ-104 action verbs)
- [ ] **Mermaid diagram included** with standard color scheme
- [ ] Real-world scenario provides business context
- [ ] **SkyCraft Choice** callout included (≥1, explains architectural decision)
- [ ] **Multi-modal instructions** (Portal + CLI + PowerShell) for all steps
- [ ] Time breakdown adds up to total
- [ ] Prerequisites list all dependencies + **verification CLI block**
- [ ] Every concept section has 📖 emoji
- [ ] Steps numbered sequentially
- [ ] Each step group has "Expected Result"
- [ ] All resource names follow `project-standards.md`
- [ ] All tags match `bicep-standards.md`
- [ ] 5-7 Knowledge Check questions with `<details>` answers
- [ ] Troubleshooting covers 5+ issues with **Root Cause** analysis
- [ ] **Infrastructure Deployed** table in Lab Summary
- [ ] **Closing note** linking lab to broader project
- [ ] Module navigation links work (← Back + ← Previous + Next →)
- [ ] **No validation commands** (belong in checklist)
- [ ] **No open-ended reflection questions** (belong in checklist)

---

## 12. Related Standards

This document complements:

- **lab-guide-template.md**: Ready-to-copy skeleton with `[PLACEHOLDER]` markers
- **checklist-standards.md**: Defines verification checklists (the counterpart to lab guides)
- **project-standards.md**: Defines resource naming conventions
- **bicep-standards.md**: Specifies required tags and IaC patterns
- **powershell-standards.md**: PowerShell script conventions

**Rule of Thumb**: If it **teaches or explains**, it belongs in the lab guide. If it **verifies or assesses**, it belongs in the checklist.

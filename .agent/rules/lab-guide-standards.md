---
trigger: always_on
---

# SkyCraft Lab Guide Creation Standards

> **MEMORY FILE** for creating standardized lab guides (`lab-guide-X.Y.md`).

---

## 1. Required Sections (In Order)

Every lab guide must include these sections with their emojis:

| Section                | Emoji | Purpose                                         |
| ---------------------- | ----- | ----------------------------------------------- |
| Title                  | n/a   | `# Lab X.Y: [Title] ([Duration] hours)`         |
| Learning Objectives    | 🎯    | 3-6 measurable outcomes with action verbs       |
| Architecture Overview  | 🏗️    | **MANDATORY** Mermaid diagram                   |
| Real-World Scenario    | 📋    | Business context with SkyCraft deployment       |
| Estimated Time         | ⏱️    | Section-by-section breakdown                    |
| Prerequisites          | ✅    | Dependencies, roles, required knowledge         |
| Instructional Sections | 📖    | Concepts + Step-by-step instructions            |
| Lab Checklist          | ✅    | Quick verification (link to detailed checklist) |
| Troubleshooting        | 🔧    | 5-10 common issues with solutions               |
| Knowledge Check        | 🎓    | 5-7 Q&A with `<details>` answers                |
| Additional Resources   | 📚    | Microsoft Learn and docs links                  |
| Module Navigation      | 📌    | Previous/next lab links                         |
| Lab Summary            | 📝    | Accomplishments recap                           |

---

## 2. Mermaid Diagram Requirements

**Color Scheme** (MANDATORY):

```mermaid
style HubResources fill:#e1f5ff,stroke:#0078d4,stroke-width:3px   # Platform/Hub
style DevResources fill:#fff4e1,stroke:#f39c12,stroke-width:2px   # Development
style ProdResources fill:#ffe1e1,stroke:#e74c3c,stroke-width:2px  # Production
```

**Must Include**:

- Resource group boundaries (`subgraph`)
- Resource names following STANDARDS.md
- CIDR ranges for networks
- Relationship arrows with labels

---

## 3. Step Formatting

```markdown
### Step X.Y.Z: [Action Name]

1. Navigate to **[Azure Portal section]**
2. Click **[Button/Link]**
3. Fill in the details:

| Field    | Value                             |
| -------- | --------------------------------- |
| Name     | `exact-value-following-standards` |
| Location | **Sweden Central**                |

4. Click **[Action]**

**Expected Result**: [Describe what success looks like]
```

**Rules**:

- **Bold** for Azure Portal UI elements
- `Code formatting` for values to enter
- Tables for multi-field forms
- Always include **Expected Result** after step groups

---

## 4. Knowledge Check Format

```markdown
## 🎓 Knowledge Check

1. **[Question about concept]?**

   <details>
     <summary>**Click to see the answer**</summary>

   **Answer**: [Detailed explanation with reasoning]
   </details>
```

> **CRITICAL**: Knowledge Checks have **PROVIDED ANSWERS** in `<details>` blocks. This distinguishes them from Checklist Reflection Questions (which are open-ended).

---

## 5. Writing Style

| Aspect         | Correct                    | Incorrect                           |
| -------------- | -------------------------- | ----------------------------------- |
| Voice          | Active: "Create a VNet"    | Passive: "A VNet should be created" |
| Address        | "You will configure..."    | "The student configures..."         |
| Instructions   | Imperative: "Click Create" | "You should click Create"           |
| Portal Name    | Azure Portal               | "portal", "azure portal"            |
| Region         | Sweden Central             | east us, myRegion                   |
| Resource Names | `prod-skycraft-swc-rg`     | "myResourceGroup"                   |

---

## 6. Time Guidelines

| Module  | Typical Duration |
| ------- | ---------------- |
| Lab 1.x | 2-3 hours each   |
| Lab 2.x | 1.5-3 hours each |
| Lab 3.x | 3-4 hours each   |

Break into 15-30 minute sections, include reading/understanding time.

---

## 7. Anti-Patterns to AVOID

| ❌ Don't                              | ✅ Do                                            |
| ------------------------------------- | ------------------------------------------------ |
| Long theory blocks (5+ paragraphs)    | Brief context (2-3 paragraphs), then action      |
| Vague results: "VNet will be created" | Specific: "VNet appears with status 'Available'" |
| Bare instructions without context     | Explain WHY: "Must be `/26` (64 IPs minimum)"    |
| Generic names: `myResourceGroup`      | Standard names: `platform-skycraft-swc-rg`       |
| No troubleshooting section            | 5-10 issues with symptoms and solutions          |

---

## 8. Lab Guide Boilerplate

````markdown
# Lab X.Y: [Title] ([Duration] hours)

## 🎯 Learning Objectives

By completing this lab, you will:

- [Objective 1]
- [Objective 2]
- [Objective 3]

---

## 🏗️ Architecture Overview

[Description]: ```mermaid

graph TB
subgraph "Resource Group"
Resource1[name<br/>details]
end
````

## 📋 Real-World Scenario

**Situation**: [Business problem with SkyCraft context]

**Your Task**: [What student will accomplish]

## ⏱️ Estimated Time: X hours

- **Section 1**: [Description] (X min)
- **Section 2**: [Description] (X min)

## ✅ Prerequisites

Before starting this lab:

- [ ] Completed Lab X.Y
- [ ] [Required role] assigned
- [ ] Understanding of [concept 1], [concept 2]

---

## 📖 Section 1: [Concept Name] (Duration)

### What is [Technology]?

[2-3 paragraph explanation]

### Step X.Y.1: [Action]

1. [Instruction]
2. [Instruction]

**Expected Result**: [Success description]

---

## ✅ Lab Checklist

- [ ] [Major accomplishment 1]
- [ ] [Major accomplishment 2]
- [ ] All resources tagged correctly

**For detailed verification**, see [lab-checklist-X.Y.md](lab-checklist-X.Y.md)

## 🔧 Troubleshooting

### Issue 1: [Problem]

**Symptom**: [Description]

**Solution**:

- [Step to resolve]

## 🎓 Knowledge Check

1. **[Question]?**

   <details>
     <summary>**Click to see the answer**</summary>

   **Answer**: [Explanation]
   </details>

## 📚 Additional Resources

- [Azure Documentation Link]
- [Microsoft Learn Module]

## 📌 Module Navigation

[← Back to Module X Index](../README.md)

[Next Lab: X.Y →](link)

## 📝 Lab Summary

**What You Accomplished:**

✅ [Achievement 1]
✅ [Achievement 2]
✅ [Achievement 3]

**Time Spent**: ~X hours

**Ready for Lab X.Y?** Next, you'll [preview of next lab].

```

---

## 9. Quality Checklist

Before finalizing any lab guide, verify:

- [ ] Title includes lab number and duration
- [ ] 3-6 clear learning objectives
- [ ] **Mermaid diagram included**
- [ ] Real-world scenario provides business context
- [ ] Time breakdown adds up to total
- [ ] Prerequisites list all dependencies
- [ ] Every section has 📖 emoji
- [ ] Steps numbered sequentially
- [ ] Each step group has "Expected Result"
- [ ] All resource names follow STANDARDS.md
- [ ] All tags match BICEP_STANDARDS.md
- [ ] 5-7 Knowledge Check questions with `<details>` answers
- [ ] Troubleshooting covers common issues
- [ ] Module navigation links work
- [ ] **No validation commands** (belong in checklist)
- [ ] **No open-ended reflection questions** (belong in checklist)

---

**Rule of Thumb**: If it **teaches or explains**, it belongs in the lab guide. If it **verifies or assesses**, it belongs in the checklist.

```

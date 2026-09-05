# Lab Guide Template — SkyCraft

> **Purpose**: This is a universal skeleton for generating new lab guides. All domain-specific content has been replaced with `[PLACEHOLDER]` markers. Fill each placeholder according to the instructions in brackets.
>
> **Source**: Extracted from Lab 3.1, 3.2, 4.1, and 4.2.

---

## Template Usage Notes

| Convention                  | Meaning                                       |
| --------------------------- | --------------------------------------------- |
| `[PLACEHOLDER_NAME]`        | Replace with lab-specific content             |
| `[PLACEHOLDER_NAME — hint]` | Hint describes what type of content goes here |
| `<!-- OPTIONAL -->`         | Section may be omitted if not applicable      |
| `<!-- REPEAT -->`           | Section/block should be repeated as needed    |

---

<!-- ============================================================ -->
<!-- BEGIN TEMPLATE -->
<!-- ============================================================ -->

# Lab [MODULE.LAB_NUMBER]: [LAB_TITLE] ([DURATION] hours)

## 🎯 Learning Objectives

By completing this lab, you will:

- [OBJECTIVE_1 — Master [AZ-104 skill] by [action]]
- [OBJECTIVE_2 — Implement [AZ-104 skill] for [use case]]
- [OBJECTIVE_3 — Configure [feature] following [best practice]]
- [OBJECTIVE_4 — Troubleshoot [common failure] scenarios]
- [OBJECTIVE_5 — Validate deployments using [CLI/PowerShell]]

---

## 🏗️ Architecture Overview

[ARCHITECTURE_DESCRIPTION — 1-2 sentences describing what the diagram shows]:

```mermaid
graph TB
    subgraph "[RESOURCE_GROUP_NAME_1 — e.g. platform-skycraft-swc-rg]"
        style [STYLE_ID_1] fill:#e1f5ff,stroke:#0078d4,stroke-width:3px
        [RESOURCE_1]["[RESOURCE_DISPLAY_NAME]<br/>[RESOURCE_DETAILS]"]
    end

    subgraph "[RESOURCE_GROUP_NAME_2 — e.g. dev-skycraft-swc-rg]"
        style [STYLE_ID_2] fill:#fff4e1,stroke:#f39c12,stroke-width:2px
        [RESOURCE_2]["[RESOURCE_DISPLAY_NAME]<br/>[RESOURCE_DETAILS]"]
    end

    subgraph "[RESOURCE_GROUP_NAME_3 — e.g. prod-skycraft-swc-rg]"
        style [STYLE_ID_3] fill:#ffe1e1,stroke:#e74c3c,stroke-width:2px
        [RESOURCE_3]["[RESOURCE_DISPLAY_NAME]<br/>[RESOURCE_DETAILS]"]
    end

    [RESOURCE_1] -->|"[RELATIONSHIP_LABEL]"| [RESOURCE_2]
    [RESOURCE_2] -->|"[RELATIONSHIP_LABEL]"| [RESOURCE_3]
```

<!-- NOTE: Color scheme MUST follow standard:
  - Platform/Hub:   fill:#e1f5ff, stroke:#0078d4, stroke-width:3px
  - Development:    fill:#fff4e1, stroke:#f39c12, stroke-width:2px
  - Production:     fill:#ffe1e1, stroke:#e74c3c, stroke-width:2px
  - Key resources:  use accent colors (green #4CAF50, purple #9C27B0, orange #FF9800)
  Always include resource names following project-standards.md and CIDR ranges for networks.
-->

<!-- OPTIONAL: Additional diagrams (e.g. flowcharts for processes, tier transitions) -->

---

## 📋 Real-World Scenario

**Situation**: [BUSINESS_PROBLEM — describe the SkyCraft infrastructure challenge that motivates this lab. Frame as a pain point or growth need. 3-6 lines.]

| [COMPARISON_COLUMN_1 — e.g. Environment/Data Type] | [COMPARISON_COLUMN_2 — e.g. Use Case/Access Pattern] | [COMPARISON_COLUMN_3 — e.g. Requirement] | [COMPARISON_COLUMN_4 — e.g. Priority] |
| --- | --- | --- | --- |
| [ROW_1_VALUE_1] | [ROW_1_VALUE_2] | [ROW_1_VALUE_3] | [ROW_1_VALUE_4] |
| [ROW_2_VALUE_1] | [ROW_2_VALUE_2] | [ROW_2_VALUE_3] | [ROW_2_VALUE_4] |
| [ROW_3_VALUE_1] | [ROW_3_VALUE_2] | [ROW_3_VALUE_3] | [ROW_3_VALUE_4] |

<!-- OPTIONAL: comparison table above — use when lab covers multiple environments or data categories -->

**Your Task**: [TASK_SUMMARY — imperative description of what the student will accomplish. Use bullet list for multi-part tasks]:

- [TASK_ITEM_1]
- [TASK_ITEM_2]
- [TASK_ITEM_3]

**Business Impact**:

- [IMPACT_1 — quantify where possible: "90% reduction in...", "Zero drift..."]
- [IMPACT_2]
- [IMPACT_3]
- [IMPACT_4]

---

## ⏱️ Estimated Time: [TOTAL_DURATION] hours

- **Section 1**: [SECTION_1_TITLE] ([DURATION_1] min)
- **Section 2**: [SECTION_2_TITLE] ([DURATION_2] min)
- **Section 3**: [SECTION_3_TITLE] ([DURATION_3] min)
- **Section 4**: [SECTION_4_TITLE] ([DURATION_4] min)
- **Section 5**: [SECTION_5_TITLE] ([DURATION_5] min)

<!-- NOTE: Individual section durations must sum to total. Typical sections: 15-45 min each. -->

---

## ✅ Prerequisites

Before starting this lab:

- [ ] Completed [PREREQUISITE_LAB — e.g. Lab 2.1 (Virtual Networks)]
- [ ] Existing resources:
  - [EXISTING_RESOURCE_1 — e.g. Resource groups: `platform-skycraft-swc-rg`, `dev-skycraft-swc-rg`]
  - [EXISTING_RESOURCE_2 — e.g. VNets: `platform-skycraft-swc-vnet`, `dev-skycraft-swc-vnet`]
- [ ] [REQUIRED_TOOL_1 — e.g. Azure CLI installed (version 2.50.0 or later)]
- [ ] [REQUIRED_TOOL_2 — e.g. PowerShell Az module installed]
- [ ] [REQUIRED_ROLE — e.g. Contributor or Owner role at subscription level]
- [ ] Understanding of [CONCEPT_PREREQUISITES — e.g. cloud storage concepts]

<!-- OPTIONAL: CLI verification block -->

**Verify prerequisites**:

```azurecli
# [VERIFICATION_DESCRIPTION]
[VERIFICATION_COMMAND_1]

# [VERIFICATION_DESCRIPTION]
[VERIFICATION_COMMAND_2]
````

---

<!-- ============================================================ -->
<!-- INSTRUCTIONAL SECTIONS — REPEAT block below for each section  -->
<!-- ============================================================ -->

## 📖 Section [N]: [SECTION_TITLE] ([DURATION] minutes)

### What is [TECHNOLOGY_NAME]?

[CONCEPT_EXPLANATION — 2-3 paragraphs explaining the technology/concept. Keep it concise, then move to action. Use active voice and direct address ("you").]

<!-- OPTIONAL: Concept comparison table -->

| [COMPARISON_HEADER_1] | [COMPARISON_HEADER_2] | [COMPARISON_HEADER_3] | [COMPARISON_HEADER_4 — e.g. SkyCraft Use Case] |
| --------------------- | --------------------- | --------------------- | ---------------------------------------------- |
| [ROW_VALUE_1]          | [ROW_VALUE_2]          | [ROW_VALUE_3]          | [ROW_VALUE_4]                                   |

<!-- OPTIONAL: Key characteristics bullet list -->

**Key Characteristics**:

- [CHARACTERISTIC_1]
- [CHARACTERISTIC_2]
- [CHARACTERISTIC_3]

<!-- OPTIONAL: Strategy/decision table for SkyCraft -->

### [SKYCRAFT_CONTEXT_HEADING — e.g. "SkyCraft Redundancy Strategy", "VM Sizing for Game Servers"]

| [DECISION_COLUMN_1 — e.g. Environment] | [DECISION_COLUMN_2 — e.g. Choice] | [DECISION_COLUMN_3 — e.g. Justification] |
| -------------------------------------- | --------------------------------- | ---------------------------------------- |
| [ROW_VALUE_1]                          | [ROW_VALUE_2]                     | [ROW_VALUE_3]                            |

> **SkyCraft Choice**: We chose **[OPTION]** because [JUSTIFICATION — relate to cost, performance, or business requirement].

---

### Step [MODULE.LAB.STEP]: [STEP_ACTION_NAME — imperative verb: Create, Configure, Verify, Enable]

[STEP_CONTEXT — 1-2 sentences explaining WHY this step is needed. Optional.]

#### Option 1: Azure Portal (GUI)

1. Navigate to **[AZURE_PORTAL_SECTION]** → **[SUB_SECTION]**
2. Click **[BUTTON_NAME]**
3. Fill in the details:

| Field     | Value                               |
| --------- | ----------------------------------- |
| [FIELD_1] | `[EXACT_VALUE_FOLLOWING_STANDARDS]` |
| [FIELD_2] | **[VALUE_WITH_EMPHASIS]**           |
| [FIELD_3] | [Your subscription]                 |

4. Click **[ACTION_BUTTON — e.g. Review + create]**
5. Click **[CONFIRM_BUTTON — e.g. Create]**

#### Option 2: Azure CLI

```bash
# [COMMAND_DESCRIPTION]
az [COMMAND] \
  --name [RESOURCE_NAME] \
  --resource-group [RESOURCE_GROUP] \
  --location $LOCATION \
  [ADDITIONAL_FLAGS]
```

#### Option 3: PowerShell

```powershell
# [COMMAND_DESCRIPTION]
[POWERSHELL_CMDLET] `
    -ResourceGroupName [RESOURCE_GROUP] `
    -Name [RESOURCE_NAME] `
    -Location $Location `
    [ADDITIONAL_PARAMETERS]
```

**Expected Result**: [SPECIFIC_SUCCESS_DESCRIPTION — describe what success looks like, e.g. "VM `dev-skycraft-swc-auth-vm` created in Zone 1"]

![Step Description](images/step-[MODULE.LAB.STEP].png)

<!-- OPTIONAL: Verification table -->

| Property     | Expected Value     |
| ------------ | ------------------ |
| [PROPERTY_1] | [EXPECTED_VALUE_1] |
| [PROPERTY_2] | [EXPECTED_VALUE_2] |

<!-- NOTE: Alerts — use for important callouts within steps -->

> [!NOTE]
> [INFORMATIONAL_NOTE — background context or explanation for a design choice]

> [!TIP]
> [HELPFUL_TIP — performance optimization, best practice, or efficiency suggestion]

> [!IMPORTANT]
> [ESSENTIAL_REQUIREMENT — must-know information, critical prerequisite, or mandatory step]

> [!WARNING]
> [DEPRECATION_OR_BREAKING_CHANGE — potential problems, preview features, or compatibility issues]

> [!CAUTION]
> [HIGH_RISK_ACTION — data loss, cost implications, or security vulnerabilities. E.g. "Do not interrupt the encryption process."]

<!-- END REPEAT: Steps -->
<!-- END REPEAT: Sections -->

---

## ✅ Lab Checklist

<!-- NOTE: Quick verification items grouped by category. Use sub-headers for complex labs. -->

### [CATEGORY_1 — e.g. Resources Created]

- [ ] [VERIFICATION_ITEM_1 — e.g. `dev-skycraft-swc-auth-vm` deployed in Zone 1]
- [ ] [VERIFICATION_ITEM_2]
- [ ] [VERIFICATION_ITEM_3]

### [CATEGORY_2 — e.g. Configuration Applied]

- [ ] [VERIFICATION_ITEM_4]
- [ ] [VERIFICATION_ITEM_5]

### [CATEGORY_3 — e.g. Tags Applied]

- [ ] Project = SkyCraft
- [ ] Environment = [ENVIRONMENT_VALUE]
- [ ] CostCenter = MSDN

<!-- NOTE: Always include tag verification. Tags are mandatory per governance policy. -->

**For detailed verification**, see [lab-checklist-[MODULE.LAB].md](lab-checklist-[MODULE.LAB].md)

---

## 🔧 Troubleshooting

<!-- NOTE: Include 5-10 common issues. Each follows the pattern below. -->

### Issue 1: [PROBLEM_SHORT_TITLE]

**Symptom**: [ERROR_MESSAGE_OR_OBSERVABLE_BEHAVIOR]

**Root Cause**: [EXPLANATION_OF_WHY_IT_HAPPENED]

**Solution**:

- [SOLUTION_STEP_1]
- [SOLUTION_STEP_2]
- [SOLUTION_STEP_3]

<!-- OPTIONAL: Code snippet for resolution -->

```bash
# [FIX_DESCRIPTION]
[FIX_COMMAND]
```

<!-- REPEAT: Issues 2-7+ -->

### Issue 2: [PROBLEM_SHORT_TITLE]

**Symptom**: [ERROR_MESSAGE_OR_OBSERVABLE_BEHAVIOR]

**Solution**:

- [SOLUTION_STEP_1]
- [SOLUTION_STEP_2]

### Issue 3: [PROBLEM_SHORT_TITLE]

**Symptom**: [ERROR_MESSAGE_OR_OBSERVABLE_BEHAVIOR]

**Solution**:

- [SOLUTION_STEP_1]
- [SOLUTION_STEP_2]

### Issue 4: [PROBLEM_SHORT_TITLE]

**Symptom**: [ERROR_MESSAGE_OR_OBSERVABLE_BEHAVIOR]

**Solution**:

- [SOLUTION_STEP_1]
- [SOLUTION_STEP_2]

### Issue 5: [PROBLEM_SHORT_TITLE]

**Symptom**: [ERROR_MESSAGE_OR_OBSERVABLE_BEHAVIOR]

**Solution**:

- [SOLUTION_STEP_1]
- [SOLUTION_STEP_2]

---

## 🎓 Knowledge Check

<!-- NOTE: 5-7 questions with provided answers in <details> blocks. -->
<!-- Questions should test CONCEPTUAL understanding, not just recall. -->
<!-- Use "Why", "What is the difference", "When should you" style questions. -->

1. **[QUESTION_1 — conceptual, e.g. "What is the difference between X and Y?"]?**

   <details>
     <summary>**Click to see the answer**</summary>

   **Answer**: [DETAILED_ANSWER — explain reasoning, provide examples, reference SkyCraft context where helpful. Can include tables, code snippets, or bullet lists for complex answers.]
   </details>

2. **[QUESTION_2]?**

   <details>
     <summary>**Click to see the answer**</summary>

   **Answer**: [DETAILED_ANSWER]
   </details>

3. **[QUESTION_3]?**

   <details>
     <summary>**Click to see the answer**</summary>

   **Answer**: [DETAILED_ANSWER]
   </details>

4. **[QUESTION_4]?**

   <details>
     <summary>**Click to see the answer**</summary>

   **Answer**: [DETAILED_ANSWER]
   </details>

5. **[QUESTION_5]?**

   <details>
     <summary>**Click to see the answer**</summary>

   **Answer**: [DETAILED_ANSWER]
   </details>

<!-- OPTIONAL: Questions 6-7 for longer labs -->

6. **[QUESTION_6]?**

   <details>
     <summary>**Click to see the answer**</summary>

   **Answer**: [DETAILED_ANSWER]
   </details>

7. **[QUESTION_7]?**

   <details>
     <summary>**Click to see the answer**</summary>

   **Answer**: [DETAILED_ANSWER]
   </details>

---

## 📚 Additional Resources

<!-- NOTE: Group by category for longer resource lists. Always include Microsoft Learn links. -->

- [LINK_TITLE_1](https://learn.microsoft.com/[PATH_1])
- [LINK_TITLE_2](https://learn.microsoft.com/[PATH_2])
- [LINK_TITLE_3](https://learn.microsoft.com/[PATH_3])
- [LINK_TITLE_4](https://learn.microsoft.com/[PATH_4])
- [AZ-104 LEARNING_PATH_LINK — if applicable](https://learn.microsoft.com/training/paths/[PATH])

<!-- OPTIONAL: Sub-categories for extensive resource lists -->

**[SUBCATEGORY — e.g. Best Practices]**:

- [LINK_TITLE_5](https://learn.microsoft.com/[PATH_5])

---

## 📌 Module Navigation

[← Back to Module [MODULE_NUMBER] Index](../README.md)

<!-- OPTIONAL: Previous lab link -->

[← Previous Lab: [PREVIOUS_LAB_NUMBER] - [PREVIOUS_LAB_TITLE]](../[PREVIOUS_LAB_FOLDER]/lab-guide-[PREVIOUS_LAB_NUMBER].md)

[Next Lab: [NEXT_LAB_NUMBER] - [NEXT_LAB_TITLE] →](../[NEXT_LAB_FOLDER]/lab-guide-[NEXT_LAB_NUMBER].md)

---

## 📝 Lab Summary

**What You Accomplished:**

✅ [ACCOMPLISHMENT_1 — past tense, specific]
✅ [ACCOMPLISHMENT_2]
✅ [ACCOMPLISHMENT_3]
✅ [ACCOMPLISHMENT_4]
✅ [ACCOMPLISHMENT_5]

<!-- OPTIONAL: Deployed resources table for infrastructure-heavy labs -->

**Infrastructure Deployed**:

| Resource          | Name              | Configuration        |
| ----------------- | ----------------- | -------------------- |
| [RESOURCE_TYPE_1] | [RESOURCE_NAME_1] | [KEY_CONFIG_DETAILS] |
| [RESOURCE_TYPE_2] | [RESOURCE_NAME_2] | [KEY_CONFIG_DETAILS] |

<!-- OPTIONAL: Skills summary for skill-heavy labs -->

**Skills Gained**:

- [SKILL_1]
- [SKILL_2]
- [SKILL_3]

<!-- OPTIONAL: Business impact summary -->

**[IMPACT_CATEGORY — e.g. Cost Optimization Impact]**:

- [IMPACT_1]
- [IMPACT_2]

**Time Spent**: ~[TOTAL_DURATION] hours

**Ready for Lab [NEXT_LAB_NUMBER]?** Next, you'll [NEXT_LAB_PREVIEW — 1 sentence describing what the next lab covers].

<!-- OPTIONAL: Closing note for context-setting -->

---

_Note: [CLOSING_NOTE — optional contextual note linking this lab to the broader project. E.g. "The VMs are now ready for software installation. The focus of this lab was Azure VM infrastructure."]_

<!-- ============================================================ -->
<!-- END TEMPLATE -->
<!-- ============================================================ -->

## 9. Quality Checklist

Before finalizing any lab guide, verify:

- [ ] Title includes lab number and duration
- [ ] 3-6 clear learning objectives (AZ-104 aligned)
- [ ] **Mermaid diagram included** with color scheme
- [ ] Real-world scenario provides business context
- [ ] **SkyCraft Choice** callout included (explains architectural decision)
- [ ] **Multi-modal instructions** (Portal/CLI/PS) provided where applicable
- [ ] Time breakdown adds up to total
- [ ] Prerequisites list all dependencies
- [ ] Every section has 📖 emoji
- [ ] Steps numbered sequentially
- [ ] Each step group has "Expected Result"
- [ ] **Screenshots placed AFTER Expected Result** (Instructions → Expected Result → Screenshot)
- [ ] All resource names follow `project-standards.md`
- [ ] All tags match `bicep-standards.md`
- [ ] 5-7 Knowledge Check questions with `<details>` answers
- [ ] Troubleshooting covers common issues with **Root Cause**
- [ ] Module navigation links work
- [ ] **Module README.md** matches standard structure (compare against Module 1 or 2)
- [ ] **No validation commands** (belong in checklist)
- [ ] **No open-ended reflection questions** (belong in checklist)
- [ ] **No duplicate content** across labs (consolidate to earliest lab, cross-reference)

---

**Rule of Thumb**: If it **teaches or explains**, it belongs in the lab guide. If it **verifies or assesses**, it belongs in the checklist.

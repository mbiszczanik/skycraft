# SkyCraft Project Standards

This document serves as the **Source of Truth** for project organization, documentation conventions, and the learning loop. For Azure-specific naming, topology, and architecture decisions, see [azure-reference.md](azure-reference.md).

---

## 1. Directory Structure

- **Modules**: Root-level folders named `module-X-topic`.
- **Labs**: Sub-folders named `X.Y-lab-name`.
- **Files**:
  - `lab-guide-X.Y.md`: Main instructions.
  - `lab-checklist-X.Y.md`: Verification steps.

### 1.1 Module README Standards (L004)

Every module-level `README.md` **must** contain the following 13 sections in this order. This prevents inconsistency between modules and ensures every module is equally navigable.

| #   | Section                           | Required Content                                   |
| --- | --------------------------------- | -------------------------------------------------- |
| 1   | **Module Overview** (`📚`)        | Description + real-world context paragraph         |
| 2   | **Learning Objectives** (`🎯`)    | Bulleted list with bold action verbs               |
| 3   | **Module Sections** (`📋`)        | Table with Lab, Duration, Topic, Exam Weight       |
| 4   | **Architecture Overview** (`🏗️`)  | Mermaid diagram showing resource relationships     |
| 5   | **Prerequisites** (`✅`)          | Checklist with prior module verification steps     |
| 6   | **Getting Started** (`🚀`)        | Numbered step-by-step to begin labs                |
| 7   | **How to Use This Module** (`📖`) | Lab resource descriptions + recommended approach   |
| 8   | **AZ-104 Exam Alignment** (`🎓`)  | Exam weight percentage + key topics list           |
| 9   | **Time Management** (`⏱️`)        | Total time + per-lab breakdown + pacing suggestion |
| 10  | **Useful Resources** (`🔗`)       | 4-6 Microsoft Learn documentation links            |
| 11  | **Getting Help** (`📞`)           | Troubleshooting pointers                           |
| 12  | **What's Next** (`✨`)            | Milestone checklist + next module link             |
| 13  | **Module Navigation** (`📌`)      | Back to Course Home + all lab links                |

**Rules**:

- **Directory naming must match link targets exactly**. In the main `README.MD`, every module link must point to the actual directory name on disk (e.g., `module-5-monitoring-maintenance/`, not `module-5-monitoring/`). Mismatched directory names cause broken links.
- **Lab links must point to verified paths**. If a lab guide file does not exist yet, link to the lab directory instead of a non-existent file.
- **Durations must be consistent**. The hours in the module README table must match `docs/course-structure.md`. If they differ, `course-structure.md` is the source of truth.
- **Do not duplicate sections in the main `README.MD`**. If information already appears in Quick Start (e.g., prerequisites), do not repeat it in a separate section below.

---

## 2. Documentation

- All lab guides must reference the specific resource names defined in [azure-reference.md](azure-reference.md).
- Do not use generic names like `myVNet` or `test-rg` in guides.

---

## 3. Media and Images

- **Storage**: Screenshots and diagrams should be stored in an `images` folder within the same directory as the lab guide.
  - Example: `module-2-networking/2.1-virtual-networks/images/`
- **Naming**: Use descriptive, lowercase names with hyphens.
  - Example: `vnet-peering-connected.png`
- **Referencing**: Use relative paths in Markdown.
  - Example: `![VNet Peering Status](images/vnet-peering-connected.png)`

---

## 4. Learning Loop & Updates

The `docs/` directory is the **Source of Truth** for all project standards. It is typically updated during Phase 3 (`/validate-lab`).

**When to Update Standards**:

1.  **New Constraint Found**: If a lab fails due to a SKU/Region issue, add a rule to `azure-reference.md`.
2.  **Process Improvement**: If a workflow step is consistently confusing, update the relevant `workflow.md`.
3.  **New Pattern**: If a better way to structure guides is found, update `lab-guide-template.md`.

**Rule**: Do not create separate "lessons learned" files. Update the files in `docs/` directly to prevent the error from happening again.

### 4.1 Writing for AI & Retrieval (RAG)

When updating standards, write for machine readability:

- **Self-Contained**: Avoid "as mentioned above". Repeat the context (e.g., "In Storage Accounts...").
- **Explicit naming**: Use full resource names (e.g., "Azure Key Vault") instead of abbreviations ("KV").
- **Semantic Chunking**: Use clear headers (`###`) for each distinct concept so retrieval systems can index it separately.

---

## 5. Related Standards

| Document                                           | Purpose                                                 |
| -------------------------------------------------- | ------------------------------------------------------- |
| [azure-reference.md](azure-reference.md)           | Azure naming, topology, architecture, storage decisions |
| [bicep-standards.md](bicep-standards.md)           | Bicep IaC coding conventions and templates              |
| [powershell-standards.md](powershell-standards.md) | PowerShell script conventions                           |
| [checklist-standards.md](checklist-standards.md)   | Lab checklist structure and guidelines                  |
| [lab-guide-template.md](lab-guide-template.md)     | Lab guide template with placeholders                    |
| [course-structure.md](course-structure.md)         | Curriculum outline with hours and objectives            |

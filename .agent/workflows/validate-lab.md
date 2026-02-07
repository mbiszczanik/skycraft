---
description: Phase 3 - Run this workflow to audit a specific lab against SkyCraft standards
---

# Validate Lab (Quality Assurance)

Run this workflow to audit a specific lab against SkyCraft standards.

## 1. Documentation Structure Audit

- [ ] **Lab Guide** (`lab-guide-X.Y.md`):
  - [ ] Title follows format: `# Lab X.Y: [Title] ([Duration] hours)`
  - [ ] **Mermaid Diagram** exists and uses correct color scheme (Red/Blue/Orange for Prod/Hub/Dev)
  - [ ] **Scenario** connects to SkyCraft business goal
  - [ ] **Prerequisites** list previous labs and roles
  - [ ] **Steps** use "Action Verbs" (Navigate, Click, Run)
  - [ ] **Expected Results** listed after every major step
  - [ ] **Knowledge Check** has 5-7 questions with `<details>` answers
  - [ ] **Troubleshooting** section covers common errors

- [ ] **Checklist** (`lab-checklist-X.Y.md`):
  - [ ] NO step-by-step instructions (only verification items)
  - [ ] NO theoretical questions (only "Document your..." reflection)
  - [ ] Validation commands included (Azure CLI/PowerShell)
  - [ ] Summary table present

## 2. Content Depth & Technical Accuracy

- [ ] **Course Alignment**: Configuration matches `docs/Course Structure (40 hours).md` objectives
- [ ] **Complexity**: Does the lab go beyond "Click Next"?
  - [ ] Explains _why_ settings are chosen (e.g., LRS vs GRS, Hot vs Cool)
  - [ ] Includes "Real World" constraints or decisions
- [ ] **Naming Conventions**: Matches `docs/STANDARDS.md` (e.g., `prod-skycraft-swc-rg`)

## 3. Media & Assets

- [ ] **Images**: Stored in `images/` folder
- [ ] **Links**: Relative links work (`../README.md`, etc.)
- [ ] **Diagrams**: Mermaid renders correctly

## 4. Manual Verification Run

> **Crucial**: Perform the lab yourself to catch logic errors.

- [ ] Can a fresh learner complete this without outside help?
- [ ] Are the time estimates accurate?

## 5. Output

If valid:

- [ ] Mark as Ready for Phase 2 (Code Generation)

If invalid:

- [ ] List specific gaps and fix them.

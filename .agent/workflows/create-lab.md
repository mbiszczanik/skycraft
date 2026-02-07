---
description: Phase 1 - Create lab folder structure, documentation (guide + checklist), and validate
---

# Create Lab (Phase 1)

Complete Phase 1 of lab development: scaffold, create documentation, validate structure.

## 1. Scaffold Structure

Create the lab folder and file structure:

```
module-X-topic/
└── X.Y-lab-name/
    ├── lab-guide-X.Y.md
    ├── lab-checklist-X.Y.md
    ├── images/
    ├── bicep/
    │   ├── main.bicep
    │   └── modules/
    └── scripts/
        ├── Deploy-Bicep.ps1
        ├── Test-Lab.ps1
        └── Remove-LabResource.ps1
```

## 2. Check Azure Dependencies

> ⚠️ **Before writing documentation, validate feature compatibility!**

| Feature Required       | Incompatible With       | Solution               |
| ---------------------- | ----------------------- | ---------------------- |
| Archive tier (Storage) | ZRS, GZRS, RA-GZRS      | Use LRS or GRS         |
| Premium Files          | LRS only (some regions) | Check regional support |
| NFS Azure Files        | Standard tier           | Use Premium tier       |
| Private Endpoints      | Classic resources       | Use ARM-based          |

Reference: Check the `docs/` directory for known constraints and standards.

## 3. Create Lab Guide

Follow `docs/LAB_GUIDE_STANDARDS.md` (which now includes the template):

1. **Header**: Title, duration, learning objectives
2. **Architecture**: Mermaid diagram with color scheme
3. **Scenario**: Real-world SkyCraft context
4. **Deep Dive**: Theory concepts with comparison table (SKUs/Tiers)
5. **SkyCraft Choice**: Callout explaining architectural decision
6. **Prerequisites**: Dependencies on previous labs
7. **Sections (Multi-Modal)**: Step-by-step instructions for Portal, CLI, and PowerShell
   - Use **Action Verbs** (Navigate, Click, Run)
   - Use **Alerts** for critical info (Note, Warning)
8. **Knowledge Check**: 5-7 questions with `<details>` answers
9. **Troubleshooting**: Common issues and solutions

## 4. Create Lab Checklist

Follow `docs/CHECKLIST_STANDARDS.md`:

1. **Verification steps**: Convert Expected Results to checkboxes
2. **CLI commands**: Include validation commands
3. **Reflection questions**: Open-ended (unlike guide's answered questions)

## 5. Manual Testing Checkpoint

> **PAUSE HERE** - Test the lab guide manually in Azure Portal

Before proceeding to Phase 2:

- [ ] Execute each step in the Azure Portal
- [ ] Verify Expected Results match actual behavior
- [ ] Correct any misalignments in the guide
- [ ] Note any Azure feature quirks for Troubleshooting section

**After corrections, proceed to `/create-lab-code` (Phase 2)**

## 6. Lint Documentation

Final validation before Phase 2:

- [ ] All resource names follow `docs/STANDARDS.md`
- [ ] All tags follow `docs/BICEP_STANDARDS.md`
- [ ] Mermaid diagram renders correctly
- [ ] Image placeholders use correct paths
- [ ] Links between guide and checklist work
- [ ] **No hardcoded subscriptions/secrets**
- [ ] Default location is `swedencentral`

## Output

Phase 1 complete when:

- [ ] `lab-guide-X.Y.md` created and manually tested
- [ ] `lab-checklist-X.Y.md` created
- [ ] Corrections applied based on Portal testing
- [ ] Ready for Phase 2: `/create-lab-code`

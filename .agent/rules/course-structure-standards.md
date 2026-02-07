# SkyCraft Course Structure Standards

> **MEMORY FILE** for maintaining curriculum consistency across the 40-hour AZ-104 aligned course.

---

## 1. Module Structure

| Module | Topic                     | Hours | AZ-104 Weight |
| ------ | ------------------------- | ----- | ------------- |
| **1**  | Identities and Governance | 9     | 20-25%        |
| **2**  | Virtual Networking        | 7     | 15-20%        |
| **3**  | Compute Resources         | 10    | 20-25%        |
| **4**  | Storage                   | 7     | 15-20%        |
| **5**  | Monitor and Maintain      | 5     | 10-15%        |

**Capstone**: Integrated throughout (Hour 40)

---

## 2. Naming Conventions

### Directory Structure

```
module-X-topic/
├── X.Y-lab-name/
│   ├── lab-guide-X.Y.md
│   ├── lab-checklist-X.Y.md
│   ├── bicep/
│   │   ├── main.bicep
│   │   └── modules/
│   ├── scripts/
│   │   ├── Deploy-Bicep.ps1
│   │   ├── Test-Lab.ps1
│   │   └── Remove-LabResource.ps1
│   └── images/
└── README.md
```

### File Naming

- Lab guides: `lab-guide-X.Y.md` (e.g., `lab-guide-2.1.md`)
- Checklists: `lab-checklist-X.Y.md`
- Module index: `README.md` in module root

---

## 3. Section Time Allocation

Each lab section should target:

| Section Type         | Duration  | Example           |
| -------------------- | --------- | ----------------- |
| Concept Introduction | 10-15 min | "What is a VNet?" |
| Hands-on Steps       | 30-45 min | Create resources  |
| Verification         | 10-15 min | Run Test-Lab.ps1  |
| Knowledge Check      | 5-10 min  | Q&A with answers  |

**Total per lab**: 1.5-4 hours depending on complexity

---

## 4. Prerequisites Chain

Labs must follow this dependency order:

```
Module 1 (Identity/Governance)
    └── Module 2 (Networking)
            └── Module 3 (Compute)
                    └── Module 4 (Storage)
                            └── Module 5 (Monitoring)
```

### Prerequisites Format

```markdown
## ✅ Prerequisites

Before starting this lab:

- [ ] Completed Lab X.Y: [Previous Lab Title]
- [ ] Resource groups exist: `platform-skycraft-swc-rg`, `dev-skycraft-swc-rg`
- [ ] [Role] role assigned at subscription level
```

---

## 5. Practical Task Requirements

Every lab **MUST** include:

1. **SkyCraft Context** — Relate to game server deployment
2. **Azure Portal Steps** — Primary instruction method
3. **CLI/PowerShell Equivalent** — For automation learners
4. **Bicep Template** — IaC implementation
5. **Verification Script** — `Test-Lab.ps1`

---

## 6. Milestone Checkpoints

Each module ends with a **Milestone** statement:

| Module | Milestone                                          |
| ------ | -------------------------------------------------- |
| 1      | Identity and governance foundation ready           |
| 2      | Secure, high-availability network infrastructure   |
| 3      | Complete compute with VMs, containers, automation  |
| 4      | Storage layer with redundancy, security, lifecycle |
| 5      | Production-ready monitoring and disaster recovery  |

---

## 7. Lab Numbering

| Format  | Example | Meaning                 |
| ------- | ------- | ----------------------- |
| `X.Y`   | `2.1`   | Module 2, Lab 1         |
| `X.Y.Z` | `2.1.3` | Module 2, Lab 1, Step 3 |

- **X**: Module number (1-5)
- **Y**: Lab within module (1-4 typically)
- **Z**: Step within lab (1-10+)

---

## 8. Duration Guidelines

| Lab Complexity | Duration    | Example                      |
| -------------- | ----------- | ---------------------------- |
| Simple         | 1.5-2 hours | Single resource type         |
| Medium         | 2-3 hours   | Multiple related resources   |
| Complex        | 3-4 hours   | Full architecture deployment |

**Rule**: If a lab exceeds 4 hours, split into sub-labs (e.g., 3.1a, 3.1b).

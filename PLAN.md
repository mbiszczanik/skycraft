# Lab 1.3: screenshot retakes (#329)

PR #337 rewrote the Lab 1.3 guide and removed the screenshots its new text contradicts; their
retakes moved to the Portal pass before the Lab 1.3 recording PR (#329). This branch collects them.
It starts from the head of #337 (206fb81); once #337 is merged, merge `main` into it (or
cherry-pick its commits onto a fresh branch from `main`).

Screenshots are crops of the region the step is about: no account menu, no subscription name or id,
no tenant name. Step numbers are the guide's after #337.

- [x] `step-1.3.6a.png` (1.3.6): the Tags tab error after **Review + create**, with the
      non-compliance message and **Policy details**. Taken on 2026-10-14 in the second agent Portal pass
      of #337, cropped. The mouse pointer covers part of "Azure" in the tab's intro text; retake if a
      clean one comes up.
- [ ] Reference `step-1.3.6a.png` in the guide, after the Expected Result of item 5 in 1.3.6
- [ ] 1.3.5 (replaces the removed `step-1.3.5b.png`): Basics tab with **Policy enforcement** on
      Default (enforcement)
- [ ] 1.3.7 (replaces the removed `step-1.3.21a.png` and `step-1.3.21b.png`): the action group's
      Basics (Region Sweden Central, `skycraft-advisor-ag`, `SkyAdvisor`), then **Alerts (Preview)**
      listing `Advisor-Cost-Recommendations`
- [ ] 1.3.12 (replaces the removed lock-notification image, old `step-1.3.11.png`): the
      **Failed to delete resource group** notification; optional
- [ ] 1.3.17 (replaces the removed `step-1.3.16.png`, the Add filter route): the resource group's
      **Budgets** with **+ Add**
- [ ] Retake `step-1.3.11.png` (1.3.11): its Notes field shows other text than the guide's table
- [ ] Retake `step-1.3.18a.png` (1.3.18): the VIEW menu with the **Built-in views** heading
- [ ] Reference every new image in the guide; run `tests/Guide-Step-Numbering.Tests.ps1` and
      `tests/Guide-Drift-Parser.Tests.ps1`
- [ ] Delete this PLAN.md in the PR's last commit

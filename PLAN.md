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
- [x] Reference `step-1.3.6a.png` in the guide, after the Expected Result of item 5 in 1.3.6
- [x] 1.3.5 (replaces the removed `step-1.3.5b.png`): Basics tab with **Policy enforcement** on
      Default (enforcement)
- [x] 1.3.7 (replaces the removed `step-1.3.21a.png` and `step-1.3.21b.png`): the action group's
      Basics (Region Sweden Central, `skycraft-advisor-ag`, `SkyAdvisor`), then **Alerts (Preview)**
      listing `Advisor-Cost-Recommendations`
      Done: `step-1.3.7b.png` (the alert listed, subscription name replaced by `<your subscription>`).
      Done after the cleanup: `step-1.3.7a.png` (the action group's Basics, not created; while
      `skycraft-advisor-ag` exists the form shows "The specified name already exists").
- [x] 1.3.12 (replaces the removed lock-notification image, old `step-1.3.11.png`): the
      **Failed to delete resource group** notification; optional
- [x] 1.3.17 (replaces the removed `step-1.3.16.png`, the Add filter route): the resource group's
      **Budgets** with **+ Add**
- [x] Retake `step-1.3.11.png` (1.3.11): its Notes field shows other text than the guide's table
- [x] Retake `step-1.3.18a.png` (1.3.18): the VIEW menu with the **Built-in views** heading
- [x] Reference every new image in the guide ; run `tests/Guide-Step-Numbering.Tests.ps1` and
      `tests/Guide-Drift-Parser.Tests.ps1`
- [x] Recording `tools/guide-drift/recordings/lab-1.3.json` from the supervised run of 2026-10-14
      (run 20261014-171319, exit 15). Steps the runner could not do were done with az / Az PowerShell
      and answered `c`; 1.3.5 by hand in the run's browser; 1.3.18 skipped (no label for "Click your
      subscription" and the tag filter). Start blades recorded after such steps were removed.
- [x] Guide wording the run showed: the "..." button of **Policy definition** (1.3.5, 1.3.8, 1.3.9)
      and the **Allowed locations** list (1.3.9) as clickable items; 1.3.5's Scope left as the wizard
      fills it; collapsed **Settings** / **Cost Management** groups in the resource group pane (1.3.11,
      1.3.12, 1.3.13, 1.3.17); 1.3.19 without the extra "Click Advisor service"
- [x] `SKYCRAFT_GUIDE_DRIFT_ALERT_EMAIL` for the budget alert recipients (1.3.16, 1.3.17)
- [ ] File the runner gaps the run showed as one issue: two menus on screen (ambiguous **Tags**),
      the unnamed Category combobox of Create Advisor Alerts, the Monthly option of Reset period,
      bold words in conceptual steps and Expected View lists read as actions
- [ ] Replay `-Lab 1.3` after the screenshots, to check the rewritten picker steps
- [x] Clean up the subscription after the screenshots: `Remove-LabResource.ps1 -Force` (2026-10-14, exit 0)
- [ ] Delete this PLAN.md in the PR's last commit

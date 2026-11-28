# Classification, evidence and where findings go

## Step results

| Result | Meaning |
|---|---|
| OK | The Portal matches the guide and the Expected Result holds |
| DRIFT | Wording, navigation or a default differs; a learner can still complete the step |
| WRONG | The result differs from the Expected Result, or a policy/permission error the guide does not prepare for |
| BLOCKED | A learner cannot complete the step from the text |
| NA | The step has no action (a concept section) or was skipped by decision; say which |

Classify what a learner would experience, not what the agent could work around. An environment artefact (pre-existing objects, a stalled view, an earlier lab not done) is noted but does not make a step WRONG.

## Risky defaults

On every wizard tab and settings page, ask three questions, whatever the guide says:

1. **Does it cost money?** Backup, Defender plans, diagnostics or monitoring, geo-redundancy, premium tiers, a running App Service plan or Container App with minimum replicas above 0.
2. **Does it delete data?** Lifecycle and retention rules (check their **scope**: a rule without a prefix filter applies to the whole account, #356), auto-delete, soft-delete periods shorter than the guide's.
3. **Does it open access?** Public network access, anonymous blob access, key access, SAS scope, NSG or firewall rules wider than the step needs.

Record each hit as a step finding (DRIFT when the guide is silent and the default is harmless for the lab, WRONG when following the guide leaves cost, data loss or exposure behind), with the exact Portal text. Seen so far: the new file-share wizard turns **Enable backup** on by default (4.3); lifecycle rule without filters (4.2, #356); load balancer outbound SNAT (2.3, #344). Untick a costly default only when the lab does not need it, and say so in the deviations.

## Evidence

- Each row names its evidence: a screenshot file name, a toast or notification text quoted exactly, an `az` read-back, an activity-log entry (`az monitor activity-log list --offset 30m --query "[?status.value=='Failed']"`), or a Test-Lab line.
- Test-Lab output is quoted with its exit code; when the exit code was not captured, say so instead of implying success.
- **Where a handover prompt or an earlier comment states a live result, the pass shall re-run the read that produces it before ticking an item with it, and report any disagreement to the user.**
  On 2026-10-27 three stated results were wrong: the activity log held five `DefaultResourceGroup-SEC` refusals, no `ME_` group existed, and Azure no longer creates Consumption-only environments.
- When a Portal check cannot distinguish "not in effect yet" from "the form never shows it", test the backend directly (for policy: `az deployment sub validate` of the same request) before classifying.
- **If** a script fails only because of the agent's own way of running it (a process-scoped context built from an az token has no Microsoft Graph token, so `Get-AzRoleAssignment -ObjectId` fails; an MFA prompt it cannot answer), **then the pass shall** classify it as an environment limit, run the remaining part of the script's own code directly, and not file it as a lab defect. File it only when a learner signed in with `Connect-AzAccount` would hit it too.
- **If** a what-if or a Test-Lab result rests on a read that failed in the agent's context (a script that warns on a failed role read and then sends the assignment), **then the pass shall** repeat the read another way (the ARM helpers in `tools/LabCommon.psm1`, an `az` read-back) before it files the result. Lab 4.4's what-if showed a second role assignment on 2026-10-25 only because the Graph read had failed; the class issue #406 had to be corrected.

## Where findings go

| Finding | Destination |
|---|---|
| Per-lab results, Test-Lab output, answers to the tracking issue's checklist rows | one comment per lab on the tracking issue (#300 for labs 1.1-3.4) |
| Guide wording, navigation, labels, defaults, missing clicks | the module's `[Bug]: Lab X.Y: guide steps no longer match the Azure Portal` issue (input to the #329 guide PR) |
| A defect with siblings in other labs or in scripts | one class issue listing every occurrence, marked confirmed / suspected / not checked |
| Evidence for a known issue | a comment on that issue; never a duplicate |

Never write closing keywords; never close or tick other people's checkboxes.

## Class-search questions for the search agent

Give one read-only search agent, if available (otherwise run the search yourself), a thorough brief with the commit to search with `git grep <pattern> <commit> -- module-*/ tools/`, and ask, per confirmed defect, for every occurrence as `path:line - quote`. Typical questions:
1. Scripts that look objects up by a name the Portal does not set (policy assignments, display names).
2. Portal create steps whose wizard has a Region field the guide does not set (allowed-locations policy).
3. Portal creates without a tags step while `Enforce-Project-Tag` is active; forms that have no tags field at all.
4. Guide lines naming a menu item that now sits in a collapsed group.
5. Expected Results that depend on validation timing (policy deny on Review + create).
6. Steps that expect an error and then say **Cancel** before the error can appear.

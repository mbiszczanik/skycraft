# Lab acceptance evidence

Use this record before running the acceptance checks for a lab change. Keep one
record in the PR body, outside comments and code fences. Identify each affected lab
within each field. Extend the existing issue checklist rather than creating a
second status document.

## Test conditions

The acceptance record shall name the subscription lifecycle (brand-new or existing),
offer (for example Free Trial or Azure for Students), region, operator permissions
and existing prerequisite resources before the run.

The acceptance record shall identify the tested commit in `Acceptance-head`.

If the required starting state is unavailable, then the acceptance record shall
report the missing precondition and tracking issue instead of claiming a pass.

Evidence: Lab 1.3 issue #402 requires a first-use Portal pass; an already registered
provider cannot reproduce that starting state (reviewed 2026-11-02).

Do not delete shared resources or unregister providers to manufacture a clean
subscription. State preparation and cleanup need authorization covering those actions.
Record fictional roles and environment descriptions, not account or resource identifiers.

## Record format

Copy these keys into the PR body and replace every placeholder:

```text
Test-conditions: <lab IDs; lifecycle, offer, region, permissions, existing resources>
Acceptance-head: <tested commit; rerun or explain later changes>
Scripted-check: <lab IDs; date, command/run ID, expected/observed counts and exit code>
Portal-check: <lab IDs; date, changed step IDs, expected/observed result and evidence link>
Negative-check: <lab IDs; date, rejected input or failure, expected/observed failure and command>
Missing-result-check: <lab IDs; date, empty/null/zero-work input, expected/observed failure and command>
Fallback-deploy: <lab IDs; date, variant, create command/run ID, observed resource and exit code>
```

For a check unrelated to the change, use `not-applicable: <specific reason>`.
For an unavailable check, use `blocked: <missing precondition>; tracked in #N`.
Neither is a passed test. A guide-only change can explain that no validator or
fallback behavior changed; it still needs the affected Portal steps checked.

## Outcomes and missing data

The acceptance record shall separate scripted checks from Portal steps changed by
the PR, with dated evidence for each affected path.

When a validator changes, the acceptance record shall cite a negative test and a
missing-result test that exercise the validator and observe failure.

If a check receives no relevant data or processes zero expected resources, then
the validator shall report failure or an explicit incomplete result instead of success.

Evidence: Lab 1.3 remediation reported success with zero deployments; issue #340
records scripts reporting success after errors (reviewed 2026-11-02).

Use offline tests with controlled empty responses where possible. Check the real
validator's result and process exit code. Printing an error is insufficient.
Retain expected and observed counts so `0 out of 0` cannot stand for completed work.
Do not change cloud configuration just to exercise a read-only validator.

## Fallbacks and evidence freshness

Where a change recommends a fallback SKU or deployment path, the acceptance record
shall cite a deployment that created the alternative resource in the intended offer.

If only template validation ran, then the acceptance record shall describe the
fallback as unverified and name its tracking issue.

Evidence: Lab 3.4 issue #439 records a P0v3 template validation that succeeded while
actual plan creation failed (reviewed 2026-11-02).

Follow ADR-0006 decision 6 for branch changes, deferrals and issue closure. A complete
record does not authorize a deployment, merge or issue closure. A blocked item stays
open even when another acceptance path passed.

The project tracker shall hold current issue and PR status; local notes shall retain
decisions and links instead of duplicating changing PR states.

If current tracker evidence is unavailable, then a status report shall label its
current-state claims unverified.

Evidence: two local notes still called merged PR #474 a draft on 2026-11-02.

## What CI checks

`tools/Test-PrAcceptanceEvidence.ps1` uses the lab-content paths of the existing
live-verification gate. It requires exactly one visible, non-placeholder entry per
key and a tracking issue for blocked entries. The existing required
`Live Verification Declared` job runs both checks; no repository setting change is needed.
If a blocked entry accompanies an issue-closing keyword, then the completeness
check shall fail and require `Refs` instead.

If any required entry is missing, duplicated, blank or a placeholder, then the
acceptance completeness check shall exit nonzero.

CI checks completeness, not truth. Review the linked logs, observed outcomes,
revision and environment suitability before treating the behavior as accepted.

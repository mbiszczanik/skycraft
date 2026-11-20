# Guide Drift Campaign

> **Procedure** for checking the Portal steps of Labs 1.2 to 5.3 against today's Azure Portal, in one supervised campaign.

A guide drift run performs a lab's Portal steps in a visible browser and reports what no longer matches the Portal (`tools/Invoke-GuideDrift.ps1`, rules in [CONTRIBUTING.md](../CONTRIBUTING.md)). Lab 1.1 already has a recording. This procedure covers the other labs, which are checked deliberately, in order, in one campaign, instead of whenever each is next revised. Issue #204 is the campaign's tracker and holds the list of gates still open; this file does not copy that list, so it cannot go stale.

The procedure is general. The subscription, tenant, dates and people of a given campaign belong in the tracker, never here.

---

## 1. Preconditions

1. A time-limited subscription in an Entra-only test tenant, where changing tenant-wide state is acceptable. Labs 1.1 to 1.3 change users, a guest, self-service password reset, policies and management groups.
2. The identities of Lab 1.1 and the subscription of Labs 1.1 to 1.3 shall be in the same tenant. Lab 1.2 assigns roles to Lab 1.1's users and groups.
3. Every pre-campaign gate listed in issue #204 is closed, or the maintainer has accepted it as open for this campaign. Check the issue the day before; do not rely on this file.
4. No lab cycle and no other guide drift run uses the subscription. The ARM labs use the same resource group names in both tools, so a lab cycle and a guide drift run never share a subscription at the same time.

## 2. Day-1 checks

Run these once, in order, before the first guide drift run, so that trial limits show up before they cost a lab:

1. A budget alert on the subscription.
2. The regional vCPU quota for Lab 3.2: 4 vCPUs of `Standard_B2ls_v2`. Trial quotas cannot be raised, so a shortfall is a finding for the tracker, not something to work around on the day.
3. `tools/Invoke-LabCycle.ps1 -SubscriptionId <subscription-id> -DryRun`.
4. One full live lab cycle: `tools/Invoke-LabCycle.ps1 -SubscriptionId <subscription-id> -Yes`.

## 3. Lab order

Lab 1.1 runs first with `-SkipCleanup`, so its users, groups and guest stay for Lab 1.2. Then Labs 1.2, 1.3, 2.1, 2.2, 2.3, 3.1, 3.2, 3.3, 3.4, 4.1, 4.2, 4.3, 4.4, 5.1, 5.2 and 5.3, in that order. Later labs build on resources of earlier ones, so the order is part of the procedure.

For each lab X.Y:

1. Deploy the lab's prerequisites and keep them:

   ```powershell
   tools/Invoke-LabCycle.ps1 -SubscriptionId <subscription-id> -Labs <prerequisite-labs> -SkipCleanup -Yes
   ```

   Labs that need names unique across Azure take `-UniqueNames` (see the comment-based help of the script).
2. Run the supervised guide drift run:

   ```powershell
   tools/Invoke-GuideDrift.ps1 -SubscriptionId <subscription-id> -Lab X.Y
   ```

   An Entra-only lab such as 1.1 can use `-TenantId <tenant-id>` instead of `-SubscriptionId`.
3. The run's recording is `tools/guide-drift/recordings/lab-X.Y.json`.

## 4. One pull request per lab

Each lab's first supervised run ends in one pull request that adds `tools/guide-drift/recordings/lab-X.Y.json` and declares the run under [ADR-0006](adr/0006-pr-live-verification-gate.md) (`Live-verified:` line with what ran, where, the date and the exit codes). A pull request never carries the recordings of two labs.

## 5. Findings

Every finding is its own issue, filed when it is found, with the lab, the step and the evidence redacted for a public tracker. A finding is not fixed inside the recording pull request, and it does not stop the campaign: the run continues with the next lab. A defect that appears in more than one lab is one issue for the class, not one per lab.

## 6. End of each day

Tear down at the end of each day, so nothing runs idle at App Service, load balancer or VM rates. Check afterwards that the lab resource groups are gone and that no budget or alert of a lab outlived its cleanup. Lab 1.1's users and groups stay until Lab 1.2 has run; remove them with the tear-down of the last day that needs them.

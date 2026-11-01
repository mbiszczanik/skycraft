# Remove diagnostics before group teardown

Spec: issue #454.

- [x] Reuse the established diagnostic-settings API pattern and cover all group-deletion siblings.
- [x] Add failing behavioral checks for targets, deletion ordering, read/delete failures and final orphan detection.
- [x] Integrate a shared cleanup contract into the three affected teardown routes.
- [x] Run complete offline validation and independent review. All five checks report PASS; the outer process exit discrepancy remains recorded for investigation.
- [ ] Prepare a bounded live check for approval; preserve the issue until its acceptance is proven.
- [ ] Commit, push and open a draft PR; remove this plan from the final tree.

# Redaction before anything public

The skycraft repository is public. Issues, comments, PR bodies, commit messages and screenshots must not carry:

- account e-mail addresses or real people's names (lab fictional users and `@illidari.com` are fine);
- tenant, directory or organization names, or their ids;
- subscription names or ids;
- object or resource ids of a real environment, including Portal-generated 24-hex resource names;
- local paths with a user name (`C:\Users\<name>`, `/c/Users/<name>`, 8.3 short names like `ABCDEF~1`).

| Instead of | Write |
|---|---|
| the work subscription's id or name | "the rehearsal subscription", `<subscription-id>` |
| the test tenant's id or name | "the test tenant", `<test-tenant-id>` |
| an account | "the subscription owner's account", "the test tenant's admin account" |
| a generated resource name | `<generated-id-1>` |
| `Connected to Tenant: <id> as <account>` | `Connected to Tenant: <test-tenant-id> as the test tenant's admin account` |

- Built-in Azure ids (policy and role definition GUIDs) are fine.
- `render_report.py` scans the comments it writes with the publication guard: set
  `PUBLIC_CONTENT_GUARD` to the full path of the installed `guard-public-content.py` (its
  `public-content.json` sits next to it), e.g. `export PUBLIC_CONTENT_GUARD=<guard-dir>/guard-public-content.py`
  in bash or `$env:PUBLIC_CONTENT_GUARD = '<guard-dir>\guard-public-content.py'` in PowerShell.
  Unset or not loadable, the script writes nothing and exits 4; `--no-scan` renders without the
  scan, and every comment is then reviewed by hand before posting. Do not assume that every
  publish is guarded. If the guard is unavailable, the
  pass shall report the gap and still review and redact every proposed publication.
  Propose new deny terms to the maintainer; do not change live configuration during a pass.
- The private HTML report may name the user's own environment; the GitHub comments may not.
- Found something already published: report it to the user with the exact locations; redact only with their approval, and remind them that GitHub keeps edit history until the owner deletes those revisions by hand.

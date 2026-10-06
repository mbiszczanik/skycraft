"""Unit tests for the parts of run.py that keep tenant data out of the recording (issue #189).

Redactor, env_secrets and rejected_candidates are pure, so they are tested without a browser.
run.py imports Playwright at module level; the CI runner does not install it, so when it is
missing a stub of playwright.sync_api is put in sys.modules before the import. Nothing here
calls into Playwright.

Standard library unittest only; tests/Guide-Drift-Decide.Tests.ps1 runs this suite in CI.
Run by hand from the repository root:

    python -B -m unittest discover -s tools/guide-drift/tests -v
"""
import os
import sys
import types
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

try:
    import playwright.sync_api  # noqa: F401
except ImportError:
    class _StubTimeout(Exception):
        """Stands in for playwright.sync_api.TimeoutError."""

    _stub = types.ModuleType("playwright.sync_api")
    _stub.Page = _stub.Frame = object
    _stub.TimeoutError = _StubTimeout
    _stub.sync_playwright = None
    sys.modules["playwright"] = types.ModuleType("playwright")
    sys.modules["playwright.sync_api"] = _stub

from decide import Candidate  # noqa: E402
from run import Redactor, env_secrets, rejected_candidates  # noqa: E402

DOMAIN = "contoso.onmicrosoft.com"
TENANT = "0a1b2c3d-4e5f-4a6b-8c7d-9e0f1a2b3c4d"
TOKEN = "${SKYCRAFT_GUIDE_DRIFT_GUEST_EMAIL}"
UPN_TOKEN = "${SKYCRAFT_GUIDE_DRIFT_GUEST_EMAIL|upn}"


class RedactorTests(unittest.TestCase):
    def setUp(self) -> None:
        self.redactor = Redactor(DOMAIN, TENANT, {TOKEN: "me@example.com"})

    def test_domain_and_tenant_id_round_trip(self) -> None:
        text = f"admin@{DOMAIN} in directory {TENANT}"
        redacted = self.redactor.redact(text)
        self.assertEqual(redacted, "admin@[tenantdomain] in directory [tenantid]")
        self.assertEqual(self.redactor.restore(redacted), text)

    def test_redaction_ignores_case_and_restores_lower_case(self) -> None:
        redactor = Redactor("Contoso.OnMicrosoft.com", TENANT.upper())
        redacted = redactor.redact(f"admin@CONTOSO.onmicrosoft.COM {TENANT.upper()}")
        self.assertEqual(redacted, "admin@[tenantdomain] [tenantid]")
        self.assertEqual(redactor.restore(redacted), f"admin@{DOMAIN} {TENANT}")

    def test_guest_upn_becomes_the_upn_token_and_restores(self) -> None:
        upn = f"me_example.com#EXT#@{DOMAIN}"
        redacted = self.redactor.redact(upn)
        self.assertEqual(redacted, f"{UPN_TOKEN}#EXT#@[tenantdomain]")
        self.assertEqual(self.redactor.restore(redacted), upn)

    def test_guest_address_becomes_the_token_and_restores(self) -> None:
        redacted = self.redactor.redact("Invite me@example.com")
        self.assertEqual(redacted, f"Invite {TOKEN}")
        self.assertEqual(self.redactor.restore(redacted), "Invite me@example.com")

    def test_none_passes_through(self) -> None:
        self.assertIsNone(self.redactor.redact(None))
        self.assertIsNone(self.redactor.restore(None))

    def test_view_url_drops_tenant_pin_queries_and_object_ids(self) -> None:
        url = (f"https://portal.azure.com/?feature.x=1#@{DOMAIN}/view/Blade/id/"
               "11111111-2222-3333-4444-555555555555?q=1")
        self.assertEqual(self.redactor.view_url(url), "https://portal.azure.com/#view/Blade/id/<id>")


class EnvSecretsTests(unittest.TestCase):
    def test_only_addresses_become_secrets(self) -> None:
        recording = {"placeholders": {"[yourtenant]": "${SKYCRAFT_GUIDE_DRIFT_TENANT_PREFIX}"},
                     "steps": {"1.1.5": {"valueOverrides": {"Email": TOKEN}}}}
        env = {"SKYCRAFT_GUIDE_DRIFT_TENANT_PREFIX": "contoso",
               "SKYCRAFT_GUIDE_DRIFT_GUEST_EMAIL": "me@example.com"}
        with mock.patch.dict(os.environ, env):
            self.assertEqual(env_secrets(recording), {TOKEN: "me@example.com"})

    def test_unset_variable_is_not_a_secret(self) -> None:
        recording = {"steps": {"1.1.5": {"valueOverrides": {"Email": TOKEN}}}}
        with mock.patch.dict(os.environ, {}, clear=True):
            self.assertEqual(env_secrets(recording), {})


class RejectedCandidatesTests(unittest.TestCase):
    def test_drops_addresses_guids_and_the_chosen_name(self) -> None:
        candidates = [Candidate("button", "New group"), Candidate("button", "New user"),
                      Candidate("link", f"admin@{DOMAIN}"),
                      Candidate("cell", "11111111-2222-3333-4444-555555555555"),
                      Candidate("tab", "Groups")]
        rejected = rejected_candidates(candidates, "+ New group", "New group")
        self.assertEqual(sorted(rejected), sorted(['button "New user"', 'tab "Groups"']))

    def test_keeps_at_most_twenty_most_similar_first(self) -> None:
        candidates = [Candidate("button", f"Unrelated thing {i}") for i in range(30)]
        candidates.insert(17, Candidate("button", "New groups"))
        rejected = rejected_candidates(candidates, "+ New group", None)
        self.assertEqual(len(rejected), 20)
        self.assertEqual(rejected[0], 'button "New groups"')


if __name__ == "__main__":
    unittest.main()

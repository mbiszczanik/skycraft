"""Unit tests for recording.py, which keeps tenant data out of the recording (issue #189).

Redactor, env_secrets and rejected_candidates are pure and live outside run.py, so they are
tested without a browser and without Playwright, which the CI runner does not install.

Standard library unittest only; tests/Guide-Drift-Python.Tests.ps1 runs this suite in CI.
Run by hand from the repository root:

    python -B -m unittest discover -s tools/guide-drift/tests -v
"""
import json
import os
import shutil
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

import recording  # noqa: E402
from decide import Candidate  # noqa: E402
from recording import (Redactor, env_secrets, expand_env, missing_env,  # noqa: E402
                       rejected_candidates, resolve_value, value_action, write_json)

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

    def test_tenant_prefix_becomes_the_guides_placeholder_and_restores(self) -> None:
        redacted = self.redactor.redact(f"Contoso directory, admin@{DOMAIN}")
        self.assertEqual(redacted, "[yourtenant] directory, admin@[tenantdomain]")
        self.assertEqual(self.redactor.restore(redacted), f"contoso directory, admin@{DOMAIN}")

    def test_tenant_prefix_inside_a_longer_name_is_left_alone(self) -> None:
        for text in ("contoso-admins", "contosoville", "my_contoso", "SkyCraft-Contoso-RG"):
            with self.subTest(text=text):
                self.assertEqual(self.redactor.redact(text), text)

    def test_matcher_keeps_plain_names_exact(self) -> None:
        self.assertEqual(self.redactor.matcher("New group"), "New group")

    def test_matcher_matches_a_restored_name_whole_and_regardless_of_case(self) -> None:
        pattern = self.redactor.matcher("[yourtenant] Ltd")
        for name in ("Contoso Ltd", "contoso ltd", "CONTOSO LTD"):
            with self.subTest(name=name):
                self.assertIsNotNone(pattern.search(name))
        for name in ("Contoso Ltd 2", "My Contoso Ltd"):
            with self.subTest(name=name):
                self.assertIsNone(pattern.search(name))
        self.assertIsNotNone(self.redactor.matcher(f"{TOKEN} (Guest)").search("Me@Example.com (Guest)"))

    def test_short_tenant_prefix_is_not_redacted(self) -> None:
        redactor = Redactor("abc.onmicrosoft.com", TENANT)
        self.assertEqual(redactor.redact("abc and abc.onmicrosoft.com"), "abc and [tenantdomain]")

    def test_tenant_display_name_becomes_a_token_and_restores_as_given(self) -> None:
        redactor = Redactor(DOMAIN, TENANT, tenant_name="Northwind Traders")
        redacted = redactor.redact("Switch to NORTHWIND TRADERS (Northwind Traders-Archive)")
        # Case-insensitive, and only as a whole name: '-Archive' makes it another directory's name.
        self.assertEqual(redacted, "Switch to [tenantname] (Northwind Traders-Archive)")
        self.assertEqual(redactor.restore("[tenantname] overview"), "Northwind Traders overview")
        self.assertIsNotNone(redactor.matcher("[tenantname]").search("NORTHWIND TRADERS"))

    def test_tenant_display_name_is_redacted_before_the_prefix_it_contains(self) -> None:
        redactor = Redactor(DOMAIN, TENANT, tenant_name="Contoso Ltd")
        self.assertEqual(redactor.redact("Contoso Ltd and Contoso"), "[tenantname] and [yourtenant]")
        self.assertEqual(redactor.restore("[tenantname] and [yourtenant]"), "Contoso Ltd and contoso")

    def test_short_or_missing_display_name_is_not_redacted(self) -> None:
        for name in ("", "  ", "Abc"):
            with self.subTest(name=name):
                self.assertEqual(Redactor(DOMAIN, TENANT, tenant_name=name).redact("Abc corp"), "Abc corp")

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

    def test_a_recorded_upn_token_counts_as_a_reference(self) -> None:
        # A recording whose only mention of the guest is a redacted UPN still needs the variable,
        # or restore() could not find the guest's row again.
        recording = {"steps": {"1.1.6": {"labels": {"x": {"name": f"{UPN_TOKEN}#EXT#@[tenantdomain]"}}}}}
        with mock.patch.dict(os.environ, {}, clear=True):
            self.assertEqual(missing_env(recording), ["SKYCRAFT_GUIDE_DRIFT_GUEST_EMAIL"])
        with mock.patch.dict(os.environ, {"SKYCRAFT_GUIDE_DRIFT_GUEST_EMAIL": "me@example.com"}):
            self.assertEqual(env_secrets(recording), {TOKEN: "me@example.com"})


class ValueTests(unittest.TestCase):
    RECORDING = {"placeholders": {"[yourtenant]": "${SKYCRAFT_GUIDE_DRIFT_TENANT_PREFIX}"},
                 "steps": {"1.1.5": {"valueOverrides": {"Email": TOKEN}}}}
    ENV = {"SKYCRAFT_GUIDE_DRIFT_TENANT_PREFIX": "contoso", "SKYCRAFT_GUIDE_DRIFT_GUEST_EMAIL": "me@example.com"}

    def test_expand_env_gives_the_address_or_its_upn_form(self) -> None:
        with mock.patch.dict(os.environ, self.ENV):
            self.assertEqual(expand_env(f"{TOKEN} / {UPN_TOKEN}"), "me@example.com / me_example.com")

    def test_expand_env_stops_on_a_missing_variable(self) -> None:
        with mock.patch.dict(os.environ, {}, clear=True), self.assertRaisesRegex(SystemExit, "GUEST_EMAIL"):
            expand_env(TOKEN)

    def test_missing_env_lists_unset_names_sorted(self) -> None:
        with mock.patch.dict(os.environ, {}, clear=True):
            self.assertEqual(missing_env(self.RECORDING),
                             ["SKYCRAFT_GUIDE_DRIFT_GUEST_EMAIL", "SKYCRAFT_GUIDE_DRIFT_TENANT_PREFIX"])
        with mock.patch.dict(os.environ, self.ENV):
            self.assertEqual(missing_env(self.RECORDING), [])

    def test_resolve_value_applies_overrides_then_placeholders(self) -> None:
        with mock.patch.dict(os.environ, self.ENV):
            self.assertEqual(resolve_value(self.RECORDING, {"id": "1.1.5"}, "Email", "guest@example.org"),
                             "me@example.com")
            self.assertEqual(resolve_value(self.RECORDING, {"id": "1.1.2"}, "User principal name",
                                           "malfurion.stormrage@[yourtenant].onmicrosoft.com"),
                             "malfurion.stormrage@contoso.onmicrosoft.com")
            self.assertEqual(resolve_value(self.RECORDING, {"id": "1.1.6"}, "Group name", "SkyCraft-Admins"),
                             "SkyCraft-Admins")

    def test_value_action(self) -> None:
        for value, action in (("[Leave blank]", "skip"), (" [Leave blank] ", "skip"),
                              ("skycraft-auth-[uniqueID]", "unresolved"), ("SkyCraft-Admins", "type"), ("", "type")):
            with self.subTest(value=value):
                self.assertEqual(value_action(value), action)


class RejectedCandidatesTests(unittest.TestCase):
    def test_drops_addresses_guids_and_the_chosen_name(self) -> None:
        candidates = [Candidate("button", "New group"), Candidate("button", "New user"),
                      Candidate("link", f"admin@{DOMAIN}"),
                      Candidate("link", "11111111-2222-3333-4444-555555555555"),
                      Candidate("tab", "Groups")]
        rejected = rejected_candidates(candidates, "+ New group", "New group")
        self.assertEqual(sorted(rejected), sorted(['button "New user"', 'tab "Groups"']))

    def test_drops_table_cells_which_hold_user_data(self) -> None:
        candidates = [Candidate("cell", "Malfurion Stormrage"), Candidate("cell", "New group members"),
                      Candidate("button", "New user")]
        self.assertEqual(rejected_candidates(candidates, "+ New group", None), ['button "New user"'])

    def test_keeps_at_most_twenty_most_similar_first(self) -> None:
        candidates = [Candidate("button", f"Unrelated thing {i}") for i in range(30)]
        candidates.insert(17, Candidate("button", "New groups"))
        rejected = rejected_candidates(candidates, "+ New group", None)
        self.assertEqual(len(rejected), 20)
        self.assertEqual(rejected[0], 'button "New groups"')


class WriteJsonTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.tmp, ignore_errors=True)
        self.path = self.tmp / "state.json"

    def test_a_replace_blocked_for_a_moment_is_retried(self) -> None:
        real_replace = os.replace
        calls = []

        def replace(source, target):
            calls.append(target)
            if len(calls) <= 2:          # an antivirus scanner holds the file twice
                raise PermissionError(5, "Access is denied")
            real_replace(source, target)

        with mock.patch.object(recording.os, "replace", replace), \
                mock.patch.object(recording.time, "sleep") as sleep:
            write_json(self.path, {"a": 1})
        self.assertEqual(json.loads(self.path.read_text(encoding="utf-8")), {"a": 1})
        self.assertEqual((len(calls), sleep.call_count), (3, 2))
        self.assertFalse((self.tmp / "state.json.tmp").exists())

    def test_a_replace_that_stays_blocked_raises(self) -> None:
        with mock.patch.object(recording.os, "replace", side_effect=PermissionError(5, "Access is denied")) as replace, \
                mock.patch.object(recording.time, "sleep") as sleep, self.assertRaises(PermissionError):
            write_json(self.path, {"a": 1})
        self.assertEqual((replace.call_count, sleep.call_count),
                         (recording.REPLACE_ATTEMPTS, recording.REPLACE_ATTEMPTS - 1))



class CheckboxStateTests(unittest.TestCase):
    """The guides write checkbox values with a mark and a word; the whole value never matched a
    single word, so '✅ Checked' used to be reported as 'not a checkbox state'."""

    def test_checked_forms(self):
        for value in ("✅ Checked", "✅", "Checked", "checked", "Enabled", "Yes", "On", "✔ Enabled"):
            with self.subTest(value=value):
                self.assertIs(recording.checkbox_state(value), True)

    def test_unchecked_forms(self):
        for value in ("❌ Unchecked", "☐ Unchecked", "☐", "Uncheck", "leave unchecked", "Disabled", "No", "Off"):
            with self.subTest(value=value):
                self.assertIs(recording.checkbox_state(value), False)

    def test_neither_or_both_is_none(self):
        for value in ("Leave default", "Standard_LRS", "", "Checked or unchecked"):
            with self.subTest(value=value):
                self.assertIsNone(recording.checkbox_state(value))


if __name__ == "__main__":
    unittest.main()

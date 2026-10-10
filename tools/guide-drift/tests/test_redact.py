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
from recording import (Redactor, env_secrets, expand_env, field_action, missing_env,  # noqa: E402
                       rejected_candidates, resolve_value, resource_name, skip_reason, value_action,
                       write_json)

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

    def test_view_url_maps_an_id_without_hyphens_to_the_id_token(self) -> None:
        for raw in ("view/Blade/id/1111111122223333444455555555aaaa",
                    "view/Blade/id/%2F1111111122223333444455555555aaaa"):     # right after '%2F'
            with self.subTest(raw=raw):
                self.assertEqual(self.redactor.view_url(f"https://portal.azure.com/#{raw}"),
                                 f"https://portal.azure.com/#{raw[:raw.index('id/') + 3]}"
                                 f"{'%2F' if '%2F' in raw else ''}<id>")
        # A longer run of hex digits is no id.
        longer = "https://portal.azure.com/#view/Blade/hash/" + "a" * 40
        self.assertEqual(self.redactor.view_url(longer), longer)

    def test_view_url_keeps_nothing_that_holds_personal_or_tenant_data_once_decoded(self) -> None:
        for fragment in ("view/User/upn/someone%40example.com",            # an address, encoded
                         "view/User/upn/someone_example.com%23EXT%23",     # a guest UPN, encoded
                         "view/User/upn/someone_example.com%23ext%23",
                         "view/Blade/filter%3Fname",                       # a query, encoded
                         "view/Blade/id/1111111122223333444455555555aaa%61",   # an id, partly encoded
                         "view/Blade/id/11111111%2D2222-3333-4444-555555555555",
                         "view/Invite/me%40example.com"):
            with self.subTest(fragment=fragment):
                self.assertIsNone(self.redactor.view_url(f"https://portal.azure.com/#@{DOMAIN}/{fragment}"))

    def test_view_url_keeps_no_tenant_name_that_only_decoding_shows(self) -> None:
        redactor = Redactor(DOMAIN, TENANT, tenant_name="Fabrikam Labs")
        self.assertIsNone(redactor.view_url("https://portal.azure.com/#view/Tenant/name/Fabrikam%20Labs"))
        self.assertEqual(redactor.view_url("https://portal.azure.com/#view/Tenant/name/Fabrikam Labs"),
                         "https://portal.azure.com/#view/Tenant/name/[tenantname]")

    def test_view_url_keeps_encoded_text_without_personal_data(self) -> None:
        url = "https://portal.azure.com/#view/Blade/name/SkyCraft%20Admins"
        self.assertEqual(self.redactor.view_url(url), url)


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

    def test_resource_name_fills_placeholders_or_is_none_while_a_token_is_left(self) -> None:
        with mock.patch.dict(os.environ, self.ENV):
            self.assertEqual(resource_name(self.RECORDING, "dev-skycraft-swc-lb"), "dev-skycraft-swc-lb")
            self.assertEqual(resource_name(self.RECORDING, "[yourtenant]-skycraft-kv"), "contoso-skycraft-kv")
            self.assertIsNone(resource_name(self.RECORDING, "skycraft-auth-[uniqueID]"))
            self.assertIsNone(resource_name(self.RECORDING, "<your name>-vm"))

    def test_value_action(self) -> None:
        for value, action in (("[Leave blank]", "skip"), (" [Leave blank] ", "skip"),
                              ("skycraft-auth-[uniqueID]", "unresolved"), ("SkyCraft-Admins", "type"), ("", "type")):
            with self.subTest(value=value):
                self.assertEqual(value_action(value), action)


class FieldActionTests(unittest.TestCase):
    """A field value parse.py marked '"literal": false' is typed only when the recording resolves
    it (#202): an override for the field, or placeholders that leave a literal."""

    RECORDING = {"placeholders": {"[yourtenant]": "${SKYCRAFT_GUIDE_DRIFT_TENANT_PREFIX}"},
                 "steps": {"1.3.5": {"valueOverrides": {"Policy definition": "Require a tag on resource groups",
                                                        "Action group": "[Leave blank]"}}}}
    ENV = {"SKYCRAFT_GUIDE_DRIFT_TENANT_PREFIX": "contoso"}

    def action(self, step: str, label: str, value: str, literal: bool = False) -> tuple[str, str]:
        item = {"kind": "field", "label": label, "value": value, "line": 7}
        if not literal:
            item["literal"] = False
        with mock.patch.dict(os.environ, self.ENV):
            return field_action(self.RECORDING, {"id": step}, item)

    def test_an_instruction_without_an_override_is_reported_not_typed(self) -> None:
        self.assertEqual(self.action("1.3.5", "Scope", 'Click the "..." button'),
                         ("instruction", 'Click the "..." button'))
        self.assertEqual(self.action("1.3.8", "Allowed locations", "Select:"), ("instruction", "Select:"))

    def test_a_bracket_token_without_an_override_or_placeholder_is_unresolved(self) -> None:
        # A whole bracketed value used to be left as is and counted as a match.
        for value in ("[IP of dev-skycraft-swc-lb-pip]", "skycraft-auth-[uniqueID] (must be globally unique)"):
            with self.subTest(value=value):
                self.assertEqual(self.action("2.3.2", "IP address", value), ("unresolved", value))

    def test_an_override_is_taken_as_written(self) -> None:
        self.assertEqual(self.action("1.3.5", "Policy definition", 'Click the "..." button'),
                         ("type", "Require a tag on resource groups"))
        self.assertEqual(self.action("1.3.5", "Action group", "(leave blank for now)"), ("skip", "[Leave blank]"))

    def test_placeholders_that_leave_a_literal_make_it_typed(self) -> None:
        self.assertEqual(self.action("1.1.2", "User principal name", "malfurion.stormrage@[yourtenant].onmicrosoft.com"),
                         ("type", "malfurion.stormrage@contoso.onmicrosoft.com"))

    def test_a_literal_value_goes_to_value_action(self) -> None:
        self.assertEqual(self.action("1.1.6", "Group name", "SkyCraft-Admins", literal=True), ("type", "SkyCraft-Admins"))
        self.assertEqual(self.action("3.3.8", "Insecure connections", "Uncheck", literal=True), ("type", "Uncheck"))


class SkipReasonTests(unittest.TestCase):
    """'"skip": "<reason>"' on a step entry (#200): the reason, or an error, never a silent
    'not skipped' that would perform the step the recording meant to leave out."""

    def recording(self, entry: dict) -> dict:
        return {"steps": {"9.9.1": entry}}

    def test_no_entry_or_no_key_is_no_skip(self) -> None:
        self.assertIsNone(skip_reason({"steps": {}}, "9.9.1"))
        self.assertIsNone(skip_reason(self.recording({"labels": {}, "result": None}), "9.9.1"))

    def test_the_reason_is_returned_stripped(self) -> None:
        self.assertEqual(skip_reason(self.recording({"skip": "  Conceptual: no Portal path \n"}), "9.9.1"),
                         "Conceptual: no Portal path")

    def test_a_reason_without_text_or_not_a_string_raises(self) -> None:
        for value in ("", "  \t", None, 0, 1, True, False, [], ["optional"], {}):
            with self.subTest(value=value), self.assertRaisesRegex(ValueError, "step 9.9.1: 'skip' must be"):
                skip_reason(self.recording({"skip": value}), "9.9.1")


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
        for value in ("✅ Checked", "✅", "Checked", "checked", "Enabled", "Yes", "On", "✔ Enabled",
                      "✅ Checked (or uncheck if already have Defender)", "☑ Checked (VMs will auto-register)"):
            with self.subTest(value=value):
                self.assertIs(recording.checkbox_state(value), True)

    def test_unchecked_forms(self):
        for value in ("❌ Unchecked", "☐ Unchecked", "☐", "Uncheck", "leave unchecked", "Disabled", "No", "Off",
                      "☐ Unchecked (no VMs in hub)"):
            with self.subTest(value=value):
                self.assertIs(recording.checkbox_state(value), False)

    def test_neither_or_both_is_none(self):
        for value in ("Leave default", "Standard_LRS", "", "Checked or unchecked"):
            with self.subTest(value=value):
                self.assertIsNone(recording.checkbox_state(value))


if __name__ == "__main__":
    unittest.main()

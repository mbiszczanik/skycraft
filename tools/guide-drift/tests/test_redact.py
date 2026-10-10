"""Unit tests for recording.py, which keeps tenant data out of the recording (issue #189).

Redactor, env_secrets, rejected_candidates and the run log's scrub (#212) are pure and live
outside run.py, so they are tested without a browser and without Playwright, which the CI runner
does not install.

Standard library unittest only; tests/Guide-Drift-Python.Tests.ps1 runs this suite in CI.
Run by hand from the repository root:

    python -B -m unittest discover -s tools/guide-drift/tests -v
"""
import json
import os
import random
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
                       rejected_candidates, resolve_value, resource_name, same_blade, skip_reason,
                       start_blade, value_action, view_blade, write_json)

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
                         "view/Invite/me%40example.com",
                         # Double-encoded, as the Portal encodes blade inputs ('%2540' is '%40').
                         "view/User/upn/someone%2540example.com",
                         "view/User/u/someone%2540example%252Ecom",
                         "view/User/upn/someone_example.com%2523EXT%2523",
                         "view/Blade/id/%252F1111111122223333444455555555aaaa",
                         "view/User/upn/someone%EF%BC%A0example.com",      # a fullwidth at sign
                         "view/User/upn/x%2525252525252540example.com"):   # never stops decoding
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


class ViewBladeTests(unittest.TestCase):
    """The blade part of a recorded view (#207): what a step's start is compared by."""

    def test_a_view_address_keeps_the_extension_the_blade_and_its_menu_entry(self) -> None:
        portal = "https://portal.azure.com/#"
        for view, blade in (
                ("view/Microsoft_AAD_IAM/GroupDetailsMenuBlade/~/Members/groupId/<id>",
                 "Microsoft_AAD_IAM/GroupDetailsMenuBlade/~/Members"),
                ("view/Microsoft_AAD_IAM/ActiveDirectoryMenuBlade/~/Overview",
                 "Microsoft_AAD_IAM/ActiveDirectoryMenuBlade/~/Overview"),
                ("view/Microsoft_AAD_UsersAndTenants/UserProfileMenuBlade/~/overview/userId/<id>/hidePreviewBanner~/true",
                 "Microsoft_AAD_UsersAndTenants/UserProfileMenuBlade/~/overview"),
                ("view/Microsoft_AAD_UsersAndTenants/InviteUser.ReactView/tenantType/AAD",
                 "Microsoft_AAD_UsersAndTenants/InviteUser.ReactView"),
                ("view/Microsoft_AAD_IAM/AddGroup.ReactView", "Microsoft_AAD_IAM/AddGroup.ReactView"),
                ("blade/Microsoft_AAD_IAM/GroupsManagementMenuBlade/~/AllGroups",
                 "Microsoft_AAD_IAM/GroupsManagementMenuBlade/~/AllGroups")):
            with self.subTest(view=view):
                self.assertEqual(view_blade(portal + view), blade)

    def test_any_other_address_is_its_whole_fragment(self) -> None:
        resource = ("resource/subscriptions/<id>/resourceGroups/dev-skycraft-swc-rg/providers/"
                    "Microsoft.Network/loadBalancers/dev-skycraft-swc-lb/backendPools")
        self.assertEqual(view_blade("https://portal.azure.com/#" + resource), resource)
        self.assertEqual(view_blade("https://portal.azure.com/#home"), "home")

    def test_a_browse_blade_keeps_the_resource_type_it_lists(self) -> None:
        portal = "https://portal.azure.com/#view/HubsExtension/"
        for view, blade in (
                ("BrowseResource.ReactView/resourceType/Microsoft.Network%2FloadBalancers",
                 "HubsExtension/BrowseResource.ReactView/resourceType/Microsoft.Network%2FloadBalancers"),
                ("BrowseResource/resourceType/Microsoft.Network%2FvirtualNetworks/filter/x",
                 "HubsExtension/BrowseResource/resourceType/Microsoft.Network%2FvirtualNetworks"),
                ("BrowseResource/resourceType/Microsoft.Network/loadBalancers",      # a plain '/'
                 "HubsExtension/BrowseResource/resourceType/Microsoft.Network/loadBalancers"),
                ("BrowseResourceGroups.ReactView", "HubsExtension/BrowseResourceGroups.ReactView")):
            with self.subTest(view=view):
                self.assertEqual(view_blade(portal + view), blade)
        # Any other blade's inputs are still left out.
        self.assertEqual(view_blade("https://portal.azure.com/#view/Other/Blade/resourceType/x"), "Other/Blade")

    def test_same_blade_ignores_case_and_a_trailing_overview(self) -> None:
        lb = "resource/subscriptions/<id>/resourceGroups/dev-rg/providers/Microsoft.Network/loadBalancers/dev-lb"
        self.assertTrue(same_blade(lb, lb + "/overview"))
        self.assertTrue(same_blade(lb + "/Overview", lb.upper()))
        self.assertTrue(same_blade("Microsoft_AAD_IAM/ActiveDirectoryMenuBlade/~/Overview",
                                   "Microsoft_AAD_IAM/ActiveDirectoryMenuBlade"))
        self.assertFalse(same_blade("Microsoft_AAD_IAM/GroupDetailsMenuBlade/~/Members",
                                    "Microsoft_AAD_IAM/GroupDetailsMenuBlade"))
        self.assertFalse(same_blade(lb, lb + "/backendPools"))
        self.assertFalse(same_blade("HubsExtension/BrowseResource/resourceType/Microsoft.Network%2FloadBalancers",
                                    "HubsExtension/BrowseResource/resourceType/Microsoft.Network%2FvirtualNetworks"))

    def test_no_view_or_an_empty_fragment_is_no_blade(self) -> None:
        for view in (None, "https://portal.azure.com/#", "https://portal.azure.com/"):
            with self.subTest(view=view):
                self.assertIsNone(view_blade(view))

    def test_a_redacted_view_gives_a_redacted_blade_and_one_with_personal_data_none(self) -> None:
        redactor = Redactor(DOMAIN, TENANT)
        view = redactor.view_url(f"https://portal.azure.com/#@{DOMAIN}/view/Domains/DomainMenuBlade/~/Overview"
                                 f"/name/{DOMAIN}?x=1")
        self.assertEqual(view_blade(view), "Domains/DomainMenuBlade/~/Overview")
        self.assertIsNone(view_blade(redactor.view_url(
            "https://portal.azure.com/#view/UserBlade/upn/someone%40example.com")))


class StartBladeTests(unittest.TestCase):
    """'"startBlade": "<blade>"' in a step entry (#207): optional; absent is 'not recorded yet'."""

    def recording(self, **entry) -> dict:
        return {"steps": {"1.1.6": entry}}

    def test_no_entry_no_key_or_null_is_not_recorded(self) -> None:
        self.assertIsNone(start_blade({"steps": {}}, "1.1.6"))
        self.assertIsNone(start_blade(self.recording(labels={}), "1.1.6"))
        self.assertIsNone(start_blade(self.recording(startBlade=None), "1.1.6"))

    def test_the_blade_is_returned_as_recorded(self) -> None:
        blade = "Microsoft_AAD_IAM/GroupsManagementMenuBlade/~/AllGroups"
        self.assertEqual(start_blade(self.recording(startBlade=blade), "1.1.6"), blade)

    def test_a_blade_without_text_or_not_a_string_raises(self) -> None:
        for value in ("", "   ", True, 1, ["Microsoft_AAD_IAM/AddGroup.ReactView"]):
            with self.subTest(value=value), self.assertRaisesRegex(
                    ValueError, r"^step 1\.1\.6: 'startBlade' must be the blade part of a Portal view, a non-empty string"):
                start_blade(self.recording(startBlade=value), "1.1.6")


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



class RunLogTextTests(unittest.TestCase):
    """What a run log keeps of an error or a free text (#212): its first line, without the
    Playwright call log, typed values or element values, and redacted (recording.scrub)."""

    # The formats Playwright 1.63 raises (playwright/_impl/_helper.py parse_error and
    # _connection.py format_call_log: '<api>: <message>' + '\nCall log:\n' + its lines).
    TIMEOUT = ('Locator.fill: Timeout 8000ms exceeded.\nCall log:\n'
               '  - waiting for get_by_role("textbox", name="Password")\n'
               '    - locator resolved to <input id="p" readonly type="password" value="Qx7!fake-generated"/>\n'
               '    - fill("LoveAzeroth!2004")\n  - attempting fill action\n'
               '    2 × waiting for element to be visible, enabled and editable\n'
               '      - element is not editable\n')
    STRICT = ('Locator.fill: Error: strict mode violation: get_by_label("Password") resolved to 2 elements:\n'
              '    1) <input value="Qx7!fake-generated" aria-label="Password"/> aka get_by_role("textbox").first\n'
              '    2) <input value="b" aria-label="Password"/> aka get_by_role("textbox").nth(1)\n\n'
              'Call log:\n  - waiting for get_by_label("Password")\n')

    def setUp(self) -> None:
        self.redactor = Redactor(DOMAIN, TENANT, {TOKEN: "me@example.com"})

    def test_one_line_keeps_the_first_line_and_drops_the_call_log(self) -> None:
        self.assertEqual(recording.one_line(self.TIMEOUT), "Locator.fill: Timeout 8000ms exceeded.")
        self.assertEqual(recording.one_line(self.STRICT),
                         'Locator.fill: Error: strict mode violation: get_by_label("Password") resolved to 2 elements:')
        self.assertEqual(recording.one_line("\n  not found  \nmore"), "not found")
        self.assertEqual(recording.one_line("Call log:\n  - fill(\"x\")"), "")

    def scrub(self, text: str, secrets=frozenset(), redactor=None, whole=False) -> str:
        return recording.scrub(text, redactor or self.redactor, set(secrets), whole=whole)

    def test_scrub_masks_a_typed_value_and_an_element_value_in_the_first_line(self) -> None:
        text = 'Locator.fill: fill("LoveAzeroth!2004") failed on <input type="password" value="Qx7!fake-generated"/>'
        self.assertEqual(self.scrub(text),
                         'Locator.fill: fill("[typed]") failed on <input type="password" value="[value]"/>')
        self.assertEqual(self.scrub("type('a\\'b') then prefill(\"c\\\"d\")"),
                         "type(\"[typed]\") then prefill(\"[typed]\")")
        # Another attribute holding '>' does not hide the value.
        self.assertEqual(self.scrub('<input aria-label="a > b" value="Qx7!fake-generated"> and value=bare'),
                         '<input aria-label="a > b" value="[value]"> and value="[value]"')
        self.assertEqual(self.scrub('<input aria-label="a > b" value=Qx7!fake>'), '<input aria-label="a > b" value="[value]">')
        self.assertEqual(self.scrub("value '[Leave blank]' is an instruction"),
                         "value '[Leave blank]' is an instruction")        # the runner's own words stay

    def test_error_text_is_the_type_and_the_first_line(self) -> None:
        timeout = type("TimeoutError", (Exception,), {})
        self.assertEqual(recording.error_text(timeout(self.TIMEOUT)),
                         "TimeoutError: Locator.fill: Timeout 8000ms exceeded.")
        self.assertEqual(recording.error_text(LookupError("")), "LookupError")

    def test_scrub_redacts_tenant_data_object_ids_and_secrets_on_one_line(self) -> None:
        text = (f"LookupError: option 'malfurion.stormrage@{DOMAIN}' not found in {TENANT}, group "
                "9f8e7d6c-5b4a-4c3d-8e2f-1a0b9c8d7e6f (9F8E7D6C5B4A4C3D8E2F1A0B9C8D7E6F) for me@example.com, "
                "typed LoveAzeroth!2004\nCall log:\n  - <input value=\"Qx7!fake-generated\">")
        self.assertEqual(recording.scrub(text, self.redactor, {"LoveAzeroth!2004"}),
                         "LookupError: option 'malfurion.stormrage@[tenantdomain]' not found in [tenantid], group "
                         f"<id> (<id>) for {TOKEN}, typed [secret]")
        self.assertIsNone(recording.scrub(None, self.redactor, set()))

    def test_scrub_is_idempotent(self) -> None:
        secrets = {"LoveAzeroth!2004", "secret"}
        redactor = Redactor("tenantname.onmicrosoft.com", TENANT, {TOKEN: "me@example.com"},
                            tenant_name="tenantname")
        for text in (self.TIMEOUT, self.STRICT, f"Contoso admin@{DOMAIN} {TENANT} LoveAzeroth!2004",
                     "tenantname [tenantname] [yourtenant] <id> [secret] secret ${SKYCRAFT_GUIDE_DRIFT_GUEST_EMAIL}",
                     "plain text"):
            for r in (self.redactor, redactor):
                with self.subTest(text=text, domain=r.domain):
                    once = recording.scrub(text, r, secrets)
                    self.assertEqual(recording.scrub(once, r, secrets), once)

    def test_redaction_leaves_its_own_tokens_alone(self) -> None:
        # A tenant named like a token used to turn '[tenantname]' into '[[tenantname]]' on a second pass.
        redactor = Redactor("tenantname.onmicrosoft.com", TENANT, tenant_name="tenantname")
        once = redactor.redact("tenantname and tenantname.onmicrosoft.com")
        self.assertEqual(once, "[tenantname] and [tenantdomain]")
        self.assertEqual(redactor.redact(once), once)

    def test_typed_secrets_are_the_values_of_secret_fields(self) -> None:
        steps = {"steps": [{"id": "1.1.2", "items": [
            {"kind": "field", "label": "User principal name", "value": "malfurion.stormrage@[yourtenant].onmicrosoft.com"},
            {"kind": "field", "label": "Auto-generate password", "value": "☐ Unchecked"},
            {"kind": "field", "label": "Password", "value": "LoveAzeroth!2004"},
            {"kind": "action", "labels": ["Password reset"]}]},
            {"id": "1.1.3", "items": [{"kind": "field", "label": "Password", "value": "LoveAzeroth!2004"},
                                      {"kind": "field", "label": "Client secret", "value": "[Leave blank]"}]},
            {"id": "1.1.4", "items": [{"kind": "field", "label": "Confirm password", "value": "Ignored!1"}]}]}
        rec = {"placeholders": {}, "steps": {"1.1.4": {"valueOverrides": {"Confirm password": "${SKYCRAFT_TEST_PASSWORD}"}}}}
        with mock.patch.dict(os.environ, {"SKYCRAFT_TEST_PASSWORD": "Fake!Override9"}):
            self.assertEqual(recording.typed_secrets(rec, steps), {"LoveAzeroth!2004", "Ignored!1", "Fake!Override9"})
        with mock.patch.dict(os.environ, {}, clear=True):          # an unset variable is left out, not raised
            self.assertEqual(recording.typed_secrets(rec, steps), {"LoveAzeroth!2004", "Ignored!1"})

    def test_a_password_that_holds_a_check_box_word_is_still_a_secret(self) -> None:
        passwords = {"Password": "No!Access2024", "Admin password": "Yes-Man#2024", "Key1": "on_call 42 Off"}
        steps = {"steps": [{"id": "1.1.2", "items": (
            [{"kind": "field", "label": label, "value": value} for label, value in passwords.items()]
            + [{"kind": "field", "label": "Confirm password", "value": "[from the environment]", "literal": False},
               {"kind": "field", "label": "Auto-generate password", "value": "☐ Unchecked"},
               {"kind": "field", "label": "Require password change", "value": "✅ Checked (or uncheck if already have Defender)"},
               {"kind": "field", "label": "Show password", "value": "leave unchecked"},
               {"kind": "field", "label": "Password writeback", "value": "☑ Checked"}])}]}
        rec = {"placeholders": {}, "steps": {"1.1.2": {"valueOverrides": {"Confirm password": "${SKYCRAFT_TEST_PASSWORD}"}}}}
        with mock.patch.dict(os.environ, {"SKYCRAFT_TEST_PASSWORD": "Off-Grid!99"}):
            self.assertEqual(recording.typed_secrets(rec, steps), set(passwords.values()) | {"Off-Grid!99"})
        for value in ("☐ Unchecked", "✅", "leave unchecked", "Disabled.", "☑ Checked (VMs will auto-register)"):
            with self.subTest(value=value):
                self.assertTrue(recording.only_checkbox_state(value))
        for value in ("No!Access2024", "Off-Grid!99", "On call", "Checked-In#7", ""):
            with self.subTest(value=value):
                self.assertFalse(recording.only_checkbox_state(value))

    def test_secret_fields_are_named_as_the_portal_labels_credentials(self) -> None:
        for label in ("Password", "Client secret", "Connection string", "Primary connection string", "SAS token",
                      "Blob SAS URL", "Shared access signature", "Access key", "Storage account key", "Primary key",
                      "key1", "Key 2", "Passphrase"):
            with self.subTest(label=label):
                self.assertIsNotNone(recording.SECRET_FIELD.search(label))
        for label in ("Key vault name", "Key type", "Display name", "Keyboard layout", "Saskatoon"):
            with self.subTest(label=label):
                self.assertIsNone(recording.SECRET_FIELD.search(label))

    def test_scrub_masks_credentials_in_connection_strings_and_sas_addresses(self) -> None:
        cases = {
            "DefaultEndpointsProtocol=https;AccountName=sa;AccountKey=abc+/def==;EndpointSuffix=core.windows.net":
                "DefaultEndpointsProtocol=https;AccountName=sa;AccountKey=[secret];EndpointSuffix=core.windows.net",
            "Endpoint=sb://ns.servicebus.windows.net/;SharedAccessKeyName=Root;SharedAccessKey=xyz=":
                "Endpoint=sb://ns.servicebus.windows.net/;SharedAccessKeyName=Root;SharedAccessKey=[secret]",
            "https://sa.blob.core.windows.net/c?sv=2022-11-02&sig=abc%2Bdef%3D&se=2026":
                "https://sa.blob.core.windows.net/c?sv=2022-11-02&sig=[secret]&se=2026",
            "Server=tcp:db;User ID=admin;Password=p@ss.w0rd;Encrypt=True":
                "Server=tcp:db;User ID=admin;Password=[secret];Encrypt=True",
        }
        for text, kept in cases.items():
            with self.subTest(text=text):
                self.assertEqual(self.scrub(text), kept)
        tree = ('- textbox "Connection string": AccountKey=abc\n- textbox "key1": abc\n'
                '- textbox "SAS token" [disabled]: sv=1\n- textbox "Key vault name": kv-skycraft')
        self.assertEqual(self.scrub(tree, whole=True),
                         '- textbox "Connection string": [secret]\n- textbox "key1": [secret]\n'
                         '- textbox "SAS token" [disabled]: [secret]\n- textbox "Key vault name": kv-skycraft')

    def test_scrub_masks_every_address_outside_the_tenant(self) -> None:
        self.assertEqual(self.scrub(f"Signed in as marcin.b@fabrikam.example, user malfurion@{DOMAIN}, guest "
                                    f"me@example.com, me_example.com#EXT#@{DOMAIN}, o'neil@sub.example.org"),
                         f"Signed in as <email>, user malfurion@[tenantdomain], guest {TOKEN}, "
                         f"{UPN_TOKEN}#EXT#@[tenantdomain], <email>")
        self.assertEqual(self.scrub("- button \"Account manager for Marcin (marcin@fabrikam.example)\"", whole=True),
                         "- button \"Account manager for Marcin (<email>)\"")

    def test_scrub_masks_ids_first_so_the_tenant_prefix_beside_one_goes_too(self) -> None:
        hex_id = "9f8e7d6c5b4a4c3d8e2f1a0b9c8d7e6f"
        encoded = "9f8e7d6c%2D5b4a%2d4c3d%2D8e2f%2D1a0b9c8d7e6f"
        cases = {
            f"contoso{hex_id}": "[yourtenant]<id>",
            f"{hex_id}-contoso": "<id>-contoso",
            f"{hex_id}contoso": f"{hex_id}contoso",    # 33 hex digits in a row: no id, no prefix
            f"group {encoded}": "group <id>",
            TENANT.replace("-", ""): "[tenantid]",
            TENANT.replace("-", "%2D"): "[tenantid]",
            TENANT.upper(): "[tenantid]",
        }
        for text, kept in cases.items():
            with self.subTest(text=text):
                self.assertEqual(self.scrub(text), kept)

    def test_scrub_masks_tenant_data_as_a_regular_expression_escapes_it(self) -> None:
        redactor = Redactor(DOMAIN, TENANT, {TOKEN: "me@example.com"}, tenant_name="Contoso Ltd")
        text = ('Locator.click: Error: strict mode violation: get_by_role("option", name=re.compile('
                r'r"^malfurion\.stormrage@contoso\.onmicrosoft\.com$", re.IGNORECASE)) resolved to 2 elements:')
        self.assertEqual(self.scrub(text, redactor=redactor),
                         'Locator.click: Error: strict mode violation: get_by_role("option", name=re.compile('
                         r'r"^malfurion\.stormrage@[tenantdomain]$", re.IGNORECASE)) resolved to 2 elements:')
        self.assertEqual(self.scrub(r"^me@example\.com$ ^me_example\.com\#EXT\#$ ^Contoso\ Ltd$", redactor=redactor),
                         rf"^{TOKEN}$ ^{UPN_TOKEN}\#EXT\#$ ^[tenantname]$")

    ADJACENT = ("contoso9f8e7d6c5b4a4c3d8e2f1a0b9c8d7e6f", "9f8e7d6c5b4a4c3d8e2f1a0b9c8d7e6fcontoso",
                "contoso<id>", "<id>contoso", "[tenantdomain]contoso", "contoso[secret]", "contoso<email>",
                'value="contoso"contoso', 'fill("contoso")contoso', "a@b.cocontoso", "contoso@b.co",
                "contoso.onmicrosoft.comcontoso", "AccountKey=contoso;contoso", "sig=[secret]x",
                f"{TENANT}contoso", "secretcontoso", "LoveAzeroth!2004contoso", "Contoso Ltdcontoso")

    def test_scrub_is_idempotent_for_text_beside_a_token(self) -> None:
        redactor = Redactor(DOMAIN, TENANT, {TOKEN: "me@example.com"}, tenant_name="Contoso Ltd")
        for text in self.ADJACENT:
            for whole in (False, True):
                with self.subTest(text=text, whole=whole):
                    once = self.scrub(text, {"LoveAzeroth!2004", "secret"}, redactor, whole)
                    self.assertEqual(self.scrub(once, {"LoveAzeroth!2004", "secret"}, redactor, whole), once)

    def test_scrub_is_idempotent_for_random_text(self) -> None:
        pieces = ["contoso", "Contoso Ltd", ".onmicrosoft.com", DOMAIN, TENANT, TENANT.replace("-", ""),
                  "9f8e7d6c-5b4a-4c3d-8e2f-1a0b9c8d7e6f", "9f8e7d6c", "%2D", "me@example.com", "me_example.com",
                  "#EXT#@", "@", ".", "-", "_", " ", "\n", '"', "'", "<", ">", "=", ";", "&", "\\", "(", ")",
                  "[tenantid]", "[yourtenant]", "<id>", "<email>", "[secret]", "[typed]", "[value]", TOKEN,
                  "fill(", "value=", "<input ", "AccountKey=", "sig=", "Password=", "Call log:",
                  "LoveAzeroth!2004", "secret", "x", "ab", "b.co", "%40", "re.escape", "\\."]
        generator = random.Random(212)
        redactor = Redactor(DOMAIN, TENANT, {TOKEN: "me@example.com"}, tenant_name="Contoso Ltd")
        for _ in range(3000):
            text = "".join(generator.choice(pieces) for _ in range(generator.randint(1, 12)))
            whole = generator.random() < 0.5
            once = self.scrub(text, {"LoveAzeroth!2004"}, redactor, whole)
            self.assertEqual(self.scrub(once, {"LoveAzeroth!2004"}, redactor, whole), once, repr(text))


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

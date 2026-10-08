"""Unit tests for parse.py's reading of one list item: which searches are the Portal's global
search and which are a blade's own search box (issue #189), which '- Label: value' items with
a plain label are fields (issue #198), and which field values are not text to type (issue #202).
The full guides and the other parser rules are covered by
tests/Guide-Drift-Parser.Tests.ps1. Run from the repository root:

    python -B -m unittest discover -s tools/guide-drift/tests -v
"""
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

import parse  # noqa: E402


class SearchScopeTests(unittest.TestCase):
    def item(self, text: str) -> dict | None:
        return parse.list_item(text, 7)

    def test_a_search_that_names_the_portal_is_global(self) -> None:
        for text, label in (('Search for **"Microsoft Entra ID"** in the search bar', "Microsoft Entra ID"),
                            ("Search for **Microsoft Entra ID** in the top search bar", "Microsoft Entra ID"),
                            ("Search for **Policy** in the global search", "Policy"),
                            ('In **Azure Portal**, search for **"Resource groups"**', "Resource groups"),
                            ("In Azure Portal, search for **Advisor**", "Advisor"),
                            ('Search for **"Network Watcher"** in Azure Portal', "Network Watcher")):
            with self.subTest(text=text):
                self.assertEqual(self.item(text), {"kind": "search", "labels": [label], "scope": "global", "line": 7})

    def test_any_other_search_is_the_open_blades(self) -> None:
        for text, label in (('Search for **"Owner"**', "Owner"),
                            ("Search for **“Malfurion Stormrage”**", "Malfurion Stormrage"),
                            ("Search for **Backup vaults**.", "Backup vaults")):
            with self.subTest(text=text):
                self.assertEqual(self.item(text), {"kind": "search", "labels": [label], "scope": "blade", "line": 7})

    def test_search_for_and_select_and_searches_with_more_after_them_stay_clicks(self) -> None:
        for text, labels in (("Search for and select **Malfurion Stormrage**", ["Malfurion Stormrage"]),
                             ('Search for **"Khadgar Archmage"** (individual user)', ["Khadgar Archmage"]),
                             ("In Azure Portal, search for **SSH keys** and click **+ Create**", ["SSH keys", "+ Create"]),
                             ("Open **Settings** and search for **Advanced**", ["Settings", "Advanced"])):
            with self.subTest(text=text):
                self.assertEqual(self.item(text), {"kind": "action", "labels": labels, "line": 7})


class PlainLabelFieldTests(unittest.TestCase):
    """'- Label: value' with a plain label is a field when the value starts with a bold or code
    span (#198). Most texts here are list items from the guides."""

    def item(self, text: str) -> dict | None:
        return parse.list_item(text, 7)

    def field(self, label: str, value: str) -> dict:
        return {"kind": "field", "label": label, "value": value, "line": 7}

    def test_a_bold_or_code_value_makes_a_field(self) -> None:
        for text, label, value in (("Lock type: **Delete**", "Lock type", "Delete"),
                                   ("Name: `rg-test-no-tag`", "Name", "rg-test-no-tag"),
                                   ("Retention (days): **7**", "Retention (days)", "7"),
                                   ("Check every: **1 minute**", "Check every", "1 minute"),
                                   ("Type: **Virtual Machine**", "Type", "Virtual Machine"),
                                   ("Resource: `dev-skycraft-swc-auth-vm`", "Resource", "dev-skycraft-swc-auth-vm")):
            with self.subTest(text=text):
                self.assertEqual(self.item(text), self.field(label, value))

    def test_the_value_is_the_span_and_a_remark_after_it_is_dropped(self) -> None:
        for text, label, value in (("Name: `staging`.", "Name", "staging"),
                                   ("Public IP: `prod-skycraft-swc-lb-pip` (use existing)", "Public IP", "prod-skycraft-swc-lb-pip"),
                                   ("Remote IP: **8.8.8.8** (Example external IP)", "Remote IP", "8.8.8.8"),
                                   ("Policy sub-type: **Enhanced**. Azure defaults VM deployments to Trusted Launch, and a", "Policy sub-type", "Enhanced"),
                                   ("Anonymous access level: **Private (no anonymous access)** - the dropdown still offers Blob and Container, but leave it at Private",
                                    "Anonymous access level", "Private (no anonymous access)"),
                                   ("Region: **Sweden Central** (the wizard defaults to East US; `Test-Lab.ps1` looks under `NetworkWatcher_swedencentral`)",
                                    "Region", "Sweden Central"),
                                   ("Resource: `prod-skycraft-swc-auth-vm` *(if Lab 3.2 prod environment was deployed)*", "Resource", "prod-skycraft-swc-auth-vm")):
            with self.subTest(text=text):
                self.assertEqual(self.item(text), self.field(label, value))

    def test_a_bold_value_loses_code_marks_as_with_a_bold_label(self) -> None:
        self.assertEqual(self.item("Name: **`dev-skycraft-swc-rg`**"), self.field("Name", "dev-skycraft-swc-rg"))
        self.assertEqual(self.item("**Name**: **`dev-skycraft-swc-rg`**"), self.field("Name", "dev-skycraft-swc-rg"))

    def test_a_label_with_an_underscore_is_not_a_plain_label(self) -> None:
        # An underscore marks italics ('_Note_:') or an identifier, never a Portal label.
        for text in ("_Note_: `this` is a caption", "resource_group: `dev-skycraft-swc-rg`"):
            with self.subTest(text=text):
                self.assertIsNone(self.item(text))

    def test_a_plain_text_value_is_not_a_field(self) -> None:
        # Nearly every plain value in the guides is a line of a list to check, not a form.
        for text in ("Name: Malfurion Stormrage",
                     "Address space: 10.0.0.0/16",
                     "Compliance state: Compliant, Non-compliant, Not started",
                     "Priority 100: Allow SSH (22) from Bastion (10.0.0.0/26)",
                     "Subscription: yours",
                     "Source ASG: Select `dev-skycraft-swc-asg-auth` and `dev-skycraft-swc-asg-world`"):
            with self.subTest(text=text):
                self.assertIsNone(self.item(text))

    def test_an_instruction_before_the_colon_is_not_a_label(self) -> None:
        for text, expected in (("Enter: `10.0.0.0/16`", None),
                               ("Add tag: `Environment` = `Test`", None),
                               ("Select your VM: `dev-skycraft-swc-auth-vm`.", None),
                               ("Choose resource group: `prod-skycraft-swc-rg`", None),
                               ("Create new private DNS zone: `privatelink.blob.core.windows.net`", None),
                               ("Link to VNet: `prod-skycraft-swc-vnet`", None),
                               ("Type the VMSS name to confirm: `prod-skycraft-swc-world-vmss`", None),
                               ("Navigate to the newly created NSG: **dev-skycraft-swc-auth-nsg**",
                                {"kind": "action", "labels": ["dev-skycraft-swc-auth-nsg"], "line": 7}),
                               ('Search for: **"Require a tag on resource groups"**',
                                {"kind": "action", "labels": ["Require a tag on resource groups"], "line": 7})):
            with self.subTest(text=text):
                self.assertEqual(self.item(text), expected)

    def test_captions_and_prose_are_not_fields(self) -> None:
        for text in ("Example: `skycraft-auth-123.swedencentral.azurecontainer.io`",
                     "Note: `this` is a caption",
                     "_Note: This subnet was created in Lab 2.1 specifically for this purpose._",
                     "Download from [https://azure.microsoft.com/features/storage-explorer/](https://azure.microsoft.com/features/storage-explorer/)",
                     "See https://`example`",
                     "Once the deployment finishes the Portal shows its name: `skycraft-vm`"):
            with self.subTest(text=text):
                self.assertIsNone(self.item(text))

    def test_several_bold_spans_or_a_chain_after_the_label_stay_clicks(self) -> None:
        for text, kind, labels in (("Logs: **StorageRead** and **StorageWrite**.", "action", ["StorageRead", "StorageWrite"]),
                                   ("Frequency: **Daily** at **02:00 AM**.", "action", ["Daily", "02:00 AM"]),
                                   ("Destination: **Send to Log Analytics workspace** → `platform-skycraft-swc-law`.",
                                    "action", ["Send to Log Analytics workspace"]),
                                   ("Flow log type: **Virtual network** → **+ Select target resource** → **Confirm selection**",
                                    "navigation", ["Virtual network", "+ Select target resource", "Confirm selection"])):
            with self.subTest(text=text):
                self.assertEqual(self.item(text), {"kind": kind, "labels": labels, "line": 7})

    def test_a_bold_label_still_takes_the_whole_value(self) -> None:
        self.assertEqual(self.item("**Policy enforcement**: Enabled"), self.field("Policy enforcement", "Enabled"))
        self.assertEqual(self.item("**Region**: **Sweden Central** (recommended)"), self.field("Region", "Sweden Central (recommended)"))


class LiteralValueTests(unittest.TestCase):
    """A field value that is an instruction or a placeholder is marked '"literal": false' (#202).
    The values are the guides' own, from the lab named."""

    INSTRUCTIONS = (
        'Click the "..." button',                                        # 1.3.5
        'Search for "Allowed locations"',                                # 1.3.8
        "Select:",                                                       # 1.3.8, a list follows
        "(leave blank for now)",                                         # 1.3.15
        "Enter your email address",                                      # 1.3.15
        "[IP of dev-skycraft-swc-lb-pip]",                               # 2.3.2
        "[Your subscription]",                                           # 1.2-3.2
        "Your subscription",                                             # 1.3, 3.2-4.1
        "malfurion.stormrage@[yourtenant].onmicrosoft.com",              # 1.1, placeholder
        "skycraft-auth-[uniqueID] (must be globally unique in the region)",  # 3.3.4
        "Leave default",                                                 # 3.2.5
        "Browse to your private key file (skycraft-dev for option A)",   # 3.2.15
        "Paste your skycraft-dev.pub key",                               # 3.2.29
        "Create a container named app-backups",                          # 3.4.13
        "Select DevRevokePolicy",                                        # 4.4.4
        "uncheck Use workspace created by connection monitor and select platform-skycraft-swc-law",  # 5.3.6
        "leave unchecked. Click Review + create → Create",               # 5.3.6
        "Leave checked and select platform-skycraft-swc-law",            # more after the state
        "Check Enable auto-shutdown",                                     # a word after the verb
    )
    LITERALS = (
        "SkyCraft-Admins", "Sweden Central (or your preferred region)", "",
        # check box states, applied to a check box (fill_field), never typed
        "Uncheck", "checked", "Check", "✅ Checked", "☐ Unchecked", "❌ Disabled (for dev, you may enable)",
        "Leave checked", "leave unchecked", "Leave Unchecked ",             # a bare 'leave' state
        "Uncheck (default)", "Check (recommended)",                       # a remark, not a word, after the verb
        # the Portal's own options, which start with a verb
        "Create new", "Disable", "Allow", "Enable public access from all networks", "Use existing public key",
        "Apply rule to all blobs in your storage account", "Do not clone settings", "Limit blobs with filters",
        "Scale based on a metric", "Increase count by", "Selected networks",
    )

    def test_instructions_and_placeholders_are_not_literal(self) -> None:
        for value in self.INSTRUCTIONS:
            with self.subTest(value=value):
                self.assertFalse(parse.value_is_literal(value))

    def test_values_to_type_or_pick_and_check_box_states_are_literal(self) -> None:
        for value in self.LITERALS:
            with self.subTest(value=value):
                self.assertTrue(parse.value_is_literal(value))

    def test_a_list_item_field_carries_the_mark_only_when_it_is_not_literal(self) -> None:
        for text, label, value, literal in (('**Scope**: Click the "..." button', "Scope", 'Click the "..." button', False),
                                            ("**Allowed locations**: Select:", "Allowed locations", "Select:", False),
                                            ("**Stored access policy**: Select `DevRevokePolicy`.", "Stored access policy",
                                             "Select DevRevokePolicy", False),
                                            ("**Insecure connections** : `Uncheck`", "Insecure connections", "Uncheck", True),
                                            ("**Enable traffic analytics**: checked", "Enable traffic analytics", "checked", True),
                                            ("Lock type: **Delete**", "Lock type", "Delete", True)):
            with self.subTest(text=text):
                expected = {"kind": "field", "label": label, "value": value, "line": 7}
                if not literal:
                    expected["literal"] = False
                self.assertEqual(parse.list_item(text, 7), expected)

    def test_a_form_table_row_carries_the_mark_and_a_tag_row_never_does(self) -> None:
        lines = list(enumerate(["| Field | Value |", "| --- | --- |", "| Name | `dev` |",
                                "| IP address | [IP of dev-skycraft-swc-lb-pip] |", "",
                                "| Tag | Value |", "| --- | --- |", "| Owner | [your name] |"], start=1))
        items, _ = parse.parse_items(lines)
        self.assertEqual(items, [
            {"kind": "field", "label": "Name", "value": "dev", "line": 3},
            {"kind": "field", "label": "IP address", "value": "[IP of dev-skycraft-swc-lb-pip]", "line": 4,
             "literal": False},
            {"kind": "tag", "name": "Owner", "value": "[your name]", "line": 8}])


if __name__ == "__main__":
    unittest.main()

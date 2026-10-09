"""Unit tests for parse.py's reading of one list item: which searches are the Portal's global
search and which are a blade's own search box (issue #189), which '- Label: value' items with
a plain label are fields (issue #198), which field values are not text to type (issue #202),
which lists are checks for the Expected Result rather than steps (issue #224), and which code
spans in a navigation chain are resources to open (issue #199). The full guides and the other
parser rules are covered by tests/Guide-Drift-Parser.Tests.ps1. Run from the repository root:

    python -B -m unittest discover -s tools/guide-drift/tests -v
"""
import sys
import time
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


class ChainResourceTests(unittest.TestCase):
    """A chain step that is one code span names a resource to open (#199): a label in its place,
    its index in '"resources"'. The texts are list items from the guides, from the lab named."""

    def item(self, text: str) -> dict | None:
        return parse.list_item(text, 7)

    def navigation(self, labels: list[str], resources: list[int]) -> dict:
        return {"kind": "navigation", "labels": labels, "resources": resources, "line": 7}

    def test_a_code_span_step_is_a_resource_in_its_place_in_the_chain(self) -> None:
        for text, labels, resources in (
                ("Navigate to **Load balancers** → `dev-skycraft-swc-lb` → **Backend pools**",            # 3.2.13
                 ["Load balancers", "dev-skycraft-swc-lb", "Backend pools"], [1]),
                ("Navigate to `prodskycraftswcsa` → **Security + networking** → **Encryption**",          # 4.1.8
                 ["prodskycraftswcsa", "Security + networking", "Encryption"], [0]),
                ("Navigate to `prodskycraftswcsa` → **Containers** → `game-assets`",                      # 4.2.11
                 ["prodskycraftswcsa", "Containers", "game-assets"], [0, 2]),
                ("Navigate to **Virtual Networks** > `prod-skycraft-swc-vnet` > **Subnets**.",            # 4.4.1
                 ["Virtual Networks", "prod-skycraft-swc-vnet", "Subnets"], [1]),
                ("Go to **Data storage** > **Containers** > `scripts` (or any container).",              # 4.4.3
                 ["Data storage", "Containers", "scripts"], [2]),
                ("Open `platform-skycraft-swc-rsv` → **Monitoring** → **Diagnostic settings**",           # 5.2.8
                 ["platform-skycraft-swc-rsv", "Monitoring", "Diagnostic settings"], [0]),
                ("**+ Add sources** → **Azure endpoints** → select `prod-skycraft-swc-auth-vm` → **Add endpoints**.",  # 5.3.6
                 ["+ Add sources", "Azure endpoints", "prod-skycraft-swc-auth-vm", "Add endpoints"], [2])):
            with self.subTest(text=text):
                self.assertEqual(self.item(text), self.navigation(labels, resources))

    def test_one_bold_label_and_a_resource_make_a_navigation(self) -> None:
        self.assertEqual(self.item("Navigate to **Virtual machines** → `dev-skycraft-swc-world-vm`"),     # 3.2.14
                         self.navigation(["Virtual machines", "dev-skycraft-swc-world-vm"], [1]))
        self.assertEqual(self.item("Open `skycraft-config` → `common` → select `config.txt`"),           # 4.3.6
                         self.navigation(["skycraft-config", "common", "config.txt"], [0, 1, 2]))

    def test_a_resource_name_alone_or_outside_a_chain_is_no_item(self) -> None:
        for text in ("Navigate to `prodskycraftswcsa`",
                     "Try to delete `dev-skycraft-swc-rg` → Should fail (Contributor can't delete RGs)",   # 1.2.13
                     "`dev-skycraft-swc-rg` → Should succeed"):
            with self.subTest(text=text):
                self.assertIsNone(self.item(text))

    def test_a_code_span_with_more_in_its_step_is_a_value_or_prose(self) -> None:
        for text, kind, labels in (
                ("Click **+ Add directory** → Name: `common` → **OK**", "navigation", ["+ Add directory", "OK"]),   # 4.3.4
                ("Back in the Portal, click **Upload** → select the modified `config.txt` → check **Overwrite if "
                 "files already exist** → **Upload**", "navigation", ["Upload", "Overwrite if files already exist", "Upload"]),
                ("Browse to `common/config.txt` → click **⋯** → **Restore**", "navigation", ["⋯", "Restore"]),
                ("Open `skycraft-config` share → **Connect**", "action", ["Connect"]),                            # 4.3.8
                ("**Test groups** → **+ Add test group** → Test group name: `hub-spoke-ssh`",                     # 5.3.6
                 "navigation", ["Test groups", "+ Add test group"])):
            with self.subTest(text=text):
                self.assertEqual(self.item(text), {"kind": kind, "labels": labels, "line": 7})

    def test_the_chain_after_a_plain_label_names_no_resource(self) -> None:
        for text, kind, labels in (
                ("Destination: **Send to Log Analytics workspace** → `platform-skycraft-swc-law`.",              # 5.1.7
                 "action", ["Send to Log Analytics workspace"]),
                ("Flow log type: **Virtual network** → **+ Select target resource** → **Virtual network** → "
                 "`prod-skycraft-swc-vnet` → **Confirm selection**",                                             # 5.3.5
                 "navigation", ["Virtual network", "+ Select target resource", "Virtual network", "Confirm selection"])):
            with self.subTest(text=text):
                self.assertEqual(self.item(text), {"kind": kind, "labels": labels, "line": 7})

    def test_a_separator_inside_a_code_or_bold_span_does_not_split_a_step(self) -> None:
        # A split at the arrow inside the second code span would cut the step in the middle of that
        # span, and the step would name no resource.
        self.assertEqual(self.item("**Load balancers** → `dev-skycraft-swc-lb` (traffic flows `lb → vm`)"),
                         self.navigation(["Load balancers", "dev-skycraft-swc-lb"], [1]))
        self.assertEqual(self.item("Check that **Monitoring** shows `10.0.0.0/8 → None`"),
                         {"kind": "action", "labels": ["Monitoring"], "line": 7})
        self.assertEqual(self.item("**Settings > Advanced** → `dev-vm`"),
                         self.navigation(["Settings > Advanced", "dev-vm"], [1]))

    def test_a_name_of_nothing_but_spaces_is_no_resource(self) -> None:
        for text in ("Open **A** → ` `", "Open **A** → `\t`"):
            with self.subTest(text=text):
                self.assertEqual(self.item(text), {"kind": "action", "labels": ["A"], "line": 7})

    def test_a_label_that_ends_in_a_time_is_not_a_plain_label(self) -> None:
        # 5.2.3: '02:00:' has no space after its first colon, so PLAIN_LABEL_START does not take
        # the text before it for a plain label, and the VM stays a resource of the chain. A time
        # written '2 AM:' would read as one, and the chain would name no resource.
        self.assertEqual(self.item("Run the first backup now instead of waiting for 02:00: **Protected items** → "
                                   "**Backup items** → **Azure Virtual Machine** → `dev-skycraft-swc-auth-vm` → "
                                   "**Backup now** → **OK**."),
                         self.navigation(["Protected items", "Backup items", "Azure Virtual Machine",
                                          "dev-skycraft-swc-auth-vm", "Backup now", "OK"], [3]))

    def test_a_long_step_is_read_in_linear_time(self) -> None:
        # Two '\s*' around an optional group took about 300 s on the first of these (#199).
        for space in (" ", "\t"):
            for text in ("**A** → `x`" + space * 100_000 + "`y`",
                         "**A** → `" + space * 100_000 + "x` junk",
                         "**A** → `" + "x" * 100_000 + "` junk",
                         "**A** → `x` (" + "y" * 100_000 + ")" + space * 100_000 + "junk",
                         "**A** → Navigate" + space * 100_000 + "to" + space * 100_000 + "x"):
                with self.subTest(space=repr(space), text=text[:12]):
                    started = time.perf_counter()
                    self.assertEqual(self.item(text), {"kind": "action", "labels": ["A"], "line": 7})
                    self.assertLess(time.perf_counter() - started, 2)


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


class CheckListTests(unittest.TestCase):
    """A list introduced by 'verify:' or by an Expected Result whose text ends with a colon is a
    list of checks (#224): its items are never step items and their text extends the step's
    Expected Result. The fixtures copy the shapes of 2.2.11, 2.3.19, 4.1.2 and 4.1.11."""

    def step(self, markdown: str) -> tuple[list[dict], str | None]:
        """Items and Expected Result of the one step in markdown (its heading is line 1)."""
        body = parse.split_steps(parse.strip_hidden(markdown.splitlines()))[0]["body"]
        items, expected, _ = parse.read_step(body)
        return items, expected

    def test_the_nested_items_of_a_numbered_verify_item_are_checks_not_fields(self) -> None:
        items, expected = self.step(
            "### Step 9.9.1: Verify\n"
            "\n"
            "1. Click **platform-skycraft-swc-bas**\n"
            "2. Verify:\n"
            "   - Status: **Succeeded**\n"
            "   - Virtual network: `platform-skycraft-swc-vnet`\n")
        self.assertEqual(items, [{"kind": "action", "labels": ["platform-skycraft-swc-bas"], "line": 3}])
        self.assertEqual(expected, "Status: Succeeded; Virtual network: platform-skycraft-swc-vnet")

    def test_in_x_verify_keeps_the_click_on_x(self) -> None:
        items, expected = self.step(
            "### Step 9.9.1: Verify\n"
            "\n"
            "1. In **Configuration**, verify:\n"
            "   - Allow Blob anonymous access: **Disabled**\n")
        self.assertEqual(items, [{"kind": "action", "labels": ["Configuration"], "line": 3}])
        self.assertEqual(expected, "Allow Blob anonymous access: Disabled")

    def test_the_list_after_an_expected_result_ending_in_verify_follows_its_text(self) -> None:
        items, expected = self.step(
            "### Step 9.9.1: Create\n"
            "\n"
            "1. Click **Create**\n"
            "\n"
            "**Expected Result**: Deployment succeeds. Navigate to the resource to verify:\n"
            "\n"
            "- Name: `platformskycraftswcsa`\n"
            "- Location: Sweden Central\n")
        self.assertEqual(items, [{"kind": "action", "labels": ["Create"], "line": 3}])
        self.assertEqual(expected, "Deployment succeeds. Navigate to the resource to verify: "
                                   "Name: platformskycraftswcsa; Location: Sweden Central")

    def test_an_expected_result_ending_in_a_colon_with_no_list_keeps_its_text(self) -> None:
        items, expected = self.step(
            "### Step 9.9.1: Create\n"
            "\n"
            "**Expected Result**: Rows appear in the workspace:\n"
            "\n"
            "Then continue:\n"
            "\n"
            "1. Click **Next**\n")
        self.assertEqual(items, [{"kind": "action", "labels": ["Next"], "line": 7}])
        self.assertEqual(expected, "Rows appear in the workspace:")

    def test_the_checks_follow_an_expected_result_ending_in_a_full_stop_after_a_space(self) -> None:
        items, expected = self.step(
            "### Step 9.9.1: Verify\n"
            "\n"
            "1. Click **Overview**\n"
            "2. Verify:\n"
            "   - Status: **Succeeded**\n"
            "\n"
            "**Expected Result**: Bastion is operational.\n")
        self.assertEqual(items, [{"kind": "action", "labels": ["Overview"], "line": 3}])
        self.assertEqual(expected, "Bastion is operational. Status: Succeeded")

    def test_checks_join_a_text_after_a_space_or_without_closing_punctuation_after_a_semicolon(self) -> None:
        for text, joined in (("Bastion is operational.", "Bastion is operational. A; B"),
                             ("Shows!", "Shows! A; B"), ("Is it running?", "Is it running? A; B"),
                             ("Two files created:", "Two files created: A; B"),
                             ("Bastion is operational", "Bastion is operational; A; B"),
                             ("`skycraft-vm` is listed", "`skycraft-vm` is listed; A; B"),
                             ("", "A; B"), (None, "A; B")):
            with self.subTest(text=text):
                self.assertEqual(parse.join_checks(text, ["A", "B"]), joined)
        self.assertEqual(parse.join_checks("Bastion is operational.", []), "Bastion is operational.")
        self.assertIsNone(parse.join_checks(None, []))

    def test_a_verify_list_ends_at_the_next_numbered_item_even_after_a_blank_line(self) -> None:
        items, expected = self.step(
            "### Step 9.9.1: Verify\n"
            "\n"
            "3. Verify:\n"
            "\n"
            "   - Virtual network links: 3\n"
            "\n"
            "   - Record sets: **2**\n"
            "\n"
            "4. Click **Record sets**\n"
            "5. Name: **dev-db**\n")
        self.assertEqual(items, [{"kind": "action", "labels": ["Record sets"], "line": 9},
                                 {"kind": "field", "label": "Name", "value": "dev-db", "line": 10}])
        self.assertEqual(expected, "Virtual network links: 3; Record sets: 2")

    def test_a_verify_line_that_is_not_a_list_item_takes_the_list_right_after_it(self) -> None:
        items, expected = self.step(
            "### Step 9.9.1: Verify\n"
            "\n"
            "Verify:\n"
            "\n"
            "- Status: **Succeeded**\n"
            "\n"
            "1. Click **Next**\n")
        self.assertEqual(items, [{"kind": "action", "labels": ["Next"], "line": 7}])
        self.assertEqual(expected, "Status: Succeeded")

    def test_verify_with_more_after_the_colon_or_inside_a_word_is_no_check_list(self) -> None:
        for intro in ("Verify: **Public IP** → **SKU** shows Standard", "Reverify:", "Step2verify:",
                      "pre_verify:"):
            with self.subTest(intro=intro):
                items, expected = self.step(
                    "### Step 9.9.1: Verify\n\n"
                    f"1. {intro}\n"
                    "   - Status: **Succeeded**\n")
                self.assertIn({"kind": "field", "label": "Status", "value": "Succeeded", "line": 4}, items)
                self.assertIsNone(expected)

    def test_a_list_after_a_nested_verify_line_ends_at_the_next_numbered_step(self) -> None:
        items, expected = self.step(
            "### Step 9.9.1: X\n"
            "\n"
            "1. Open **A**\n"
            "\n"
            "   Then verify:\n"
            "   - a: **x**\n"
            "   - b\n"
            "2. Click **Next**\n")
        self.assertEqual(items, [{"kind": "action", "labels": ["A"], "line": 3},
                                 {"kind": "action", "labels": ["Next"], "line": 8}])
        self.assertEqual(expected, "a: x; b")

    def test_a_list_after_a_nested_expected_result_ends_at_the_next_numbered_step(self) -> None:
        items, expected = self.step(
            "### Step 9.9.1: X\n"
            "\n"
            "1. Click **Go**\n"
            "   - **Expected Result**: You see:\n"
            "     - a\n"
            "2. Click **Next**\n")
        self.assertEqual(items, [{"kind": "action", "labels": ["Go"], "line": 3},
                                 {"kind": "action", "labels": ["Next"], "line": 6}])
        self.assertEqual(expected, "You see: a")

    def test_a_list_ends_where_the_other_marker_kind_starts_at_its_indent(self) -> None:
        items, expected = self.step(
            "### Step 9.9.1: X\n"
            "\n"
            "**Expected Result**:\n"
            "\n"
            "- a\n"
            "  1. nested, still part of the result\n"
            "1. Click **Next**\n")
        self.assertEqual(items, [{"kind": "action", "labels": ["Next"], "line": 7}])
        self.assertEqual(expected, "a; nested, still part of the result")

    def test_an_expected_result_ends_a_check_list_and_is_read_as_usual(self) -> None:
        for intro in ("1. Verify:", "Verify:"):
            with self.subTest(intro=intro):
                items, expected = self.step(
                    "### Step 9.9.1: X\n"
                    "\n"
                    f"{intro}\n"
                    "   - Status: **Succeeded**\n"
                    "   - **Expected Result**: Bastion is up.\n"
                    "2. Click **Next**\n")
                self.assertEqual(items, [{"kind": "action", "labels": ["Next"], "line": 6}])
                self.assertEqual(expected, "Bastion is up. Status: Succeeded")

    def test_tab_indented_check_items_are_deeper_than_their_verify_item(self) -> None:
        items, expected = self.step(
            "### Step 9.9.1: X\n"
            "\n"
            "1. Verify:\n"
            "\t- Status: **Succeeded**\n"
            "\t- Subnet: `AzureBastionSubnet`\n"
            "2. Click **Next**\n")
        self.assertEqual(items, [{"kind": "action", "labels": ["Next"], "line": 6}])
        self.assertEqual(expected, "Status: Succeeded; Subnet: AzureBastionSubnet")

    def test_a_commented_out_line_inside_a_check_list_neither_ends_nor_joins_it(self) -> None:
        for intro, prefix in (("1. Verify:", ""), ("**Expected Result**: You see:", "You see: ")):
            with self.subTest(intro=intro):
                items, expected = self.step(
                    "### Step 9.9.1: X\n"
                    "\n"
                    f"{intro}\n"
                    "   - Status: **Succeeded**\n"
                    "   <!-- - Old field: **value** -->\n"
                    "   <!--\n"
                    "   - Another: **value**\n"
                    "   -->\n"
                    "   - Subnet: `AzureBastionSubnet`\n"
                    "2. Click **Next**\n")
                self.assertEqual(items, [{"kind": "action", "labels": ["Next"], "line": 10}])
                self.assertEqual(expected, prefix + "Status: Succeeded; Subnet: AzureBastionSubnet")

    def test_a_verify_list_in_another_option_is_dropped_with_it(self) -> None:
        items, expected = self.step(
            "### Step 9.9.1: Verify\n"
            "\n"
            "#### Option 1: Portal\n"
            "\n"
            "1. Click **Overview**\n"
            "\n"
            "#### Option 2: CLI\n"
            "\n"
            "1. Verify:\n"
            "   - Status: **Succeeded**\n")
        self.assertEqual(items, [{"kind": "action", "labels": ["Overview"], "line": 5}])
        self.assertIsNone(expected)


if __name__ == "__main__":
    unittest.main()

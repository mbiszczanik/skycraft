"""Unit tests for parse.py's reading of one list item (issue #189): which searches are the
Portal's global search and which are a blade's own search box. The full guides and the other
parser rules are covered by tests/Guide-Drift-Parser.Tests.ps1. Run from the repository root:

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


if __name__ == "__main__":
    unittest.main()

"""Headless Chromium tests of the runner's in-page JavaScript and of the Playwright behaviours its
lookups rely on (#342).

test_runner.py's fakes answer BLADE_OF_JS, NEXT_CONTROL_JS, LIST_SCROLL_JS and FIELD_KIND_JS as
their author assumed the browser would. Here each script runs in a real page, built with
page.set_content in the shapes the Lab 1.3 runs saw: two blades side by side and a region nested
in one, a text label before an unnamed combo box, a list that scrolls, a policy picker's grid with
a header row and a 'Select' radio per row. The Playwright behaviours the lookups depend on are
pinned too: get_by_text(exact) returns the innermost element, a row's get_by_role("gridcell",
name=..., exact=True) matches the whole name only, and an attribute set on a Locator stays on it.
Every name is a neutral one: no tenant, subscription or account.

The whole module is skipped when Playwright cannot be imported or Chromium does not launch. The CI
runner installs neither, so a CI run is no evidence for these tests: run them locally and quote
the count and the exit code. From tools/guide-drift:

    python -B -m unittest tests.test_browser_js -v
"""
import sys
import unittest
from pathlib import Path
from types import SimpleNamespace

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

try:
    from playwright.sync_api import sync_playwright
    import run  # noqa: E402 - imports Playwright itself
except ImportError as error:        # CI: no Playwright
    IMPORT_ERROR: ImportError | None = error
else:
    IMPORT_ERROR = None

PLAYWRIGHT = None
BROWSER = None
VIEWPORT = {"width": 1440, "height": 900}      # the runner's window


def setUpModule() -> None:
    global PLAYWRIGHT, BROWSER
    if IMPORT_ERROR is not None:
        raise unittest.SkipTest(f"Playwright cannot be imported: {IMPORT_ERROR}")
    if not callable(sync_playwright):       # test_runner.py's stub, loaded first where Playwright is missing
        raise unittest.SkipTest("Playwright is not installed (only test_runner.py's stub is loaded)")
    try:
        PLAYWRIGHT = sync_playwright().start()
        BROWSER = PLAYWRIGHT.chromium.launch()
    except Exception as error:      # noqa: BLE001 - no Chromium, or it cannot start here
        if PLAYWRIGHT is not None:
            PLAYWRIGHT.stop()
        raise unittest.SkipTest(f"Chromium does not launch: {error}")


def tearDownModule() -> None:
    if BROWSER is not None:
        BROWSER.close()
    if PLAYWRIGHT is not None:
        PLAYWRIGHT.stop()


class BrowserTestCase(unittest.TestCase):
    """One page at the runner's window size per class, its content replaced by every test's own
    (show): a new page costs seconds on Windows."""

    @classmethod
    def setUpClass(cls) -> None:
        context = BROWSER.new_context(viewport=VIEWPORT)
        cls.addClassCleanup(context.close)
        cls.page = context.new_page()

    def show(self, body: str) -> None:
        self.page.set_content(f"<!doctype html><html><head><style>{self.STYLE}</style></head>"
                              f"<body>{body}</body></html>")

    # Blades are side by side, as the Portal parks earlier ones to the left of the newest.
    STYLE = ("[role=region].blade { position: absolute; top: 0; width: 600px; height: 800px; } "
             "[role=combobox], input { display: block; height: 24px; width: 200px; }")

    @staticmethod
    def id_of(element) -> str:
        return element.evaluate("e => e.id")


class BladeTests(BrowserTestCase):
    """BLADE_OF_JS and newest_blade: a resource group's pane open beside the list it came from
    (run B, 1.3.11), both menus showing 'Tags'."""

    LIST = "Resource Manager | Resource groups [tenantname]"
    PANE = "prod-skycraft-swc-rg Resource group"

    def two_blades(self, pane_extra: str = "", list_extra: str = "") -> None:
        self.show(f'<div role=region class=blade aria-label="{self.LIST}" style="left: 0">'
                  f'<a href="#" id=list-tags>Tags</a>{list_extra}</div>'
                  f'<div role=region class=blade aria-label="{self.PANE}" style="left: 700px">'
                  f'<a href="#" id=pane-tags>Tags</a>{pane_extra}</div>'
                  '<a href="#" id=outside>Outside</a>')

    def test_blade_of_reads_the_closest_region_s_label_and_left_edge(self) -> None:
        self.two_blades()
        self.assertEqual(self.page.locator("#pane-tags").evaluate(run.BLADE_OF_JS), [self.PANE, 700])
        self.assertEqual(self.page.locator("#list-tags").evaluate(run.BLADE_OF_JS), [self.LIST, 0])
        self.assertIsNone(self.page.locator("#outside").evaluate(run.BLADE_OF_JS))

    def test_tags_in_both_blades_is_the_pane_s(self) -> None:
        self.two_blades()
        self.assertEqual(self.id_of(run.find_in_roles(self.page, "Tags", run.ACTION_ROLES)), "pane-tags")

    def test_a_region_nested_in_a_blade_is_the_closest_one(self) -> None:
        self.two_blades(pane_extra='<div role=region aria-label="Menu" style="margin-left: 200px">'
                                   '<a href="#" id=menu-locks>Locks</a></div>',
                        list_extra='<a href="#" id=list-locks>Locks</a>')
        blade = self.page.locator("#menu-locks").evaluate(run.BLADE_OF_JS)
        self.assertEqual(blade[0], "Menu")
        self.assertGreaterEqual(blade[1], 900)
        self.assertEqual(self.id_of(run.find_in_roles(self.page, "Locks", run.ACTION_ROLES)), "menu-locks")

    def test_two_matches_in_the_newest_blade_are_ambiguous(self) -> None:
        self.two_blades(pane_extra='<a href="#" id=pane-tags-2>Tags</a>')
        found = run.visible_across_frames(self.page, lambda f: f.get_by_role("link", name="Tags", exact=True))
        self.assertEqual(len(found), 3)
        with self.assertRaises(run.Ambiguous):
            run.newest_blade(found)

    def test_the_newest_blade_s_refresh_menu_item_wins_over_an_older_blade_s_button(self) -> None:
        # Runner.refresh_view on the real page: a button in the list, a menu item in the pane.
        self.two_blades(list_extra="<button onclick=\"document.body.dataset.refreshed = 'list'\">Refresh</button>",
                        pane_extra="<div role=menuitem tabindex=0 "
                                   "onclick=\"document.body.dataset.refreshed = 'pane'\">Refresh</div>")
        run.Runner.refresh_view(SimpleNamespace(page=self.page))
        self.assertEqual(self.page.evaluate("document.body.dataset.refreshed"), "pane")

    def portal_blades(self) -> None:
        # The Portal's own shape (run 20261017-003656): a blade is a <section class=fxs-blade>
        # labelled by its title and subtitle, with no role attribute.
        self.show('<section class=fxs-blade aria-labelledby="l1 l2" style="position: absolute; left: 0; width: 600px">'
                  '<h2 id=l1>Resource groups</h2><div id=l2>Resource Manager</div>'
                  '<a href="#" id=list-tags>Tags</a></section>'
                  '<section class=fxs-blade aria-labelledby="p1 p2" style="position: absolute; left: 700px; width: 600px">'
                  '<h2 id=p1>prod-skycraft-swc-rg</h2><div id=p2>Resource group</div>'
                  '<a href="#" id=pane-tags>Tags</a></section>')

    def test_a_portal_blade_is_a_section_named_by_its_labelling_elements(self) -> None:
        self.portal_blades()
        self.assertEqual(self.page.locator("#pane-tags").evaluate(run.BLADE_OF_JS),
                         ["prod-skycraft-swc-rg Resource group", 700])
        self.assertEqual(self.id_of(run.find_in_roles(self.page, "Tags", run.ACTION_ROLES)), "pane-tags")

    def test_an_element_in_a_frame_outside_any_region_is_in_the_blade_of_its_iframe(self) -> None:
        # Cost analysis renders in an iframe of the subscription's blade, beside the Subscriptions
        # list, and both show 'Add filter' (run 20261017-095926).
        self.show('<section aria-label="Subscriptions" style="position: absolute; left: 0; width: 600px">'
                  '<button id=list-filter>Add filter</button></section>'
                  '<section aria-label="Cost analysis" style="position: absolute; left: 700px; width: 700px">'
                  '<iframe style="width: 650px; height: 300px" '
                  'srcdoc="<main><button id=cost-filter>Add filter</button></main>"></iframe></section>')
        frame = self.page.frames[1]
        frame.wait_for_selector("#cost-filter")
        self.assertEqual(run.blade_of(frame.locator("#cost-filter")), ["Cost analysis", 700])
        found = run.visible_across_frames(self.page, lambda f: f.get_by_role("button", name="Add filter", exact=True))
        self.assertEqual(len(found), 2)
        self.assertEqual(self.id_of(run.newest_blade(found)), "cost-filter")

    def test_a_section_named_by_aria_label_is_a_blade_and_an_unnamed_one_is_none(self) -> None:
        self.show('<section aria-label="Menu" style="margin-left: 50px"><a href="#" id=named>Tags</a></section>'
                  '<section><a href="#" id=unnamed>Tags</a></section>')
        self.assertEqual(self.page.locator("#named").evaluate(run.BLADE_OF_JS), ["Menu", 58])
        self.assertIsNone(self.page.locator("#unnamed").evaluate(run.BLADE_OF_JS))

class TextLabelTests(BrowserTestCase):
    """NEXT_CONTROL_JS through find_by_text_label: the Advisor alert's unnamed combo boxes under the
    texts 'Category', 'Sub-category' and 'Impact level' (1.3.7)."""

    ADVISOR = ('<div>Category</div><div role=combobox tabindex=0 id=category></div>'
               '<div>Sub-category</div><div role=combobox tabindex=0 id=sub-category></div>'
               '<div>Impact level</div><div role=combobox tabindex=0 id=impact></div>')

    def test_each_text_gives_the_unnamed_combo_box_after_it(self) -> None:
        self.show(self.ADVISOR)
        for label, control in (("Category", "category"), ("Sub-category", "sub-category"),
                               ("Impact level", "impact")):
            with self.subTest(label=label):
                self.assertEqual(self.id_of(run.find_by_text_label(self.page, label)), control)
                self.assertEqual(self.id_of(run.find_by_text_label(self.page, label, opens_list=True)), control)

    def test_text_with_other_text_before_the_control_is_no_label(self) -> None:
        self.show("<div>Category</div><div>Pick one of these</div><input id=category>")
        self.assertIsNone(run.find_by_text_label(self.page, "Category"))

    def test_a_hidden_control_is_passed_over(self) -> None:
        self.show('<div>Name</div><input type=hidden><input id=gone style="display: none"><input id=name>')
        self.assertEqual(self.id_of(run.find_by_text_label(self.page, "Name")), "name")

    def test_an_interactive_text_is_no_label(self) -> None:
        self.show('<a href="#">Category</a><input id=category>')
        self.assertIsNone(run.find_by_text_label(self.page, "Category"))

    def test_a_css_only_required_marker_leaves_the_text_whole(self) -> None:
        self.show('<style>.required::after { content: " *"; }</style>'
                  '<div class=required>Impact level</div><div role=combobox tabindex=0 id=impact></div>')
        self.assertEqual(self.id_of(run.find_by_text_label(self.page, "Impact level")), "impact")

    def test_a_label_wrapping_its_control_is_found_as_a_field_by_its_name(self) -> None:
        self.show("<label>Name <input id=name></label>")
        self.assertEqual(self.id_of(run.find_exact(self.page, "Name", field=True)), "name")

    def test_the_same_text_in_two_blades_gives_the_newest_blade_s_control(self) -> None:
        self.show('<div role=region class=blade aria-label="Older" style="left: 0">'
                  '<div>Category</div><div role=combobox tabindex=0 id=older></div></div>'
                  '<div role=region class=blade aria-label="Newest" style="left: 700px">'
                  '<div>Category</div><div role=combobox tabindex=0 id=newest></div></div>')
        self.assertEqual(self.id_of(run.find_by_text_label(self.page, "Category")), "newest")


class ListScrollTests(BrowserTestCase):
    """LIST_SCROLL_JS and scroll_list: a Region list that scrolls (1.3.6), sixty options of 20 px
    in a list 100 px high."""

    def region_list(self, overflow: str = "auto") -> None:
        options = "".join(f'<div role=option style="height: 20px">(Europe) Region {n}</div>' for n in range(60))
        self.show('<div role=combobox tabindex=0 aria-controls=regions aria-expanded=true id=region>Region</div>'
                  f'<div role=listbox id=regions style="height: 100px; overflow-y: {overflow}">{options}</div>')

    def scroll_top(self) -> int:
        return self.page.locator("#regions").evaluate("e => e.scrollTop")

    def test_the_list_scrolls_a_page_at_a_time_and_says_when_it_has_ended(self) -> None:
        self.region_list()
        moves = 0
        while self.page.locator("#regions").evaluate(run.LIST_SCROLL_JS):
            moves += 1
            self.assertEqual(self.scroll_top(), min(100 * moves, 60 * 20 - 100))
            self.assertLess(moves, 20)
        self.assertEqual((moves, self.scroll_top()), (11, 60 * 20 - 100))

    def test_from_an_option_its_nearest_scrolling_ancestor_scrolls(self) -> None:
        self.region_list()
        self.assertTrue(self.page.get_by_role("option").first.evaluate(run.LIST_SCROLL_JS))
        self.assertEqual(self.scroll_top(), 100)

    def test_a_list_that_does_not_scroll_answers_false(self) -> None:
        self.region_list(overflow="visible")
        self.assertFalse(self.page.locator("#regions").evaluate(run.LIST_SCROLL_JS))

    def test_scroll_list_scrolls_the_list_the_combo_box_names(self) -> None:
        self.region_list()
        self.assertTrue(run.scroll_list(self.page, self.page.locator("#region")))
        self.assertEqual(self.scroll_top(), 100)


class PickerRowTests(BrowserTestCase):
    """find_row_control on a policy picker's grid (1.3.5, 1.3.9): a header row, then rows of a
    'Select' radio and the policy's name, version, category and type."""

    ROWS = ("Allowed locations", "Azure Cosmos DB allowed locations", "Allowed locations for resource groups")

    def picker(self, rows=ROWS) -> None:
        header = ('<div role=row><div role=columnheader>Select</div><div role=columnheader>Name</div>'
                  '<div role=columnheader>Version</div></div>')
        body = "".join(f'<div role=row id=row-{n}><div role=gridcell><input type=radio name=pick aria-label=Select>'
                       f'</div><div role=gridcell>{name}</div><div role=gridcell>1.1.0</div>'
                       '<div role=gridcell>General</div><div role=gridcell>BuiltIn</div></div>'
                       for n, name in enumerate(rows))
        self.show(f"<div role=grid>{header}{body}</div>")

    def test_the_row_named_exactly_gives_its_select_radio_marked_for_act_on_label(self) -> None:
        self.picker()
        control = run.find_row_control(self.page, "Allowed locations")
        self.assertEqual(control.evaluate("e => e.closest('[role=row]').id"), "row-0")
        self.assertEqual(control.evaluate("e => e.type"), "radio")
        self.assertTrue(getattr(control, run.ROW_CONTROL_MARK, False))

    def test_the_header_row_is_no_row(self) -> None:
        self.picker()
        self.assertIsNone(run.find_row_control(self.page, "Name"))

    def test_two_rows_of_that_exact_name_are_ambiguous(self) -> None:
        self.picker(self.ROWS + ("Allowed locations",))
        with self.assertRaises(run.Ambiguous):
            run.find_row_control(self.page, "Allowed locations")

    def test_a_row_s_gridcell_matches_the_whole_name_only(self) -> None:
        self.picker()
        for n, count in ((0, 1), (1, 0), (2, 0)):
            with self.subTest(row=self.ROWS[n]):
                row = self.page.locator(f"#row-{n}")
                self.assertEqual(row.get_by_role("gridcell", name="Allowed locations", exact=True).count(), count)


class PlaywrightBehaviourTests(BrowserTestCase):
    """What the lookups take for granted about Playwright (1.63)."""

    def test_get_by_text_exact_returns_the_innermost_element(self) -> None:
        self.show('<div id=outer><div id=middle><span id=inner>Category</span></div></div>'
                  '<a href="#" id=users>Users<span> (preview)</span></a>')
        found = self.page.get_by_text("Category", exact=True)
        self.assertEqual((found.count(), self.id_of(found)), (1, "inner"))
        # Child elements count: 'Users (preview)' is no 'Users' (interactive_text).
        self.assertEqual(self.page.get_by_text("Users", exact=True).count(), 0)

    def test_an_attribute_set_on_a_locator_stays_on_that_locator(self) -> None:
        self.show("<input type=radio id=select aria-label=Select>")
        control = self.page.get_by_role("radio", name="Select")
        setattr(control, run.ROW_CONTROL_MARK, True)
        self.assertTrue(getattr(control, run.ROW_CONTROL_MARK, False))
        self.assertFalse(getattr(self.page.get_by_role("radio", name="Select"), run.ROW_CONTROL_MARK, False))

    def test_opens_a_list_reads_a_combo_box_and_a_listbox_popup(self) -> None:
        self.show('<div role=combobox tabindex=0 id=combo></div>'
                  '<button aria-haspopup=listbox id=dropdown>Pick</button>'
                  '<button id=plain>Save</button><input id=text>')
        for element, opens in (("combo", True), ("dropdown", True), ("plain", False), ("text", False)):
            with self.subTest(element=element):
                self.assertEqual(run.opens_a_list(self.page.locator(f"#{element}")), opens)

class ZeroSizeComboBoxTests(BrowserTestCase):
    """ZERO_SIZE_COMBOBOX_JS, visible_in and click_target on Cost analysis' VIEW list (1.3.18, run
    20261017-003656): an ng-select whose input, the combo box, has no width inside a visible
    container that opens the list on mousedown."""

    def view_list(self, extra: str = "", container_style: str = "", proxy_style: str = "") -> None:
        self.show(f'<div class="ng-select-container" id=container style="width: 150px; height: 44px; {container_style}" '
                  "onmousedown=\"document.getElementById('view').setAttribute('aria-expanded', 'true')\">"
                  '<div class="ng-value-container"><span>VIEW</span><div>AccumulatedCosts</div></div>'
                  f'<div class="ng-input" id=proxy style="width: 150px; height: 16px; {proxy_style}">'
                  '<input role=combobox aria-label=VIEW aria-expanded=false readonly id=view '
                  f'style="width: 0; height: 16px; padding: 0; border: 0">{extra}</div></div>')

    def test_the_combo_box_counts_as_visible_and_is_clicked_at_its_container(self) -> None:
        self.view_list()
        view = self.page.get_by_role("combobox", name="VIEW", exact=True)
        self.assertFalse(view.is_visible())         # what Playwright says of a zero-width element
        self.assertEqual(len(run.visible_in(view, VIEWPORT)), 1)
        self.assertEqual(self.id_of(run.find_exact(self.page, "VIEW")), "view")
        target = run.click_target(view)
        self.assertEqual(self.id_of(target), "proxy")
        target.click(timeout=2000)
        self.assertEqual(view.get_attribute("aria-expanded"), "true")

    def test_a_transparent_stand_in_counts_as_the_portal_s_does(self) -> None:
        # ng-select's '.ng-input' has opacity 0 in the Portal (run 20261017-095926); a click
        # still reaches it and opens the list.
        self.view_list(proxy_style="opacity: 0")
        view = self.page.get_by_role("combobox", name="VIEW", exact=True)
        self.assertEqual(len(run.visible_in(view, VIEWPORT)), 1)
        run.click_target(view).click(timeout=2000)
        self.assertEqual(view.get_attribute("aria-expanded"), "true")

    def test_an_ancestor_holding_another_control_gives_no_stand_in(self) -> None:
        self.view_list("<button>Clear</button>")
        view = self.page.get_by_role("combobox", name="VIEW", exact=True)
        self.assertEqual(run.visible_in(view, VIEWPORT), [])
        self.assertIsNone(view.evaluate(run.ZERO_SIZE_COMBOBOX_JS, None))

    def test_a_combo_box_with_a_box_of_its_own_is_clicked_itself(self) -> None:
        self.show("<div role=combobox tabindex=0 aria-label=Region id=region>East US</div>")
        region = self.page.get_by_role("combobox", name="Region")
        self.assertIsNone(region.evaluate(run.ZERO_SIZE_COMBOBOX_JS, "1"))
        self.assertEqual(self.id_of(run.click_target(region)), "region")



class TagGridTests(BrowserTestCase):
    """fill_tag on the Portal's Tags grid (1.3.1, run 20261017-123546): the tags a group has as rows
    of plain cells, name, ':' and value, then an empty row with combo boxes named 'Name' and
    'Value'; Lab 1.2's Bicep path made the group with Lab 1.3's tags."""

    def grid(self, rows) -> None:
        listed = "".join(f'<div role=row><div role=gridcell>{name}</div><div role=gridcell>:</div>'
                         f'<div role=gridcell>{value}</div><div role=gridcell><button>Delete</button></div></div>'
                         for name, value in rows)
        self.show(f'<div role=grid aria-label="Add or edit tags grid">{listed}'
                  '<div role=row><div role=gridcell><input role=combobox aria-label=Name id=new-name></div>'
                  '<div role=gridcell>:</div>'
                  '<div role=gridcell><input role=combobox aria-label=Value id=new-value></div></div></div>')

    def typed(self) -> tuple:
        return (self.page.locator("#new-name").input_value(), self.page.locator("#new-value").input_value())

    def test_a_listed_tag_with_its_value_is_already_set_and_nothing_is_typed(self) -> None:
        self.grid([("CostCenter", "MSDN"), ("Owner", "SkyCraft-Admins")])
        self.assertEqual(run.fill_tag(self.page, "owner", "SkyCraft-Admins"), run.ALREADY_SET)
        self.assertEqual(self.typed(), ("", ""))

    def test_a_listed_tag_with_another_value_is_reported_not_typed_again(self) -> None:
        self.grid([("Environment", "Production")])
        with self.assertRaisesRegex(LookupError, "listed with the value 'Production', not 'Development'"):
            run.fill_tag(self.page, "Environment", "Development")
        self.assertEqual(self.typed(), ("", ""))

    def test_a_new_tag_goes_into_the_empty_row(self) -> None:
        self.grid([("Environment", "Development")])
        self.assertIsNone(run.fill_tag(self.page, "Project", "SkyCraft"))
        self.assertEqual(self.typed(), ("Project", "SkyCraft"))


if __name__ == "__main__":
    unittest.main()

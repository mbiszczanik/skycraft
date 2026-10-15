# Guide drift: operate the Portal controls Lab 1.3 stopped at (#342, runner side of #296)

Branch `feat/342-guide-drift-portal-controls`, stacked on `feat/329-lab13-recording` (PR #341). The evidence is the two supervised runs, kept outside the repository next to the worktree's parent: `drift13/logs/20261014-171319` (run A) and `drift13b/logs/20261015-092629` (run B). Each holds `summary.md`, `results.jsonl`, `steps.json`, `blade-*.aria.txt`, `search-*.aria.txt`, screenshots, and next to the log folder an `answers.txt` and `run.log`. Done means: a replay of Lab 1.3 runs 1.3.1-1.3.22 with exit 0, no c/s answer and no proposed edit, and every control in #342's table has an offline test.

## Global constraints

- English only, in code, docs, tests and commits.
- Existing files have CRLF in the working tree (`git ls-files --eol`). Edit them with the Edit tool or Python binary I/O (`Path.read_bytes()` / `write_bytes()`). Never use sed/awk in Git Bash, which strips CR. A new file follows its neighbours' line endings.
- No identifying data in code, fixtures, tests or commits: no e-mail address, GUID, tenant or organisation name, subscription name or id.
  - The evidence folders hold a corporate tenant's data. Their outlines carry the subscription's display name in grid rows and region titles, an organisation name in the Compliance grid, and the account in the top bar.
  - A fixture is a hand-trimmed excerpt with only the lines its test needs. Use `<id>`, `[tenantname]`, `[tenantdomain]`, `[yoursubscription]` (from Task 11 on) or neutral names ("Example Subscription").
  - The pre-commit/publish hook is a backstop, not the check: read every copied line.
- Every behaviour change is documented where its rule lives: run.py's module docstring and the docstring of the function changed; `tools/Invoke-GuideDrift.ps1` comment help for anything a run's user sees (new files in the run folder, new recording keys, new arguments); parse.py's docstring for parser rules; recording.py's header for new helpers.
- Offline only: no Azure, Portal, az or Az PowerShell in Tasks 1-12. Tests use the fake `Screen`/`ScreenNode`/`FakePage` of `tools/guide-drift/tests/test_runner.py`, extended where a task needs it.
- Each task commits its own work from the worktree, with a conventional message (`feat(guide-drift): ...`, `fix(...)`, `chore(...)`, `docs(...)`). `(#342)` or `(#296)` may be referenced. Never put a closing keyword (fixes/closes/resolves) next to an issue number. Never use `--no-verify`. No Co-Authored-By line.
- Before each commit, run both suites:
  - `cd tools/guide-drift && python -B -m unittest discover -s tests`
  - `pwsh -NoProfile -Command "Invoke-Pester -Path tests/Guide-Drift-Parser.Tests.ps1,tests/Guide-Drift-Recording.Tests.ps1,tests/Guide-Drift-Python.Tests.ps1,tests/Guide-Step-Numbering.Tests.ps1 -Output Detailed"` (from the worktree root)

## Evidence map (which excerpt each test is cut from)

| Control (#342 table) | Step | Source | What the excerpt keeps |
|---|---|---|---|
| Two menus both show **Tags**; collapsed **Settings** / **Cost Management** of the pane | 1.3.1-1.3.3, 1.3.11-1.3.13, 1.3.17 | B `blade-1.3.11-421.aria.txt` | the two `region` lines (list: rename the title to `Resource Manager \| Resource groups [tenantname]`; pane: `prod-skycraft-swc-rg Resource group`), each region's `button "Expand all headers"` and `link "Tags"`, the pane's `button "Close content 'prod-skycraft-swc-rg'"`, `button "Toggle Settings"`, `button "Toggle Cost Management"`. Drop both grids: they hold the subscription name |
| Expand clicked while the menu loads | 1.3.15 (B) | B `blade-1.3.15-510.aria.txt` | `button "Expand all headers"`, `list "Loading..."`, `button "Toggle Monitoring"`; rename the region to `Cost Management: Example Subscription \| Overview` |
| Region option | 1.3.6 | no tree saved (`pick_option` keeps none); B `Step-1.3.6.png` shows a scrolling list with `(Europe) North Europe`, `(Europe) Sweden Central`, ... and no filter box | hand-made option names from the screenshot |
| Reset period option | 1.3.15 | B `blade-1.3.16-545.aria.txt` | `combobox "Reset period"`, `dialog`, `tree "List of options"`, `treeitem "Billing month"` ... `treeitem "Monthly"`, `treeitem "Quarterly"`, `treeitem "Annually"` |
| Picker row (`radio "Select"`), three rows | 1.3.5, 1.3.8, 1.3.9 | B `blade-1.3.5-188`, `blade-1.3.9-366` | the grid: header row, and rows `Select Allowed locations 1.1.0 General BuiltIn` (and the Cosmos DB and "for resource groups" rows), each `gridcell "Select"`, `radio "Select"`, `gridcell "<name>"` |
| Multi-select opened by visible label | 1.3.9 | B `blade-1.3.9-374` + run B's records | `tabpanel "Parameters"`, `searchbox "Search by parameter name"`, `combobox "Location"`; the text "Allowed locations" before it (the outline drops text: take it from the guide). The open list's shape was not saved: options `Sweden Central` / `North Europe` with `aria-selected`, per run B's record (`North Europe` found by exact name and clicked) |
| Unnamed combobox in an iframe | 1.3.7 | B `blade-1.3.7-283` + `Step-1.3.7.png` | `radiogroup "Configured by"`, three unnamed `combobox` lines; their visible labels "Category", "Sub-category", "Impact level" come from the screenshot |
| Radiogroup = label = container | 1.3.5 | B `blade-1.3.5-188` | `radiogroup "Policy enforcement"`, `radio "Default (enforcement)"`, `radio "Do not enforce"`, `radio "Enroll"`, plus a `label` and a `div` of the same name (from the run's error "label, div, radiogroup") |
| View that fills in later | 1.3.10 | A `blade-1.3.10-387` (grid present), B `blade-1.3.10-395` (content iframe empty) | grid rows `Require-Environment-Tag-RG`, `Enforce-Project-Tag`, `Restrict-Azure-Regions` with a `link` each. Drop every Scope cell (subscription name), the `ASC Default (subscription: <id>)` row and the organisation-scoped row |
| Step without a label: subscription; tag filter | 1.3.18 | B `blade-1.3.18-597` | `region "Subscriptions [tenantname] ([tenantdomain])"`, a `row` with `gridcell`/`link "Example Subscription"` (renamed). No tree of the filter pill exists (Task 13) |
| Search result with category | 1.3.1, 1.3.4, 1.3.6, 1.3.11, 1.3.17, 1.3.22 | B `search-1.3.1.aria.txt`, A `search-1.3.22.aria.txt` | `group "Services"`: `option "Resource groups Resource Manager"` (strong + text), `option "Subscriptions Keywords: resource groups"`, `option "Resource Manager Includes: Resource groups"`; `group "Marketplace"`: `option "Resource group"` |
| Global search without results list | 1.3.22 (B) | B `search-1.3.22.aria.txt` | the top bar's `combobox "Search resources, services, and docs (G+/)"` and the closing text `... 0 results found Searching ...`. Never the `Account menu` line |
| Bold in Expected View / conceptual steps | 1.3.10, 1.3.14, 1.3.22 | the guide | guide-shaped markdown in test_parse.py |

## Where #342 is wrong or asks for more than is needed

- **#296 is mostly done.** The parser side (`checked` / `unchecked` / `stateOnly`) and `set_state` for check boxes, radios and switches shipped in #316 (e9b5411), as run.py's docstring describes. The 1.3.9 case is something else: the list's entries are `option` elements whose state is `aria-selected`. `toggle_kind` returns None for them, so `act_on_label` clicked an already selected North Europe. Task 1 covers exactly that.
- **"A group heading removed" is not needed.** Reset period's options are `treeitem "Monthly"` etc. inside `tree "List of options"`; the heading ("Calendar months") is a separate text line. The miss was the role: `find_option` looks only for `option`. Region-prefix matching ("(Europe) ") stays.
- **"Under X: open that collapsed group" needs no parser change.** The parser already drops the place, and the runner opens collapsed groups with "Expand all headers". It failed because two such buttons were on screen (list menu and pane), so `unique_visible` raised Ambiguous, which `expand_menu_groups` swallowed; and in 1.3.15 of run B the click landed while the menu read `list "Loading..."`. Task 2 fixes the button choice and the retry.
- **1.3.22's "Tenant Root Group"** is in a numbered item ("3. You'll see the **Tenant Root Group**"); neither parser rule reaches it. The fix is the guide's wording (an Expected Result) plus a recorded result text (Task 10).
- **An Expected View list is dropped, not joined to the Expected Result.** Joining it would make every replay ask once for a text to look for, and "likely <100% initially" is no text on screen.
- **The Compliance wait is opt-in per label (recording key, Task 9).** A generic wait-and-reload for every missing label would cost minutes on every real drift.
- **1.3.18's tag filter:** no run saved a tree of Cost analysis' filter pill, so its key and value labels cannot be known offline. Task 13 (controller, live) captures them; Task 11 does the offline part: the subscription token and item 2.
- **Out of scope:** #236 beyond 1.3.18 (built-in placeholders for the ~27 Subscription fields of other labs).
- **1.3.6 Region:** neither run saved the open list. Task 6 adds prefix matching, a filter box, a bounded scroll for a virtualised list, and a `list-<step>-<line>.aria.txt` diagnostic. The first replay confirms the shape.

## Tasks

### Task 1: (a) #296, an option of a multi-select list is set, never toggled (1.3.9 North Europe)

- [ ] **Files:** `tools/guide-drift/run.py`, `tools/guide-drift/tests/test_runner.py`.
- [ ] **Behaviour:**
  - `toggle_kind` returns `"option"` for an element of role `option`, `treeitem`, `menuitemcheckbox` or `menuitemradio` that carries `aria-selected` or `aria-checked` (`"true"`/`"false"`).
  - An option with no state attribute but exactly one check box inside is set through that box (`"check"`).
  - A new `toggle_state(element, kind)` reads `is_checked()` for check/radio and the attribute for option. `set_state`, `state_within` and the "already set" test in `act_on_label` (currently `element.is_checked(...) == state`) use it.
  - An option is set by one click, then read back for `CHECK_TIMEOUT_MS`. It is unknown ("it was clicked to make it checked, but it is still unchecked") when the state does not change.
  - An option without a state attribute is clicked as before (`stateOnly` makes it unknown, as for any non-toggle).
- [ ] **Fake:** `ScreenNode` reads `aria-selected` from `attrs`; a new flag `selects_on_click` flips it on `click()`. `evaluate` answers the new state-reading script, if one is used.
- [ ] **Tests (class `StatedStateTests`):** `test_an_option_already_selected_is_already_set_and_not_clicked` (1.3.9 North Europe, state True); `test_an_unselected_option_is_clicked_once_and_read_back`; `test_an_option_whose_state_does_not_change_is_unknown`; `test_unchecked_clears_a_selected_option`; `test_an_option_holding_one_check_box_sets_the_box`; `test_an_option_without_a_state_attribute_is_clicked_as_before`.
- [ ] **Docs:** run.py docstring paragraph "A label of an action or a navigation that the guide gives a state ..." names options of a multi-select list.
- [ ] **Commit:** `feat(guide-drift): keep a selected option of a multi-select list as the guide states it (#296)`

### Task 2: (d) prefer the blade the step works on, and open its collapsed menu groups

- [ ] **Files:** `run.py`, `tests/test_runner.py`.
- [ ] **Newest-blade preference:** new `BLADE_OF_JS` (the closest `[role=region]` ancestor's `aria-label` and its left edge, or null); new `newest_blade(found)`: of several matches, when every one sits in a region and the regions differ, the one match in the right-most region (the newest blade; earlier ones are parked left), otherwise `Ambiguous` as today. `find_in_roles`' default `choose` and `expand_menu_groups`' button lookup use it.
- [ ] **Expand retry:** `expand_menu_groups` sets `self.expanded` only once that blade shows `Collapse all headers` within `SETTLE_MS`; otherwise it may click again on a later look, at most `EXPAND_TRIES = 3` per item (1.3.15: the menu still read `Loading...`).
- [ ] **Tests (class `NewestBladeTests`):** `test_tags_in_the_list_menu_and_the_open_pane_takes_the_pane` (1.3.1-1.3.3); `test_two_matches_in_the_newest_blade_stay_ambiguous`; `test_a_match_outside_any_region_keeps_it_ambiguous`; `test_locks_shows_after_the_panes_expand_all_headers` (1.3.11-1.3.13; the pane's button is clicked, the list's is not); `test_budgets_under_the_panes_cost_management_group` (1.3.17); `test_an_expand_click_while_the_menu_loads_is_tried_again` (1.3.15 run B); `test_expand_is_clicked_at_most_three_times`.
- [ ] **Docs:** run.py docstring ("only on one: several matches are reported as unknown rather than guessed" gains the newest-blade exception; the 'Expand all headers' sentence gains the retry). Invoke help: the "It never clicks one of several matching elements" sentence.
- [ ] **Commit:** `feat(guide-drift): act in the blade the step works on and open its collapsed menu groups (#342)`

### Task 3: (c) a picker row is selected by the cell that names it

- [ ] **Files:** `run.py`, `tests/test_runner.py`.
- [ ] **Behaviour:**
  - New `find_row_control(page, label)`: the visible rows (role `row`, not a header row) holding a `gridcell`/`cell` whose accessible name is exactly `label` (so "Allowed locations" never matches "Azure Cosmos DB allowed locations" or "Allowed locations for resource groups").
  - One row: its one radio, or else its one check box whose name is no decoration of the label. Two rows of that exact cell: `Ambiguous`. A row without one selection control: none.
  - Looked for by `find_exact` for an action, after `find_decorated`, from `SETTLE_MS` on.
  - It is the guide's element: a match, nothing recorded, no guide edit. A radio is selected with `select_radio`; a check box with `set_state(..., True)`, so selecting a row never clears it.
- [ ] **Tests:** `test_a_picker_row_is_selected_by_its_select_radio` (1.3.5, one row); `test_the_row_named_exactly_wins_among_three` (1.3.9); `test_two_rows_of_that_exact_name_are_ambiguous`; `test_a_row_already_selected_is_already_set`; `test_a_row_without_one_selection_control_is_not_found`; `test_the_header_row_is_no_row`.
- [ ] **Docs:** run.py docstring, next to the decorations paragraph.
- [ ] **Commit:** `feat(guide-drift): select a picker row by the cell that names it (#342)`

### Task 4: (e) a field found by the visible text label next to it

- [ ] **Files:** `run.py`, `tests/test_runner.py`.
- [ ] **Behaviour:**
  - New `NEXT_CONTROL_JS` and `find_by_text_label(page, label)`: non-interactive text whose whole text is `label`, and the first control after it in document order (`input`, `select`, `textarea`, roles `combobox`, `textbox`, `listbox`, `spinbutton`, `radiogroup`), with no other non-empty text between. It counts whether the control's accessible name is empty (Category) or differs ("Enter a unique name" for Name; "Location" for Allowed locations). The same label twice: `Ambiguous`.
  - `find_field` uses it after its labelled and role lookups, from `SETTLE_MS` on (as decorated names). `find_exact` for an action uses it only when the control opens a list (combobox, or `aria-haspopup` listbox); Task 7 uses this.
  - It is the guide's element: a match, nothing recorded, no edit. `find_form` / `editable` accept it, so 1.3.7 writes no wrong-blade record.
- [ ] **Fake:** `ScreenNode.next_control` (what `NEXT_CONTROL_JS` answers for a text node).
- [ ] **Tests:** `test_category_is_the_unnamed_combobox_after_its_text` (1.3.7: Category, Sub-category, Impact level); `test_name_is_the_textbox_named_by_its_placeholder` (1.3.15); `test_text_with_other_text_before_the_control_is_no_label`; `test_a_text_label_on_screen_twice_is_ambiguous`; `test_a_field_named_by_its_accessible_name_still_wins`; `test_a_form_whose_first_field_is_found_by_its_text_is_open` (no WRONG_BLADE record).
- [ ] **Docs:** run.py docstring (field lookup and the form check); Invoke help, "A STEP ON THE WRONG BLADE".
- [ ] **Commit:** `feat(guide-drift): find a field by the text label beside it (#342)`

### Task 5: (e) a radiogroup named like its label and its container

- [ ] **Files:** `run.py`, `tests/test_runner.py`.
- [ ] **Behaviour:** in `find_field`, when the labelled elements are containers only and exactly one has role `radiogroup` holding radios, it is the field; it wins over a `<label>` and a wrapper `div` of the same name (one way: a "group" tier in `one_field` after "value" and "dropdown"). `fill_field` then goes through `fill_parts`, and `pick_radio` selects the radio the value names.
- [ ] **Tests:** `test_policy_enforcement_label_div_and_radiogroup_take_the_radiogroup` ("Default (enforcement)" already selected: already set); `test_do_not_enforce_is_selected`; `test_two_radiogroups_of_the_name_stay_ambiguous`.
- [ ] **Docs:** run.py docstring, the `fill_parts` / radio paragraph.
- [ ] **Commit:** `feat(guide-drift): fill a radio group that shares its name with its label and container (#342)`

### Task 6: (b) a list option by its name, a filter box, a long list

- [ ] **Files:** `run.py`, `tests/test_runner.py`.
- [ ] **Behaviour:**
  - `find_option` looks for roles `option` and `treeitem`, inside the listbox, tree or dialog the combobox names, else on screen.
  - A name matches exactly, or else after removing a region prefix (`REGION_PREFIX = ^\([^()]+\)\s+`) from the option's name; several by that rule: `Ambiguous`. `pick_option`'s `shows()` accepts the field showing the prefixed name (already set).
  - Before looking: when the open popup holds one searchbox/textbox, or the combobox is an editable input, the value (prefix removed) is typed into it.
  - When the option is still missing and the list scrolls, it is scrolled a page at a time, at most `LIST_SCROLL_PAGES = 20` (`LIST_SCROLL_JS`), looking after each page.
  - `pick_option` / `fill_field` take an optional `diagnose`; on "option not found" the open list's snapshot is saved, scrubbed, as `list-<step>-<line>.aria.txt`.
- [ ] **Tests (class `ListOptionTests`):** `test_reset_period_monthly_is_a_treeitem_under_calendar_months` (1.3.15 / 1.3.17); `test_region_sweden_central_finds_the_europe_prefixed_option` (1.3.6); `test_a_field_showing_the_prefixed_name_is_already_set`; `test_two_options_after_removing_the_prefix_are_ambiguous`; `test_the_filter_box_is_typed_into_first`; `test_an_option_shown_only_after_scrolling_is_found`; `test_scrolling_stops_after_twenty_pages`; `test_a_missing_option_saves_the_list_tree_scrubbed`.
- [ ] **Docs:** run.py docstring ("A field is filled as its control takes a value" and the run-folder paragraph); Invoke help, "WHAT A RUN LEAVES BEHIND" (`list-*.aria.txt`).
- [ ] **Commit:** `feat(guide-drift): pick a list option under its region prefix, through a filter box or a long list (#342)`

### Task 7: (b) a multi-select list opened by its visible label (1.3.9; needs Tasks 1, 4, 6)

- [ ] **Files:** `run.py`, `tests/test_runner.py`.
- [ ] **Behaviour:** in `run_step`, when a label of an action or navigation item clicks a control that opens a list (Task 4's text-label combobox, or any combobox), `Runner.open_list` keeps it. The item's later labels are looked for as options of that list first (Task 6's rules and filter typing), else on screen as today; they are set to the item's stated state with Task 1's toggles, or clicked when the guide states none. At the item's end, a list still open is closed (Escape on the combobox), so the next tab click is not intercepted. Reset per item.
- [ ] **Tests:** `test_allowed_locations_opens_the_location_combobox_and_ticks_both_regions`; `test_north_europe_already_ticked_stays_ticked` (the 1.3.9 run B case, end to end); `test_sweden_central_appears_after_typing_in_the_filter_box`; `test_the_list_is_closed_after_the_item`; `test_a_label_not_in_the_list_is_looked_for_on_screen`.
- [ ] **Docs:** run.py docstring (a new paragraph on lists opened by a label).
- [ ] **Commit:** `feat(guide-drift): open a multi-select list by its label and tick the options the guide names (#342)`

### Task 8: (f) a search result with its category, and one retry of a search without results

- [ ] **Files:** `decide.py`, `run.py`, `tests/test_decide.py`, `tests/test_runner.py`.
- [ ] **Category results:** `Decoration` gains `search: bool = False`; new entry `Decoration("", " Resource Manager", ("option",), "the search result's service group", fields=False, search=True)` (only categories a run has seen). `find_decorated` skips search decorations. `search_results`: when no exact result is found, a second `find_in_roles` on role `option` inside the dropdown for the label plus a search decoration, through `search_result`, so Services only and Marketplace never. Decision handling follows from `decoration_of`: ReplayDecider and HumanDecider give use, and `not_proposed` gives `DECORATION_REASON`.
- [ ] **Retry:** in `search_results`, when the deadline passes with no dropdown identified, `close_search` is called and the label is typed again once, with a new deadline; the tree is saved only after that try.
- [ ] **Tests:** `test_resource_groups_resource_manager_is_the_resource_groups_result` ("Subscriptions Keywords: resource groups" and "Resource Manager Includes: Resource groups" must not match); `test_tags_and_management_groups_resource_manager_too`; `test_an_exact_result_wins_over_a_category_one`; `test_a_category_result_outside_services_never_counts`; `test_a_search_without_a_results_list_is_typed_again_once` (1.3.22 run B); `test_a_second_miss_saves_the_tree_and_asks`; in test_decide.py: `test_replay_of_a_recorded_category_result_is_use`, `test_a_human_pick_of_it_is_use`.
- [ ] **Docs:** run.py docstring (the "Search for **X**" paragraph and the decorations paragraph), decide.py docstring, Invoke help (the search sentence in "SUPERVISED FIRST").
- [ ] **Commit:** `feat(guide-drift): read a search result with its service group as the guide's, and retry a search once (#342)`

### Task 9: (g) a view that fills in later is refreshed for a bounded time (1.3.10)

- [ ] **Files:** `recording.py`, `run.py`, `tests/test_redact.py`, `tests/test_runner.py`, `tests/Guide-Drift-Recording.Tests.ps1`, `tools/guide-drift/recordings/lab-1.3.json`, `tools/Invoke-GuideDrift.ps1`.
- [ ] **Recording key:** `"lateLabels": {"<label>": <minutes>}` in a step entry; `recording.late_minutes(recording, step_id, label)`; `recording.late_label_problems(recording)`: whole minutes from 1 to 60; run.py refuses to start (254) on a problem, as for a skip without a reason. The Pester test also checks that the label is one of the step's parsed labels.
- [ ] **Runner:** new `Runner.wait_for_late_view(step, item, label, look)`, modelled on `wait_for_deployment`. After `wait_for_blade` found nothing, and before the deciders: say once how long it waits; every `LATE_POLL_S = 60` click the newest blade's one visible `Refresh` (button or menuitem, Task 2's preference), or else `page.reload()`, then look for `FIND_TIMEOUT_MS`; say every `DEPLOYMENT_SAY_S` how long it has waited; at the limit, go on to the deciders as before. lab-1.3.json 1.3.10 gets `"lateLabels": {"Require-Environment-Tag-RG": 30}`.
- [ ] **Tests:** `test_compliance_lists_the_assignment_after_two_refreshes`; `test_the_page_is_reloaded_when_no_refresh_is_on_screen`; `test_the_label_is_asked_about_after_the_limit`; `test_no_wait_without_a_late_label`; `test_a_late_label_of_zero_or_of_text_is_refused` (test_redact); Pester `Describe 'Guide drift recordings - a late label waits whole minutes for a label of its step'` with rule cases (valid, 0, 61, "30", unknown label).
- [ ] **Docs:** run.py docstring (after the deployment paragraph), recording.py header, Invoke help (a new paragraph, "A VIEW THAT FILLS IN LATER"), the Recording test's synopsis.
- [ ] **Commit:** `feat(guide-drift): refresh a view that lists a label only later, for as long as the recording allows (#342)`

### Task 10: (h) parser: Expected View lists and steps without numbered items; 1.3.22's wording

- [ ] **Files:** `parse.py`, `tests/test_parse.py`, `tests/Guide-Drift-Parser.Tests.ps1`, `module-1-identities-governance/1.3-governance/lab-guide-1.3.md`, `tools/guide-drift/recordings/lab-1.3.json`.
- [ ] **Parser rules:** `EXPECTED_VIEW`: a line `**Expected View**:` with nothing after the colon; the list right after it (`following_list`) is neither items nor joined to the Expected Result (with text after the colon, 2.1 line 529 and 2.2 line 517, nothing changes). A step whose read body holds no numbered list item gives no action, navigation or search item from its lists; its form-table fields and tags stay (today this drops only 1.3.14 and 2.2.16; 3.2.10 and 3.2.11 keep their fields).
- [ ] **Guide 1.3.22:** item 3 "You'll see the **Tenant Root Group**" becomes `**Expected Result**: **Management groups** lists the **Tenant Root Group**.`
- [ ] **Recording, in the same commit so Pester stays green:** drop 1.3.10 "Overall compliance percentage"; drop 1.3.14's entry (the step becomes `portal: false`); drop 1.3.22 "Tenant Root Group"; add to 1.3.22 `"result": {"text": "Tenant Root Group"}, "asked": ["result"]`.
- [ ] **Tests:** test_parse.py: `test_an_expected_view_list_is_no_action`, `test_an_expected_view_with_text_is_read_as_before`, `test_a_step_without_numbered_items_gives_no_clicks`, `test_its_form_table_still_gives_fields`; Guide-Drift-Parser.Tests.ps1: `It 'reads lab 1.3: no Overall compliance percentage in 1.3.10, 1.3.14 without a portal part, 1.3.22 ending in its Expected Result'` and `It 'drops list clicks only in steps 1.3.14 and 2.2.16 of every guide'`; Guide-Step-Numbering stays green.
- [ ] **Docs:** parse.py docstring (the two rules, and the Known gaps entry if one applies).
- [ ] **Commit:** `feat(guide-drift): read no click from an Expected View list or a step without numbered items (#342)`

### Task 11: (i) the run's subscription as a label and a redaction token; 1.3.18 item 2

- [ ] **Files:** `recording.py`, `run.py`, `tools/Invoke-GuideDrift.ps1`, `tests/test_redact.py`, `tests/test_runner.py`, `tests/Guide-Drift-Parser.Tests.ps1`, the Lab 1.3 guide.
- [ ] **Redactor:** takes `subscription_name`; token `SUBSCRIPTION = "[yoursubscription]"` in `TOKENS`, so `REDACTION_TOKENS` covers it; same rule as the tenant name (at least 4 characters, bounded by non-word characters, placed before the prefix pair). This also closes a leak: run B's outlines carry the subscription's display name in clear.
- [ ] **run.py:** new `--subscription-name` argument; `looking_for` looks a label that holds a Redactor token up by `redactor.matcher(label)` (the restored name), so the guide's **[yoursubscription]** finds the run's subscription link as a match.
- [ ] **Invoke-GuideDrift.ps1:** passes `--subscription-name (Get-AzContext).Subscription.Name` in subscription mode only, not when empty; the help lists the token.
- [ ] **Guide 1.3.18:** item 2 becomes `2. Click your subscription, **[yoursubscription]**` (parse.py already reads it as a label).
- [ ] Not here: #236's built-in placeholders for Subscription fields.
- [ ] **Tests:** test_redact: `test_the_subscription_name_becomes_yoursubscription_and_back`, `test_a_short_subscription_name_is_left_alone`, `test_yoursubscription_is_a_redaction_token`; test_runner: `test_yoursubscription_finds_the_runs_subscription_link` (neutral "Example Subscription"), `test_a_blade_outline_scrubs_the_subscription_name`; parser pin for 1.3.18 item 2.
- [ ] **Docs:** run.py docstring (scrub and Usage), recording.py Redactor docstring, Invoke help (`-SubscriptionId` and "WHAT A RUN LEAVES BEHIND").
- [ ] **Commit:** `feat(guide-drift): find and redact the run's subscription as [yoursubscription] (#342)`

### Task 12: (j) the Lab 1.3 recording drops the workarounds the runner no longer needs

- [ ] **Files:** `tools/guide-drift/recordings/lab-1.3.json`, `tests/test_runner.py` (or a new `tests/test_recordings.py`).
- [ ] **Drop:** the "Resource groups" entries of 1.3.1, 1.3.6, 1.3.11 and 1.3.17, 1.3.4's "Tags" and 1.3.22's "Management groups" (Task 8); 1.3.5's "Require a tag on resource groups" and 1.3.8's "Require a tag and its value on resources", both `radio "Select"` (Task 3); 1.3.5's valueOverride "Policy enforcement": "[Leave blank]" (Task 5); 1.3.15's "Name" -> "Enter a unique name" (Task 4).
- [ ] **Keep:** the "[Leave blank]" overrides of 1.3.7 Subscription and the 1.3.8 / 1.3.9 Scope (fields marked `literal: false`, which the recording test requires), 1.3.15's date and amount overrides, the alert e-mail overrides, every `viewUrl` / `startBlade`, and Task 9's `lateLabels`.
- [ ] **Test:** `test_the_lab_1_3_recording_works_around_no_control_the_runner_operates`: no label entry of any recording is a `use` of `radio "Select"`, or of an option whose name is its label plus a search decoration. Pester `Guide-Drift-Recording.Tests.ps1` green.
- [ ] **Commit:** `chore(guide-drift): drop the Lab 1.3 recording's workarounds for controls the runner now operates (#342)`

### Task 13: 1.3.18's tag filter as fields (controller only, needs the maintainer's sign-in; not for an implementer subagent)

- [ ] A supervised run `.\tools\Invoke-GuideDrift.ps1 -SubscriptionId <id> -Lab 1.3 -FromStep 1.3.18 -SkipCleanup`. At the filter pill, answer `u` so its outline is kept as `blade-1.3.18-<line>.aria.txt`.
- [ ] From that outline, rewrite items 6 and 7 as field items the parser reads (`- <Portal label>: \`project\``, `- <Portal label>: \`skycraft\``; the same for the resource group filter), with the Portal's own labels.
- [ ] Add a parser pin, and a unit test on a trimmed excerpt of the pill (no subscription name). Record decisions only if a label still differs.
- [ ] **Commit:** `docs(lab-1.3): give Cost analysis' tag filter fields the run can fill (#342)`

### Task 14: Live acceptance (controller only, needs the maintainer's sign-in; not for an implementer subagent)

- [ ] **Preconditions:** Lab 1.2's resource groups exist; no Lab 1.3 leftovers (run `module-1-identities-governance/1.3-governance/scripts/Remove-LabResource.ps1 -Force` first if needed); `SKYCRAFT_GUIDE_DRIFT_ALERT_EMAIL` is set; the module-2 session sharing the subscription has agreed.
- [ ] Replay `.\tools\Invoke-GuideDrift.ps1 -SubscriptionId <id> -Lab 1.3 -SkipCleanup`. It must end with exit 0: every step 1.3.1-1.3.22 performed; no blocking or misleading drift, no unknown, no proposed edit; no `c` or `s` answer, and no label prompt. 1.3.10 may wait up to its 30 recorded minutes. A prompt means a defect: answer `q`, fix it offline with a test, and replay.
- [ ] `module-1-identities-governance/1.3-governance/scripts/Test-Lab.ps1` passes on the state that run leaves.
- [ ] `Remove-LabResource.ps1 -Force` exits 0.
- [ ] Put the run id and exit code on the PR's Live-verified line. Copy summary.md, not the console.
- [ ] Delete this PLAN.md in the PR's last commit.

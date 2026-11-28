# Browser and Portal handling

Discover browser tools by capability: navigation, page inspection, clicking,
typing, screenshots saved locally, and dialog handling. Names vary between agent tools. Map each
capability to an available tool before the pass; if any required capability is unavailable, the
pass shall stop before live work. Create an isolated browser session or fresh tab group and never
reuse another session's tab ids. The tool behaviour below was observed with a Chrome
browser extension; use the available equivalent. When the pass opens its tab group, it shall tell the user that the group is a separate Chrome window.

## Portal behaviour seen in passes

- **React views stall on the loader** in the automated tab (Create user, All users, Advisor Overview, policy forms). Wait ~10 s once; then press F5 (a key press) - that fixes it. A blade title can update while the content stays stale: check the content, not the title.
- **Text typed before a blade finishes loading is lost.** Click a field, wait 3-4 s (1-2 s was not enough in Module 4), type, then zoom to verify. Batch long sequences only after the form is visibly loaded.
- **Combobox editors** (Tags Name/Value, scope pickers): click, wait 2 s, type, then click the next field directly. Escape clears what was typed.
- **Delete-confirmation fields** enable **Delete** only after the field loses focus: type the name, press Tab, then click. A second **Delete confirmation** modal follows (a Portal pane, not a browser dialog).
- **Drop-downs** sometimes ignore the first selection (seen on Add lock's Lock type): zoom to verify the value before OK, especially when the default is the dangerous option (Read-only). When a click on a list item does not stick, type the filter text into the control, then press Down and Return (seen on Resource group and Severity in the alert rule wizard, 2026-11-02).
- **Wizard tabs** can be clicked directly; a guide's "Next" count is often off because new tabs appear (Managed identity, Set alerts).
- **Errors from Create** often appear only under the notification bell, while the form stays on its last page. Open the bell after every Create that does not navigate away.
- **The Portal remembers scopes** (Cost Management, Budgets): later steps can land on the last scope used, not the one the guide assumes.
- **Escape closes more than you think:** in a date picker inside a form (stored access policy), Escape closes the whole form and discards it. Click outside the picker instead.
- **Some views hang for good in the automated tab:** the resource list, a container's overview blade, and a create wizard opened by its `#create/...` URL. Do not wait: reach the same thing another way - a different service view (Storage center > **+ Create**), the row's **...** menu in a list (container > **Access policy**). Do not open a new tab: a tab or tab group the extension creates can land on *Pick an account*, which only the user can clear (five sign-ins on 2026-10-27).
- **When the pass leaves a filled create wizard or pane, the agent shall close it with the blade's X (top right) before navigating, not navigate away or close the tab.**
  Navigating away raises the native "leave site" dialog, which `Return` did not dismiss and which froze the tab twice on 2026-10-26/27; the X closed the VM wizard with no dialog.
- **When a tab freezes, the agent shall open a second tab in the same group before closing the frozen one.**
  Closing the only tab destroys the group and its signed-in window; on 2026-11-02 that cost the maintainer two more sign-ins.
- **Native file pickers** (Upload) cannot be driven: the upload is a user step. The Upload panes of file shares and containers render in a frame: element search sees no file input and a file-upload action cannot reach it. Walk the pane's labels, leave the upload to the user.
- **The Portal session can expire mid-pass:** the tab lands on *Pick an account*. Stop clicking and ask the user to sign in; never pick a tile.
- **Delete under a lock:** a blob container delete opens *Delete confirmation* with **Attempt override of delete lock** (see `safety-and-accounts.md`); a classic file share delete opens *Share can't be deleted* with **Delete** greyed out.
- Menus regroup over time (Policy > Authoring > Assignments, RG > Settings > Locks, Cost Management > Monitoring > Budgets, Advisor > Recommendations): record the path seen, it is DRIFT.

## Tool behaviour

- **Keep the Chrome window visible and alone.** Chrome freezes the renderer of an occluded or minimised window (screenshots time out, panes stop updating), and two sessions driving the same Chrome fight over tabs. When screenshots time out repeatedly, ask the user to bring Chrome to the front before anything else; ask peer sessions by message before live work.

- Screenshots time out about every other call while the Portal renders; retry once before treating the tab as frozen. Three failures in a row: stop and ask the user to look at the tab.
- Page-text extraction was denied on the Portal domain; read with screenshots and region zoom.
- Long batched waits (>60 s total) time out the extension; split waits into batches of five 10-s waits.
- Scrolling to an element found by search scrolls inner panes that ignore wheel scrolling.
- A screenshot saved to disk keeps the call's scale: use scale 1 for any shot that goes into the repository. Capture with region zoom on a region below the Portal's top bar, so the account never shows, and prefer a tab without the subscription name (a create wizard's Basics tab shows it; its Security tab does not). Move the mouse off the region first.
- Save discrepancy screenshots to disk, then copy them under step-numbered names; they stay local unless cropped and free of identifiers. Screens that show the user's **public IP** (storage firewall "Add your client IP address", NSG source rules) or account names stay local, whole.

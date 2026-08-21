# Manual QA checklist

Run against a live Omarchy shell (`scripts/dev.sh`, widget enabled) before
every release. Automated coverage (Model.js, bin scripts) does not replace
this — these are the interactions only a human can judge.

## Panel basics
- [ ] Bar icon opens/closes the panel on click; `omarchy-shell downloads toggle` does the same
- [ ] Header shows plausible total size and file count; "Open" opens the folder in the file manager
- [ ] Recent list shows the configured number of files, newest first
- [ ] Image files show thumbnails; other files show the type glyph and extension chip
- [ ] Long file names elide in the middle without breaking the row layout

## Live tracking
- [ ] Download a real file in a browser: a downloading row appears (accent color, size ticking)
- [ ] When it finishes, the row becomes a normal file at the top of the list
- [ ] With the panel closed, finishing a download shows the badge dot on the bar icon
- [ ] Opening the panel clears the badge

## Quick actions
- [ ] Row click opens the file with its default app and closes the panel
- [ ] Folder icon reveals the file in the file manager (file selected where supported)
- [ ] Copy icon: paste works in the file manager; paste in a chat/upload also works
- [ ] Trash icon shows the confirmation dialog; Confirm moves the file to trash; Cancel keeps it
- [ ] With "Confirm before trashing" off, trash acts immediately
- [ ] Trashed file is recoverable from the system trash
- [ ] Trashing a file morphs that row in place into a "✓ Moved … to trash" confirmation, holds briefly, then collapses smoothly (rows below slide up, no jump)
- [ ] Trashing the last (or only) visible/filtered row shows the same inline confirmation before collapsing to the empty state — no flicker or layout jump
- [ ] Copying a file shows a "✓ Copied … to clipboard" toast banner at the bottom of the panel, which auto-dismisses after ~2.5s
- [ ] Closing and reopening the panel clears any toast or in-progress trash confirmation still showing

## Search & keyboard
- [ ] Panel opens with the search field focused; typing filters the whole folder, not just recents
- [ ] Up/Down move the selection; Enter opens the selected file; Delete key trashes (with dialog)
- [ ] Esc clears the query first, then closes the panel
- [ ] No matches shows the "No matches" empty state; empty folder shows "No downloads yet"

## Settings & environment
- [ ] Changing "Folder to watch" points the widget at the new folder
- [ ] Changing "Recent files shown" resizes the list
- [ ] Theme switch (`omarchy theme set …`) recolors the panel correctly
- [ ] Works with the bar at top and bottom, and on multiple monitors
- [ ] `journalctl --user -f` shows no QML errors while doing all of the above

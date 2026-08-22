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
- [ ] Download a real file in a browser (Chrome and Firefox, if both available): a downloading row appears, reading just "downloading…" (no size)
- [ ] The downloading row shows a spinning dot-ring icon where the reveal/copy/trash actions normally appear
- [ ] If the browser creates a zero-byte placeholder file under the final download name while downloading, it does NOT appear anywhere in the list (search for it by name too — it still shouldn't show)
- [ ] The bar icon pulses (fades in/out on a loop) while the download is in progress
- [ ] When it finishes, the row becomes a normal file at the top of the list (showing its real size again), its spinner is replaced by the usual hover actions, and the bar icon stops pulsing and returns to full opacity
- [ ] With the panel closed, finishing a download shows the badge dot on the bar icon
- [ ] Opening the panel clears the badge
- [ ] Start a download, then freeze it (kill the browser mid-download, or disconnect networking) and wait ~30-40s: the row switches to a static, urgent-toned "Stalled — download incomplete" label, the bar icon/header stop indicating an active download, and reveal/trash become available on hover while copy stays hidden
- [ ] A genuinely slow-but-active download (steadily growing, even if only every few seconds) never gets flagged stalled while bytes keep arriving
- [ ] If the stalled download resumes growing before being trashed, the row goes back to the normal "downloading…" state on its own

## Quick actions
- [ ] Row click opens the file with its default app and closes the panel
- [ ] Folder icon reveals the file in the file manager (file selected where supported)
- [ ] Copy icon: paste works in the file manager; paste in a chat/upload also works
- [ ] Trash icon shows the confirmation dialog; Confirm moves the file to trash; Cancel keeps it
- [ ] With "Confirm before trashing" off, trash acts immediately
- [ ] Trashed file is recoverable from the system trash
- [ ] Trashing a file shows a "Moved … to trash" toast banner at the bottom of the panel, which auto-dismisses after ~2.5s
- [ ] Copying a file shows a "Copied … to clipboard" toast banner in the same spot, which also auto-dismisses
- [ ] Closing and reopening the panel clears any toast still showing

## Search & keyboard
- [ ] Panel opens with the search field focused; typing filters the whole folder, not just recents
- [ ] Up/Down move the selection; Enter opens the selected file
- [ ] With the search box empty, Delete trashes the selected file (with dialog)
- [ ] With a query typed, Delete edits the text (forward-delete) and does NOT trash — check this with "Confirm before trashing" off too
- [ ] Shift+Delete trashes the selected file even mid-search
- [ ] Esc clears the query first, then closes the panel
- [ ] No matches shows the "No matches" empty state; empty folder shows "No downloads yet"

## Settings & environment
- [ ] Changing "Folder to watch" points the widget at the new folder
- [ ] Point it at a folder inside a hidden directory (e.g. `~/.local/share/testdl`) and at a hidden folder itself (`~/.testdl`): the header total matches the listed files instead of reading "0 B · 0 files"
- [ ] Changing "Recent files shown" resizes the list
- [ ] Theme switch (`omarchy theme set …`) recolors the panel correctly
- [ ] Works with the bar at top and bottom, and on multiple monitors
- [ ] `journalctl --user -f` shows no QML errors while doing all of the above

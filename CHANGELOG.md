# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com), and the project adheres to
[Semantic Versioning](https://semver.org).

## [1.0.1] - 2026-08-23

### Security
- Bounded the resource use of folder scanning, flagged in marketplace review. A large or adversarial downloads tree could previously keep the helper busy and amplify CPU/memory in the long-lived shell process:
  - `resync()` now processes at most 2,000 of the newest folder entries per pass, instead of copying and re-sorting the whole folder on every watcher event and every 2s poll.
  - `bin/downloads-stats` bounds its recursive walk (`-maxdepth 20`, a 20,000-file output cap, and a 10s `timeout`), degrading to a floor total rather than failing.
  - Overdue helpers are now stopped rather than left running: the shell kills `downloads-stats` after 15s, and `downloads-file-size` after 10s — the latter also unblocks the stall-confirmation queue, which a single hung `stat()` on an unresponsive mount could previously wedge permanently.
- Filesystem-derived text (file names, and error messages that quote a path) is now always rendered as plain text instead of Qt's default `AutoText`, which could otherwise interpret a crafted file name as rich-text markup — an `<img>` tag in a filename would have been enough to make the panel fetch a remote URL.

### Fixed
- Folder totals silently read "0 B · 0 files" instead of reporting an error when `timeout` was unavailable.

## [1.0.0] - 2026-08-22

### Added
- Live download status in the panel: the header reads "DOWNLOADING FILES" while something is in flight and "NO CURRENT DOWNLOADS" otherwise, with the folder's total size and file count on their own line.
- The bar icon turns the theme's accent color and pulses while a download is in progress, so the bar shows activity without opening the panel.
- A "Recent downloads" title above the file list, to distinguish it from search results.
- Success toast banner ("Moved … to trash" / "Copied … to clipboard") shown after a quick action completes, auto-dismissing after ~2.5s.
- Stalled-download detection: a partial download whose size stops changing (an aborted or failed download, not just a slow one) is flagged "Stalled — download incomplete" and becomes actionable (reveal/trash) instead of being stuck non-actionable forever; the bar icon and header stop indicating it as an active download. A suspected stall is double-checked against the file's real on-disk size (`bin/downloads-file-size`) before being shown as stalled, since the cached size Quickshell reports while a file is being actively written can itself lag for many seconds — so a genuinely active download is never misflagged, at the cost of taking up to ~40s to confirm a truly dead one.

### Changed
- File names no longer repeat the extension; each row now shows the size and type together below the name (e.g. "130.8 KB · .PNG").
- A file still downloading shows a "downloading" label with cycling dots in place of its size and quick actions, so an incomplete file can't be opened or copied by accident.
- Default recent-file count raised from 5 to 7, using space the panel already had.
- Delete now trashes the selected file only while the search box is empty, so it can act as forward-delete while typing a query; Shift+Delete trashes from anywhere.
- Panel layout polish: the folder size is labelled as a total, the divider sits above the search field, and section labels are uppercased.
- The folder totals are recalculated when a file appears, vanishes, or is renamed, and otherwise at most every 10s — a download in flight no longer re-walks the whole folder every two seconds.
- The file list is only republished when its contents actually changed, so an unrelated folder event no longer resets the list's scroll position or re-requests every thumbnail.

### Fixed
- Folder totals read "0 B total" once the watched folder exceeded ~2.1 GB, because the byte count overflowed a 32-bit signed integer and rendered as a negative size.
- Browsers that reserve the final filename as a zero-byte placeholder while downloading (observed with Chrome) no longer show that placeholder as a normal, actionable row — trashing it mid-download could break the download.
- Copying or revealing a file whose name contains non-ASCII characters produced a malformed `file://` URI; paths are now percent-encoded byte-by-byte as UTF-8.
- With panels open on more than one monitor, closing one could clear the completion badge while another was still open.
- Two quick actions fired in rapid succession could race on a shared process, silently dropping the second; copy and trash are now queued.
- A file row's hover highlight stuck around after the mouse actually left it, because hovering synced the keyboard-navigation cursor to that row and nothing ever reset it on mouse-exit; separately, the first row always appeared highlighted on open, since the cursor defaults to index 0. The highlight now only follows real-time hover or an actual arrow-key press — the keyboard cursor still defaults to the first row (so Enter/Delete have something sensible to act on immediately), it just doesn't look selected until the user actually navigates to it.
- Moving the mouse onto a row's reveal/copy/trash button could make the row's highlight (and the buttons themselves) flicker rapidly, since Qt Quick hands hover to whichever item is topmost at the pointer — once a button claimed it, the row's own hover state dropped, hiding the very button under the cursor and un-hovering it, which handed hover back to the row and repeated. Each button's hover now also keeps the row highlighted.
- The in-progress download row's spinning icon could freeze mid-rotation after the panel was closed and reopened, since Qt Quick pauses a window's animations while it isn't visible. Replaced with an animated "downloading." / ".." / "..." dot cycle driven by a Timer, which keeps advancing regardless of the panel's visibility.
- Search results past the eighth match were drawn outside the popout card, leaving them unreachable by mouse and keyboard. The file list now scrolls once it exceeds eight rows, and arrow-key navigation keeps the selected row in view.
- Folder totals read "0 B · 0 files" whenever the watched folder was itself hidden (`~/.downloads`) or lived under a hidden directory (`~/.local/share/downloads`), because the hidden-file filter tested the whole path instead of each entry's own name.
- A completed download whose name collides with a JavaScript object member (`constructor`, `toString`, …) never raised the completion badge.
- "Confirm before trashing" is now read strictly as a boolean, so a stored string value can no longer be misread as enabled.

## [0.1.0] - 2026-08-20

### Added
- Live folder watching with in-progress download detection and completion badge.
- Whole-folder search with keyboard navigation (arrows, Enter, Delete, Esc).
- Quick actions per file: open, reveal in file manager, copy to clipboard, move to trash with confirmation.
- Folder totals in the header with an Open-folder button.
- Image thumbnails and extension chips in the file list.
- Configurable folder, recent-file count, badge, and trash confirmation.

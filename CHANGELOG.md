# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com), and the project adheres to
[Semantic Versioning](https://semver.org).

## [Unreleased]

### Added
- Success toast banner ("Moved … to trash" / "Copied … to clipboard") shown after a quick action completes, auto-dismissing after ~2.5s.
- Stalled-download detection: a partial download whose size stops changing (an aborted or failed download, not just a slow one) is flagged "Stalled — download incomplete" and becomes actionable (reveal/trash) instead of being stuck non-actionable forever; the bar icon and header stop indicating it as an active download. A suspected stall is double-checked against the file's real on-disk size (`bin/downloads-file-size`) before being shown as stalled, since the cached size Quickshell reports while a file is being actively written can itself lag for many seconds — so a genuinely active download is never misflagged, at the cost of taking up to ~40s to confirm a truly dead one.

### Changed
- File names no longer repeat the extension; each row now shows the size and type together below the name (e.g. "130.8 KB · .PNG").
- Default recent-file count raised from 5 to 7, using space the panel already had.
- Delete now trashes the selected file only while the search box is empty, so it can act as forward-delete while typing a query; Shift+Delete trashes from anywhere.
- The folder totals are recalculated when a file appears, vanishes, or is renamed, and otherwise at most every 10s — a download in flight no longer re-walks the whole folder every two seconds.
- The file list is only republished when its contents actually changed, so an unrelated folder event no longer resets the list's scroll position or re-requests every thumbnail.

### Fixed
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

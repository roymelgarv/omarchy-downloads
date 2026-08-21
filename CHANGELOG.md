# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com), and the project adheres to
[Semantic Versioning](https://semver.org).

## [Unreleased]

### Added
- Success toast banner ("Moved … to trash" / "Copied … to clipboard") shown after a quick action completes, auto-dismissing after ~2.5s.

### Changed
- File names no longer repeat the extension; each row now shows the size and type together below the name (e.g. "130.8 KB · .PNG").
- Default recent-file count raised from 5 to 7, using space the panel already had.

### Fixed
- Search results past the eighth match were drawn outside the popout card, leaving them unreachable by mouse and keyboard. The file list now scrolls once it exceeds eight rows, and arrow-key navigation keeps the selected row in view.

## [0.1.0] - 2026-08-20

### Added
- Live folder watching with in-progress download detection and completion badge.
- Whole-folder search with keyboard navigation (arrows, Enter, Delete, Esc).
- Quick actions per file: open, reveal in file manager, copy to clipboard, move to trash with confirmation.
- Folder totals in the header with an Open-folder button.
- Image thumbnails and extension chips in the file list.
- Configurable folder, recent-file count, badge, and trash confirmation.

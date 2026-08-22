# Contributing

Thanks for helping improve Omarchy Downloads!

## Development setup

Requirements: a running Omarchy 4.x shell, `node` (>= 20) for unit tests, and optionally `bats` + `shellcheck` for script tests.

```bash
git clone https://github.com/roymelgarv/omarchy-downloads
cd omarchy-downloads
scripts/dev.sh            # deploy to ~/.config/omarchy/plugins/ and validate
omarchy plugin enable roymelgarv.omarchy-downloads --section right
```

`scripts/dev.sh` deploys to `~/.config/omarchy/plugins/`, validates the manifest, and asks the shell to rescan. Use `scripts/dev.sh --watch` to redeploy on every save.

Hot reload has two limits worth knowing before you debug a change that "didn't work":

- A running `kind: "service"` instance is **never** reinstantiated. Any `Service.qml` edit needs `scripts/dev.sh --restart`, which deploys and then blocks until a *new* shell pid is answering IPC.
- Even for widget-only files, a rescan has been observed to keep rendering the previously compiled component after a *structural* change (a new child item or a changed root type — not just a property tweak). If an edit doesn't appear, diff the deployed file against your working tree to rule out a bad deploy, then redeploy with `--restart` before assuming the code is wrong.

QML errors appear in `journalctl --user -f`.

Useful IPC commands while developing:

```bash
omarchy-shell downloads toggle          # open/close the panel
omarchy-shell shell listPlugins         # confirm the plugin is registered
omarchy-shell shell rescanPlugins       # force a rescan
```

## Tests

```bash
node --test tests/*.test.mjs                     # Model.js unit tests — must pass
shellcheck -x -P SCRIPTDIR bin/* scripts/*.sh    # same flags CI uses, so lib.sh resolves
bats tests/bin.bats                              # bin script tests
```

All pure logic (sorting, search, size formatting, partial-download and stall detection) lives in `Model.js` and must be covered by unit tests. QML files stay thin; the manual UI checklist is `tests/qa-checklist.md`.

## Branches and commits

- `main` — releases only, tagged `vX.Y.Z`.
- `development` — integration branch; open PRs against this.
- Work branches: `feat/<topic>`, `fix/<topic>`, `chore/<topic>`, `docs/<topic>`.
- Commit messages follow [Conventional Commits](https://www.conventionalcommits.org): `feat: ...`, `fix: ...`, `docs: ...`, etc.

## Releases

1. On `development`: bump `version` in `manifest.json`, update `CHANGELOG.md`, commit as `chore(release): vX.Y.Z`.
2. Merge `development` into `main`.
3. Tag: `git tag vX.Y.Z && git push origin main vX.Y.Z` — the release workflow verifies the tag matches the manifest and publishes a GitHub Release.

## Security expectations

This plugin runs unsandboxed inside the Omarchy shell, so the bar is high: no network access, no sudo/pkexec, no bundled binaries, no writes outside the plugin's own settings and the actions the user explicitly triggers. PRs that add any of these will be declined — they would also fail the marketplace security baseline.

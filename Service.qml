import QtQuick
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Io
import "Model.js" as Model

// Shell-wide singleton (kind: "service"): watches the downloads folder and
// owns every piece of state the bar widgets read. One instance regardless of
// monitor count, so the badge and file list agree on every screen.
//
// Root is Item, not QtObject: Item carries the default `data` property that
// lets plain children (IpcHandler, Timer, Process) attach without wrappers.
Item {
  id: root

  // decodeURIComponent matters here: Qt.resolvedUrl percent-encodes special
  // characters (a checkout path containing a space becomes %20), and this
  // value is spliced straight into bash argv for every bin/ invocation — an
  // un-decoded %20 there is a literal three-character path segment, not a
  // space, and every helper script fails to find itself.
  readonly property string pluginDir: decodeURIComponent(String(Qt.resolvedUrl(".")).replace(/^file:\/\//, "")).replace(/\/$/, "")
  readonly property string home: Quickshell.env("HOME") || ""

  // Settings live on the bar widget (manifest schema); the widget pushes them
  // here so the singleton — which gets no settings injection — sees them too.
  property string folder: home + "/Downloads"
  property bool badgeOnComplete: true

  function applyFolderSetting(value) {
    var path = String(value || "").trim()
    if (path === "") path = "~/Downloads"
    if (path.indexOf("~") === 0) path = home + path.slice(1)
    if (path !== folder) folder = path
  }

  readonly property bool folderExists: files.status !== FolderListModel.Null && String(files.folder) !== ""

  // [{name, path, size, mtime, partial, stalled}] newest first — the panel's model.
  property var entries: []
  // Active downloads only — a partial file whose bytes stopped arriving
  // (aborted/failed, not just slow) is `stalled` and excluded here so the
  // bar icon/pulse/header stop claiming it's in progress.
  readonly property int downloadingCount: entries.filter(function (e) { return e.partial && !e.stalled }).length
  // Any partial file regardless of stall state — keeps the polling timers
  // below alive even once every in-flight download has stalled, so a
  // resumed download is still noticed.
  readonly property int partialFileCount: entries.filter(function (e) { return e.partial }).length
  // Keyed by file name -> {size, lastChanged}; see Model.trackPartialProgress.
  property var _partialHistory: null
  // Names a real stat() has confirmed show no growth since the last real
  // check — only these (combined with a current candidateStalled) become the
  // `stalled: true` shown to the UI. See confirmStall() below.
  property var _confirmedStalledNames: Object.create(null)
  // Name -> last real (stat-confirmed) size, so confirmStall can tell "grew
  // since last real check" apart from "still the same as last time".
  property var _confirmedSizes: Object.create(null)
  // Names currently awaiting a queued confirmStall() result, so a name
  // already in flight isn't queued a second time on the next poll tick.
  property var _pendingConfirmations: Object.create(null)

  // real, not int: QML's int is a 32-bit signed value (~2.1 GB ceiling) and
  // silently overflows negative for larger Downloads folders.
  property real totalBytes: 0
  property int totalCount: 0
  property string lastError: ""

  // Badge: a download finished (or a file appeared) while no panel was open.
  property bool hasNewCompleted: false
  readonly property bool anyPanelOpen: registry.anyOpen
  property var _prevNames: null // null = first scan, never badge for it

  onAnyPanelOpenChanged: if (anyPanelOpen) hasNewCompleted = false
  onFolderChanged: {
    _prevNames = null; hasNewCompleted = false; lastError = ""
    _partialHistory = null
    _confirmedStalledNames = Object.create(null)
    _confirmedSizes = Object.create(null)
    _pendingConfirmations = Object.create(null)
  }

  PanelRegistry { id: registry }

  function registerPanel(panel) { registry.register(panel) }
  function unregisterPanel(panel) { registry.unregister(panel) }

  FolderListModel {
    id: files
    // Qt.resolvedUrl percent-encodes as needed (a "#" or literal "%" in the
    // folder name would otherwise land in the URL unescaped, or worse — "#"
    // would truncate the path at a bogus fragment).
    folder: Qt.resolvedUrl(root.folder)
    showDirs: false
    showHidden: false
    showOnlyReadable: true
    // Sorting is done in Model.js from the extracted entries; the model's own
    // order is irrelevant, but Time keeps incremental updates cheap.
    sortField: FolderListModel.Time

    onCountChanged: root.scheduleResync()
    onStatusChanged: if (status === FolderListModel.Ready) root.scheduleResync()
  }

  // Collapse bursts of watcher events (a finishing download fires several)
  // into a single rebuild.
  Timer {
    id: resyncDebounce
    interval: 250
    repeat: false
    onTriggered: root.resync()
  }

  function scheduleResync() { resyncDebounce.restart() }

  // While a download is in flight the watcher only reports size changes as
  // dataChanged on existing rows; poll lightly so the partial's own size stays
  // honest, and so the suffix-rename that some browsers do (foo.part -> foo)
  // is never missed.
  Timer {
    interval: 2000
    repeat: true
    // partialFileCount, not downloadingCount: a stalled partial still needs
    // polling, or a resumed download would never be noticed again.
    running: root.partialFileCount > 0
    onTriggered: root.resync()
  }

  function resync() {
    var out = []
    var names = []
    for (var i = 0; i < files.count; i++) {
      var name = String(files.get(i, "fileName"))
      var modified = files.get(i, "fileModified")
      out.push({
        name: name,
        path: String(files.get(i, "filePath")),
        size: Number(files.get(i, "fileSize")),
        mtime: modified ? modified.getTime() : 0,
        partial: Model.isPartialDownload(name)
      })
      names.push(name)
    }

    // Advance the cheap candidate-stall check before sorting. candidateStalled
    // is only a suspicion — FolderListModel's fileSize does not reliably
    // refresh while a file is actively being written, so it is never shown
    // to the UI directly; only a real stat() (confirmStall, below) that also
    // finds no growth promotes a name into _confirmedStalledNames, which is
    // what the final `stalled` field actually reflects.
    var tracked = Model.trackPartialProgress(_partialHistory, out, Date.now(), Model.PARTIAL_STALL_MS)
    _partialHistory = tracked.history

    var finalEntries = []
    var currentNames = Object.create(null)
    for (var t = 0; t < tracked.entries.length; t++) {
      var te = tracked.entries[t]
      currentNames[te.name] = true
      var isStalled = false
      if (te.candidateStalled) {
        if (_confirmedStalledNames[te.name] === true) {
          isStalled = true
        } else if (_pendingConfirmations[te.name] !== true) {
          _pendingConfirmations[te.name] = true
          queueConfirm(te.name, te.path)
        }
      } else if (_confirmedStalledNames[te.name] === true) {
        // Resumed growing (per the cheap check) since it was confirmed
        // stalled — self-heal immediately rather than waiting on another
        // confirmStall() round-trip.
        delete _confirmedStalledNames[te.name]
      }
      finalEntries.push({ name: te.name, path: te.path, size: te.size, mtime: te.mtime,
        partial: te.partial, stalled: isStalled })
    }
    // Drop bookkeeping for names no longer present (renamed to final,
    // deleted, or moved) — trackPartialProgress already does this for
    // _partialHistory; these three need the same treatment since they live
    // outside that pure function.
    for (var confirmedName in _confirmedStalledNames) if (!currentNames[confirmedName]) delete _confirmedStalledNames[confirmedName]
    for (var sizeName in _confirmedSizes) if (!currentNames[sizeName]) delete _confirmedSizes[sizeName]

    // Only republish when something actually changed. Reassigning `entries`
    // hands every bound ListView a new model, which resets its scroll
    // position and re-requests every thumbnail — watcher events fire for
    // plenty of reasons that leave this list identical.
    var next = Model.sortByMtimeDesc(finalEntries)
    var entriesChanged = !Model.entriesEqual(entries, next)
    if (entriesChanged) entries = next

    var namesChanged = !Model.namesEqual(_prevNames, names)

    if (_prevNames !== null && badgeOnComplete && !anyPanelOpen &&
        Model.completedSince(_prevNames, names).length > 0)
      hasNewCompleted = true
    _prevNames = names

    // The totals come from a recursive walk of the whole tree, so the two
    // kinds of change get different urgency. A file appearing, vanishing, or
    // being renamed moves the visible count and is worth walking for right
    // away; a size-only change only nudges the byte total, so it is left to
    // the slow refresh below rather than re-walking the folder every 2s poll.
    if (namesChanged) {
      _statsStale = false
      statsDebounce.restart()
    } else if (entriesChanged) {
      _statsStale = true
    }
  }

  // FIFO + single Process, same shape as ActionRunner's copy/trash queue:
  // confirmations are rare (only at a candidate-stall's ~20s cooldown edge)
  // and cheap (one stat() call), but two downloads can go candidate-stalled
  // in the same tick, so they're serialized rather than racing a shared
  // Process's command/running properties.
  property var _confirmQueue: []
  property bool _confirmRunning: false

  function queueConfirm(name, path) {
    _confirmQueue.push({ name: name, path: path })
    _runNextConfirm()
  }

  function _runNextConfirm() {
    if (_confirmRunning || _confirmQueue.length === 0) return
    var next = _confirmQueue.shift()
    _confirmRunning = true
    confirmProcess._name = next.name
    confirmProcess.command = ["bash", pluginDir + "/bin/downloads-file-size", next.path]
    confirmProcess.running = true
  }

  property Process confirmProcess: Process {
    running: false
    command: []
    property string _name: ""
    stdout: StdioCollector {
      id: confirmStdout
      waitForEnd: true
    }
    onExited: function (exitCode) {
      var name = confirmProcess._name
      delete root._pendingConfirmations[name]
      if (exitCode === 0) {
        var realSize = Number(String(confirmStdout.text).trim())
        if (isFinite(realSize)) {
          var lastConfirmed = root._confirmedSizes[name]
          if (lastConfirmed === undefined || realSize > lastConfirmed) {
            // Grew since the last real check (or this is the first check):
            // the candidate was a FolderListModel lag, not a real stall.
            // Reset the cheap detector's cooldown so it takes a fresh full
            // window before suspecting this file again.
            root._confirmedSizes[name] = realSize
            if (root._partialHistory && root._partialHistory[name])
              root._partialHistory[name].lastChanged = Date.now()
          } else {
            // No growth across two independent real measurements — genuinely
            // stalled, not just a lagging cache.
            root._confirmedStalledNames[name] = true
          }
        }
      }
      // exitCode !== 0 (file renamed/removed mid-check, racing completion):
      // skip silently — the next resync's candidate check decides, and the
      // file is presumably already gone or finished.
      _confirmRunning = false
      root.scheduleResync()
      _runNextConfirm()
    }
  }

  // Catches the byte total up when no file came or went, on a slow cadence.
  //
  // `partialFileCount > 0` has to be its own trigger rather than relying on
  // _statsStale: FolderListModel does not re-stat a growing file on every
  // poll, so a download in flight can leave `entries` byte-identical from one
  // resync to the next while the bytes on disk keep climbing. The partial
  // suffix is a name, not a size, so it stays a reliable signal either way.
  // partialFileCount (not downloadingCount) on purpose: the two have
  // diverged now that a stalled partial no longer counts as "downloading",
  // but its size is still worth double-checking on this slow cadence.
  // An idle folder matches neither condition and never walks the tree.
  property bool _statsStale: false
  Timer {
    interval: 10000
    repeat: true
    running: root._statsStale || root.partialFileCount > 0
    onTriggered: {
      root._statsStale = false
      statsDebounce.restart()
    }
  }

  Timer {
    id: statsDebounce
    interval: 800
    repeat: false
    onTriggered: {
      // A previous run outlived the debounce window (slow disk, huge
      // folder); reassigning `command`/`running` on an already-running
      // Process is a no-op, so retry instead of silently dropping this
      // update.
      if (statsProcess.running) { statsDebounce.restart(); return }
      statsProcess.command = ["bash", root.pluginDir + "/bin/downloads-stats", root.folder]
      statsProcess.running = true
    }
  }

  property Process statsProcess: Process {
    running: false
    command: []
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var parsed = JSON.parse(text)
          root.totalBytes = Number(parsed.bytes) || 0
          root.totalCount = Number(parsed.count) || 0
        } catch (e) {
          // stale folder mid-switch; next resync corrects it, but leaving no
          // trace at all makes a genuinely broken downloads-stats output
          // indistinguishable from this expected case.
          console.warn("omarchy-downloads: failed to parse downloads-stats output:", e)
        }
      }
    }
  }

  function openFile(path) {
    Quickshell.execDetached(["xdg-open", path])
  }

  function revealFile(path) {
    Quickshell.execDetached(["bash", pluginDir + "/bin/downloads-reveal", path])
  }

  function openFolder() {
    Quickshell.execDetached(["bash", pluginDir + "/bin/downloads-reveal", folder])
  }

  function copyFile(path) { actions.run("copy", path) }
  function trashFile(path) { actions.run("trash", path) }

  // Re-emitted from the runner so widgets have one thing to connect to.
  signal actionCompleted(string action, string name, bool success)

  ActionRunner {
    id: actions
    pluginDir: root.pluginDir
    onFinished: function (action, name, success) {
      root.lastError = actions.lastError
      root.actionCompleted(action, name, success)
      root.scheduleResync()
    }
  }

  IpcHandler {
    target: "downloads"
    function open(): void { if (registry.first) registry.first.open() }
    function close(): void { if (registry.first) registry.first.close() }
    function toggle(): void { if (registry.first) registry.first.toggle() }
    function status(): string {
      return JSON.stringify({
        folder: root.folder,
        files: root.totalCount,
        bytes: root.totalBytes,
        downloading: root.downloadingCount,
        badge: root.hasNewCompleted,
        panels: registry.count
      })
    }
  }

  Component.onCompleted: scheduleResync()
}

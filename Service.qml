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

  // [{name, path, size, mtime, partial}] newest first — the panel's model.
  property var entries: []
  readonly property int downloadingCount: entries.filter(function (e) { return e.partial }).length

  // real, not int: QML's int is a 32-bit signed value (~2.1 GB ceiling) and
  // silently overflows negative for larger Downloads folders.
  property real totalBytes: 0
  property int totalCount: 0
  property string lastError: ""

  // Badge: a download finished (or a file appeared) while no panel was open.
  property bool hasNewCompleted: false
  // Derived from the registered panels themselves (not a flag one panel sets
  // on open/close): with one panel per monitor, a flag last written by
  // whichever panel changed most recently goes stale the moment a second
  // monitor's panel closes while the first is still open.
  readonly property bool anyPanelOpen: _panels.some(function (p) { return p.opened === true })
  property var _prevNames: null // null = first scan, never badge for it

  onAnyPanelOpenChanged: if (anyPanelOpen) hasNewCompleted = false
  onFolderChanged: { _prevNames = null; hasNewCompleted = false; lastError = "" }

  // Bar-widget panels (one per monitor) register so IPC has a panel to act
  // on. Named for what it actually is — whichever panel registered first —
  // not "the primary monitor's panel", which this doesn't attempt to resolve.
  property var _panels: []
  readonly property var _firstPanel: _panels.length > 0 ? _panels[0] : null

  function registerPanel(panel) {
    if (_panels.indexOf(panel) === -1) _panels = _panels.concat([panel])
  }

  function unregisterPanel(panel) {
    var at = _panels.indexOf(panel)
    if (at === -1) return
    var next = _panels.slice()
    next.splice(at, 1)
    _panels = next
  }

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
  // into one rebuild + one stats run.
  Timer {
    id: resyncDebounce
    interval: 250
    repeat: false
    onTriggered: root.resync()
  }

  function scheduleResync() { resyncDebounce.restart() }

  // While a download is in flight the watcher only reports size changes as
  // dataChanged on existing rows; poll lightly so the partial's size and the
  // totals stay honest, and so the suffix-rename that some browsers do
  // (foo.part -> foo) is never missed.
  Timer {
    interval: 2000
    repeat: true
    running: root.downloadingCount > 0
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
    entries = Model.sortByMtimeDesc(out)

    if (_prevNames !== null && badgeOnComplete && !anyPanelOpen &&
        Model.completedSince(_prevNames, names).length > 0)
      hasNewCompleted = true
    _prevNames = names

    statsDebounce.restart()
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

  function copyFile(path) {
    runAction("copy", path)
  }

  function trashFile(path) {
    runAction("trash", path)
  }

  // Fired after copy/trash finishes, success or not, so the widget can show
  // a confirmation toast. `name` is derived from the path (not `entries`,
  // which may already have been rebuilt by the time the process exits).
  signal actionCompleted(string action, string name, bool success)

  property string _pendingAction: ""
  property string _pendingName: ""
  property bool _actionRunning: false
  // FIFO of {action, path} — copy/trash share one Process (both are
  // near-instant, and a shared instance means a single place turns a nonzero
  // exit into lastError), so a second quick action fired before the first's
  // process exits is queued rather than clobbering _pendingAction/
  // _pendingName and silently no-oping on the already-running Process.
  property var _actionQueue: []

  function runAction(action, path) {
    _actionQueue.push({ action: action, path: path })
    _runNextQueuedAction()
  }

  function _runNextQueuedAction() {
    if (_actionRunning || _actionQueue.length === 0) return
    var next = _actionQueue.shift()
    _pendingAction = next.action
    _pendingName = String(next.path).split("/").pop()
    _actionRunning = true
    actionProcess.command = ["bash", pluginDir + "/bin/downloads-" + next.action, next.path]
    actionProcess.running = true
  }

  property Process actionProcess: Process {
    running: false
    command: []
    // Read only from onExited, not from this collector's own
    // onStreamFinished: Process/StdioCollector don't guarantee stderr closes
    // before onExited fires, so setting lastError here and clearing it
    // separately in onExited raced. `text` is stable by the time onExited
    // runs because waitForEnd holds the collector open until the stream
    // closes.
    stderr: StdioCollector {
      id: actionStderr
      waitForEnd: true
    }
    onExited: function (exitCode) {
      var success = exitCode === 0
      root.lastError = success ? "" : String(actionStderr.text).trim()
      root.actionCompleted(root._pendingAction, root._pendingName, success)
      root._actionRunning = false
      root.scheduleResync()
      root._runNextQueuedAction()
    }
  }

  IpcHandler {
    target: "downloads"
    function open(): void { if (root._firstPanel) root._firstPanel.open() }
    function close(): void { if (root._firstPanel) root._firstPanel.close() }
    function toggle(): void { if (root._firstPanel) root._firstPanel.toggle() }
    function status(): string {
      return JSON.stringify({
        folder: root.folder,
        files: root.totalCount,
        bytes: root.totalBytes,
        downloading: root.downloadingCount,
        badge: root.hasNewCompleted,
        panels: root._panels.length
      })
    }
  }

  Component.onCompleted: scheduleResync()
}

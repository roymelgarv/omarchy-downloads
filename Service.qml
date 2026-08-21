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

  readonly property string pluginDir: String(Qt.resolvedUrl(".")).replace(/^file:\/\//, "").replace(/\/$/, "")
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

  property int totalBytes: 0
  property int totalCount: 0
  property string lastError: ""

  // Badge: a download finished (or a file appeared) while no panel was open.
  property bool hasNewCompleted: false
  property bool anyPanelOpen: false
  property var _prevNames: null // null = first scan, never badge for it

  onAnyPanelOpenChanged: if (anyPanelOpen) hasNewCompleted = false
  onFolderChanged: { _prevNames = null; hasNewCompleted = false }

  // Bar-widget panels (one per monitor) register so IPC has a panel to act on.
  property var _panels: []
  readonly property var _primaryPanel: _panels.length > 0 ? _panels[0] : null

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
    folder: "file://" + root.folder
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
          // stale folder mid-switch; next resync corrects it
        }
      }
    }
  }

  // ------------------------------------------------------------- actions

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

  function runAction(action, path) {
    _pendingAction = action
    _pendingName = String(path).split("/").pop()
    actionProcess.command = ["bash", pluginDir + "/bin/downloads-" + action, path]
    actionProcess.running = true
  }

  // Copy and trash share one Process: both are near-instant, and a shared
  // instance means a single place turns a nonzero exit into lastError.
  property Process actionProcess: Process {
    running: false
    command: []
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.lastError = String(text).trim()
    }
    onExited: function (exitCode) {
      var success = exitCode === 0
      if (success) root.lastError = ""
      root.actionCompleted(root._pendingAction, root._pendingName, success)
      root.scheduleResync()
    }
  }

  IpcHandler {
    target: "downloads"
    function open(): void { if (root._primaryPanel) root._primaryPanel.open() }
    function close(): void { if (root._primaryPanel) root._primaryPanel.close() }
    function toggle(): void { if (root._primaryPanel) root._primaryPanel.toggle() }
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

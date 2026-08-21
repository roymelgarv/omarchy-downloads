import QtQuick
import Quickshell.Io

// Runs the bin/downloads-<action> helpers one at a time. copy and trash share
// a single Process — both are near-instant, and one instance means one place
// turns a nonzero exit into an error message — so a second action fired before
// the first exits is queued rather than clobbering the pending action and
// silently no-oping on the already-running Process.
Item {
  id: root

  property string pluginDir: ""

  // The action name is concatenated into the helper's path, so only these
  // values may ever reach the command line. Anything else is dropped rather
  // than resolved against bin/, which would let a caller reach outside it.
  readonly property var allowedActions: ["copy", "trash"]

  property string lastError: ""
  readonly property bool busy: _running

  // Fired after an action finishes, success or not, so a widget can show a
  // confirmation toast.
  signal finished(string action, string name, bool success)

  property var _queue: []
  property bool _running: false
  property string _action: ""
  property string _name: ""

  function run(action, path) {
    if (allowedActions.indexOf(action) === -1) {
      console.warn("omarchy-downloads: refusing unknown action:", action)
      return
    }
    _queue.push({ action: action, path: String(path) })
    _runNext()
  }

  function _runNext() {
    if (_running || _queue.length === 0) return
    var job = _queue.shift()
    _action = job.action
    // Derived from the path, not from the service's entries list, which may
    // already have been rebuilt by the time the process exits.
    _name = job.path.split("/").pop()
    _running = true
    process.command = ["bash", root.pluginDir + "/bin/downloads-" + job.action, job.path]
    process.running = true
  }

  property Process process: Process {
    running: false
    command: []
    // Read only from onExited, not from this collector's own
    // onStreamFinished: Process/StdioCollector don't guarantee stderr closes
    // before onExited fires, so setting lastError here and clearing it
    // separately in onExited raced. `text` is stable by the time onExited
    // runs because waitForEnd holds the collector open until the stream
    // closes.
    stderr: StdioCollector {
      id: collector
      waitForEnd: true
    }
    onExited: function (exitCode) {
      var success = exitCode === 0
      root.lastError = success ? "" : String(collector.text).trim()
      root.finished(root._action, root._name, success)
      root._running = false
      root._runNext()
    }
  }
}

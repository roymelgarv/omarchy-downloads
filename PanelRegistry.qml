import QtQuick

// The bar-widget panels currently alive (one per monitor). Owned by the
// service so IPC has a panel to act on, and so the badge can tell whether the
// user is already looking at the list on any screen.
Item {
  id: root

  property var panels: []
  readonly property int count: panels.length

  // Whichever panel registered first. This deliberately does not try to
  // resolve which monitor is primary.
  readonly property var first: panels.length > 0 ? panels[0] : null

  // Derived from the panels' own `opened` state rather than a flag each panel
  // sets on open/close: with one panel per monitor, a shared flag written by
  // whichever panel changed most recently goes stale the moment a second
  // monitor's panel closes while the first is still open.
  readonly property bool anyOpen: panels.some(function (p) { return p.opened === true })

  function register(panel) {
    if (panels.indexOf(panel) === -1) panels = panels.concat([panel])
  }

  function unregister(panel) {
    var at = panels.indexOf(panel)
    if (at === -1) return
    var next = panels.slice()
    next.splice(at, 1)
    panels = next
  }
}

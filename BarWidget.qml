import QtQuick
import QtQuick.Controls
import Quickshell
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Bar widget + popout for Downloads. One file on purpose, matching the
// keyboard-cleaner layout: a qs.Ui Panel root owning the bar button and the
// KeyboardPanel popout, with all folder state read from the singleton service.
Panel {
  id: root
  moduleName: "roymelgarv.omarchy-downloads"
  ipcTarget: "downloads"
  manageIpc: false

  // Must match manifest.json's `id`: the shell keys its singleton service
  // registry by plugin id, so a mismatch silently yields a null service.
  readonly property string pluginId: "roymelgarv.omarchy-downloads"
  readonly property var service: bar?.shell?.firstPartyServiceFor(root.pluginId) ?? null

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  readonly property int recentCount: setting("recentCount", 5)
  readonly property bool confirmTrash: setting("confirmTrash", true)

  property string query: ""
  property int cursor: 0
  property var pendingTrash: null

  // Success toast for a completed copy, auto-dismissed. Trash gets its own
  // inline-in-row confirmation instead (see confirmedRemoval below), since
  // that row is disappearing and deserves the feedback exactly where it was.
  property string toastMessage: ""

  Timer {
    id: toastTimer
    interval: 2500
    repeat: false
    onTriggered: root.toastMessage = ""
  }

  // Snapshot of the entry being trashed, taken at confirm time (while it's
  // still in visibleEntries) so we know its position once it's gone.
  property var _trashingEntry: null
  property int _trashingIndex: 0

  // {entry, index, collapsing} while a trashed row's confirmation is
  // showing; reconstructed into visibleEntries by Model.withGhostEntry.
  property var confirmedRemoval: null

  // Hold the "Moved to trash" message, then collapse the row's height
  // before actually dropping it, so rows below slide up instead of
  // snapping into place.
  Timer {
    id: confirmHoldTimer
    interval: 850
    repeat: false
    onTriggered: {
      if (root.confirmedRemoval) root.confirmedRemoval = Object.assign({}, root.confirmedRemoval, { collapsing: true })
      confirmCollapseTimer.restart()
    }
  }

  Timer {
    id: confirmCollapseTimer
    interval: 150
    repeat: false
    onTriggered: root.confirmedRemoval = null
  }

  Connections {
    target: root.service
    function onActionCompleted(action, name, success) {
      if (action === "trash") {
        if (success && root._trashingEntry && root._trashingEntry.name === name) {
          root.confirmedRemoval = { entry: root._trashingEntry, index: root._trashingIndex, collapsing: false }
          confirmHoldTimer.restart()
        }
        root._trashingEntry = null
        return
      }
      if (!success) return
      var text = Model.actionToastMessage(action, name)
      if (text === "") return
      root.toastMessage = text
      toastTimer.restart()
    }
  }

  readonly property var visibleEntries: {
    if (!service) return []
    var filtered = Model.filterEntries(query, service.entries)
    var list = query.trim() === "" ? filtered.slice(0, recentCount) : filtered
    if (!confirmedRemoval) return list
    var ghost = Object.assign({}, confirmedRemoval.entry, { confirmed: true, collapsing: confirmedRemoval.collapsing === true })
    return Model.withGhostEntry(list, ghost, confirmedRemoval.index)
  }

  onVisibleEntriesChanged: if (cursor >= visibleEntries.length) cursor = Math.max(0, visibleEntries.length - 1)

  // Settings are injected here, not into the service; forward what it needs.
  function pushSettings() {
    if (!service) return
    service.applyFolderSetting(setting("folder", "~/Downloads"))
    service.badgeOnComplete = setting("badgeOnComplete", true) === true
  }

  // Both hooks are needed: the service binding may already be resolved when
  // this widget completes (no change signal), or resolve later (no onCompleted).
  onServiceChanged: {
    pushSettings()
    if (service) service.registerPanel(root)
  }
  Component.onCompleted: {
    pushSettings()
    if (service) service.registerPanel(root)
  }
  onSettingsChanged: pushSettings()
  Component.onDestruction: if (service) service.unregisterPanel(root)

  onOpenedChanged: {
    if (service) service.anyPanelOpen = opened
    if (opened) {
      query = ""
      cursor = 0
      pendingTrash = null
      toastTimer.stop()
      toastMessage = ""
      confirmHoldTimer.stop()
      confirmCollapseTimer.stop()
      confirmedRemoval = null
      _trashingEntry = null
      Qt.callLater(function () { searchField.forceActiveFocus() })
    }
  }

  function activate(entry) {
    if (!entry || entry.partial === true || entry.confirmed === true || !service) return
    service.openFile(entry.path)
    root.close()
  }

  function requestTrash(entry) {
    if (!entry || entry.confirmed === true || !service) return
    if (confirmTrash) {
      pendingTrash = entry
    } else {
      _trashingEntry = entry
      _trashingIndex = visibleEntries.findIndex(function (e) { return e.path === entry.path })
      service.trashFile(entry.path)
    }
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  // --------------------------------------------------------------- bar icon
  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    iconComponent: Component {
      Item {
        Text {
          anchors.centerIn: parent
          text: "󰇚"
          color: (!!root.service && root.service.downloadingCount > 0) ? Color.accent : root.barForeground
          font.family: root.fontFamily
          font.pixelSize: Style.font.icon
        }

        // Completed-download badge, cleared when any panel opens.
        Rectangle {
          visible: !!root.service && root.service.hasNewCompleted
          width: Style.space(7)
          height: Style.space(7)
          radius: width / 2
          color: Color.accent
          anchors.right: parent.right
          anchors.top: parent.top
          anchors.rightMargin: -Style.space(2)
          anchors.topMargin: -Style.space(1)
        }
      }
    }
    tooltipText: "Downloads"
    onPressed: function (buttonCode) {
      if (buttonCode === Qt.LeftButton) root.toggle()
    }
  }

  // ---------------------------------------------------------------- popout
  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: searchField
    contentWidth: panel.fittedContentWidth(Style.space(400))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(560))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: searchField.activeFocus || root.pendingTrash !== null
      onCloseRequested: root.close()
      onTabRequested: function (direction) { root.switchPanel(direction) }

      Column {
        id: column
        width: parent.width
        spacing: Style.space(12)

        // ---------------------------------------------------------- hero
        PanelHero {
          width: parent.width
          title: "Downloads"
          meta: root.service
            ? Model.humanSize(root.service.totalBytes) + " total · " + root.service.totalCount +
              (root.service.totalCount === 1 ? " file" : " files") +
              (root.service.downloadingCount > 0 ? " · " + root.service.downloadingCount + " downloading" : "")
            : "Loading…"
          foreground: root.foreground
          fontFamily: root.fontFamily

          iconComponent: Component {
            Text {
              text: "󰇚"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.display
            }
          }

          trailingControl: Component {
            Button {
              text: "Open"
              tooltipText: "Open the folder in the file manager"
              foreground: root.foreground
              fontFamily: root.fontFamily
              bordered: true
              onClicked: {
                if (root.service) root.service.openFolder()
                root.close()
              }
            }
          }
        }

        // -------------------------------------------------------- search
        TextField {
          id: searchField
          width: parent.width
          placeholderText: "Search downloads…"
          foreground: root.foreground
          text: root.query
          onTextChanged: {
            root.query = text
            root.cursor = 0
          }
          Keys.onPressed: function (event) {
            if (root.pendingTrash !== null) {
              if (confirmDialog.handleKey(event)) { event.accepted = true }
              return
            }
            if (event.key === Qt.Key_Down) {
              root.cursor = Math.min(root.cursor + 1, root.visibleEntries.length - 1)
              event.accepted = true
            } else if (event.key === Qt.Key_Up) {
              root.cursor = Math.max(root.cursor - 1, 0)
              event.accepted = true
            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
              root.activate(root.visibleEntries[root.cursor])
              event.accepted = true
            } else if (event.key === Qt.Key_Escape) {
              if (root.query !== "") { root.query = "" } else { root.close() }
              event.accepted = true
            } else if (event.key === Qt.Key_Delete) {
              root.requestTrash(root.visibleEntries[root.cursor])
              event.accepted = true
            }
          }
        }

        Text {
          visible: !!root.service && root.service.lastError !== ""
          width: parent.width
          text: root.service ? root.service.lastError : ""
          color: root.urgent
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.WordWrap
        }

        PanelSeparator { foreground: root.foreground }

        // ---------------------------------------------------------- list
        Column {
          width: parent.width
          spacing: Style.space(2)

          Repeater {
            model: root.visibleEntries
            Item {
              id: rowSlot
              required property var modelData
              required property int index
              width: parent.width
              height: {
                if (modelData.confirmed !== true) return Style.space(44)
                if (modelData.collapsing === true) return 0
                return Math.max(Style.space(44), confirmText.implicitHeight + Style.space(16))
              }
              clip: true

              Behavior on height {
                NumberAnimation { duration: 150; easing.type: Easing.InQuad }
              }

              FileRow {
                anchors.fill: parent
                visible: rowSlot.modelData.confirmed !== true
                entry: rowSlot.modelData
                selected: rowSlot.index === root.cursor
                foreground: root.foreground
                accent: Color.accent
                fontFamily: root.fontFamily
                onHoveredRow: root.cursor = rowSlot.index
                onOpenRequested: root.activate(rowSlot.modelData)
                onRevealRequested: if (root.service) root.service.revealFile(rowSlot.modelData.path)
                onCopyRequested: if (root.service) root.service.copyFile(rowSlot.modelData.path)
                onTrashRequested: root.requestTrash(rowSlot.modelData)
              }

              // Inline confirmation: the row itself becomes the toast for
              // the file it just lost, instead of a page-level banner.
              Rectangle {
                anchors.fill: parent
                visible: rowSlot.modelData.confirmed === true
                clip: true
                radius: Style.space(6)
                color: Util.alpha(Color.accent, 0.15)
                border.color: Color.accent
                border.width: 1

                Text {
                  id: confirmText
                  anchors.left: parent.left
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  anchors.leftMargin: Style.space(12)
                  anchors.rightMargin: Style.space(12)
                  text: "✓ " + Model.actionToastMessage("trash", rowSlot.modelData.name)
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  wrapMode: Text.WordWrap
                  horizontalAlignment: Text.AlignLeft
                }
              }
            }
          }

          Text {
            visible: root.visibleEntries.length === 0
            width: parent.width
            topPadding: Style.space(14)
            bottomPadding: Style.space(14)
            text: {
              if (!root.service) return "Loading…"
              if (root.query.trim() !== "") return "No matches for \"" + root.query + "\""
              return "No downloads yet"
            }
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            horizontalAlignment: Text.AlignHCenter
          }
        }

        // --------------------------------------------------------- toast
        Rectangle {
          id: toastBanner
          readonly property int horizontalPadding: Style.space(12)
          width: parent.width
          height: root.toastMessage !== "" ? implicitHeight : 0
          implicitHeight: toastText.implicitHeight + Style.space(16)
          clip: true
          radius: Style.space(6)
          color: Util.alpha(Color.accent, 0.15)
          border.color: Color.accent
          border.width: 1
          visible: height > 0

          Behavior on height {
            NumberAnimation { duration: 150; easing.type: Easing.OutQuad }
          }

          Text {
            id: toastText
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: toastBanner.horizontalPadding
            anchors.rightMargin: toastBanner.horizontalPadding
            text: "✓ " + root.toastMessage
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
            horizontalAlignment: Text.AlignLeft
          }
        }
      }

      // ------------------------------------------------- trash confirm
      ConfirmDialog {
        id: confirmDialog
        anchors.fill: parent
        opened: root.pendingTrash !== null
        message: root.pendingTrash
          ? "Move \"" + Model.elideMiddle(root.pendingTrash.name, 40) + "\" to the trash?"
          : ""
        confirmText: "Trash"
        fontFamily: root.fontFamily
        onCanceled: root.pendingTrash = null
        onConfirmed: {
          if (root.service && root.pendingTrash) {
            root._trashingEntry = root.pendingTrash
            root._trashingIndex = root.visibleEntries.findIndex(function (e) { return e.path === root.pendingTrash.path })
            root.service.trashFile(root.pendingTrash.path)
          }
          root.pendingTrash = null
        }
      }
    }
  }
}

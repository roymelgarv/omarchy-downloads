import QtQuick
import QtQuick.Controls
import Quickshell
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Bar widget + popout for Downloads, following the keyboard-cleaner layout: a
// qs.Ui Panel root owning the bar button and the KeyboardPanel popout, with all
// folder state read from the singleton service. The panel's own layout stays
// here; only self-contained pieces (FileRow, ActionToast) are separate files.
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
  // The single definition of the panel's muted tone; passed down to children
  // rather than re-derived by each of them.
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  // Clamped to the manifest schema's declared min/max: the shell hands back
  // whatever value is stored without re-validating it against the schema.
  readonly property int recentCount: {
    var n = Number(setting("recentCount", 7))
    if (!isFinite(n)) n = 7
    return Math.max(3, Math.min(15, Math.round(n)))
  }
  // `=== true` for the same reason: setting() hands back the raw stored value,
  // and QML would coerce the string "false" to a true bool.
  readonly property bool confirmTrash: setting("confirmTrash", true) === true

  // The list scrolls rather than growing past the card's height cap. Deriving
  // the row count from the cap and the chrome above the list keeps it correct
  // if either changes, instead of restating today's answer as a constant.
  readonly property real cardHeightCap: Style.space(560)
  // Hero, totals line, separator, search field, section header, Column spacings.
  readonly property real listChromeHeight: Style.space(184)
  // Must match FileRow's implicitHeight.
  readonly property real rowHeight: Style.space(44)
  readonly property real rowSpacing: Style.space(2)
  readonly property int maxVisibleRows:
    Math.max(3, Math.floor((cardHeightCap - listChromeHeight + rowSpacing) / (rowHeight + rowSpacing)))
  readonly property real maxListHeight:
    rowHeight * maxVisibleRows + rowSpacing * (maxVisibleRows - 1)

  property string query: ""
  property int cursor: 0
  property var pendingTrash: null

  Connections {
    target: root.service
    function onActionCompleted(action, name, success) {
      if (!success) return
      toast.show(Model.actionToastMessage(action, name))
    }
  }

  readonly property var visibleEntries:
    service ? Model.visibleEntries(query, service.entries, recentCount) : []

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
    if (opened) {
      query = ""
      cursor = 0
      pendingTrash = null
      toast.clear()
      Qt.callLater(function () { searchField.forceActiveFocus() })
    }
  }

  function activate(entry) {
    if (!entry || entry.partial === true || !service) return
    service.openFile(entry.path)
    root.close()
  }

  function requestTrash(entry) {
    if (!entry || !service) return
    if (confirmTrash) pendingTrash = entry
    else service.trashFile(entry.path)
  }

  // Delete reaches this handler before the search field's own editing, so
  // claiming it unconditionally would make forward-delete impossible while
  // typing a query — and with "Confirm before trashing" off, a mistyped
  // correction would trash a file outright. Plain Delete therefore only
  // trashes while the query is empty (the list is being navigated, not
  // edited); Shift+Delete always does, for use mid-search.
  function trashShortcutApplies(event) {
    return (event.modifiers & Qt.ShiftModifier) || query === ""
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    iconComponent: Component {
      Item {
        Text {
          id: iconText
          anchors.centerIn: parent
          text: "󰇚"
          color: (!!root.service && root.service.downloadingCount > 0) ? Color.accent : root.barForeground
          font.family: root.fontFamily
          font.pixelSize: Style.font.icon

          SequentialAnimation {
            id: pulseAnim
            running: !!root.service && root.service.downloadingCount > 0
            loops: Animation.Infinite
            onRunningChanged: if (!running) iconText.opacity = 1.0

            NumberAnimation { target: iconText; property: "opacity"; from: 1.0; to: 0.35; duration: 600; easing.type: Easing.InOutQuad }
            NumberAnimation { target: iconText; property: "opacity"; from: 0.35; to: 1.0; duration: 600; easing.type: Easing.InOutQuad }
          }
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

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: searchField
    contentWidth: panel.fittedContentWidth(Style.space(400))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, root.cardHeightCap)

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

        // Built manually rather than via PanelHero: its icon only centers
        // against its own title+meta pairing, not against a hero that also
        // includes an Open button, so the icon and both lines of text are
        // laid out here directly, icon centered against the title+status
        // pair as a whole.
        Item {
          width: parent.width
          implicitHeight: Math.max(heroIcon.implicitHeight, heroLabels.implicitHeight, openButton.implicitHeight)

          Text {
            id: heroIcon
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: "󰇚"
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.display
          }

          Column {
            id: heroLabels
            anchors.left: heroIcon.right
            anchors.leftMargin: Style.space(14)
            anchors.right: openButton.left
            anchors.rightMargin: Style.space(12)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(2)

            Text {
              width: parent.width
              text: "Downloads"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
              font.bold: true
              elide: Text.ElideRight
            }

            Text {
              visible: !!root.service
              width: parent.width
              text: (root.service && root.service.downloadingCount > 0 ? "Downloading files" : "No current downloads").toUpperCase()
              color: root.service && root.service.downloadingCount > 0 ? Color.accent : root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
              font.letterSpacing: 1.2
              elide: Text.ElideRight
            }
          }

          Button {
            id: openButton
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
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

        Text {
          visible: !!root.service
          width: parent.width
          text: root.service
            ? Model.humanSize(root.service.totalBytes) + " total · " + root.service.totalCount +
              (root.service.totalCount === 1 ? " file" : " files")
            : "Loading…"
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          font.bold: true
          elide: Text.ElideRight
        }

        PanelSeparator { foreground: root.foreground }

        TextField {
          id: searchField
          width: parent.width
          placeholderText: "Search downloads…"
          foreground: root.foreground
          text: root.query
          onTextChanged: {
            root.query = text
            root.cursor = 0
            // Reset scroll on a new query specifically, not on every
            // visibleEntries recompute — the folder watcher republishes the
            // list on any file change, which would yank a scrolled list back
            // to the top while the user is reading it.
            fileList.positionViewAtBeginning()
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
            } else if (event.key === Qt.Key_Delete && root.trashShortcutApplies(event)) {
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

        Column {
          width: parent.width
          spacing: Style.space(2)

          Text {
            visible: root.query.trim() === "" && root.visibleEntries.length > 0
            width: parent.width
            bottomPadding: Style.space(4)
            text: "Recent downloads".toUpperCase()
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            font.bold: true
          }

          // A ListView rather than a Repeater because search ignores
          // recentCount and returns every match: a Column of unbounded height
          // is silently cut off by the card's height cap, leaving matches
          // unreachable by mouse *and* keyboard. Capping the view's height
          // makes the overflow scroll, and ListView's positionViewAtIndex is
          // what keeps the keyboard cursor inside the viewport.
          ListView {
            id: fileList
            width: parent.width
            height: Math.min(contentHeight, root.maxListHeight)
            spacing: root.rowSpacing
            clip: true
            // Rubber-band overscroll reads as a glitch in a small popout card.
            boundsBehavior: Flickable.StopAtBounds
            model: root.visibleEntries
            currentIndex: root.cursor
            // ListView.Contain scrolls only when the row is actually outside
            // the viewport, so arrowing within view doesn't jump the list.
            onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Contain)

            delegate: FileRow {
              required property var modelData
              required property int index
              // A delegate's parent is the internal content item, not the
              // view, so parent.width would be wrong here.
              width: ListView.view.width
              entry: modelData
              selected: index === root.cursor
              foreground: root.foreground
              dim: root.dim
              accent: Color.accent
              fontFamily: root.fontFamily
              onHoveredRow: root.cursor = index
              onOpenRequested: root.activate(modelData)
              onRevealRequested: if (root.service) root.service.revealFile(modelData.path)
              onCopyRequested: if (root.service) root.service.copyFile(modelData.path)
              onTrashRequested: root.requestTrash(modelData)
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

        ActionToast {
          id: toast
          width: parent.width
          foreground: root.foreground
          fontFamily: root.fontFamily
        }
      }

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
          if (root.service && root.pendingTrash) root.service.trashFile(root.pendingTrash.path)
          root.pendingTrash = null
        }
      }
    }
  }
}

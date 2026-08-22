import QtQuick
import qs.Commons
import qs.Ui
import "Model.js" as Model

Item {
  id: root

  property var entry: ({})       // {name, path, size, mtime, partial, stalled}
  property bool selected: false
  property color foreground: Color.foreground
  // The panel derives its own dim tone from the bar's foreground and passes it
  // in; the theme's muted color is only the standalone fallback, so the
  // derivation lives in exactly one place (BarWidget).
  property color dim: Color.muted
  property color accent: Color.accent
  property string fontFamily: Style.font.family

  signal openRequested()
  signal revealRequested()
  signal copyRequested()
  signal trashRequested()

  readonly property string ext: Model.extOf(entry.name || "")
  readonly property bool isImage: Model.isImageExt(ext)
  // Qt Quick only delivers hover to the topmost item at the pointer, so
  // hovering a button would otherwise drop the row's own containsMouse and
  // hide the buttons (visible: root.hot && …) mid-hover. Each button's own
  // hovered() signal keeps the row "hot" across itself and all its buttons.
  readonly property bool hot: mouse.containsMouse || selected || _revealHovered || _copyHovered || _trashHovered
  property bool _revealHovered: false
  property bool _copyHovered: false
  property bool _trashHovered: false
  // A stalled partial (its bytes stopped arriving — an aborted/failed
  // download, not just a slow one) is treated like any other file: it keeps
  // its .part/.crdownload name, but the row becomes actionable so it can be
  // cleaned up. An actively-downloading partial stays fully non-actionable.
  readonly property bool activelyDownloading: entry.partial === true && entry.stalled !== true
  readonly property bool stalled: entry.partial === true && entry.stalled === true
  readonly property bool actionable: !root.activelyDownloading
  // Copy hands the file's current on-disk bytes to the clipboard; for a
  // stalled/truncated partial that's a corrupt artifact masquerading as the
  // finished file, a materially different failure mode than reveal or trash.
  readonly property bool copyable: root.actionable && !root.stalled

  implicitHeight: Style.space(44)

  // Cycles 1/2/3 trailing dots on "downloading" while active. A Timer, not a
  // RotationAnimator/NumberAnimation: Qt Quick pauses its per-window
  // animation driver while the popout is closed (reproduced live — a
  // RotationAnimator-driven spinner froze mid-rotation on close and stayed
  // frozen after reopening until some unrelated repaint happened to kick it).
  // A Timer runs on the normal event loop regardless of window visibility, so
  // this always shows the right dot count the instant the panel reopens.
  property int _downloadingDots: 1
  Timer {
    interval: 500
    repeat: true
    running: root.activelyDownloading
    onTriggered: root._downloadingDots = (root._downloadingDots % 3) + 1
    onRunningChanged: if (!running) root._downloadingDots = 1
  }

  Rectangle {
    anchors.fill: parent
    radius: Style.cornerRadius
    color: root.hot ? Util.alpha(root.foreground, 0.08) : "transparent"
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: root.actionable ? Qt.PointingHandCursor : Qt.ArrowCursor
    onClicked: if (root.actionable) root.openRequested()
  }

  Row {
    id: contentRow
    anchors.left: parent.left
    anchors.right: actions.left
    anchors.leftMargin: Style.space(8)
    anchors.rightMargin: Style.space(8)
    anchors.verticalCenter: parent.verticalCenter
    spacing: Style.space(10)

    readonly property int thumbSize: Style.space(30)

    Item {
      width: contentRow.thumbSize
      height: contentRow.thumbSize
      anchors.verticalCenter: parent.verticalCenter

      Image {
        id: thumbImage
        anchors.fill: parent
        visible: root.isImage && status === Image.Ready
        // Qt.resolvedUrl percent-encodes as needed: a "#" or literal "%" in
        // the filename ("screenshot #3.png") is not valid in a bare file URL.
        source: root.isImage && root.entry.path ? Qt.resolvedUrl(root.entry.path) : ""
        sourceSize.width: 60
        sourceSize.height: 60
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        // Thumbnails are re-requested on every resync (every 2s while a
        // download is in flight) because `entries` is reassigned wholesale;
        // caching avoids re-decoding images that haven't changed on disk.
        cache: true
      }

      Text {
        anchors.centerIn: parent
        visible: !root.isImage || thumbImage.status !== Image.Ready
        text: root.entry.partial === true ? "󰇚" : "󰈔"
        color: root.activelyDownloading ? root.accent : (root.stalled ? Color.urgent : root.dim)
        font.family: root.fontFamily
        font.pixelSize: Style.font.iconLarge
      }
    }

    Column {
      // Room left after the thumbnail/glyph and the one gap Row's spacing
      // puts between its two children, rather than a magic number that
      // silently re-encodes those two values.
      width: parent.width - contentRow.thumbSize - contentRow.spacing
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(2)

      Text {
        width: parent.width
        text: Model.baseName(root.entry.name || "")
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        elide: Text.ElideMiddle
      }

      Text {
        width: parent.width
        text: {
          if (root.activelyDownloading) return "downloading" + "...".slice(0, root._downloadingDots)
          if (root.stalled) return "Stalled — download incomplete"
          var sizeText = Model.humanSize(root.entry.size)
          return root.ext !== "" ? sizeText + " · ." + root.ext.toUpperCase() : sizeText
        }
        color: root.activelyDownloading ? root.accent : (root.stalled ? Color.urgent : root.dim)
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
      }
    }
  }

  Row {
    id: actions
    anchors.right: parent.right
    anchors.rightMargin: Style.space(6)
    anchors.verticalCenter: parent.verticalCenter
    spacing: Style.space(2)

    PanelActionButton {
      visible: root.hot && root.actionable
      anchors.verticalCenter: parent.verticalCenter
      iconText: "󰉋"
      tooltipText: "Show in file manager"
      foreground: root.foreground
      fontFamily: root.fontFamily
      onClicked: root.revealRequested()
      onHovered: function (isHovered) { root._revealHovered = isHovered }
    }

    PanelActionButton {
      visible: root.hot && root.copyable
      anchors.verticalCenter: parent.verticalCenter
      iconText: "󰆏"
      tooltipText: "Copy file"
      foreground: root.foreground
      fontFamily: root.fontFamily
      onClicked: root.copyRequested()
      onHovered: function (isHovered) { root._copyHovered = isHovered }
    }

    PanelActionButton {
      visible: root.hot && root.actionable
      anchors.verticalCenter: parent.verticalCenter
      iconText: "󰩹"
      tooltipText: "Move to trash"
      foreground: root.foreground
      hoverColor: Color.urgent
      fontFamily: root.fontFamily
      onClicked: root.trashRequested()
      onHovered: function (isHovered) { root._trashHovered = isHovered }
    }
  }
}

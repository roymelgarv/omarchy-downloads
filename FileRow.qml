import QtQuick
import qs.Commons
import qs.Ui
import "Model.js" as Model

Item {
  id: root

  property var entry: ({})       // {name, path, size, mtime, partial}
  property bool selected: false
  property color foreground: Color.foreground
  // Has a live default so standalone use works, but a caller that already
  // computed a dim color should pass it down instead — keeps the
  // Qt.darker() formula in one place.
  property color dim: Qt.darker(foreground, 1.55)
  property color accent: Color.accent
  property string fontFamily: Style.font.family

  signal openRequested()
  signal revealRequested()
  signal copyRequested()
  signal trashRequested()
  signal hoveredRow()

  readonly property string ext: Model.extOf(entry.name || "")
  readonly property bool isImage: Model.isImageExt(ext)
  readonly property bool hot: mouse.containsMouse || selected
  readonly property bool actionable: !(entry.partial === true)

  implicitHeight: Style.space(44)

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
    onEntered: root.hoveredRow()
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
        // Qt.resolvedUrl percent-encodes as needed; string concatenation
        // left "#" truncating the path at a bogus URL fragment and left "%"
        // ambiguous with percent-encoding, both plausible in a downloaded
        // filename (e.g. "screenshot #3.png").
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
        color: root.entry.partial === true ? root.accent : root.dim
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
          if (root.entry.partial === true) return "downloading…"
          var sizeText = Model.humanSize(root.entry.size)
          return root.ext !== "" ? sizeText + " · ." + root.ext.toUpperCase() : sizeText
        }
        color: root.entry.partial === true ? root.accent : root.dim
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

    Text {
      visible: root.entry.partial === true
      anchors.verticalCenter: parent.verticalCenter
      text: "󱥸"
      color: root.accent
      font.family: root.fontFamily
      font.pixelSize: Style.font.icon

      RotationAnimator on rotation {
        running: root.entry.partial === true
        from: 0
        to: 360
        duration: 800
        loops: Animation.Infinite
      }
    }

    PanelActionButton {
      visible: root.hot && root.actionable
      anchors.verticalCenter: parent.verticalCenter
      iconText: "󰉋"
      tooltipText: "Show in file manager"
      foreground: root.foreground
      fontFamily: root.fontFamily
      onClicked: root.revealRequested()
    }

    PanelActionButton {
      visible: root.hot && root.actionable
      anchors.verticalCenter: parent.verticalCenter
      iconText: "󰆏"
      tooltipText: "Copy file"
      foreground: root.foreground
      fontFamily: root.fontFamily
      onClicked: root.copyRequested()
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
    }
  }
}

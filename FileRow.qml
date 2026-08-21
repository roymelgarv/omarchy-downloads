import QtQuick
import qs.Commons
import qs.Ui
import "Model.js" as Model

// One downloads-list row: thumbnail (images) or type glyph, name with its
// size and type below it, and hover/selection-revealed quick actions.
Item {
  id: root

  property var entry: ({})       // {name, path, size, mtime, partial}
  property bool selected: false
  property color foreground: Color.foreground
  property color accent: Color.accent
  property string fontFamily: Style.font.family

  signal openRequested()
  signal revealRequested()
  signal copyRequested()
  signal trashRequested()
  signal hoveredRow()

  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string ext: Model.extOf(entry.name || "")
  readonly property bool isImage: ["jpg", "jpeg", "png", "gif", "webp", "bmp", "svg", "avif"].indexOf(ext) !== -1
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
    anchors.left: parent.left
    anchors.right: actions.left
    anchors.leftMargin: Style.space(8)
    anchors.rightMargin: Style.space(8)
    anchors.verticalCenter: parent.verticalCenter
    spacing: Style.space(10)

    // Thumbnail for images, glyph for everything else.
    Item {
      width: Style.space(30)
      height: Style.space(30)
      anchors.verticalCenter: parent.verticalCenter

      Image {
        anchors.fill: parent
        visible: root.isImage && status === Image.Ready
        source: root.isImage ? "file://" + (root.entry.path || "") : ""
        sourceSize.width: 60
        sourceSize.height: 60
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: false
      }

      Text {
        anchors.centerIn: parent
        visible: !root.isImage || parent.children[0].status !== Image.Ready
        text: root.entry.partial === true ? "󰇚" : "󰈔"
        color: root.entry.partial === true ? root.accent : root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.iconLarge
      }
    }

    Column {
      width: parent.width - Style.space(40)
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
          var sizeText = Model.humanSize(root.entry.size)
          if (root.entry.partial === true) return "downloading… · " + sizeText
          return root.ext !== "" ? sizeText + " | ." + root.ext.toUpperCase() : sizeText
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

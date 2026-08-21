import QtQuick
import qs.Commons
import qs.Ui
import "Model.js" as Model

// One downloads-list row: thumbnail (images) or type glyph, name with its
// type + size below it, and hover/selection-revealed quick actions.
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
  readonly property bool showTypeChip: entry.partial !== true && ext !== ""

  implicitHeight: Math.max(Style.space(44), metaColumn.implicitHeight + Style.space(16))

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
      id: metaColumn
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
        text: root.entry.partial === true
          ? "downloading… · " + Model.humanSize(root.entry.size)
          : Model.humanSize(root.entry.size)
        color: root.entry.partial === true ? root.accent : root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
      }

      // Type chip on its own line below the size: sharp corners,
      // background/text inverted from the row's own palette so it stays
      // readable across theme switches.
      Rectangle {
        visible: root.showTypeChip
        radius: 0
        color: root.foreground
        width: chipText.implicitWidth + Style.space(8)
        height: chipText.implicitHeight + Style.space(2)

        Text {
          id: chipText
          anchors.centerIn: parent
          text: "." + root.ext
          color: Color.background
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
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

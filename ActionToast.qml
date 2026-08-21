import QtQuick
import qs.Commons
import qs.Ui

// Transient confirmation banner shown under the file list after a copy or
// trash completes. Collapses to zero height when empty so the card shrinks
// back rather than leaving a gap.
Item {
  id: root

  property color foreground: Color.foreground
  property string fontFamily: Style.font.family
  property int visibleFor: 2500

  readonly property string message: _message
  property string _message: ""

  readonly property int horizontalPadding: Style.space(12)
  readonly property int bottomMargin: Style.space(10)

  function show(text) {
    if (!text) return
    _message = text
    timer.restart()
  }

  function clear() {
    timer.stop()
    _message = ""
  }

  height: _message !== "" ? (box.implicitHeight + root.bottomMargin) : 0
  visible: height > 0

  Behavior on height {
    NumberAnimation { duration: 150; easing.type: Easing.OutQuad }
  }

  Timer {
    id: timer
    interval: root.visibleFor
    repeat: false
    onTriggered: root._message = ""
  }

  Rectangle {
    id: box
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    implicitHeight: label.implicitHeight
    clip: true
    radius: Style.space(6)
    color: Util.alpha(Color.accent, 0.15)
    border.color: Color.accent
    border.width: 1

    Text {
      id: label
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.leftMargin: root.horizontalPadding
      anchors.rightMargin: root.horizontalPadding
      topPadding: Style.space(8)
      bottomPadding: Style.space(8)
      text: "✓ " + root._message
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
      wrapMode: Text.WordWrap
      horizontalAlignment: Text.AlignLeft
    }
  }
}

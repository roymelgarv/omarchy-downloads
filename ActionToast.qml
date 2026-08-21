import QtQuick
import qs.Commons
import qs.Ui

// Transient confirmation banner shown under the file list after a copy or
// trash completes. Collapses to zero height when empty so the card shrinks
// back rather than leaving a gap.
Rectangle {
  id: root

  property color foreground: Color.foreground
  property string fontFamily: Style.font.family
  property int visibleFor: 2500

  readonly property string message: _message
  property string _message: ""

  readonly property int horizontalPadding: Style.space(12)

  function show(text) {
    if (!text) return
    _message = text
    timer.restart()
  }

  function clear() {
    timer.stop()
    _message = ""
  }

  height: _message !== "" ? implicitHeight : 0
  implicitHeight: label.implicitHeight + Style.space(16)
  visible: height > 0
  clip: true
  radius: Style.space(6)
  color: Util.alpha(Color.accent, 0.15)
  border.color: Color.accent
  border.width: 1

  Behavior on height {
    NumberAnimation { duration: 150; easing.type: Easing.OutQuad }
  }

  Timer {
    id: timer
    interval: root.visibleFor
    repeat: false
    onTriggered: root._message = ""
  }

  Text {
    id: label
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    anchors.leftMargin: root.horizontalPadding
    anchors.rightMargin: root.horizontalPadding
    text: "✓ " + root._message
    color: root.foreground
    font.family: root.fontFamily
    font.pixelSize: Style.font.bodySmall
    wrapMode: Text.WordWrap
    horizontalAlignment: Text.AlignLeft
  }
}

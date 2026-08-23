import QtQuick
import qs.Commons
import qs.Ui

// Transient confirmation banner shown under the file list after a copy or
// trash completes. Collapses to zero height when empty so the card shrinks
// back rather than leaving a gap.
//
// No bottom margin of its own: as the Column's last child it sits directly on
// the card's own popupPadding, which is what gives every other element its
// inset. Adding a margin here would inset the toast further from the card edge
// than the list is from the sides.
Rectangle {
  id: root

  property color foreground: Color.foreground
  property string fontFamily: Style.font.family
  property int visibleFor: 2500

  readonly property string message: _message
  property string _message: ""

  // One value for all four sides so the text sits symmetrically in the box.
  readonly property int contentPadding: Style.space(14)

  function show(text) {
    if (!text) return
    _message = text
    timer.restart()
  }

  function clear() {
    timer.stop()
    _message = ""
  }

  // Driven by the text's own height rather than a fixed row height so a
  // wrapped two-line message still gets even padding above and below.
  implicitHeight: label.implicitHeight
  height: _message !== "" ? implicitHeight : 0
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

  // Anchored to the top, not vertically centred: while the collapse animation
  // runs the banner's height is between 0 and implicitHeight, and centring
  // would slide the text through the shrinking box instead of clipping it.
  Text {
    id: label
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.leftMargin: root.contentPadding
    anchors.rightMargin: root.contentPadding
    topPadding: root.contentPadding
    bottomPadding: root.contentPadding
    text: "✓ " + root._message
    // root._message embeds a filesystem-controlled file name (see
    // Model.actionToastMessage) — force plain text so a crafted name can't
    // get promoted to RichText by Text's default AutoText.
    textFormat: Text.PlainText
    color: root.foreground
    font.family: root.fontFamily
    font.pixelSize: Style.font.bodySmall
    // Text.Wrap, not WordWrap: file names are often one unbroken "word"
    // wider than the banner, and WordWrap lets those overflow past the
    // padding into the border instead of breaking mid-name.
    wrapMode: Text.Wrap
    horizontalAlignment: Text.AlignLeft
  }
}

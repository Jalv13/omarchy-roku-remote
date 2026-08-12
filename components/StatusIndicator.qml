import QtQuick
import qs.Commons

Row {
  id: root

  property string state: "none"
  property string message: "No Roku found"
  property color foreground: Color.popups.text

  spacing: Style.spacing.sm

  Rectangle {
    width: Style.space(7)
    height: width
    radius: width / 2
    anchors.verticalCenter: parent.verticalCenter
    color: root.state === "connected"
      ? Color.accent
      : root.state === "offline"
        ? Color.urgent
        : Color.muted

    SequentialAnimation on opacity {
      running: root.state === "searching"
      loops: Animation.Infinite
      NumberAnimation { to: 0.35; duration: 500 }
      NumberAnimation { to: 1; duration: 500 }
    }
  }

  Text {
    text: root.message
    textFormat: Text.PlainText
    color: root.state === "offline" ? Color.urgent : root.foreground
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
    anchors.verticalCenter: parent.verticalCenter
  }
}

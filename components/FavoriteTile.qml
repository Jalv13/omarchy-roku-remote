import QtQuick
import qs.Commons
import qs.Ui

BorderSurface {
  id: root

  required property var favorite
  property bool managing: false
  property string iconBaseUrl: ""
  property bool showIcon: true
  property color foreground: Color.popups.text

  signal triggered()

  readonly property bool channel: String(favorite.kind || "") === "channel"
  readonly property bool artworkVisible: channel || showIcon
  readonly property bool down: pointer.pressed
  readonly property bool hot: hover.hovered || activeFocus

  implicitHeight: artworkVisible ? Style.space(98) : Style.space(42)
  radius: Style.cornerRadius
  activeFocusOnTab: enabled
  opacity: enabled ? 1 : 0.38
  color: down
    ? Style.pressedFillFor(foreground, Color.accent)
    : hot
      ? Style.hoverFillFor(foreground, Color.accent)
      : Style.normalFillFor(foreground, Color.accent)
  borderSpec: activeFocus
    ? Border.controlSpec("focus", foreground, Color.accent)
    : Border.controlSpec(hot ? "hover-cursor" : "normal", foreground, Color.accent)

  Accessible.role: Accessible.Button
  Accessible.name: managing
    ? "Remove " + String(favorite.name || favorite.id || "favorite")
    : "Open " + String(favorite.name || favorite.id || "favorite")
  Accessible.onPressAction: if (root.enabled) root.triggered()

  Item {
    anchors.fill: parent
    anchors.margins: Style.spacing.sm

    Rectangle {
      id: artwork
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      height: root.artworkVisible ? Style.space(58) : 0
      visible: root.artworkVisible
      radius: Math.max(1, Style.cornerRadius - Style.spacing.sm)
      color: root.channel ? Util.alpha(Color.accent, 0.20) : Util.alpha(root.foreground, 0.06)
      clip: true

      Image {
        id: appIcon
        anchors.fill: parent
        anchors.margins: Style.spacing.md
        visible: root.showIcon && !root.channel && status !== Image.Error
        source: visible && root.iconBaseUrl
          ? root.iconBaseUrl + encodeURIComponent(String(root.favorite.id || "")) : ""
        fillMode: Image.PreserveAspectFit
        asynchronous: true
        cache: true
      }

      Column {
        anchors.centerIn: parent
        visible: root.channel || appIcon.status === Image.Error || !root.iconBaseUrl
        spacing: 0

        Text {
          anchors.horizontalCenter: parent.horizontalCenter
          text: root.channel ? "TV" : "󰀻"
          textFormat: Text.PlainText
          color: root.foreground
          font.family: Style.font.family
          font.pixelSize: root.channel ? Style.font.caption : Style.font.iconLarge
          font.bold: true
        }

        Text {
          visible: root.channel
          anchors.horizontalCenter: parent.horizontalCenter
          text: String(root.favorite.id || "")
          textFormat: Text.PlainText
          color: root.foreground
          font.family: Style.font.family
          font.pixelSize: Style.font.subtitle
          font.bold: true
        }
      }

      Rectangle {
        visible: root.managing
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.margins: Style.spacing.xs
        width: Style.space(24)
        height: width
        radius: width / 2
        color: Color.urgent

        Text {
          anchors.centerIn: parent
          text: "󰆴"
          textFormat: Text.PlainText
          color: root.foreground
          font.family: Style.font.family
          font.pixelSize: Style.font.icon
        }
      }
    }

    Text {
      anchors.left: parent.left
      anchors.right: parent.right
      y: root.artworkVisible ? artwork.height + Style.spacing.xs : 0
      height: parent.height - y
      text: String(root.favorite.name || root.favorite.id || "Favorite")
      textFormat: Text.PlainText
      color: root.foreground
      font.family: Style.font.family
      font.pixelSize: Style.font.bodySmall
      font.bold: true
      elide: Text.ElideRight
      horizontalAlignment: Text.AlignHCenter
      verticalAlignment: Text.AlignVCenter
    }
  }

  Keys.onPressed: function(event) {
    if (event.isAutoRepeat) return
    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
      root.triggered()
      event.accepted = true
    }
  }

  HoverHandler { id: hover }
  MouseArea {
    id: pointer
    anchors.fill: parent
    enabled: root.enabled
    hoverEnabled: true
    cursorShape: root.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
    onClicked: {
      root.forceActiveFocus()
      root.triggered()
    }
  }

  PanelToolTip {
    visible: hover.hovered
    text: root.managing
      ? "Remove " + String(root.favorite.name || root.favorite.id || "favorite")
      : (root.channel
        ? "Open TV channel " + String(root.favorite.id || "")
        : "Open " + String(root.favorite.name || root.favorite.id || "Roku app"))
  }
}

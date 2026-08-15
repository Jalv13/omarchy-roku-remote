import QtQuick
import qs.Commons

Item {
  id: root

  required property QtObject service
  property bool controlsEnabled: false
  property string highlightedKey: ""

  implicitWidth: Style.space(210)
  implicitHeight: implicitWidth

  function begin(key) { if (root.controlsEnabled) root.service.holdKey(key) }
  function end(key) { root.service.releaseHeldKey(key) }

  Rectangle {
    anchors.centerIn: parent
    width: Style.space(174)
    height: width
    radius: width / 2
    color: Style.normalFillFor(Color.popups.text, Color.accent)
  }

  RemoteButton {
    id: upButton
    width: Style.space(70)
    height: Style.space(54)
    anchors.top: parent.top
    anchors.horizontalCenter: parent.horizontalCenter
    iconText: "󰁝"
    iconSize: Style.font.iconLarge
    holdable: true
    accessibleName: "Up"
    tooltipText: "Hold for continuous Up"
    enabled: root.controlsEnabled
    keyboardPressed: root.highlightedKey === "Up"
    onControlPressed: root.begin("Up")
    onControlReleased: root.end("Up")
  }

  RemoteButton {
    id: leftButton
    width: Style.space(54)
    height: Style.space(70)
    anchors.left: parent.left
    anchors.verticalCenter: parent.verticalCenter
    iconText: "󰁍"
    iconSize: Style.font.iconLarge
    holdable: true
    accessibleName: "Left"
    tooltipText: "Hold for continuous Left"
    enabled: root.controlsEnabled
    keyboardPressed: root.highlightedKey === "Left"
    onControlPressed: root.begin("Left")
    onControlReleased: root.end("Left")
  }

  RemoteButton {
    id: rightButton
    width: Style.space(78)
    height: width
    anchors.centerIn: parent
    text: "OK"
    fontSize: Style.font.title
    selected: true
    accessibleName: "Select"
    enabled: root.controlsEnabled
    keyboardPressed: root.highlightedKey === "Select"
    onTriggered: root.service.sendKey("Select")
  }

  RemoteButton {
    width: Style.space(54)
    height: Style.space(70)
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    iconText: "󰁔"
    iconSize: Style.font.iconLarge
    holdable: true
    accessibleName: "Right"
    tooltipText: "Hold for continuous Right"
    enabled: root.controlsEnabled
    keyboardPressed: root.highlightedKey === "Right"
    onControlPressed: root.begin("Right")
    onControlReleased: root.end("Right")
  }

  RemoteButton {
    id: downButton
    width: Style.space(70)
    height: Style.space(54)
    anchors.bottom: parent.bottom
    anchors.horizontalCenter: parent.horizontalCenter
    iconText: "󰁅"
    iconSize: Style.font.iconLarge
    holdable: true
    accessibleName: "Down"
    tooltipText: "Hold for continuous Down"
    enabled: root.controlsEnabled
    keyboardPressed: root.highlightedKey === "Down"
    onControlPressed: root.begin("Down")
    onControlReleased: root.end("Down")
  }
}

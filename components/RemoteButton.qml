import QtQuick
import qs.Commons
import qs.Ui

BorderSurface {
  id: root

  property string text: ""
  property string iconText: ""
  property string accessibleName: text
  property string tooltipText: ""
  property bool selected: false
  property bool holdable: false
  property bool keyboardPressed: false
  property color foreground: Color.popups.text
  property color background: "transparent"
  property color accent: Color.accent
  property real fontSize: Style.font.body
  property real iconSize: Style.font.icon
  property real horizontalPadding: Style.spacing.controlPaddingX
  property real verticalPadding: Style.spacing.controlPaddingY
  property real minimumButtonWidth: Style.space(52)
  property real minimumButtonHeight: Style.space(38)

  signal controlPressed()
  signal controlReleased()
  signal triggered()

  readonly property bool hot: hover.hovered || activeFocus
  readonly property bool down: pointer.pressed || keyboardPressed
  readonly property var focusBorderSpec: Border.controlSpec("focus", foreground, accent)
  readonly property var hoverBorderSpec: Border.controlSpec("hover-cursor", foreground, accent)
  readonly property var normalBorderSpec: Border.controlSpec("normal", foreground, accent)

  implicitWidth: Math.max(minimumButtonWidth, labelRow.implicitWidth + horizontalPadding * 2)
  implicitHeight: Math.max(minimumButtonHeight, labelRow.implicitHeight + verticalPadding * 2)
  radius: Style.cornerRadius
  opacity: enabled ? 1 : 0.38
  activeFocusOnTab: enabled

  color: down
    ? Style.pressedFillFor(foreground, accent)
    : activeFocus
      ? Style.focusFillFor(foreground, accent)
      : hover.hovered
        ? Style.hoverFillFor(foreground, accent)
        : selected
          ? Style.selectedFillFor(foreground, accent)
          : background
  borderSpec: activeFocus ? focusBorderSpec : (hover.hovered ? hoverBorderSpec : normalBorderSpec)

  Behavior on color { ColorAnimation { duration: 100 } }

  Accessible.role: Accessible.Button
  Accessible.name: accessibleName
  Accessible.description: tooltipText
  Accessible.onPressAction: {
    if (!root.enabled) return
    if (root.holdable) {
      root.controlPressed()
      root.controlReleased()
    } else root.triggered()
  }

  Keys.onPressed: function(event) {
    if (!root.enabled || event.isAutoRepeat) return
    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
      root.keyboardPressed = true
      root.controlPressed()
      event.accepted = true
    }
  }
  Keys.onReleased: function(event) {
    if (!root.enabled || event.isAutoRepeat) return
    if (root.keyboardPressed && (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space)) {
      root.keyboardPressed = false
      root.controlReleased()
      if (!root.holdable) root.triggered()
      event.accepted = true
    }
  }

  Row {
    id: labelRow
    anchors.centerIn: parent
    spacing: Style.spacing.controlGap

    Text {
      visible: root.iconText !== ""
      text: root.iconText
      textFormat: Text.PlainText
      color: root.foreground
      font.family: Style.font.family
      font.pixelSize: root.iconSize
      anchors.verticalCenter: parent.verticalCenter
    }

    Text {
      visible: root.text !== ""
      text: root.text
      textFormat: Text.PlainText
      color: root.foreground
      font.family: Style.font.family
      font.pixelSize: root.fontSize
      font.bold: root.selected
      anchors.verticalCenter: parent.verticalCenter
    }
  }

  HoverHandler { id: hover }

  MouseArea {
    id: pointer
    anchors.fill: parent
    enabled: root.enabled
    hoverEnabled: true
    cursorShape: root.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
    onPressed: {
      root.forceActiveFocus()
      root.controlPressed()
    }
    onReleased: root.controlReleased()
    onCanceled: root.controlReleased()
    onClicked: if (!root.holdable) root.triggered()
  }

  PanelToolTip {
    visible: root.tooltipText !== "" && hover.hovered
    text: root.tooltipText
  }
}

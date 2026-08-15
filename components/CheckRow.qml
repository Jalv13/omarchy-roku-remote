import QtQuick
import qs.Commons
import qs.Ui

Item {
  id: root

  property string label: ""
  property string tooltipText: ""
  property bool checked: false
  property color foreground: Color.popups.text

  signal toggled(bool checked)

  implicitHeight: Style.space(28)
  activeFocusOnTab: true

  Accessible.role: Accessible.CheckBox
  Accessible.name: root.label
  Accessible.description: root.tooltipText
  Accessible.checked: root.checked
  Accessible.onToggleAction: root.toggled(!root.checked)

  function toggle() {
    root.toggled(!root.checked)
  }

  Keys.onPressed: function(event) {
    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter
        || event.key === Qt.Key_Space) {
      root.toggle()
      event.accepted = true
    }
  }

  Rectangle {
    id: checkBox
    width: Style.space(18)
    height: width
    anchors.left: parent.left
    anchors.verticalCenter: parent.verticalCenter
    radius: Math.max(1, Style.cornerRadius / 2)
    color: root.checked
      ? Style.selectedFillFor(root.foreground, Color.accent)
      : Style.normalFillFor(root.foreground, Color.accent)
    border.width: Math.max(1, Style.spacing.hairline)
    border.color: root.activeFocus ? Color.accent : Color.muted

    Text {
      anchors.centerIn: parent
      visible: root.checked
      text: "✓"
      textFormat: Text.PlainText
      color: root.foreground
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      font.bold: true
    }
  }

  Text {
    anchors.left: checkBox.right
    anchors.leftMargin: Style.spacing.md
    anchors.verticalCenter: parent.verticalCenter
    text: root.label
    textFormat: Text.PlainText
    color: root.foreground
    font.family: Style.font.family
    font.pixelSize: Style.font.body
  }

  HoverHandler { id: hover }

  MouseArea {
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: {
      root.forceActiveFocus()
      root.toggle()
    }
  }

  PanelToolTip {
    visible: root.tooltipText !== "" && hover.hovered
    text: root.tooltipText
  }
}

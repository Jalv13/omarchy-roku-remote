import QtQuick
import qs.Commons
import qs.Ui

Column {
  id: root

  property var devices: []
  property string selectedIp: ""
  property string statusState: "none"
  property string statusMessage: "No Roku found"
  property bool searching: false
  property color foreground: Color.popups.text
  readonly property bool popupOpen: deviceDropdown.popupOpen

  signal selected(string ip)
  signal refreshRequested()
  signal addRequested()
  signal forgetRequested(string ip)

  spacing: Style.spacing.sm

  function safeUiText(value) {
    return String(value || "").replace(/</g, "‹").replace(/>/g, "›")
  }

  function currentDevice() {
    for (var i = 0; i < devices.length; i++)
      if (String(devices[i].ip) === selectedIp) return devices[i]
    return null
  }

  readonly property var optionsForDevices: {
    var result = []
    for (var i = 0; i < devices.length; i++) {
      var device = devices[i]
      result.push({
        value: String(device.ip),
        label: root.safeUiText(device.name || "Roku") + " — " + String(device.ip)
      })
    }
    return result
  }
  readonly property var selectedDevice: currentDevice()

  Row {
    width: parent.width
    spacing: Style.spacing.md

    Dropdown {
      id: deviceDropdown
      width: parent.width - status.implicitWidth - parent.spacing
      value: root.selectedIp
      options: root.optionsForDevices
      showLabel: false
      foreground: root.foreground
      onChanged: function(value) { root.selected(value) }
    }

    StatusIndicator {
      id: status
      state: root.statusState
      message: root.statusMessage
      foreground: root.foreground
      anchors.verticalCenter: parent.verticalCenter
    }
  }

  Row {
    width: parent.width
    spacing: Style.spacing.md

    Button {
      iconText: "󰑐"
      text: root.searching ? "Searching…" : "Refresh"
      enabled: !root.searching
      focusable: true
      bordered: true
      onClicked: root.refreshRequested()
    }

    Button {
      iconText: "+"
      text: "Add IP"
      focusable: true
      bordered: true
      onClicked: root.addRequested()
    }

    Item { width: Math.max(0, parent.width - Style.space(230)); height: 1 }

    Button {
      visible: root.selectedDevice && root.selectedDevice.manual === true
      iconText: "󰆴"
      tooltipText: "Forget this manually added Roku"
      focusable: true
      onClicked: root.forgetRequested(root.selectedIp)
    }
  }
}

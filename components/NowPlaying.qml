import QtQuick
import qs.Commons
import qs.Ui

BorderSurface {
  id: root

  property bool deviceSelected: false
  property bool controlsEnabled: false
  property bool loading: false
  property string error: ""
  property var statusInfo: null

  signal refreshRequested()

  readonly property var media: statusInfo && statusInfo.media ? statusInfo.media : null
  readonly property var channel: statusInfo && statusInfo.channel ? statusInfo.channel : null

  function playbackLabel(state) {
    var value = String(state || "").toLowerCase()
    if (value === "play") return "Playing"
    if (value === "pause") return "Paused"
    if (value === "buffer") return "Buffering"
    if (value === "close" || value === "none" || value === "unknown") return "Idle"
    return value ? value.charAt(0).toUpperCase() + value.slice(1) : "Idle"
  }

  function mediaTime(value) {
    var match = String(value || "").match(/\d+/)
    if (!match) return ""
    var seconds = Math.max(0, Math.floor(Number(match[0]) / 1000))
    var hours = Math.floor(seconds / 3600)
    var minutes = Math.floor((seconds % 3600) / 60)
    var remainder = seconds % 60
    if (hours > 0)
      return String(hours) + ":" + String(minutes).padStart(2, "0")
        + ":" + String(remainder).padStart(2, "0")
    return String(minutes) + ":" + String(remainder).padStart(2, "0")
  }

  function titleText() {
    if (!root.deviceSelected) return "Select a Roku"
    if (root.loading) return "Checking playback…"
    if (root.error) return "Playback unavailable"
    if (root.channel && root.channel.program) return String(root.channel.program)
    if (root.media && root.media.appName) return String(root.media.appName)
    return "Nothing playing"
  }

  function detailText() {
    if (!root.deviceSelected) return "Playback details will appear here"
    if (root.loading) return "Reading the selected device"
    if (root.error) return root.error
    if (root.channel) {
      var channelText = root.channel.number ? "Channel " + String(root.channel.number) : "Live TV"
      if (root.channel.name) channelText += " · " + String(root.channel.name)
      return channelText
    }
    if (root.media) {
      var detail = root.playbackLabel(root.media.state)
      var position = root.mediaTime(root.media.position)
      var duration = root.mediaTime(root.media.duration)
      if (position) detail += " · " + position + (duration ? " / " + duration : "")
      return detail
    }
    return "No active media details"
  }

  width: parent ? parent.width : implicitWidth
  height: content.implicitHeight + Style.spacing.lg * 2
  radius: Style.cornerRadius
  color: Style.normalFillFor(Color.popups.text, Color.accent)
  borderSpec: Border.controlSpec("normal", Color.popups.text, Color.accent)

  Row {
    id: content
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    anchors.margins: Style.spacing.lg
    spacing: Style.spacing.md

    Column {
      width: parent.width - refreshButton.width - parent.spacing
      spacing: Style.spacing.xs

      Text {
        text: "Now playing"
        textFormat: Text.PlainText
        color: Color.muted
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        font.bold: true
      }

      Text {
        width: parent.width
        text: root.titleText()
        textFormat: Text.PlainText
        color: root.error ? Color.urgent : Color.popups.text
        font.family: Style.font.family
        font.pixelSize: Style.font.subtitle
        font.bold: true
        elide: Text.ElideRight
      }

      Text {
        width: parent.width
        text: root.detailText()
        textFormat: Text.PlainText
        color: root.error ? Color.urgent : Color.muted
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
      }
    }

    Button {
      id: refreshButton
      anchors.verticalCenter: parent.verticalCenter
      iconText: "󰑐"
      tooltipText: "Refresh now playing"
      focusable: true
      enabled: root.controlsEnabled && !root.loading
      onClicked: root.refreshRequested()
    }
  }
}

import QtQuick
import qs.Commons
import qs.Ui

Column {
  id: root

  property var apps: []
  property bool appsLoading: false
  property string appsError: ""
  property string favoriteError: ""
  property bool controlsEnabled: false
  property string iconBaseUrl: ""
  property bool deviceOnly: false
  property bool iconsEnabled: true
  property color foreground: Color.popups.text
  readonly property bool popupOpen: appSearch.popupOpen
  readonly property bool editing: appSearch.activeFocus

  signal refreshAppsRequested()
  signal addRequested(string kind, string id, string name, bool deviceOnly)
  signal iconsToggled(bool enabled)

  spacing: 0

  function safeUiText(value) {
    return String(value || "").replace(/</g, "‹").replace(/>/g, "›")
  }

  readonly property var appOptions: {
    var result = []
    for (var i = 0; i < root.apps.length; i++) {
      var app = root.apps[i]
      result.push({
        value: String(app.id || ""),
        label: root.safeUiText(app.name || "Roku app"),
        description: "App ID " + String(app.id || "")
      })
    }
    return result
  }

  function selectedApp() {
    for (var i = 0; i < root.apps.length; i++)
      if (String(root.apps[i].id || "") === String(appSearch.value || ""))
        return root.apps[i]
    return null
  }

  function addSelectedApp() {
    var app = root.selectedApp()
    if (!app) return
    root.addRequested(
      "app", String(app.id || ""), String(app.name || "Roku app"), root.deviceOnly)
  }

  function clearForm() {
    appSearch.value = ""
    root.deviceOnly = false
  }

  BorderSurface {
    width: parent.width
    height: editor.implicitHeight + Style.spacing.xl * 2
    radius: Style.cornerRadius
    color: Style.normalFillFor(root.foreground, Color.accent)
    borderSpec: Border.controlSpec("normal", root.foreground, Color.accent)

    Column {
      id: editor
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.margins: Style.spacing.xl
      spacing: Style.spacing.md

      Row {
        width: parent.width
        spacing: Style.spacing.md

        Text {
          width: parent.width - refreshApps.width - parent.spacing
          text: "Add favorite app"
          textFormat: Text.PlainText
          color: root.foreground
          font.family: Style.font.family
          font.pixelSize: Style.font.subtitle
          font.bold: true
          anchors.verticalCenter: parent.verticalCenter
        }

        Button {
          id: refreshApps
          iconText: "󰑐"
          tooltipText: "Refresh installed apps"
          focusable: true
          enabled: !root.appsLoading && root.controlsEnabled
          onClicked: root.refreshAppsRequested()
        }
      }

      CheckRow {
        width: parent.width
        label: "This device only"
        tooltipText: "When checked, this favorite appears only on the selected Roku. Leave unchecked to show it on every device."
        checked: root.deviceOnly
        foreground: root.foreground
        onToggled: function(checked) { root.deviceOnly = checked }
      }

      CheckRow {
        width: parent.width
        label: "Icons"
        tooltipText: "Show Roku app artwork for all current favorites on every device."
        checked: root.iconsEnabled
        foreground: root.foreground
        onToggled: function(checked) { root.iconsToggled(checked) }
      }

      Row {
        width: parent.width
        spacing: Style.spacing.md

        SearchableDropdown {
          id: appSearch
          width: parent.width - addAppButton.width - parent.spacing
          value: ""
          options: root.appOptions
          showLabel: false
          foreground: root.foreground
          enabled: !root.appsLoading && root.controlsEnabled
          placeholderText: root.appsLoading ? "Loading installed apps…" : "Choose an installed app…"
          emptyText: root.appsError ? "Installed apps unavailable" : "No matching apps"
        }

        Button {
          id: addAppButton
          text: "Add"
          iconText: "+"
          bordered: true
          focusable: true
          enabled: root.controlsEnabled && appSearch.value !== ""
          onClicked: root.addSelectedApp()
        }
      }

      Text {
        visible: !root.appsLoading && root.appsError !== "" && root.apps.length === 0
        width: parent.width
        text: "Couldn't load installed apps. Check the Roku connection, then refresh."
        textFormat: Text.PlainText
        color: Color.urgent
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        wrapMode: Text.WordWrap
      }

      Text {
        visible: root.favoriteError !== ""
        width: parent.width
        text: root.favoriteError
        textFormat: Text.PlainText
        color: Color.urgent
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        wrapMode: Text.WordWrap
      }
    }
  }
}

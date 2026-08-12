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
  property color foreground: Color.popups.text
  readonly property bool popupOpen: appSearch.popupOpen

  signal refreshAppsRequested()
  signal addRequested(string kind, string id, string name)

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

  function selectApp(appId) {
    var value = String(appId || "")
    for (var i = 0; i < root.apps.length; i++) {
      if (String(root.apps[i].id || "") !== value) continue
      favoriteName.text = String(root.apps[i].name || "")
      favoriteTarget.text = value
      return
    }
  }

  function clearForm() {
    appSearch.value = ""
    favoriteName.text = ""
    favoriteTarget.text = ""
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
          text: "Add favorite"
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

      SearchableDropdown {
        id: appSearch
        visible: root.apps.length > 0
        width: parent.width
        value: ""
        options: root.appOptions
        showLabel: false
        foreground: root.foreground
        placeholderText: "Search installed apps…"
        emptyText: "No matching apps"
        onChanged: function(value) { root.selectApp(value) }
      }

      Text {
        visible: root.appsLoading || (root.appsError !== "" && root.apps.length === 0)
        width: parent.width
        text: root.appsLoading
          ? "Loading installed apps…"
          : "Can't load installed apps. Enter an app ID manually."
        textFormat: Text.PlainText
        color: Color.muted
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        wrapMode: Text.WordWrap
      }

      Row {
        width: parent.width
        spacing: Style.spacing.md

        Image {
          width: appSearch.value && root.iconBaseUrl ? Style.spacing.controlHeight : 0
          height: Style.spacing.controlHeight
          visible: width > 0
          source: visible ? root.iconBaseUrl + encodeURIComponent(appSearch.value) : ""
          fillMode: Image.PreserveAspectFit
          asynchronous: true
          cache: true
        }

        TextField {
          id: favoriteName
          width: (parent.width - favoriteTarget.width
            - (appSearch.value && root.iconBaseUrl ? Style.spacing.controlHeight + parent.spacing * 2 : parent.spacing))
          placeholderText: "Name, e.g. YouTube"
          maximumLength: 48
        }

        TextField {
          id: favoriteTarget
          width: (parent.width - parent.spacing) * 0.38
          placeholderText: "App ID or 5.1"
          maximumLength: 128
        }
      }

      Row {
        spacing: Style.spacing.md

        Button {
          text: "App"
          iconText: "󰀻"
          bordered: true
          focusable: true
          onClicked: root.addRequested("app", favoriteTarget.text, favoriteName.text)
        }

        Button {
          text: "TV channel"
          iconText: "󰑈"
          bordered: true
          focusable: true
          onClicked: root.addRequested("channel", favoriteTarget.text, favoriteName.text)
        }
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

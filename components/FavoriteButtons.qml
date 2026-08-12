import QtQuick
import qs.Commons
import qs.Ui

Column {
  id: root

  property var favorites: []
  property bool managing: false
  property bool controlsEnabled: false
  property color foreground: Color.popups.text

  signal removeRequested(var favorite)
  signal launchRequested(var favorite)

  visible: favorites.length > 0
  spacing: Style.spacing.sm

  readonly property var favoriteRows: {
    var rows = []
    for (var i = 0; i < root.favorites.length; i += 4)
      rows.push(root.favorites.slice(i, i + 4))
    return rows
  }

  function displayName(favorite, rowSize) {
    var label = root.safeUiText(favorite.name || favorite.id || "Favorite")
    var limit = rowSize >= 4 ? 11 : (rowSize === 3 ? 16 : (rowSize === 2 ? 24 : 48))
    return label.length > limit ? label.slice(0, limit - 1) + "…" : label
  }

  function safeUiText(value) {
    return String(value || "").replace(/</g, "‹").replace(/>/g, "›")
  }

  Text {
    text: "Favorites"
    textFormat: Text.PlainText
    color: root.foreground
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
    font.bold: true
  }

  Repeater {
    model: root.favoriteRows

    Row {
      id: favoriteRow
      required property var modelData

      width: root.width
      spacing: Style.spacing.rowGap
      readonly property real cellWidth: (width - spacing * (modelData.length - 1)) / modelData.length

      Repeater {
        model: favoriteRow.modelData

        Item {
          id: favoriteCell
          required property var modelData

          width: favoriteRow.cellWidth
          height: favoriteButton.implicitHeight

          Button {
            id: favoriteButton
            width: parent.width
            iconText: root.managing
              ? "󰆴"
              : (favoriteRow.modelData.length >= 4
                ? ""
                : (modelData.kind === "channel" ? "󰑈" : "󰀻"))
            text: root.displayName(modelData, favoriteRow.modelData.length)
            tooltipText: root.managing
              ? "Remove " + root.safeUiText(modelData.name || modelData.id || "favorite")
              : (modelData.kind === "channel"
                ? "Open TV channel " + String(modelData.id || "")
                : "Open Roku app " + root.safeUiText(modelData.name || modelData.id || ""))
            bordered: true
            focusable: true
            enabled: root.controlsEnabled
            clip: true
            horizontalPadding: Style.spacing.sm
            fontSize: favoriteRow.modelData.length >= 4
              ? Style.font.bodySmall
              : Style.font.body
            onClicked: {
              if (root.managing) root.removeRequested(modelData)
              else root.launchRequested(modelData)
            }
          }
        }
      }
    }
  }
}

import QtQuick
import qs.Commons

Column {
  id: root

  property var favorites: []
  property bool managing: false
  property bool controlsEnabled: false
  property string iconBaseUrl: ""
  property bool iconsEnabled: true
  property color foreground: Color.popups.text

  signal removeRequested(var favorite)
  signal launchRequested(var favorite)

  visible: favorites.length > 0
  spacing: Style.spacing.sm

  readonly property var favoriteRows: {
    var rows = []
    for (var i = 0; i < root.favorites.length; i += 3)
      rows.push(root.favorites.slice(i, i + 3))
    return rows
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
      readonly property real cellWidth: (width - spacing * 2) / 3

      Repeater {
        model: favoriteRow.modelData

        FavoriteTile {
          required property var modelData
          width: favoriteRow.cellWidth
          favorite: modelData
          managing: root.managing
          iconBaseUrl: root.iconBaseUrl
          showIcon: root.iconsEnabled
          foreground: root.foreground
          enabled: root.controlsEnabled
          onTriggered: {
            if (root.managing) root.removeRequested(modelData)
            else root.launchRequested(modelData)
          }
        }
      }
    }
  }
}

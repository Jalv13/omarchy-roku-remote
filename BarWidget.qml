import QtQuick
import qs.Ui

BarWidget {
  id: root
  moduleName: "io.github.jalv13.roku"

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰞢"
    tooltipText: "Roku Remote"

    onPressed: function(_button) {
      if (!root.bar) return
      root.bar.run("omarchy-shell shell toggle io.github.jalv13.roku '{}'")
    }
  }
}

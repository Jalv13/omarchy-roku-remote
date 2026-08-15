import QtQuick 2.15

FocusScope {
  id: root

  property bool blocked: false
  property bool controlsEnabled: false
  property bool confirmKeysEnabled: true
  property string heldDirection: ""

  signal commandRequested(string key)
  signal holdRequested(string key)
  signal releaseRequested(string key)
  signal closeRequested()
  signal helpRequested()

  function directionFor(key) {
    if (key === Qt.Key_Up) return "Up"
    if (key === Qt.Key_Down) return "Down"
    if (key === Qt.Key_Left) return "Left"
    if (key === Qt.Key_Right) return "Right"
    return ""
  }

  function commandFor(key) {
    if (key === Qt.Key_Home || key === Qt.Key_H) return "Home"
    if (key === Qt.Key_Backspace) return "Back"
    if (key === Qt.Key_Period) return "VolumeUp"
    if (key === Qt.Key_Comma) return "VolumeDown"
    if (key === Qt.Key_P) return "Play"
    if (key === Qt.Key_R) return "InstantReplay"
    if (key === Qt.Key_I) return "Info"
    if (key === Qt.Key_Space) return root.confirmKeysEnabled ? "VolumeMute" : ""
    if (key === Qt.Key_Return || key === Qt.Key_Enter)
      return root.confirmKeysEnabled ? "Select" : ""
    return ""
  }

  function cancelHeld() {
    if (!root.heldDirection) return
    var value = root.heldDirection
    root.heldDirection = ""
    root.releaseRequested(value)
  }

  Keys.priority: Keys.BeforeItem
  Keys.onPressed: function(event) {
    if (event.key === Qt.Key_Escape) {
      root.cancelHeld()
      root.closeRequested()
      event.accepted = true
      return
    }
    if (root.blocked) return
    if (event.key === Qt.Key_Question) {
      if (!event.isAutoRepeat) root.helpRequested()
      event.accepted = true
      return
    }

    var direction = root.directionFor(event.key)
    if (direction) {
      event.accepted = true
      if (!root.controlsEnabled || event.isAutoRepeat) return
      if (root.heldDirection && root.heldDirection !== direction) root.cancelHeld()
      if (!root.heldDirection) {
        root.heldDirection = direction
        root.holdRequested(direction)
      }
      return
    }

    var command = root.commandFor(event.key)
    if (!command) return
    event.accepted = true
    if (root.controlsEnabled && !event.isAutoRepeat) root.commandRequested(command)
  }

  Keys.onReleased: function(event) {
    var direction = root.directionFor(event.key)
    if (!direction || direction !== root.heldDirection) return
    root.cancelHeld()
    event.accepted = true
  }

  onActiveFocusChanged: if (!activeFocus) root.cancelHeld()
  Component.onDestruction: root.cancelHeld()
}

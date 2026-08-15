import QtQuick 2.15
import QtTest 1.2
import "../../components" as Components

TestCase {
  id: testCase
  name: "KeyboardShortcuts"
  when: windowShown
  width: 320
  height: 240

  Components.KeyboardShortcuts {
    id: shortcuts
    anchors.fill: parent
    focus: true
    controlsEnabled: true
  }

  SignalSpy { id: commandSpy; target: shortcuts; signalName: "commandRequested" }
  SignalSpy { id: holdSpy; target: shortcuts; signalName: "holdRequested" }
  SignalSpy { id: releaseSpy; target: shortcuts; signalName: "releaseRequested" }
  SignalSpy { id: helpSpy; target: shortcuts; signalName: "helpRequested" }

  function init() {
    shortcuts.blocked = false
    shortcuts.controlsEnabled = true
    shortcuts.confirmKeysEnabled = true
    shortcuts.forceActiveFocus()
    commandSpy.clear()
    holdSpy.clear()
    releaseSpy.clear()
    helpSpy.clear()
  }

  function test_commandMappings_data() {
    return [
      { tag: "enter", key: Qt.Key_Return, command: "Select" },
      { tag: "keypad-enter", key: Qt.Key_Enter, command: "Select" },
      { tag: "back", key: Qt.Key_Backspace, command: "Back" },
      { tag: "volume-up", key: Qt.Key_Period, command: "VolumeUp" },
      { tag: "volume-down", key: Qt.Key_Comma, command: "VolumeDown" },
      { tag: "mute", key: Qt.Key_Space, command: "VolumeMute" },
      { tag: "play", key: Qt.Key_P, command: "Play" },
      { tag: "replay", key: Qt.Key_R, command: "InstantReplay" },
      { tag: "info", key: Qt.Key_I, command: "Info" },
      { tag: "home", key: Qt.Key_H, command: "Home" }
    ]
  }

  function test_commandMappings(data) {
    keyClick(data.key)
    compare(commandSpy.count, 1)
    compare(commandSpy.signalArguments[0][0], data.command)
  }

  function test_arrowHoldUsesBalancedEvents() {
    keyPress(Qt.Key_Down)
    compare(holdSpy.count, 1)
    compare(holdSpy.signalArguments[0][0], "Down")
    compare(releaseSpy.count, 0)

    keyRelease(Qt.Key_Down)
    compare(releaseSpy.count, 1)
    compare(releaseSpy.signalArguments[0][0], "Down")
  }

  function test_blockedWhileTyping() {
    shortcuts.blocked = true
    keyClick(Qt.Key_P)
    keyClick(Qt.Key_Space)
    keyClick(Qt.Key_Up)
    compare(commandSpy.count, 0)
    compare(holdSpy.count, 0)
  }

  function test_confirmKeysCanRemainWithFocusedButtons() {
    shortcuts.confirmKeysEnabled = false
    keyClick(Qt.Key_Return)
    keyClick(Qt.Key_Space)
    keyClick(Qt.Key_H)
    compare(commandSpy.count, 1)
    compare(commandSpy.signalArguments[0][0], "Home")
  }

  function test_helpShortcut() {
    keyClick(Qt.Key_Question)
    compare(helpSpy.count, 1)
  }
}

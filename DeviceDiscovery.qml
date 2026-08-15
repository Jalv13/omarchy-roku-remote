import QtQuick
import Quickshell.Io

QtObject {
  id: root

  required property string helperPath
  property var manualDevices: []
  property real discoveryTimeout: 1.6
  property real infoTimeout: 0.8
  property bool restartRequested: false
  property string _output: ""
  property string _errorOutput: ""
  property string _probeIp: ""
  property int _probePort: 8060
  property string _probeOutput: ""
  property string _probeErrorOutput: ""

  readonly property bool running: discoveryProcess.running
  readonly property bool probing: probeProcess.running

  signal finished(var devices, var warnings)
  signal failed(string message)
  signal probeFinished(var device)
  signal probeFailed(string ip, string message)

  function manualIp(device) {
    if (device && typeof device === "object") return String(device.ip || "")
    return String(device || "")
  }

  function commandLine() {
    var args = [
      "python3", root.helperPath, "discover",
      "--timeout", String(root.discoveryTimeout),
      "--info-timeout", String(root.infoTimeout)
    ]
    for (var i = 0; i < root.manualDevices.length; i++) {
      var ip = root.manualIp(root.manualDevices[i]).trim()
      if (ip) args.push("--manual", ip)
    }
    return args
  }

  function start() {
    if (discoveryProcess.running) {
      root.restartRequested = true
      discoveryProcess.running = false
      return
    }
    root._output = ""
    root._errorOutput = ""
    discoveryProcess.command = root.commandLine()
    discoveryProcess.running = true
  }

  function probe(ip, port) {
    var value = String(ip || "").trim()
    if (!value) return false
    if (probeProcess.running) return false
    root._probeIp = value
    root._probePort = Number(port || 8060)
    root._probeOutput = ""
    root._probeErrorOutput = ""
    probeProcess.command = [
      "python3", root.helperPath, "info",
      "--ip", root._probeIp, "--port", String(root._probePort),
      "--timeout", "0.55"
    ]
    probeProcess.running = true
    return true
  }

  function finish(exitCode) {
    if (root.restartRequested) {
      root.restartRequested = false
      Qt.callLater(root.start)
      return
    }

    var payload = null
    try { payload = JSON.parse(String(root._output || "").trim()) } catch (e) {}
    if (exitCode === 0 && payload && payload.ok && Array.isArray(payload.devices)) {
      root.finished(payload.devices, Array.isArray(payload.warnings) ? payload.warnings : [])
      return
    }
    var message = payload && payload.error
      ? String(payload.error)
      : String(root._errorOutput || "Device discovery failed").trim()
    root.failed(message || "Device discovery failed")
  }

  function finishProbe(exitCode) {
    var payload = null
    try { payload = JSON.parse(String(root._probeOutput || "").trim()) } catch (e) {}
    if (exitCode === 0 && payload && payload.ok && payload.device) {
      root.probeFinished(payload.device)
      return
    }
    var message = payload && payload.error
      ? String(payload.error)
      : String(root._probeErrorOutput || "Roku did not respond").trim()
    root.probeFailed(root._probeIp, message || "Roku did not respond")
  }

  property Process discoveryProcess: Process {
    id: discoveryProcess
    command: []
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root._output = text
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: root._errorOutput = text
    }
    onExited: function(exitCode) { root.finish(exitCode) }
  }


  property Process probeProcess: Process {
    id: probeProcess
    command: []
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root._probeOutput = text
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: root._probeErrorOutput = text
    }
    onExited: function(exitCode) { root.finishProbe(exitCode) }
  }
}

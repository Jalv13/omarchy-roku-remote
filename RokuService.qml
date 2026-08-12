import QtQuick
import Quickshell.Io

QtObject {
  id: root

  required property string helperPath
  property string selectedIp: ""
  property int selectedPort: 8060
  property bool connected: false
  property bool accessBlocked: false
  property string lastError: ""
  property string lastStatus: ""
  property var apps: []
  property bool appsLoading: false
  property string appsError: ""
  property var statusInfo: null
  property bool statusLoading: false
  property string statusError: ""
  property var diagnosticResult: null
  property string diagnosticName: ""
  property bool diagnosticLoading: false
  property string diagnosticError: ""

  property var _queue: []
  property var _current: null
  property string _commandOutput: ""
  property string _commandError: ""
  property string _heldKey: ""
  property string _heldIp: ""
  property int _heldPort: 8060
  property string _appsIp: ""
  property string _appsOutput: ""
  property string _appsErrorOutput: ""
  property bool _appsRestartRequested: false
  property string _auxOutput: ""
  property string _auxErrorOutput: ""
  property string _auxKind: ""
  property string _auxIp: ""

  readonly property bool busy: commandProcess.running || appsProcess.running
    || auxProcess.running
  readonly property var allowedKeys: [
    "Home", "Rev", "Fwd", "Play", "Select", "Left", "Right", "Down",
    "Up", "Back", "InstantReplay", "Info", "Backspace", "Enter",
    "PowerOff", "PowerOn", "VolumeDown", "VolumeMute", "VolumeUp"
  ]
  readonly property var diagnosticNames: [
    "chanperf", "graphics-frame-rate", "r2d2-bitmaps", "sgnodes", "registry"
  ]

  signal requestFinished(string action, string key, bool ok)
  signal statusMessage(string message, bool isError)

  onSelectedIpChanged: {
    root.releaseHeldKey()
    root.connected = false
    root.accessBlocked = false
    root.lastError = ""
    root.apps = []
    root.appsError = ""
    root.statusInfo = null
    root.statusLoading = false
    root.statusError = ""
    root.diagnosticResult = null
    root.diagnosticLoading = false
    root.diagnosticError = ""
  }

  function keyAllowed(key) {
    return root.allowedKeys.indexOf(String(key)) !== -1
  }

  function baseArgs(ip, port) {
    return [
      "python3", root.helperPath,
      "control", "--ip", String(ip), "--port", String(port),
      "--timeout", "1.2"
    ]
  }

  function commandFor(request) {
    if (request.kind === "literal") {
      return [
        "python3", root.helperPath,
        "literal", "--ip", request.ip, "--port", String(request.port),
        "--timeout", "1.2", "--text", request.text
      ]
    }
    if (request.kind === "launchApp") {
      var launchArgs = [
        "python3", root.helperPath,
        "launch-app", "--ip", request.ip, "--port", String(request.port),
        "--timeout", "1.2", "--id", request.appId
      ]
      var parameters = request.parameters || ({})
      for (var name in parameters)
        launchArgs.push("--param", String(name) + "=" + String(parameters[name]))
      return launchArgs
    }
    if (request.kind === "launchChannel") {
      return [
        "python3", root.helperPath,
        "launch-channel", "--ip", request.ip, "--port", String(request.port),
        "--timeout", "1.2", "--channel", request.channel
      ]
    }
    if (request.kind === "exitApp") {
      var exitArgs = [
        "python3", root.helperPath,
        "exit-app", "--ip", request.ip, "--port", String(request.port),
        "--timeout", "1.2", "--id", request.appId
      ]
      if (request.force) exitArgs.push("--force")
      return exitArgs
    }
    var args = root.baseArgs(request.ip, request.port)
    args.push("--action", request.action, "--key", request.key)
    return args
  }

  function enqueue(request) {
    if (!request || !request.ip) {
      root.lastError = "Select a Roku first"
      root.statusMessage(root.lastError, true)
      return false
    }
    if (root._queue.length >= 12) return false
    root._queue = root._queue.concat([request])
    root.startNext()
    return true
  }

  function startNext() {
    if (commandProcess.running || root._queue.length === 0) return
    var next = root._queue[0]
    root._queue = root._queue.slice(1)
    root._current = next
    root._commandOutput = ""
    root._commandError = ""
    commandProcess.command = root.commandFor(next)
    commandProcess.running = true
  }

  function parsed(raw) {
    try { return JSON.parse(String(raw || "").trim()) } catch (e) { return null }
  }

  function finishCommand(exitCode) {
    var current = root._current
    var payload = root.parsed(root._commandOutput)
    var ok = exitCode === 0 && payload && payload.ok
    if (ok) {
      root.connected = true
      if (current && current.kind === "control"
          && ["VolumeUp", "VolumeDown", "VolumeMute"].indexOf(String(current.key || "")) === -1)
        root.accessBlocked = false
      root.lastError = ""
      if (current && current.kind === "literal") root.lastStatus = "Text sent"
      else if (current && (current.kind === "launchApp" || current.kind === "launchChannel")) {
        root.lastStatus = "Opened " + String(current.name || "favorite")
        root.statusMessage(root.lastStatus, false)
      } else if (current && current.kind === "exitApp") {
        root.lastStatus = "Closed app " + String(current.appId)
        root.statusMessage(root.lastStatus, false)
      } else root.lastStatus = "Sent " + String(current ? current.key : "command")
    } else {
      var unsupported = payload && payload.unsupported
      var forbidden = payload && payload.kind === "forbidden"
      var navigationForbidden = forbidden && current && current.kind === "control"
      if (navigationForbidden) root.accessBlocked = true
      root.connected = payload && payload.reachable === true
      root.lastError = unsupported
        ? "This control is not supported by the selected Roku"
        : (payload && payload.error
          ? String(payload.error)
          : String(root._commandError || "Roku did not respond").trim())
      // The panel renders accessBlocked as a persistent, actionable warning.
      // Do not also raise the same 403 as a transient message above it.
      if (!navigationForbidden)
        root.statusMessage(root.lastError || "Roku did not respond", !unsupported)
    }
    root.requestFinished(
      current ? String(current.action || current.kind || "") : "",
      current ? String(current.key || "") : "",
      ok
    )
    root._current = null
    Qt.callLater(root.startNext)
  }

  function sendKey(key) {
    var value = String(key)
    if (!root.keyAllowed(value)) return false
    return root.enqueue({
      kind: "control",
      ip: root.selectedIp,
      port: root.selectedPort,
      action: "keypress",
      key: value
    })
  }

  function sendText(text) {
    var value = String(text || "")
    if (!value || value.length > 256) {
      root.statusMessage(value ? "Text is limited to 256 characters" : "Enter text first", true)
      return false
    }
    return root.enqueue({
      kind: "literal",
      ip: root.selectedIp,
      port: root.selectedPort,
      text: value
    })
  }

  function validAppId(value) {
    return /^[A-Za-z0-9._-]{1,128}$/.test(String(value || "").trim())
  }

  function validChannel(value) {
    return /^\d{1,4}(?:\.\d{1,3})?$/.test(String(value || "").trim())
  }

  function launchApp(appId, name) {
    var value = String(appId || "").trim()
    if (!root.validAppId(value)) {
      root.statusMessage("Enter a valid Roku app ID", true)
      return false
    }
    return root.enqueue({
      kind: "launchApp",
      ip: root.selectedIp,
      port: root.selectedPort,
      appId: value,
      name: String(name || "app"),
      parameters: ({})
    })
  }

  function launchDeepLink(appId, contentId, mediaType) {
    var value = String(appId || "").trim()
    var content = String(contentId || "")
    var media = String(mediaType || "")
    if (!root.validAppId(value) || !content || content.length > 254 || !media) {
      root.statusMessage("Enter an app ID, content ID, and media type", true)
      return false
    }
    return root.enqueue({
      kind: "launchApp",
      ip: root.selectedIp,
      port: root.selectedPort,
      appId: value,
      name: "deep link",
      parameters: { contentId: content, mediaType: media }
    })
  }

  function exitApp(appId, force) {
    var value = String(appId || "").trim()
    if (!root.validAppId(value)) {
      root.statusMessage("Enter a valid Roku app ID", true)
      return false
    }
    return root.enqueue({
      kind: "exitApp",
      ip: root.selectedIp,
      port: root.selectedPort,
      appId: value,
      force: force === true
    })
  }

  function iconUrl(appId) {
    var value = String(appId || "").trim()
    if (!root.selectedIp || !root.validAppId(value)) return ""
    return "http://" + root.selectedIp + ":" + String(root.selectedPort)
      + "/query/icon/" + encodeURIComponent(value)
  }

  function launchChannel(channel, name) {
    var value = String(channel || "").trim()
    if (!root.validChannel(value)) {
      root.statusMessage("Enter a TV channel such as 5 or 5.1", true)
      return false
    }
    return root.enqueue({
      kind: "launchChannel",
      ip: root.selectedIp,
      port: root.selectedPort,
      channel: value,
      name: String(name || ("Channel " + value))
    })
  }

  function refreshApps() {
    if (!root.selectedIp) {
      root.apps = []
      root.appsError = "Select a Roku first"
      return
    }
    if (appsProcess.running) {
      root._appsRestartRequested = true
      appsProcess.running = false
      return
    }
    root._appsIp = root.selectedIp
    root._appsOutput = ""
    root._appsErrorOutput = ""
    root.appsError = ""
    root.appsLoading = true
    appsProcess.command = [
      "python3", root.helperPath,
      "apps", "--ip", root._appsIp, "--port", String(root.selectedPort),
      "--timeout", "1.0"
    ]
    appsProcess.running = true
  }

  function finishApps(exitCode) {
    if (root._appsRestartRequested) {
      root._appsRestartRequested = false
      Qt.callLater(root.refreshApps)
      return
    }
    root.appsLoading = false
    if (root._appsIp !== root.selectedIp) return
    var payload = root.parsed(root._appsOutput)
    if (exitCode === 0 && payload && payload.ok && Array.isArray(payload.apps)) {
      root.apps = payload.apps
      root.appsError = ""
      return
    }
    root.apps = []
    root.appsError = payload && payload.error
      ? String(payload.error)
      : String(root._appsErrorOutput || "Installed apps are unavailable").trim()
  }

  function startAux(kind, name) {
    if (!root.selectedIp || auxProcess.running) return false
    if (kind !== "status" && root.diagnosticNames.indexOf(String(name)) === -1)
      return false
    root._auxKind = kind
    root._auxIp = root.selectedIp
    root._auxOutput = ""
    root._auxErrorOutput = ""
    if (kind === "status") {
      root.statusLoading = true
      root.statusError = ""
      auxProcess.command = [
        "python3", root.helperPath,
        "status", "--ip", root.selectedIp, "--port", String(root.selectedPort),
        "--timeout", "1.0"
      ]
    } else {
      root.diagnosticLoading = true
      root.diagnosticError = ""
      root.diagnosticName = String(name)
      auxProcess.command = [
        "python3", root.helperPath,
        "query", "--ip", root.selectedIp, "--port", String(root.selectedPort),
        "--timeout", "1.5", "--name", root.diagnosticName
      ]
    }
    auxProcess.running = true
    return true
  }

  function refreshStatus() { return root.startAux("status", "") }
  function runDiagnostic(name) { return root.startAux("diagnostic", name) }

  function finishAux(exitCode) {
    if (root._auxIp !== root.selectedIp) {
      root._auxKind = ""
      root._auxIp = ""
      return
    }
    var payload = root.parsed(root._auxOutput)
    var ok = exitCode === 0 && payload && payload.ok
    var error = payload && payload.error
      ? String(payload.error)
      : String(root._auxErrorOutput || "Roku query failed").trim()
    if (root._auxKind === "status") {
      root.statusLoading = false
      if (ok) {
        root.statusInfo = { media: payload.media || null, channel: payload.channel || null }
        root.statusError = ""
      } else root.statusError = error
    } else {
      root.diagnosticLoading = false
      if (ok) {
        root.diagnosticResult = payload.data || null
        root.diagnosticError = ""
      } else root.diagnosticError = error
    }
    root._auxKind = ""
    root._auxIp = ""
  }

  function holdKey(key, safetyMs) {
    var value = String(key)
    if (!root.keyAllowed(value) || !root.selectedIp) return false
    if (root._heldKey) root.releaseHeldKey()
    root._heldKey = value
    root._heldIp = root.selectedIp
    root._heldPort = root.selectedPort
    if (!root.enqueue({
      kind: "control",
      ip: root._heldIp,
      port: root._heldPort,
      action: "keydown",
      key: value
    })) {
      root._heldKey = ""
      root._heldIp = ""
      return false
    }
    var requestedSafety = Number(safetyMs || 1100)
    holdSafety.interval = Math.max(500, Math.min(15000, requestedSafety))
    holdSafety.restart()
    return true
  }

  function releaseHeldKey(key) {
    if (!root._heldKey) return
    if (key !== undefined && key !== null && String(key) !== root._heldKey) return
    var request = {
      ip: root._heldIp,
      port: root._heldPort,
      action: "keyup",
      key: root._heldKey
    }
    root._heldKey = ""
    root._heldIp = ""
    holdSafety.stop()
    // Keep keyup in the same queue as keydown. A separate release process can
    // overtake a queued keydown when another command is already running.
    // This internal safety command may exceed the normal queue cap by one.
    root._queue = root._queue.concat([request])
    root.startNext()
  }

  property Timer holdSafety: Timer {
    id: holdSafety
    interval: 1100
    repeat: false
    onTriggered: root.releaseHeldKey()
  }

  property Process commandProcess: Process {
    id: commandProcess
    command: []
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root._commandOutput = text
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: root._commandError = text
    }
    onExited: function(exitCode) { root.finishCommand(exitCode) }
  }

  property Process appsProcess: Process {
    id: appsProcess
    command: []
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root._appsOutput = text
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: root._appsErrorOutput = text
    }
    onExited: function(exitCode) { root.finishApps(exitCode) }
  }

  property Process auxProcess: Process {
    id: auxProcess
    command: []
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root._auxOutput = text
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: root._auxErrorOutput = text
    }
    onExited: function(exitCode) { root.finishAux(exitCode) }
  }

  Component.onDestruction: root.releaseHeldKey()
}

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import "components" as Components

Item {
  id: root

  property var shell: null
  property var manifest: null
  property bool opened: false
  property bool closingFromHost: false
  property bool stateDirectoryReady: false
  property bool stateLoaded: false
  property bool savePending: false
  property bool addingManual: false
  property bool textInputVisible: false
  property bool infoVisible: false
  property string manualError: ""
  property string transientMessage: ""
  property bool transientError: false
  property var devices: []
  property var manualDevices: []
  property string selectedIp: ""
  property string preferredDeviceId: ""
  property var favorites: []
  property bool managingFavorites: false
  property string favoriteError: ""
  property double lastDiscoveryAt: 0

  readonly property string pluginId: manifest && manifest.id
    ? String(manifest.id) : "io.github.jalv13.roku"
  readonly property string helperPath: decodeURIComponent(
    String(Qt.resolvedUrl("scripts/roku_ecp.py")).replace(/^file:\/\//, ""))
  readonly property string statePath: Quickshell.env("HOME")
    + "/.local/state/omarchy/settings/roku-remote.json"
  readonly property bool controlsEnabled: selectedIp !== ""
  readonly property var selectedDevice: deviceForIp(selectedIp)
  readonly property var currentFavorites: favoritesForCurrentDevice()
  readonly property string connectionState: discovery.running
    ? "searching"
    : (!selectedDevice
      ? "none"
      : (roku.connected ? "connected" : "offline"))
  readonly property string connectionMessage: discovery.running
    ? "Searching…"
    : (!selectedDevice
      ? "No Roku found"
      : (roku.connected ? "Connected" : "Offline"))

  function open(payloadJson) {
    root.closingFromHost = false
    root.opened = true
    var payload = ({})
    try { payload = JSON.parse(String(payloadJson || "{}")) } catch (e) {}
    if (payload && payload.ip && root.isLocalIpv4(String(payload.ip))) {
      root.rememberManual(String(payload.ip))
      root.setSelectedIp(String(payload.ip))
    }
    if (root.devices.length === 0 || Date.now() - root.lastDiscoveryAt > 60000)
      Qt.callLater(discovery.start)
    if (root.selectedIp) Qt.callLater(roku.refreshStatus)
    Qt.callLater(function() {
      scroller.contentY = 0
      keyCatcher.forceActiveFocus()
    })
  }

  function close() {
    root.closingFromHost = true
    roku.releaseHeldKey()
    root.opened = false
    root.addingManual = false
    root.managingFavorites = false
    root.infoVisible = false
    root.manualError = ""
    root.favoriteError = ""
    root.closingFromHost = false
  }

  function requestClose() {
    roku.releaseHeldKey()
    if (root.shell && typeof root.shell.hide === "function") root.shell.hide(root.pluginId)
    else root.opened = false
  }

  function deviceForIp(ip) {
    var value = String(ip || "")
    for (var i = 0; i < root.devices.length; i++)
      if (String(root.devices[i].ip || "") === value) return root.devices[i]
    return null
  }

  function manualForIp(ip) {
    var value = String(ip || "")
    for (var i = 0; i < root.manualDevices.length; i++)
      if (String(root.manualDevices[i].ip || "") === value) return root.manualDevices[i]
    return null
  }

  function favoriteDeviceKey() {
    if (!root.selectedIp) return ""
    if (root.selectedDevice && root.selectedDevice.deviceId)
      return "device:" + String(root.selectedDevice.deviceId)
    return "ip:" + root.selectedIp
  }

  function favoritesForCurrentDevice() {
    var key = root.favoriteDeviceKey()
    var result = []
    if (!key) return result
    for (var i = 0; i < root.favorites.length; i++)
      if (String(root.favorites[i].deviceKey || "") === key) result.push(root.favorites[i])
    return result
  }

  function validFavorite(kind, id) {
    var value = String(id || "").trim()
    if (kind === "app") return /^[A-Za-z0-9._-]{1,128}$/.test(value)
    if (kind === "channel") return /^\d{1,4}(?:\.\d{1,3})?$/.test(value)
    return false
  }

  function addFavorite(kind, id, name) {
    var type = String(kind || "")
    var value = String(id || "").trim()
    var label = String(name || "").trim().slice(0, 48)
    var deviceKey = root.favoriteDeviceKey()
    if (!deviceKey) {
      root.favoriteError = "Select a Roku first"
      return false
    }
    if (!root.validFavorite(type, value)) {
      root.favoriteError = type === "channel"
        ? "Enter a TV channel such as 5 or 5.1"
        : "Enter a valid Roku app ID"
      return false
    }
    if (!label) label = type === "channel" ? "Channel " + value : "App " + value
    if (root.currentFavorites.length >= 12) {
      root.favoriteError = "A Roku can have up to 12 favorites"
      return false
    }
    for (var i = 0; i < root.favorites.length; i++) {
      var existing = root.favorites[i]
      if (existing.deviceKey === deviceKey && existing.kind === type && existing.id === value) {
        root.favoriteError = label + " is already a favorite"
        return false
      }
    }
    root.favorites = root.favorites.concat([{
      deviceKey: deviceKey,
      kind: type,
      id: value,
      name: label
    }])
    root.favoriteError = ""
    root.scheduleSave()
    return true
  }

  function removeFavorite(favorite) {
    if (!favorite) return
    var kept = []
    for (var i = 0; i < root.favorites.length; i++) {
      var item = root.favorites[i]
      if (item.deviceKey === favorite.deviceKey && item.kind === favorite.kind && item.id === favorite.id)
        continue
      kept.push(item)
    }
    root.favorites = kept
    root.favoriteError = ""
    root.scheduleSave()
  }

  function launchFavorite(favorite) {
    if (!favorite) return
    if (favorite.kind === "channel") roku.launchChannel(favorite.id, favorite.name)
    else roku.launchApp(favorite.id, favorite.name)
  }

  function migrateFavoritesForDevice(ip, deviceId) {
    var sourceKey = "ip:" + String(ip || "")
    var targetKey = "device:" + String(deviceId || "")
    if (sourceKey === "ip:" || targetKey === "device:") return
    var next = []
    var seen = ({})
    var changed = false
    for (var i = 0; i < root.favorites.length; i++) {
      var source = root.favorites[i]
      var item = ({
        deviceKey: source.deviceKey === sourceKey ? targetKey : source.deviceKey,
        kind: source.kind,
        id: source.id,
        name: source.name
      })
      if (item.deviceKey !== source.deviceKey) changed = true
      var identity = item.deviceKey + "|" + item.kind + "|" + item.id
      if (seen[identity]) { changed = true; continue }
      seen[identity] = true
      next.push(item)
    }
    if (changed) {
      root.favorites = next
      root.scheduleSave()
    }
  }

  function isLocalIpv4(value) {
    var match = String(value || "").trim().match(/^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$/)
    if (!match) return false
    var octets = []
    for (var i = 1; i <= 4; i++) {
      var octet = Number(match[i])
      if (!isFinite(octet) || octet < 0 || octet > 255) return false
      octets.push(octet)
    }
    return octets[0] === 10
      || octets[0] === 127
      || (octets[0] === 100 && octets[1] >= 64 && octets[1] <= 127)
      || (octets[0] === 169 && octets[1] === 254)
      || (octets[0] === 172 && octets[1] >= 16 && octets[1] <= 31)
      || (octets[0] === 192 && octets[1] === 168)
  }

  function rememberManual(ip) {
    var value = String(ip || "").trim()
    if (!root.isLocalIpv4(value)) return false
    if (root.manualForIp(value)) return true
    root.manualDevices = root.manualDevices.concat([{
      ip: value,
      name: "Roku at " + value
    }])
    root.scheduleSave()
    return true
  }

  function addManualIp() {
    var value = String(manualField.text || "").trim()
    if (!root.isLocalIpv4(value)) {
      root.manualError = "Enter a private/local IPv4 address"
      return
    }
    root.manualError = ""
    root.rememberManual(value)
    root.setSelectedIp(value)
    manualField.text = ""
    root.addingManual = false
    discovery.start()
  }

  function forgetManual(ip) {
    var value = String(ip || "")
    var device = root.deviceForIp(value)
    var ipKey = "ip:" + value
    var deviceKey = device && device.deviceId ? "device:" + String(device.deviceId) : ""
    var kept = []
    for (var i = 0; i < root.manualDevices.length; i++)
      if (String(root.manualDevices[i].ip || "") !== value) kept.push(root.manualDevices[i])
    root.manualDevices = kept
    var keptFavorites = []
    for (var j = 0; j < root.favorites.length; j++) {
      var favorite = root.favorites[j]
      if (favorite.deviceKey === ipKey || (deviceKey && favorite.deviceKey === deviceKey)) continue
      keptFavorites.push(favorite)
    }
    root.favorites = keptFavorites
    if (root.selectedIp === value) root.selectedIp = ""
    root.scheduleSave()
    discovery.start()
  }

  function setSelectedIp(ip) {
    var value = String(ip || "")
    root.selectedIp = value
    var device = root.deviceForIp(value)
    roku.selectedIp = value
    roku.selectedPort = device && device.port ? Number(device.port) : 8060
    roku.connected = device ? device.online === true : false
    if (device && device.deviceId) root.preferredDeviceId = String(device.deviceId)
    root.scheduleSave()
    if (root.managingFavorites) Qt.callLater(roku.refreshApps)
    if (root.opened) Qt.callLater(roku.refreshStatus)
  }

  function mergeDiscovery(found) {
    var merged = []
    var nextManuals = []
    for (var i = 0; i < found.length; i++) {
      var device = found[i]
      if (device.deviceId) root.migrateFavoritesForDevice(device.ip, device.deviceId)
      var saved = root.manualForIp(device.ip)
      if (saved && !device.online && saved.name) device.name = saved.name
      merged.push(device)
      if (device.manual === true) {
        nextManuals.push({
          ip: String(device.ip),
          name: device.online ? String(device.name || saved && saved.name || "Roku")
            : String(saved && saved.name || device.name || "Roku")
        })
      }
    }
    // Keep a manually stored entry even if a future helper skips it because
    // of malformed state; it remains visible and forgettable until removed.
    for (var j = 0; j < root.manualDevices.length; j++) {
      var old = root.manualDevices[j]
      var present = false
      for (var k = 0; k < nextManuals.length; k++)
        if (nextManuals[k].ip === old.ip) { present = true; break }
      if (!present && root.isLocalIpv4(old.ip)) {
        nextManuals.push(old)
        merged.push({
          ip: old.ip, port: 8060, name: old.name || ("Roku at " + old.ip),
          model: "Roku", deviceId: "", isTv: false, online: false, manual: true
        })
      }
    }
    root.manualDevices = nextManuals
    root.devices = merged
    root.lastDiscoveryAt = Date.now()

    var chosen = root.deviceForIp(root.selectedIp)
    if (!chosen && root.preferredDeviceId) {
      for (var p = 0; p < root.devices.length; p++) {
        if (String(root.devices[p].deviceId || "") === root.preferredDeviceId) {
          chosen = root.devices[p]
          break
        }
      }
    }
    if (!chosen && root.devices.length > 0) {
      chosen = root.devices[0]
      for (var q = 0; q < root.devices.length; q++)
        if (root.devices[q].online === true) { chosen = root.devices[q]; break }
    }
    root.setSelectedIp(chosen ? String(chosen.ip) : "")
    root.scheduleSave()
  }

  function markSelectedOnline(online) {
    if (!root.selectedIp) return
    var next = []
    for (var i = 0; i < root.devices.length; i++) {
      var source = root.devices[i]
      if (String(source.ip) !== root.selectedIp) {
        next.push(source)
        continue
      }
      var copy = ({})
      for (var key in source) copy[key] = source[key]
      copy.online = online
      next.push(copy)
    }
    root.devices = next
  }

  function loadState(raw) {
    var state = ({})
    try { state = JSON.parse(String(raw || "{}")) } catch (e) {}
    var manuals = []
    if (state && Number(state.version || 0) >= 1 && Array.isArray(state.manualDevices)) {
      for (var i = 0; i < state.manualDevices.length; i++) {
        var item = state.manualDevices[i]
        var ip = String(item && item.ip || "")
        if (root.isLocalIpv4(ip)) manuals.push({ ip: ip, name: String(item.name || "Roku at " + ip) })
      }
    }
    var savedFavorites = []
    if (state && Number(state.version || 0) >= 2 && Array.isArray(state.favorites)) {
      for (var j = 0; j < state.favorites.length && savedFavorites.length < 60; j++) {
        var favorite = state.favorites[j]
        var kind = String(favorite && favorite.kind || "")
        var id = String(favorite && favorite.id || "").trim()
        var deviceKey = String(favorite && favorite.deviceKey || "")
        if (!root.validFavorite(kind, id)) continue
        if (!/^(device:|ip:).+/.test(deviceKey)) continue
        savedFavorites.push({
          deviceKey: deviceKey,
          kind: kind,
          id: id,
          name: String(favorite.name || (kind === "channel" ? "Channel " + id : "App " + id)).slice(0, 48)
        })
      }
    }
    root.manualDevices = manuals
    root.favorites = savedFavorites
    root.selectedIp = state && root.isLocalIpv4(state.selectedIp) ? String(state.selectedIp) : ""
    root.preferredDeviceId = state ? String(state.preferredDeviceId || "") : ""
    root.stateLoaded = true
    roku.selectedIp = root.selectedIp
    if (root.opened) discovery.start()
  }

  function scheduleSave() {
    root.savePending = true
    saveDebounce.restart()
  }

  function saveState() {
    if (!root.stateDirectoryReady) {
      root.savePending = true
      return
    }
    var payload = {
      version: 2,
      selectedIp: root.selectedIp,
      preferredDeviceId: root.preferredDeviceId,
      manualDevices: root.manualDevices,
      favorites: root.favorites
    }
    stateFile.setText(JSON.stringify(payload, null, 2) + "\n")
    root.savePending = false
  }

  function showStatus(message, isError) {
    root.transientMessage = String(message || "")
    root.transientError = isError === true
    messageTimer.restart()
  }

  DeviceDiscovery {
    id: discovery
    helperPath: root.helperPath
    manualDevices: root.manualDevices
    onFinished: function(found, warnings) {
      root.mergeDiscovery(found)
      if (warnings.length && found.length === 0) root.showStatus(String(warnings[0]), true)
    }
    onFailed: function(message) { root.showStatus(message, true) }
  }

  RokuService {
    id: roku
    helperPath: root.helperPath
    onRequestFinished: function(_action, _key, ok) { root.markSelectedOnline(ok || roku.connected) }
    onStatusMessage: function(message, isError) { root.showStatus(message, isError) }
  }

  Timer {
    id: saveDebounce
    interval: 180
    onTriggered: root.saveState()
  }

  Timer {
    id: messageTimer
    interval: 3500
    onTriggered: root.transientMessage = ""
  }

  Process {
    id: stateMkdir
    command: [
      "install", "-d", "-m", "0700",
      Quickshell.env("HOME") + "/.local/state/omarchy/settings"
    ]
    onExited: function(exitCode) {
      root.stateDirectoryReady = exitCode === 0
      stateFile.reload()
      if (root.savePending) Qt.callLater(root.saveState)
    }
  }

  FileView {
    id: stateFile
    path: root.statePath
    watchChanges: false
    atomicWrites: true
    printErrors: false
    onLoaded: root.loadState(text())
    onLoadFailed: root.loadState("")
  }

  IpcHandler {
    target: "roku"

    function open(): string { root.open("{}"); return "ok" }
    function close(): string { root.requestClose(); return "ok" }
    function refresh(): string { discovery.start(); return "ok" }
    function refreshApps(): string { roku.refreshApps(); return "ok" }
    function manageFavorites(): string {
      root.managingFavorites = true
      roku.refreshApps()
      return "ok"
    }
    function sendKey(key: string): string { return roku.sendKey(key) ? "ok" : "invalid" }
    function launchApp(appId: string): string {
      return roku.launchApp(appId, "App " + appId) ? "ok" : "invalid"
    }
    function launchDeepLink(appId: string, contentId: string, mediaType: string): string {
      return roku.launchDeepLink(appId, contentId, mediaType) ? "ok" : "invalid"
    }
    function launchChannel(channel: string): string {
      return roku.launchChannel(channel, "Channel " + channel) ? "ok" : "invalid"
    }
    function iconUrl(appId: string): string { return roku.iconUrl(appId) }
    function refreshStatus(): string { return roku.refreshStatus() ? "started" : "busy" }
    function diagnostic(name: string): string {
      return roku.runDiagnostic(name) ? "started" : "invalid-or-busy"
    }
    function exitApp(appId: string, force: bool): string {
      return roku.exitApp(appId, force) ? "ok" : "invalid"
    }
    function addFavorite(kind: string, id: string, name: string): string {
      return root.addFavorite(kind, id, name) ? "ok" : root.favoriteError
    }
    function removeFavorite(kind: string, id: string): string {
      for (var i = 0; i < root.currentFavorites.length; i++) {
        var favorite = root.currentFavorites[i]
        if (favorite.kind === kind && favorite.id === id) {
          root.removeFavorite(favorite)
          return "ok"
        }
      }
      return "unknown"
    }
    function select(ip: string): string {
      if (!root.isLocalIpv4(ip)) return "invalid"
      root.rememberManual(ip)
      root.setSelectedIp(ip)
      return "ok"
    }
    function forget(ip: string): string {
      if (!root.manualForIp(ip)) return "unknown"
      root.forgetManual(ip)
      return "ok"
    }
    function state(): string {
      return JSON.stringify({
        opened: root.opened,
        selectedIp: root.selectedIp,
        connected: roku.connected,
        accessBlocked: roku.accessBlocked,
        lastError: roku.lastError,
        searching: discovery.running,
        appsLoading: roku.appsLoading,
        apps: roku.apps,
        statusLoading: roku.statusLoading,
        status: roku.statusInfo,
        statusError: roku.statusError,
        diagnosticLoading: roku.diagnosticLoading,
        diagnosticName: roku.diagnosticName,
        diagnostic: roku.diagnosticResult,
        diagnosticError: roku.diagnosticError,
        favorites: root.currentFavorites,
        devices: root.devices
      })
    }
  }

  PanelWindow {
    id: panel
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "omarchy-roku-remote"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.opened
      ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    onVisibleChanged: {
      if (visible) Qt.callLater(function() { keyCatcher.forceActiveFocus() })
      else if (!root.closingFromHost && root.opened) root.requestClose()
    }

    Rectangle {
      anchors.fill: parent
      color: Color.menu.scrim
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.requestClose()
    }

    BorderSurface {
      id: card
      readonly property int pad: Style.spacing.panelPadding
      width: Math.min(Style.space(410), panel.width - Style.gapsOut * 2)
      height: Math.min(
        remoteContent.implicitHeight + pad * 2 + borderTop + borderBottom,
        panel.height - Style.gapsOut * 2)
      anchors.centerIn: parent
      radius: Style.cornerRadius
      color: Color.popups.background
      borderSpec: Border.surfaceSpec("popups", "border", Color.popups.border, Math.max(1, Style.space(2)))
      padding: pad

      MouseArea { anchors.fill: parent; onClicked: function(mouse) { mouse.accepted = true } }

      FocusScope {
        id: keyCatcher
        anchors.fill: parent
        anchors.topMargin: card.contentTopInset
        anchors.rightMargin: card.contentRightInset
        anchors.bottomMargin: card.contentBottomInset
        anchors.leftMargin: card.contentLeftInset
        focus: true

        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function(event) {
          if (event.key === Qt.Key_Escape) {
            root.requestClose(); event.accepted = true; return
          }
          if (manualField.activeFocus || literalField.activeFocus
              || selector.popupOpen || favoritesEditor.popupOpen) return
          if (event.key === Qt.Key_Up) {
            roku.sendKey("Up"); event.accepted = true
          } else if (event.key === Qt.Key_Down) {
            roku.sendKey("Down"); event.accepted = true
          } else if (event.key === Qt.Key_Left) {
            roku.sendKey("Left"); event.accepted = true
          } else if (event.key === Qt.Key_Right) {
            roku.sendKey("Right"); event.accepted = true
          } else if (event.key === Qt.Key_Home) {
            roku.sendKey("Home"); event.accepted = true
          } else if (event.key === Qt.Key_Backspace) {
            roku.sendKey("Back"); event.accepted = true
          } else if (event.key === Qt.Key_Space && panel.activeFocusItem === keyCatcher) {
            roku.sendKey("Play"); event.accepted = true
          } else if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
              && panel.activeFocusItem === keyCatcher) {
            roku.sendKey("Select"); event.accepted = true
          }
        }

        Flickable {
          id: scroller
          anchors.fill: parent
          contentWidth: width
          contentHeight: remoteContent.implicitHeight
          clip: true
          boundsBehavior: Flickable.StopAtBounds

          Column {
            id: remoteContent
            width: scroller.width
            spacing: Style.spacing.panelGap

            Row {
              width: parent.width
              spacing: Style.spacing.md

              Text {
                width: parent.width - closeButton.width - parent.spacing
                text: "Roku Remote"
                textFormat: Text.PlainText
                color: Color.popups.text
                font.family: Style.font.family
                font.pixelSize: Style.font.heading
                font.bold: true
                anchors.verticalCenter: parent.verticalCenter
              }

              Button {
                id: closeButton
                iconText: "󰅖"
                tooltipText: "Close (Escape)"
                focusable: true
                onClicked: root.requestClose()
              }
            }

            Components.DeviceSelector {
              id: selector
              width: parent.width
              devices: root.devices
              selectedIp: root.selectedIp
              statusState: root.connectionState
              statusMessage: root.connectionMessage
              searching: discovery.running
              onSelected: function(ip) { root.setSelectedIp(ip) }
              onRefreshRequested: discovery.start()
              onAddRequested: {
                root.addingManual = !root.addingManual
                root.manualError = ""
                if (root.addingManual) Qt.callLater(function() { manualField.forceActiveFocus() })
              }
              onForgetRequested: function(ip) { root.forgetManual(ip) }
            }

            Components.NowPlaying {
              width: parent.width
              deviceSelected: root.selectedIp !== ""
              controlsEnabled: root.controlsEnabled
              loading: roku.statusLoading
              error: roku.statusError
              statusInfo: roku.statusInfo
              onRefreshRequested: roku.refreshStatus()
            }

            BorderSurface {
              width: parent.width
              height: root.addingManual ? manualColumn.implicitHeight + Style.spacing.xl * 2 : 0
              visible: root.addingManual
              radius: Style.cornerRadius
              color: Style.normalFillFor(Color.popups.text, Color.accent)
              borderSpec: Border.controlSpec("normal", Color.popups.text, Color.accent)

              Column {
                id: manualColumn
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.margins: Style.spacing.xl
                spacing: Style.spacing.md

                Text {
                  text: "Add a Roku by IP"
                  textFormat: Text.PlainText
                  color: Color.popups.text
                  font.family: Style.font.family
                  font.pixelSize: Style.font.subtitle
                  font.bold: true
                }

                Row {
                  width: parent.width
                  spacing: Style.spacing.md
                  TextField {
                    id: manualField
                    width: parent.width - addIpButton.width - parent.spacing
                    placeholderText: "192.168.1.50"
                    inputMethodHints: Qt.ImhFormattedNumbersOnly
                    onAccepted: root.addManualIp()
                  }
                  Button {
                    id: addIpButton
                    text: "Add"
                    bordered: true
                    focusable: true
                    onClicked: root.addManualIp()
                  }
                }

                Text {
                  visible: root.manualError !== ""
                  width: parent.width
                  text: root.manualError
                  textFormat: Text.PlainText
                  color: Color.urgent
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption
                  wrapMode: Text.WordWrap
                }
              }
            }

            Text {
              visible: root.transientMessage !== "" && !(root.transientError && roku.accessBlocked)
              width: parent.width
              text: root.transientMessage
              textFormat: Text.PlainText
              color: root.transientError ? Color.urgent : Color.accent
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
            }

            BorderSurface {
              width: parent.width
              height: roku.accessBlocked ? accessWarning.implicitHeight + Style.spacing.xl * 2 : 0
              visible: roku.accessBlocked
              radius: Style.cornerRadius
              color: Util.alpha(Color.urgent, 0.10)
              borderSpec: Border.flat(Util.alpha(Color.urgent, 0.55), Style.spacing.hairline)

              Text {
                id: accessWarning
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.margins: Style.spacing.xl
                text: "Navigation blocked. On the TV: Settings → System → Advanced system settings → Control by mobile apps → Network access → Enabled."
                textFormat: Text.PlainText
                color: Color.urgent
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
                wrapMode: Text.WordWrap
              }
            }

            Button {
              width: parent.width
              iconText: root.managingFavorites ? "󰄬" : "+"
              text: root.managingFavorites ? "Done" : "Add favorite"
              tooltipText: root.managingFavorites
                ? "Close the favorite editor"
                : "Add an app or TV channel"
              bordered: true
              focusable: true
              onClicked: {
                root.managingFavorites = !root.managingFavorites
                root.favoriteError = ""
                if (root.managingFavorites) roku.refreshApps()
              }
            }

            Components.Favorites {
              id: favoritesEditor
              visible: root.managingFavorites
              width: parent.width
              apps: roku.apps
              appsLoading: roku.appsLoading
              appsError: roku.appsError
              favoriteError: root.favoriteError
              controlsEnabled: root.controlsEnabled
              iconBaseUrl: root.controlsEnabled
                ? "http://" + root.selectedIp + ":" + String(roku.selectedPort) + "/query/icon/"
                : ""
              onRefreshAppsRequested: roku.refreshApps()
              onAddRequested: function(kind, id, name) {
                if (root.addFavorite(kind, id, name)) favoritesEditor.clearForm()
              }
            }

            PanelSeparator { foreground: Color.popups.text }

            Row {
              width: parent.width
              spacing: Style.spacing.rowGap
              readonly property real cellWidth: (width - spacing * 2) / 3

              Components.RemoteButton {
                width: parent.cellWidth
                iconText: "󰐥"
                text: "Power on"
                accessibleName: "Power on"
                tooltipText: "Supported Roku TVs and players only"
                enabled: root.controlsEnabled
                onTriggered: roku.sendKey("PowerOn")
              }
              Components.RemoteButton {
                width: parent.cellWidth
                iconText: "󰐥"
                text: "Off"
                accessibleName: "Power off"
                tooltipText: "Roku TV only"
                enabled: root.controlsEnabled
                onTriggered: roku.sendKey("PowerOff")
              }
              Components.RemoteButton {
                width: parent.cellWidth
                iconText: "󰋜"
                text: "Home"
                accessibleName: "Home"
                enabled: root.controlsEnabled
                onTriggered: roku.sendKey("Home")
              }
            }

            Components.DirectionPad {
              anchors.horizontalCenter: parent.horizontalCenter
              controlsEnabled: root.controlsEnabled
              service: roku
            }

            Components.FavoriteButtons {
              width: parent.width
              favorites: root.currentFavorites
              managing: root.managingFavorites
              controlsEnabled: root.controlsEnabled
              onRemoveRequested: function(favorite) { root.removeFavorite(favorite) }
              onLaunchRequested: function(favorite) { root.launchFavorite(favorite) }
            }

            Row {
              width: parent.width
              spacing: Style.spacing.rowGap
              readonly property real cellWidth: (width - spacing) / 2
              Components.RemoteButton {
                width: parent.cellWidth
                iconText: "󰁍"
                text: "Back"
                enabled: root.controlsEnabled
                onTriggered: roku.sendKey("Back")
              }
              Components.RemoteButton {
                width: parent.cellWidth
                iconText: "*"
                text: "Options"
                accessibleName: "Info and options"
                enabled: root.controlsEnabled
                onTriggered: roku.sendKey("Info")
              }
            }

            Row {
              width: parent.width
              spacing: Style.spacing.rowGap
              readonly property real cellWidth: (width - spacing) / 2
              Components.RemoteButton {
                width: parent.cellWidth
                text: "Delete"
                accessibleName: "Backspace"
                enabled: root.controlsEnabled
                onTriggered: roku.sendKey("Backspace")
              }
              Components.RemoteButton {
                width: parent.cellWidth
                text: "Enter"
                accessibleName: "Complete text entry"
                enabled: root.controlsEnabled
                onTriggered: roku.sendKey("Enter")
              }
            }

            Row {
              width: parent.width
              spacing: Style.spacing.rowGap
              readonly property real cellWidth: (width - spacing * 3) / 4
              Components.RemoteButton {
                width: parent.cellWidth
                iconText: "󰒮"
                accessibleName: "Rewind"
                tooltipText: "Rewind"
                enabled: root.controlsEnabled
                onTriggered: roku.sendKey("Rev")
              }
              Components.RemoteButton {
                width: parent.cellWidth
                iconText: "󰐊"
                accessibleName: "Play or pause"
                tooltipText: "Play / Pause"
                selected: true
                enabled: root.controlsEnabled
                onTriggered: roku.sendKey("Play")
              }
              Components.RemoteButton {
                width: parent.cellWidth
                iconText: "󰒭"
                accessibleName: "Fast forward"
                tooltipText: "Fast Forward"
                enabled: root.controlsEnabled
                onTriggered: roku.sendKey("Fwd")
              }
              Components.RemoteButton {
                width: parent.cellWidth
                iconText: "󰑐"
                accessibleName: "Instant replay"
                tooltipText: "Instant Replay"
                enabled: root.controlsEnabled
                onTriggered: roku.sendKey("InstantReplay")
              }
            }

            Column {
              width: parent.width
              spacing: Style.spacing.md
              Text {
                text: "Volume"
                textFormat: Text.PlainText
                color: Color.muted
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
                font.bold: true
              }
              Row {
                width: parent.width
                spacing: Style.spacing.rowGap
                readonly property real cellWidth: (width - spacing * 2) / 3
                Components.RemoteButton {
                  width: parent.cellWidth
                  iconText: "−"
                  text: "Down"
                  accessibleName: "Volume down"
                  tooltipText: "Roku TV only"
                  enabled: root.controlsEnabled
                  onTriggered: roku.sendKey("VolumeDown")
                }
                Components.RemoteButton {
                  width: parent.cellWidth
                  iconText: "󰝟"
                  text: "Mute"
                  accessibleName: "Mute"
                  tooltipText: "Roku TV only"
                  enabled: root.controlsEnabled
                  onTriggered: roku.sendKey("VolumeMute")
                }
                Components.RemoteButton {
                  width: parent.cellWidth
                  iconText: "+"
                  text: "Up"
                  accessibleName: "Volume up"
                  tooltipText: "Roku TV only"
                  enabled: root.controlsEnabled
                  onTriggered: roku.sendKey("VolumeUp")
                }
              }
            }

            Button {
              iconText: "󰌌"
              text: root.textInputVisible ? "Hide keyboard input" : "Keyboard input"
              focusable: true
              bordered: true
              onClicked: {
                root.textInputVisible = !root.textInputVisible
                if (root.textInputVisible) Qt.callLater(function() { literalField.forceActiveFocus() })
              }
            }

            Row {
              visible: root.textInputVisible
              width: parent.width
              spacing: Style.spacing.md
              TextField {
                id: literalField
                width: parent.width - sendTextButton.width - parent.spacing
                placeholderText: "Type into the active Roku field"
                maximumLength: 256
                onAccepted: {
                  if (roku.sendText(text)) text = ""
                }
              }
              Button {
                id: sendTextButton
                text: "Send"
                bordered: true
                focusable: true
                enabled: root.controlsEnabled && literalField.text !== ""
                onClicked: if (roku.sendText(literalField.text)) literalField.text = ""
              }
            }

            Button {
              width: parent.width
              iconText: root.infoVisible ? "󰄬" : "󰋼"
              text: root.infoVisible ? "Hide device info" : "Device & media info"
              bordered: true
              focusable: true
              enabled: root.controlsEnabled
              onClicked: {
                root.infoVisible = !root.infoVisible
                if (root.infoVisible) roku.refreshStatus()
              }
            }

            BorderSurface {
              width: parent.width
              height: root.infoVisible ? infoColumn.implicitHeight + Style.spacing.xl * 2 : 0
              visible: root.infoVisible
              radius: Style.cornerRadius
              color: Style.normalFillFor(Color.popups.text, Color.accent)
              borderSpec: Border.controlSpec("normal", Color.popups.text, Color.accent)

              Column {
                id: infoColumn
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.margins: Style.spacing.xl
                spacing: Style.spacing.sm

                Row {
                  width: parent.width
                  spacing: Style.spacing.md
                  Text {
                    width: parent.width - refreshInfo.width - parent.spacing
                    text: root.selectedDevice
                      ? String(root.selectedDevice.model || "Roku") + " · OS "
                        + String(root.selectedDevice.softwareVersion || "unknown")
                      : "Roku information"
                    textFormat: Text.PlainText
                    color: Color.popups.text
                    font.family: Style.font.family
                    font.pixelSize: Style.font.subtitle
                    font.bold: true
                    elide: Text.ElideRight
                    anchors.verticalCenter: parent.verticalCenter
                  }
                  Button {
                    id: refreshInfo
                    iconText: "󰑐"
                    tooltipText: "Refresh media information"
                    enabled: !roku.statusLoading
                    onClicked: roku.refreshStatus()
                  }
                }

                Text {
                  width: parent.width
                  text: roku.statusLoading
                    ? "Loading current media…"
                    : (roku.statusError
                      ? roku.statusError
                      : (roku.statusInfo && roku.statusInfo.media
                        ? String(roku.statusInfo.media.state || "unknown").toUpperCase()
                          + (roku.statusInfo.media.appName
                            ? " · " + String(roku.statusInfo.media.appName) : "")
                          + (roku.statusInfo.media.position
                            ? " · " + String(roku.statusInfo.media.position) : "")
                        : "No active media details"))
                  textFormat: Text.PlainText
                  color: roku.statusError ? Color.urgent : Color.popups.text
                  font.family: Style.font.family
                  font.pixelSize: Style.font.body
                  wrapMode: Text.WordWrap
                }

                Text {
                  visible: roku.statusInfo && roku.statusInfo.channel
                  width: parent.width
                  text: roku.statusInfo && roku.statusInfo.channel
                    ? "Channel " + String(roku.statusInfo.channel.number || "")
                      + (roku.statusInfo.channel.name ? " · " + String(roku.statusInfo.channel.name) : "")
                      + (roku.statusInfo.channel.program ? " · " + String(roku.statusInfo.channel.program) : "")
                    : ""
                  textFormat: Text.PlainText
                  color: Color.muted
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption
                  wrapMode: Text.WordWrap
                }
              }
            }

            Text {
              width: parent.width
              text: "Keyboard: arrows · Enter · Space · Backspace · Escape closes"
              textFormat: Text.PlainText
              color: Color.muted
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
              horizontalAlignment: Text.AlignHCenter
            }
          }
        }
      }
    }
  }

  Component.onCompleted: stateMkdir.running = true
  Component.onDestruction: roku.releaseHeldKey()
}

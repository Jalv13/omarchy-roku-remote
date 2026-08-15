# Changelog

## 1.5.0 (unreleased)

- Map the focused panel's keyboard controls more naturally: Enter selects,
  Backspace goes back, period/comma adjust volume, and Space toggles mute.
- Add H/P/R/I shortcuts, held-arrow navigation, matching button feedback, an
  in-panel shortcut guide, and automated QML keyboard-event coverage.
- Reconnect directly to the last-used Roku before full discovery completes and
  distinguish reconnecting, refreshing, connected, and offline states.
- Replace the app/channel favorite mode buttons with one queried installed-app
  dropdown and Add button, then render favorites as artwork-based visual tiles.
- Make new favorites available across devices by default, add an unchecked
  **This device only** option, and reduce favorite-tile artwork size.
- Explain device-only scope in a tooltip and add a persisted global **Icons**
  option that updates artwork for all existing app favorites immediately.
- Remove the misleading Search control: ECP can open Roku's voice interface,
  but it cannot carry microphone audio from the computer.
- Reject HTTP redirects, unsafe XML declarations, invalid ports, public route
  scans, oversized responses, and subnet scans beyond 512 total candidates.
- Render Roku-provided labels as plain text and protect private state-directory
  permissions.
- Pin GitHub Actions to immutable commits, add explicit safe-removal guidance,
  and move the marketplace preview to `preview.png`.

## 1.4.0

- Rename the plugin ID to `io.github.jalv13.roku` and use the public developer
  handle in package metadata.

## 1.3.1

- Make Escape close the panel and move the Roku Back keyboard action to
  Backspace.

## 1.3.0

- Add a native Omarchy bar icon as the primary launcher for the centered Roku
  Remote panel.
- Add a compact, on-demand now-playing summary near the top of the panel.
- Add package validation and continuous integration checks.
- Document local-network privacy behavior and security reporting.
- Add marketplace listing copy, support templates, and a neutral remote icon.

## 1.2.0

- Add per-device favorite apps and TV channels.
- Add on-demand media information and developer diagnostics.
- Add bounded subnet discovery fallback and actionable Roku access errors.

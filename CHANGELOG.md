# Changelog

## 1.5.0 (unreleased)

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

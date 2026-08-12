# Marketplace Listing Copy

This file contains publication-ready copy for the Omarchy plugin marketplace.

## Identity

- **Name:** Roku Remote
- **Plugin ID:** `io.github.jalv13.roku`
- **Version:** `1.5.0`
- **Developer:** Jalv13
- **Category:** Hardware
- **License:** MIT
- **Tags:** Bar, Media, Quickshell
- **Icon:** `assets/icon.svg`
- **Primary screenshot:** `preview.png`

## Short description

Control Roku TVs and streaming players from a native Omarchy panel.

## Long description

Roku Remote places a theme-aware remote in the Omarchy bar. It discovers Roku
TVs and players on the local network, opens from a compact bar icon, and
provides navigation, playback, power, volume, text entry, favorite apps and TV
channels, plus an on-demand now-playing summary. It requires no cloud account
and uses only Roku's local External Control Protocol.

## Capabilities

- Native Omarchy bar launcher and centered Quickshell panel
- Automatic SSDP discovery with a bounded private-subnet fallback
- Multiple Roku devices and manual private IPv4 addresses
- Navigation, playback, Roku TV volume/power, and literal text entry
- Per-device favorite apps and live-TV channels
- On-demand media, current app, and active-channel information
- Keyboard navigation and mouse/touch long-press controls

## Access and disclosures

- Connects only to local/private IPv4 addresses supplied by discovery or the user
- Uses SSDP multicast and Roku ECP HTTP port `8060`
- Executes the bundled dependency-free Python helper through Quickshell
- Stores selected devices and favorites locally; no credentials or telemetry
- Does not request microphone access, record audio, or transmit audio
- Does not require authentication, a cloud service, or a listening server
- Uses Omarchy's standard plugin installation and removal commands; it has no
  installer or uninstaller script and does not overwrite user configuration
- Removal deletes only the installed plugin checkout and bar registration;
  the plugin-specific state file is retained unless the user explicitly
  removes it

## Compatibility

- Omarchy 4 (Quattro) with `omarchy-shell`
- Quickshell 0.3 or newer
- Python 3 standard library
- Roku mobile-app network access set to **Enabled**

The final listing should link to `README.md`, `PRIVACY.md`, `SECURITY.md`, and
`SUPPORT.md` in the published repository.

## Maintainer notes

The plugin requires Omarchy 4/Quattro, Quickshell 0.3 or newer, Python 3's
standard library, and local-network access to a Roku on ECP port `8060`. It
does not install packages or services. Standard removal is documented in the
README and does not delete unrelated files or the user's retained favorites.

## Repository links

- **Repository:** https://github.com/Jalv13/omarchy-roku-remote
- **Documentation:** https://github.com/Jalv13/omarchy-roku-remote#readme
- **Privacy:** https://github.com/Jalv13/omarchy-roku-remote/blob/main/PRIVACY.md
- **Security:** https://github.com/Jalv13/omarchy-roku-remote/blob/main/SECURITY.md
- **Support:** https://github.com/Jalv13/omarchy-roku-remote/blob/main/SUPPORT.md

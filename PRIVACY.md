# Privacy

Roku Remote is a local-network controller. It does not use a cloud service,
create an account, collect analytics, send telemetry, or run a listening
server.

## Network activity

When the panel opens or the user requests a refresh, the plugin searches for
Roku devices with SSDP multicast on `239.255.255.250:1900`. If multicast does
not return a device, it performs a bounded scan of the directly connected
private IPv4 subnet for Roku ECP port `8060`, checking no more than 512
addresses. It then communicates directly with the selected Roku over HTTP on
the local network.

The plugin rejects public IP addresses and hostnames supplied through its
manual-address interface. ECP requests do not follow HTTP redirects, preventing
a local endpoint from redirecting a request outside the local network. The
plugin does not intentionally send Roku data outside the local network.

The plugin does not request microphone access, record audio, or transmit
audio.

## Stored data

The plugin stores the selected Roku's local IP and stable device identifier,
manually added local IP addresses, and per-device favorite names and IDs in:

```text
~/.local/state/omarchy/settings/roku-remote.json
```

It does not store Roku account credentials. Removing that file clears all
saved Roku Remote data. Removing the plugin does not automatically remove the
state file so an update or reinstall does not unexpectedly erase favorites.
The containing state directory is created with user-only permissions.

Roku is a trademark of Roku, Inc. This unofficial plugin is not affiliated
with or endorsed by Roku, Inc.

# Security Policy

Security fixes are provided for the latest released version of Roku Remote.

Please do not open a public issue for a suspected vulnerability. Use the
repository's [private vulnerability reporting form](https://github.com/Jalv13/omarchy-roku-remote/security/advisories/new)
so the report can be reviewed privately. Include the plugin version, Omarchy
version, reproduction steps, and the security impact. Do not include Roku
account credentials or other private network data.

The plugin runs inside the long-lived `omarchy-shell` process and invokes its
bundled Python helper. Review the source before installation and install only
from the repository URL documented in the README.

The helper accepts only local/private IPv4 targets, refuses HTTP redirects,
uses bounded response sizes and timeouts, and invokes system commands without
a shell. Text originating from a Roku is rendered as plain text or sanitized
before it reaches shared Omarchy controls.

#!/usr/bin/env python3
"""Run a tiny local Roku ECP mock for manual plugin testing."""

from __future__ import annotations

import argparse
import json
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


DEVICE_XML = b"""<?xml version="1.0" encoding="UTF-8" ?>
<device-info>
  <user-device-name>Mock Living Room Roku</user-device-name>
  <model-name>Omarchy Test Roku TV</model-name>
  <serial-number>MOCK-ROKU-001</serial-number>
  <device-id>MOCK-ROKU-001</device-id>
  <software-version>14.5.0</software-version>
  <is-tv>true</is-tv>
</device-info>
"""

APPS_XML = b"""<?xml version="1.0" encoding="UTF-8" ?>
<apps>
  <app id="12" type="appl" version="6.4.0">Netflix</app>
  <app id="13" type="appl" version="15.2.1">Prime Video</app>
  <app id="837" type="appl" version="2.24.1">YouTube</app>
</apps>
"""

MEDIA_XML = b"""<?xml version="1.0" encoding="UTF-8" ?>
<player error="false" state="play">
  <plugin id="837" name="YouTube"/><format audio="aac" video="h264" video_res="1920x1080"/>
  <position>6916 ms</position><duration>887999 ms</duration><is_live>false</is_live>
</player>
"""

ACTIVE_CHANNEL_XML = b"""<?xml version="1.0" encoding="UTF-8" ?>
<tv-channel><channel><number>14.3</number><name>getTV</name>
<active-input>true</active-input><program-title>Airwolf</program-title></channel></tv-channel>
"""


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/query/device-info":
            body = DEVICE_XML
        elif self.path == "/query/apps":
            body = APPS_XML
        elif self.path == "/query/media-player":
            body = MEDIA_XML
        elif self.path == "/query/tv-active-channel":
            body = ACTIVE_CHANNEL_XML
        elif self.path.startswith("/query/icon/"):
            body = b"mock-image"
        elif self.path in {
            "/query/tv-channels", "/query/chanperf", "/query/graphics-frame-rate",
            "/query/r2d2-bitmaps", "/query/sgnodes", "/query/registry",
        }:
            body = b"<result><status>OK</status></result>"
        else:
            self.send_error(404)
            return
        self.send_response(200)
        self.send_header("Content-Type", "text/xml")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_POST(self):
        print(json.dumps({"method": "POST", "path": self.path}), flush=True)
        self.send_response(200)
        self.send_header("Content-Length", "0")
        self.end_headers()

    def log_message(self, format_string, *args):
        print(format_string % args, flush=True)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8060)
    args = parser.parse_args()
    server = ThreadingHTTPServer((args.host, args.port), Handler)
    print(f"Mock Roku listening at http://{args.host}:{args.port}", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == "__main__":
    main()

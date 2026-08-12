from __future__ import annotations

import socket
import sys
import threading
import time
import unittest
import ipaddress
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from unittest import mock


SCRIPTS = Path(__file__).resolve().parents[1] / "scripts"
sys.path.insert(0, str(SCRIPTS))
import roku_ecp  # noqa: E402


DEVICE_XML = """<?xml version="1.0" encoding="UTF-8" ?>
<device-info>
  <user-device-name>Living Room Roku</user-device-name>
  <model-name>Roku TV 4K</model-name>
  <serial-number>YN0012345678</serial-number>
  <device-id>DEV-123</device-id>
  <software-version>14.5.0</software-version>
  <is-tv>true</is-tv>
</device-info>
"""

APPS_XML = """<?xml version="1.0" encoding="UTF-8" ?>
<apps>
  <app id="13" type="appl" version="15.2.1">Prime Video</app>
  <app id="837" type="appl" version="2.24.1">YouTube</app>
  <app id="12" type="appl" version="6.4.0">Netflix</app>
</apps>
"""

MEDIA_XML = """<?xml version="1.0" encoding="UTF-8" ?>
<player error="false" state="play">
  <plugin bandwidth="44692475 bps" id="837" name="YouTube"/>
  <format audio="aac" container="mp4" video="mpeg4_15" video_res="1280x720"/>
  <buffering current="1000" max="1000" target="0"/>
  <position>6916 ms</position>
  <duration>887999 ms</duration>
  <is_live>false</is_live>
  <runtime>887999 ms</runtime>
</player>
"""

ACTIVE_CHANNEL_XML = """<?xml version="1.0" encoding="UTF-8" ?>
<tv-channel><channel>
  <number>14.3</number><name>getTV</name><type>air-digital</type>
  <active-input>true</active-input><signal-state>valid</signal-state>
  <signal-quality>20</signal-quality><program-title>Airwolf</program-title>
</channel></tv-channel>
"""


class MockRokuHandler(BaseHTTPRequestHandler):
    paths: list[str] = []
    delay = 0.0
    post_status = 200
    redirect_followed = False

    def do_GET(self):
        if self.delay:
            time.sleep(self.delay)
        if self.path == "/redirect-source":
            self.send_response(302)
            self.send_header("Location", "/redirect-target")
            self.end_headers()
            return
        if self.path == "/redirect-target":
            type(self).redirect_followed = True
            body = b"redirect followed"
        elif self.path == "/query/device-info":
            body = DEVICE_XML.encode()
        elif self.path == "/query/apps":
            body = APPS_XML.encode()
        elif self.path == "/query/media-player":
            body = MEDIA_XML.encode()
        elif self.path == "/query/tv-active-channel":
            body = ACTIVE_CHANNEL_XML.encode()
        elif self.path in {
            "/query/tv-channels", "/query/chanperf", "/query/graphics-frame-rate",
            "/query/r2d2-bitmaps", "/query/sgnodes", "/query/registry",
        }:
            body = b"<result><status>OK</status></result>"
        elif self.path == "/query/icon/837":
            body = b"mock-image"
        else:
            self.send_error(404)
            return
        self.send_response(200)
        self.send_header("Content-Type", "text/xml")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        try:
            self.wfile.write(body)
        except BrokenPipeError:
            pass

    def do_POST(self):
        type(self).paths.append(self.path)
        body = b"ECP command not allowed" if self.post_status == 403 else b""
        self.send_response(self.post_status)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        if body:
            self.wfile.write(body)

    def log_message(self, _format, *_args):
        pass


class MockRoku:
    def __enter__(self):
        MockRokuHandler.paths = []
        MockRokuHandler.delay = 0.0
        MockRokuHandler.post_status = 200
        MockRokuHandler.redirect_followed = False
        self.server = ThreadingHTTPServer(("127.0.0.1", 0), MockRokuHandler)
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()
        return self.server.server_address[1]

    def __exit__(self, *_args):
        self.server.shutdown()
        self.server.server_close()
        self.thread.join(timeout=1)


class SsdpTests(unittest.TestCase):
    def test_parses_case_insensitive_roku_response(self):
        response = (
            "HTTP/1.1 200 OK\r\n"
            "Location: http://192.168.1.42:8060/\r\n"
            "ST: roku:ecp\r\n"
            "USN: uuid:roku:ecp:ABC\r\n\r\n"
        )
        location = roku_ecp.parse_ssdp_response(response)
        self.assertEqual((location.ip, location.port), ("192.168.1.42", 8060))
        self.assertEqual(location.usn, "uuid:roku:ecp:ABC")

    def test_rejects_malformed_and_non_roku_responses(self):
        self.assertIsNone(roku_ecp.parse_ssdp_response("garbage"))
        self.assertIsNone(
            roku_ecp.parse_ssdp_response(
                "HTTP/1.1 200 OK\r\nLOCATION: http://192.168.1.3:8060/\r\nST: upnp:rootdevice\r\n\r\n"
            )
        )
        self.assertIsNone(
            roku_ecp.parse_ssdp_response(
                "HTTP/1.1 200 OK\r\nLOCATION: http://8.8.8.8:8060/\r\nST: roku:ecp\r\n\r\n"
            )
        )

    def test_deduplicates_responses(self):
        locations = [
            roku_ecp.Location("192.168.1.9", 8060, "one"),
            roku_ecp.Location("192.168.1.9", 8060, "two"),
            roku_ecp.Location("192.168.1.10", 8060, "three"),
        ]
        self.assertEqual(len(roku_ecp.dedupe_locations(locations)), 2)

    def test_parses_and_bounds_local_routes(self):
        routes = """[
          {"dst":"10.0.0.0/24","dev":"wlan0","prefsrc":"10.0.0.44"},
          {"dst":"192.168.0.0/16","dev":"eth0","prefsrc":"192.168.7.8"},
          {"dst":"0.0.0.0/1","dev":"bad0","prefsrc":"10.1.2.3"},
          {"dst":"default","dev":"wlan0","gateway":"10.0.0.1"},
          {"dst":"203.0.113.0/24","dev":"tun0","prefsrc":"203.0.113.8"}
        ]"""
        self.assertEqual(
            roku_ecp.route_networks_from_json(routes),
            [ipaddress.ip_network("10.0.0.0/24"), ipaddress.ip_network("192.168.7.0/24")],
        )


class EndpointAndXmlTests(unittest.TestCase):
    def test_ecp_endpoints(self):
        self.assertEqual(
            roku_ecp.ecp_url("192.168.1.50", "keypress", "Home"),
            "http://192.168.1.50:8060/keypress/Home",
        )
        self.assertEqual(
            roku_ecp.ecp_url("192.168.1.50", "keydown", "Down"),
            "http://192.168.1.50:8060/keydown/Down",
        )
        self.assertEqual(
            roku_ecp.ecp_url("192.168.1.50", "keyup", "Down"),
            "http://192.168.1.50:8060/keyup/Down",
        )
        self.assertTrue(roku_ecp.ecp_url("192.168.1.50", "keypress", "Lit_ ").endswith("/Lit_%20"))
        self.assertEqual(
            roku_ecp.ecp_url("192.168.1.50", "keypress", "PowerOff"),
            "http://192.168.1.50:8060/keypress/PowerOff",
        )
        self.assertEqual(
            roku_ecp.ecp_url("192.168.1.50", "keypress", "PowerOn"),
            "http://192.168.1.50:8060/keypress/PowerOn",
        )
        self.assertEqual(
            roku_ecp.launch_url("192.168.1.50", "837"),
            "http://192.168.1.50:8060/launch/837",
        )
        self.assertEqual(
            roku_ecp.launch_url("192.168.1.50", "tvinput.dtv", channel="5.1"),
            "http://192.168.1.50:8060/launch/tvinput.dtv?ch=5.1",
        )
        self.assertEqual(
            roku_ecp.launch_url(
                "192.168.1.50", "837", parameters={"contentId": "a & b", "mediaType": "movie"}
            ),
            "http://192.168.1.50:8060/launch/837?contentId=a+%26+b&mediaType=movie",
        )
        self.assertEqual(
            roku_ecp.icon_url("192.168.1.50", "837"),
            "http://192.168.1.50:8060/query/icon/837",
        )

    def test_rejects_public_invalid_and_unknown_keys(self):
        for value in ("8.8.8.8", "roku.example.com", "999.1.1.1", ""):
            with self.subTest(value=value), self.assertRaises(roku_ecp.EcpError):
                roku_ecp.normalize_local_ip(value)
        for port in (0, -1, 65536, "not-a-port"):
            with self.subTest(port=port), self.assertRaises(roku_ecp.EcpError):
                roku_ecp.ecp_url("192.168.1.50", "keypress", "Home", port=port)
        with self.assertRaises(roku_ecp.EcpError):
            roku_ecp.ecp_url("192.168.1.50", "keypress", "FactoryReset")
        for app_id in ("", "../settings", "app id", "x" * 129):
            with self.subTest(app_id=app_id), self.assertRaises(roku_ecp.EcpError):
                roku_ecp.launch_url("192.168.1.50", app_id)
        for channel in ("abc", "5.1.2", "5&foo=bar"):
            with self.subTest(channel=channel), self.assertRaises(roku_ecp.EcpError):
                roku_ecp.launch_url("192.168.1.50", "tvinput.dtv", channel=channel)
        with self.assertRaises(roku_ecp.EcpError):
            roku_ecp.launch_url("192.168.1.50", "837", parameters={"bad&name": "value"})
        with self.assertRaises(roku_ecp.EcpError):
            roku_ecp.query_endpoint("192.168.1.50", "arbitrary-path")

    def test_device_info_parser(self):
        device = roku_ecp.parse_device_info(DEVICE_XML, "192.168.1.42")
        self.assertEqual(device["name"], "Living Room Roku")
        self.assertEqual(device["deviceId"], "DEV-123")
        self.assertEqual(device["model"], "Roku TV 4K")
        self.assertTrue(device["isTv"])

    def test_malformed_xml(self):
        with self.assertRaises(roku_ecp.EcpError):
            roku_ecp.parse_device_info("<device-info>", "192.168.1.42")
        with self.assertRaises(roku_ecp.EcpError):
            roku_ecp.parse_apps("<apps>")
        for declaration in (
            '<!DOCTYPE apps [<!ENTITY x "unsafe">]><apps>&x;</apps>',
            '<!ENTITY x "unsafe"><apps/>',
        ):
            with self.subTest(declaration=declaration), self.assertRaises(roku_ecp.EcpError):
                roku_ecp.parse_apps(declaration)

    def test_apps_parser(self):
        apps = roku_ecp.parse_apps(APPS_XML)
        self.assertEqual([app["name"] for app in apps], ["Netflix", "Prime Video", "YouTube"])
        self.assertEqual(apps[2]["id"], "837")

    def test_media_and_tv_channel_parsers(self):
        media = roku_ecp.parse_media_player(MEDIA_XML)
        self.assertEqual((media["state"], media["appName"]), ("play", "YouTube"))
        self.assertEqual((media["audio"], media["resolution"]), ("aac", "1280x720"))
        channels = roku_ecp.parse_tv_channels(ACTIVE_CHANNEL_XML)
        self.assertEqual(channels[0]["number"], "14.3")
        self.assertEqual(channels[0]["program"], "Airwolf")
        self.assertTrue(channels[0]["active"])

    def test_diagnostic_xml_is_structured(self):
        tree = roku_ecp.xml_tree(roku_ecp.ET.fromstring(
            '<chanperf><plugin id="dev"><memory><used>12</used></memory></plugin></chanperf>'
        ))
        self.assertEqual(tree["tag"], "chanperf")
        self.assertEqual(tree["children"][0]["attributes"]["id"], "dev")


class NetworkTests(unittest.TestCase):
    def test_http_redirects_are_not_followed(self):
        with MockRoku() as port:
            request = roku_ecp.urllib.request.Request(
                f"http://127.0.0.1:{port}/redirect-source"
            )
            with self.assertRaises(roku_ecp.EcpError) as caught:
                roku_ecp._open(request, 0.5)
            self.assertEqual(caught.exception.kind, "redirect")
            self.assertFalse(MockRokuHandler.redirect_followed)

    def test_mock_roku_info_and_controls(self):
        with MockRoku() as port:
            device = roku_ecp.query_device_info("127.0.0.1", port=port)
            self.assertEqual(device["name"], "Living Room Roku")
            apps = roku_ecp.query_apps("127.0.0.1", port=port)
            self.assertEqual(apps[-1]["name"], "YouTube")
            result = roku_ecp.request_ecp("127.0.0.1", "keypress", "Home", port=port)
            self.assertTrue(result["ok"])
            roku_ecp.request_ecp("127.0.0.1", "keydown", "Down", port=port)
            roku_ecp.request_ecp("127.0.0.1", "keyup", "Down", port=port)
            roku_ecp.request_launch("127.0.0.1", "837", port=port)
            roku_ecp.request_launch(
                "127.0.0.1", "837", port=port,
                parameters={"contentId": "movie 1", "mediaType": "movie"},
            )
            roku_ecp.request_launch("127.0.0.1", "tvinput.dtv", port=port, channel="5.1")
            status = roku_ecp.query_status("127.0.0.1", port=port)
            self.assertEqual(status["media"]["state"], "play")
            self.assertEqual(status["channel"]["number"], "14.3")
            diagnostic = roku_ecp.query_endpoint("127.0.0.1", "chanperf", port=port)
            self.assertEqual(diagnostic["data"]["tag"], "result")
            roku_ecp.request_exit_app("127.0.0.1", "837", port=port, force=True)
            self.assertEqual(
                MockRokuHandler.paths,
                [
                    "/keypress/Home",
                    "/keydown/Down",
                    "/keyup/Down",
                    "/launch/837",
                    "/launch/837?contentId=movie+1&mediaType=movie",
                    "/launch/tvinput.dtv?ch=5.1",
                    "/exit-app/837/true",
                ],
            )

    def test_bounded_subnet_fallback_finds_ecp_port(self):
        with MockRoku() as port:
            locations = roku_ecp.scan_ecp_hosts(
                [ipaddress.ip_network("127.0.0.1/32")], port=port, timeout=0.1
            )
            self.assertEqual([(item.ip, item.port) for item in locations], [("127.0.0.1", port)])

    def test_subnet_fallback_caps_total_candidates(self):
        attempted: list[str] = []

        def closed(ip, _port, _timeout):
            attempted.append(ip)
            return False

        networks = [
            ipaddress.ip_network("10.0.0.0/24"),
            ipaddress.ip_network("192.168.0.0/24"),
            ipaddress.ip_network("172.16.0.0/24"),
        ]
        with mock.patch.object(roku_ecp, "_port_open", side_effect=closed):
            self.assertEqual(roku_ecp.scan_ecp_hosts(networks), [])
        self.assertEqual(len(attempted), 512)

    def test_forbidden_control_is_actionable(self):
        with MockRoku() as port:
            MockRokuHandler.post_status = 403
            with self.assertRaises(roku_ecp.EcpError) as caught:
                roku_ecp.request_ecp("127.0.0.1", "keypress", "Home", port=port)
            self.assertEqual(caught.exception.kind, "forbidden")
            self.assertEqual(caught.exception.status, 403)
            self.assertIn("Network access", str(caught.exception))

    def test_connection_refused(self):
        sock = socket.socket()
        sock.bind(("127.0.0.1", 0))
        port = sock.getsockname()[1]
        sock.close()
        with self.assertRaises(roku_ecp.EcpError) as caught:
            roku_ecp.query_device_info("127.0.0.1", port=port, timeout=0.1)
        self.assertEqual(caught.exception.kind, "network")

    def test_timeout(self):
        with MockRoku() as port:
            MockRokuHandler.delay = 0.2
            with self.assertRaises(roku_ecp.EcpError) as caught:
                roku_ecp.query_device_info("127.0.0.1", port=port, timeout=0.05)
            self.assertEqual(caught.exception.kind, "timeout")

    def test_device_disappears(self):
        mock = MockRoku()
        port = mock.__enter__()
        roku_ecp.query_device_info("127.0.0.1", port=port)
        mock.__exit__()
        with self.assertRaises(roku_ecp.EcpError):
            roku_ecp.request_ecp("127.0.0.1", "keypress", "Home", port=port, timeout=0.1)


if __name__ == "__main__":
    unittest.main()

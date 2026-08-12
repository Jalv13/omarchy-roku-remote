#!/usr/bin/env python3
"""Small, dependency-free Roku ECP client used by the Quickshell plugin.

All output is one JSON object on stdout. Diagnostics go to stderr. The helper
accepts only local IPv4 targets and never starts a listening service.
"""

from __future__ import annotations

import argparse
import concurrent.futures
import ipaddress
import json
import re
import socket
# Used only with the absolute /usr/bin/ip path, static arguments, and no shell.
import subprocess  # nosec B404
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
# XML is size-bounded and declarations/entities are rejected before parsing.
import xml.etree.ElementTree as ET  # nosec B405
from dataclasses import dataclass
from typing import Iterable


SSDP_ADDRESS = ("239.255.255.250", 1900)
SSDP_REQUEST = (
    "M-SEARCH * HTTP/1.1\r\n"
    "HOST: 239.255.255.250:1900\r\n"
    'MAN: "ssdp:discover"\r\n'
    "MX: 1\r\n"
    "ST: roku:ecp\r\n"
    "\r\n"
).encode("ascii")

ALLOWED_KEYS = {
    "Home", "Rev", "Fwd", "Play", "Select", "Left", "Right", "Down",
    "Up", "Back", "InstantReplay", "Info", "Backspace", "Search", "Enter",
    "PowerOff", "PowerOn", "VolumeDown", "VolumeMute", "VolumeUp",
}

APP_ID_PATTERN = re.compile(r"^[A-Za-z0-9._-]{1,128}$")
TV_CHANNEL_PATTERN = re.compile(r"^\d{1,4}(?:\.\d{1,3})?$")
PARAMETER_NAME_PATTERN = re.compile(r"^[A-Za-z][A-Za-z0-9_.-]{0,63}$")
QUERY_ENDPOINTS = {
    "media-player": "media-player",
    "tv-channels": "tv-channels",
    "tv-active-channel": "tv-active-channel",
    "chanperf": "chanperf",
    "graphics-frame-rate": "graphics-frame-rate",
    "r2d2-bitmaps": "r2d2-bitmaps",
    "sgnodes": "sgnodes",
    "registry": "registry",
}
MAX_XML_BYTES = 2 * 1024 * 1024
IP_COMMAND = "/usr/bin/ip"

LOCAL_NETWORKS = tuple(
    ipaddress.ip_network(value)
    for value in (
        "10.0.0.0/8",
        "100.64.0.0/10",
        "127.0.0.0/8",
        "169.254.0.0/16",
        "172.16.0.0/12",
        "192.168.0.0/16",
    )
)


class EcpError(RuntimeError):
    def __init__(self, message: str, *, kind: str = "network", status: int = 0):
        super().__init__(message)
        self.kind = kind
        self.status = status


class _NoRedirectHandler(urllib.request.HTTPRedirectHandler):
    """Keep local ECP requests from being redirected to another origin."""

    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


HTTP_OPENER = urllib.request.build_opener(_NoRedirectHandler())


@dataclass(frozen=True)
class Location:
    ip: str
    port: int = 8060
    location: str = ""
    usn: str = ""


def json_result(payload: dict, exit_code: int = 0) -> int:
    print(json.dumps(payload, ensure_ascii=False, separators=(",", ":")))
    return exit_code


def normalize_local_ip(value: str) -> str:
    candidate = str(value or "").strip()
    if not candidate:
        raise EcpError("IP address is empty", kind="invalid")
    try:
        address = ipaddress.ip_address(candidate)
    except ValueError as exc:
        raise EcpError(f"Invalid IPv4 address: {candidate}", kind="invalid") from exc
    if address.version != 4 or not any(address in network for network in LOCAL_NETWORKS):
        raise EcpError("Only local-network IPv4 addresses are allowed", kind="invalid")
    return str(address)


def normalize_port(value: int | str) -> int:
    try:
        port = int(value)
    except (TypeError, ValueError) as exc:
        raise EcpError("Invalid ECP port", kind="invalid") from exc
    if not 1 <= port <= 65535:
        raise EcpError("ECP port must be between 1 and 65535", kind="invalid")
    return port


def ecp_url(ip: str, action: str, key: str, port: int = 8060) -> str:
    host = normalize_local_ip(ip)
    target_port = normalize_port(port)
    if action not in {"keypress", "keydown", "keyup"}:
        raise EcpError(f"Unsupported ECP action: {action}", kind="invalid")
    if key.startswith("Lit_"):
        literal = key[4:]
        if not literal:
            raise EcpError("Literal key is empty", kind="invalid")
        encoded_key = "Lit_" + urllib.parse.quote(literal, safe="")
    elif key in ALLOWED_KEYS:
        encoded_key = key
    else:
        raise EcpError(f"Unsupported ECP key: {key}", kind="invalid")
    return f"http://{host}:{target_port}/{action}/{encoded_key}"


def _open(request: urllib.request.Request, timeout: float):
    try:
        return HTTP_OPENER.open(request, timeout=max(0.05, timeout))
    except urllib.error.HTTPError as exc:
        status = exc.code
        exc.close()
        if 300 <= status < 400:
            raise EcpError(
                "Roku response attempted an HTTP redirect; redirects are not allowed",
                kind="redirect",
                status=status,
            ) from exc
        if status == 403:
            raise EcpError(
                "Roku blocked remote commands; enable Settings > System > Advanced system settings > Control by mobile apps > Network access",
                kind="forbidden",
                status=status,
            ) from exc
        unsupported = status in {400, 404, 405, 501}
        kind = "unsupported" if unsupported else "http"
        raise EcpError(f"Roku returned HTTP {status}", kind=kind, status=status) from exc
    except (urllib.error.URLError, TimeoutError, socket.timeout, ConnectionError) as exc:
        reason = getattr(exc, "reason", exc)
        kind = "timeout" if isinstance(reason, (TimeoutError, socket.timeout)) else "network"
        if "timed out" in str(reason).lower():
            kind = "timeout"
        raise EcpError(str(reason), kind=kind) from exc


def _read_limited(response, limit: int, label: str) -> bytes:
    raw = response.read(limit + 1)
    if len(raw) > limit:
        raise EcpError(f"{label} exceeds {limit // 1024} KiB", kind="malformed")
    return raw


def parse_xml(xml_text: str, label: str) -> ET.Element:
    value = str(xml_text)
    if len(value.encode("utf-8", errors="replace")) > MAX_XML_BYTES:
        raise EcpError(f"{label} XML exceeds 2 MiB", kind="malformed")
    if re.search(r"<!\s*(?:DOCTYPE|ENTITY)\b", value, flags=re.IGNORECASE):
        raise EcpError(f"{label} XML declarations are not allowed", kind="malformed")
    try:
        # Input is bounded and DTD/entity declarations were rejected above.
        return ET.fromstring(value)  # nosec B314
    except ET.ParseError as exc:
        raise EcpError(f"Malformed {label} XML: {exc}", kind="malformed") from exc


def request_ecp(
    ip: str,
    action: str,
    key: str,
    *,
    timeout: float = 1.2,
    port: int = 8060,
) -> dict:
    url = ecp_url(ip, action, key, port)
    request = urllib.request.Request(
        url,
        data=b"",
        method="POST",
        headers={"User-Agent": "Omarchy-Roku-Remote/1.0"},
    )
    started = time.monotonic()
    with _open(request, timeout) as response:
        response.read(1024)
        status = int(getattr(response, "status", 200))
    return {
        "ok": True,
        "reachable": True,
        "action": action,
        "key": key,
        "url": url,
        "status": status,
        "elapsedMs": round((time.monotonic() - started) * 1000),
    }


def request_literal(
    ip: str,
    text: str,
    *,
    timeout: float = 1.2,
    port: int = 8060,
) -> dict:
    if len(text) > 256:
        raise EcpError("Text input is limited to 256 characters", kind="invalid")
    sent = 0
    for character in text:
        request_ecp(ip, "keypress", "Lit_" + character, timeout=timeout, port=port)
        sent += 1
    return {"ok": True, "reachable": True, "sent": sent}


def normalize_app_id(value: str) -> str:
    app_id = str(value or "").strip()
    if not APP_ID_PATTERN.fullmatch(app_id):
        raise EcpError("Invalid Roku app ID", kind="invalid")
    return app_id


def normalize_tv_channel(value: str) -> str:
    channel = str(value or "").strip()
    if not TV_CHANNEL_PATTERN.fullmatch(channel):
        raise EcpError("Invalid TV channel; use a number such as 5 or 5.1", kind="invalid")
    return channel


def launch_url(
    ip: str,
    app_id: str,
    *,
    port: int = 8060,
    channel: str = "",
    parameters: dict[str, str] | None = None,
) -> str:
    host = normalize_local_ip(ip)
    target_port = normalize_port(port)
    target = normalize_app_id(app_id)
    url = f"http://{host}:{target_port}/launch/{urllib.parse.quote(target, safe='')}"
    query: dict[str, str] = {}
    if channel:
        query["ch"] = normalize_tv_channel(channel)
    for raw_name, raw_value in (parameters or {}).items():
        name = str(raw_name).strip()
        value = str(raw_value)
        if not PARAMETER_NAME_PATTERN.fullmatch(name):
            raise EcpError(f"Invalid launch parameter name: {name}", kind="invalid")
        if len(value) > 512 or (name.lower() == "contentid" and len(value) > 254):
            raise EcpError(f"Launch parameter is too long: {name}", kind="invalid")
        query[name] = value
    if len(query) > 16:
        raise EcpError("A launch can include at most 16 parameters", kind="invalid")
    if query:
        url += "?" + urllib.parse.urlencode(query)
    return url


def request_launch(
    ip: str,
    app_id: str,
    *,
    timeout: float = 1.2,
    port: int = 8060,
    channel: str = "",
    parameters: dict[str, str] | None = None,
) -> dict:
    url = launch_url(ip, app_id, port=port, channel=channel, parameters=parameters)
    request = urllib.request.Request(
        url,
        data=b"",
        method="POST",
        headers={"User-Agent": "Omarchy-Roku-Remote/1.0"},
    )
    started = time.monotonic()
    with _open(request, timeout) as response:
        response.read(1024)
        status = int(getattr(response, "status", 200))
    return {
        "ok": True,
        "reachable": True,
        "appId": app_id,
        "channel": channel,
        "parameters": parameters or {},
        "url": url,
        "status": status,
        "elapsedMs": round((time.monotonic() - started) * 1000),
    }


def parse_device_info(xml_text: str, ip: str, port: int = 8060) -> dict:
    root = parse_xml(xml_text, "Roku device")

    values = {child.tag: (child.text or "").strip() for child in root}
    name = next(
        (
            values.get(key, "")
            for key in (
                "user-device-name",
                "friendly-device-name",
                "default-device-name",
                "model-name",
            )
            if values.get(key, "")
        ),
        f"Roku at {ip}",
    )
    return {
        "ip": ip,
        "port": int(port),
        "name": name,
        "model": values.get("model-name", "Roku"),
        "serial": values.get("serial-number", ""),
        "deviceId": values.get("device-id", "") or values.get("serial-number", ""),
        "softwareVersion": values.get("software-version", ""),
        "isTv": values.get("is-tv", "").lower() == "true",
        "online": True,
    }


def parse_apps(xml_text: str) -> list[dict]:
    root = parse_xml(xml_text, "Roku apps")

    apps: list[dict] = []
    seen: set[str] = set()
    for node in root.findall("app"):
        app_id = str(node.attrib.get("id", "")).strip()
        name = "".join(node.itertext()).strip()
        if not APP_ID_PATTERN.fullmatch(app_id) or not name or app_id in seen:
            continue
        seen.add(app_id)
        apps.append(
            {
                "id": app_id,
                "name": name,
                "type": str(node.attrib.get("type", "")).strip(),
                "version": str(node.attrib.get("version", "")).strip(),
            }
        )
    return sorted(apps, key=lambda item: item["name"].casefold())


def _text(node: ET.Element | None) -> str:
    return "" if node is None else "".join(node.itertext()).strip()


def parse_media_player(xml_text: str) -> dict:
    root = parse_xml(xml_text, "Roku media-player")
    if root.tag != "player":
        raise EcpError("Unexpected Roku media-player response", kind="malformed")
    plugin = root.find("plugin")
    media_format = root.find("format")
    buffering = root.find("buffering")
    return {
        "state": str(root.attrib.get("state", "unknown")),
        "error": str(root.attrib.get("error", "false")).lower() == "true",
        "appId": "" if plugin is None else str(plugin.attrib.get("id", "")),
        "appName": "" if plugin is None else str(plugin.attrib.get("name", "")),
        "position": _text(root.find("position")),
        "duration": _text(root.find("duration")),
        "runtime": _text(root.find("runtime")),
        "isLive": _text(root.find("is_live")).lower() == "true",
        "audio": "" if media_format is None else str(media_format.attrib.get("audio", "")),
        "video": "" if media_format is None else str(media_format.attrib.get("video", "")),
        "resolution": "" if media_format is None else str(media_format.attrib.get("video_res", "")),
        "buffering": "" if buffering is None else str(buffering.attrib.get("current", "")),
        "bufferingMax": "" if buffering is None else str(buffering.attrib.get("max", "")),
    }


def parse_tv_channels(xml_text: str) -> list[dict]:
    root = parse_xml(xml_text, "Roku TV channel")
    result: list[dict] = []
    for channel in root.findall(".//channel"):
        values = {child.tag: _text(child) for child in channel}
        if not values.get("number") and not values.get("name"):
            continue
        result.append({
            "number": values.get("number", ""),
            "name": values.get("name", ""),
            "type": values.get("type", ""),
            "active": values.get("active-input", "").lower() == "true",
            "signal": values.get("signal-state", ""),
            "quality": values.get("signal-quality", ""),
            "program": values.get("program-title", ""),
            "description": values.get("program-description", ""),
        })
    return result


def xml_tree(node: ET.Element) -> dict:
    result: dict = {"tag": node.tag}
    if node.attrib:
        result["attributes"] = dict(node.attrib)
    text = (node.text or "").strip()
    if text:
        result["text"] = text
    children = [xml_tree(child) for child in node]
    if children:
        result["children"] = children
    return result


def query_xml(
    ip: str,
    endpoint: str,
    *,
    timeout: float = 1.0,
    port: int = 8060,
) -> str:
    host = normalize_local_ip(ip)
    target_port = normalize_port(port)
    path = QUERY_ENDPOINTS.get(str(endpoint))
    if not path:
        raise EcpError(f"Unsupported Roku query: {endpoint}", kind="invalid")
    url = f"http://{host}:{target_port}/query/{path}"
    request = urllib.request.Request(url, headers={"User-Agent": "Omarchy-Roku-Remote/1.0"})
    with _open(request, timeout) as response:
        raw = _read_limited(response, 2 * 1024 * 1024, "Roku query response")
    return raw.decode("utf-8", errors="replace")


def query_endpoint(
    ip: str,
    endpoint: str,
    *,
    timeout: float = 1.0,
    port: int = 8060,
) -> dict:
    raw = query_xml(ip, endpoint, timeout=timeout, port=port)
    root = parse_xml(raw, f"Roku {endpoint}")
    return {"endpoint": endpoint, "data": xml_tree(root)}


def query_status(ip: str, *, timeout: float = 1.0, port: int = 8060) -> dict:
    result = {"media": parse_media_player(query_xml(
        ip, "media-player", timeout=timeout, port=port
    )), "channel": None}
    try:
        channels = parse_tv_channels(query_xml(
            ip, "tv-active-channel", timeout=timeout, port=port
        ))
        result["channel"] = channels[0] if channels else None
    except EcpError as exc:
        if exc.kind != "unsupported":
            raise
    return result


def icon_url(ip: str, app_id: str, *, port: int = 8060) -> str:
    host = normalize_local_ip(ip)
    target_port = normalize_port(port)
    target = normalize_app_id(app_id)
    return f"http://{host}:{target_port}/query/icon/{urllib.parse.quote(target, safe='')}"


def request_exit_app(
    ip: str,
    app_id: str,
    *,
    force: bool = False,
    timeout: float = 1.2,
    port: int = 8060,
) -> dict:
    host = normalize_local_ip(ip)
    target_port = normalize_port(port)
    target = normalize_app_id(app_id)
    suffix = "/true" if force else ""
    url = f"http://{host}:{target_port}/exit-app/{urllib.parse.quote(target, safe='')}{suffix}"
    request = urllib.request.Request(
        url, data=b"", method="POST", headers={"User-Agent": "Omarchy-Roku-Remote/1.0"}
    )
    with _open(request, timeout) as response:
        response.read(1024)
        status = int(getattr(response, "status", 200))
    return {"ok": True, "reachable": True, "appId": target, "force": force, "status": status}


def query_device_info(ip: str, *, timeout: float = 0.8, port: int = 8060) -> dict:
    host = normalize_local_ip(ip)
    target_port = normalize_port(port)
    url = f"http://{host}:{target_port}/query/device-info"
    request = urllib.request.Request(url, headers={"User-Agent": "Omarchy-Roku-Remote/1.0"})
    with _open(request, timeout) as response:
        raw = _read_limited(response, 256 * 1024, "Roku device-info response").decode(
            "utf-8", errors="replace"
        )
    result = parse_device_info(raw, host, target_port)
    result["location"] = f"http://{host}:{target_port}/"
    return result


def query_apps(ip: str, *, timeout: float = 1.0, port: int = 8060) -> list[dict]:
    host = normalize_local_ip(ip)
    target_port = normalize_port(port)
    url = f"http://{host}:{target_port}/query/apps"
    request = urllib.request.Request(url, headers={"User-Agent": "Omarchy-Roku-Remote/1.0"})
    with _open(request, timeout) as response:
        raw = _read_limited(response, 512 * 1024, "Roku apps response").decode(
            "utf-8", errors="replace"
        )
    return parse_apps(raw)


def parse_ssdp_response(data: bytes | str) -> Location | None:
    text = data.decode("iso-8859-1", errors="replace") if isinstance(data, bytes) else str(data)
    lines = text.replace("\r\n", "\n").split("\n")
    if not lines or not lines[0].strip().upper().startswith("HTTP/1.1 200"):
        return None
    headers: dict[str, str] = {}
    for line in lines[1:]:
        if ":" not in line:
            continue
        key, value = line.split(":", 1)
        headers[key.strip().lower()] = value.strip()
    if "roku:ecp" not in (headers.get("st", "") + " " + headers.get("usn", "")).lower():
        return None
    location = headers.get("location", "")
    try:
        parsed = urllib.parse.urlsplit(location)
        if parsed.scheme.lower() != "http" or not parsed.hostname:
            return None
        ip = normalize_local_ip(parsed.hostname)
        port = parsed.port or 8060
    except (ValueError, EcpError):
        return None
    return Location(ip=ip, port=port, location=location, usn=headers.get("usn", ""))


def dedupe_locations(locations: Iterable[Location]) -> list[Location]:
    unique: dict[tuple[str, int], Location] = {}
    for location in locations:
        unique[(location.ip, location.port)] = location
    return list(unique.values())


def discover_locations(timeout: float = 1.6) -> tuple[list[Location], list[str]]:
    warnings: list[str] = []
    found: list[Location] = []
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM, socket.IPPROTO_UDP)
    try:
        sock.setsockopt(socket.IPPROTO_IP, socket.IP_MULTICAST_TTL, 2)
        sock.settimeout(0.2)
        sock.sendto(SSDP_REQUEST, SSDP_ADDRESS)
        deadline = time.monotonic() + max(0.1, timeout)
        resent = False
        while time.monotonic() < deadline:
            if not resent and time.monotonic() >= deadline - timeout / 2:
                sock.sendto(SSDP_REQUEST, SSDP_ADDRESS)
                resent = True
            try:
                data, _sender = sock.recvfrom(65535)
            except socket.timeout:
                continue
            location = parse_ssdp_response(data)
            if location is not None:
                found.append(location)
    except OSError as exc:
        warnings.append(f"SSDP unavailable: {exc}")
    finally:
        sock.close()
    return dedupe_locations(found), warnings


def route_networks_from_json(raw: str) -> list[ipaddress.IPv4Network]:
    try:
        routes = json.loads(raw)
    except (TypeError, json.JSONDecodeError):
        return []
    networks: list[ipaddress.IPv4Network] = []
    for route in routes if isinstance(routes, list) else []:
        destination = str(route.get("dst", ""))
        if not destination or destination == "default" or route.get("dev") == "lo":
            continue
        try:
            network = ipaddress.ip_network(destination, strict=False)
        except ValueError:
            continue
        if network.version != 4 or not any(network.subnet_of(local) for local in LOCAL_NETWORKS):
            continue
        # A local /16 should not turn one refresh into 65k probes. Narrow it
        # to the /24 containing the preferred source; ordinary /23-/32 links
        # remain exact.
        if network.num_addresses > 512:
            try:
                source = ipaddress.ip_address(str(route.get("prefsrc", "")))
                network = ipaddress.ip_network(f"{source}/24", strict=False)
            except ValueError:
                continue
        if network not in networks:
            networks.append(network)
    return networks


def local_ipv4_networks() -> tuple[list[ipaddress.IPv4Network], list[str]]:
    try:
        # Absolute executable, static arguments, and shell=False (the default).
        completed = subprocess.run(  # nosec B603
            [IP_COMMAND, "-j", "-4", "route", "show", "scope", "link"],
            check=False,
            capture_output=True,
            text=True,
            timeout=1.0,
        )
    except (OSError, subprocess.SubprocessError) as exc:
        return [], [f"Could not inspect local routes: {exc}"]
    if completed.returncode != 0:
        return [], ["Could not inspect local routes for Roku fallback discovery"]
    return route_networks_from_json(completed.stdout), []


def _port_open(ip: str, port: int, timeout: float) -> bool:
    try:
        with socket.create_connection((ip, port), timeout=max(0.03, timeout)):
            return True
    except OSError:
        return False


def scan_ecp_hosts(
    networks: Iterable[ipaddress.IPv4Network],
    *,
    port: int = 8060,
    timeout: float = 0.12,
) -> list[Location]:
    candidates: list[str] = []
    seen: set[str] = set()
    for network in networks:
        for address in network.hosts():
            value = str(address)
            if value not in seen:
                seen.add(value)
                candidates.append(value)
                if len(candidates) >= 512:
                    break
        if len(candidates) >= 512:
            break
    found: list[Location] = []
    # At most 48 short-lived TCP handshakes keep a /24 fallback below a
    # second on a responsive LAN while avoiding a flood of parallel sockets.
    with concurrent.futures.ThreadPoolExecutor(max_workers=min(48, max(1, len(candidates)))) as pool:
        futures = {pool.submit(_port_open, ip, port, timeout): ip for ip in candidates}
        for future in concurrent.futures.as_completed(futures):
            ip = futures[future]
            try:
                if future.result():
                    found.append(Location(ip=ip, port=port, location=f"http://{ip}:{port}/"))
            except OSError:
                continue
    return sorted(found, key=lambda item: tuple(int(part) for part in item.ip.split(".")))


def discover_devices(
    manual_ips: list[str],
    timeout: float,
    info_timeout: float,
    *,
    subnet_scan: bool = True,
    scan_timeout: float = 0.12,
) -> dict:
    locations, warnings = discover_locations(timeout)
    if not locations and subnet_scan:
        networks, route_warnings = local_ipv4_networks()
        warnings.extend(route_warnings)
        if networks:
            locations.extend(scan_ecp_hosts(networks, timeout=scan_timeout))
    manual_set: set[str] = set()
    for raw in manual_ips:
        try:
            ip = normalize_local_ip(raw)
            manual_set.add(ip)
            locations.append(Location(ip=ip, port=8060, location=f"http://{ip}:8060/"))
        except EcpError as exc:
            warnings.append(str(exc))
    locations = dedupe_locations(locations)

    devices: list[dict] = []
    for location in locations:
        is_manual = location.ip in manual_set
        try:
            device = query_device_info(location.ip, timeout=info_timeout, port=location.port)
            device["manual"] = is_manual
            device["usn"] = location.usn
            devices.append(device)
        except EcpError as exc:
            if is_manual:
                devices.append(
                    {
                        "ip": location.ip,
                        "port": location.port,
                        "name": f"Roku at {location.ip}",
                        "model": "Roku",
                        "serial": "",
                        "deviceId": "",
                        "isTv": False,
                        "online": False,
                        "manual": True,
                        "error": str(exc),
                    }
                )
            else:
                warnings.append(f"{location.ip}: {exc}")

    # A Roku occasionally replies on both wired and wireless interfaces. Once
    # device info is available, prefer one row per stable device id.
    deduped: list[dict] = []
    seen: set[str] = set()
    for device in sorted(devices, key=lambda item: (not item["online"], item["name"].lower(), item["ip"])):
        identity = device.get("deviceId") or f"ip:{device['ip']}"
        if identity in seen:
            continue
        seen.add(identity)
        deduped.append(device)
    return {"ok": True, "devices": deduped, "warnings": warnings}


def parser() -> argparse.ArgumentParser:
    result = argparse.ArgumentParser(description="Local Roku ECP helper")
    sub = result.add_subparsers(dest="command", required=True)

    discover = sub.add_parser("discover")
    discover.add_argument("--timeout", type=float, default=1.6)
    discover.add_argument("--info-timeout", type=float, default=0.8)
    discover.add_argument("--scan-timeout", type=float, default=0.12)
    discover.add_argument("--no-subnet-scan", action="store_true")
    discover.add_argument("--manual", action="append", default=[])

    info = sub.add_parser("info")
    info.add_argument("--ip", required=True)
    info.add_argument("--port", type=int, default=8060)
    info.add_argument("--timeout", type=float, default=0.8)

    apps = sub.add_parser("apps")
    apps.add_argument("--ip", required=True)
    apps.add_argument("--port", type=int, default=8060)
    apps.add_argument("--timeout", type=float, default=1.0)

    endpoint = sub.add_parser("endpoint")
    endpoint.add_argument("--ip", required=True)
    endpoint.add_argument("--port", type=int, default=8060)
    endpoint.add_argument("--action", choices=("keypress", "keydown", "keyup"), required=True)
    endpoint.add_argument("--key", required=True)

    control = sub.add_parser("control")
    control.add_argument("--ip", required=True)
    control.add_argument("--port", type=int, default=8060)
    control.add_argument("--timeout", type=float, default=1.2)
    control.add_argument("--action", choices=("keypress", "keydown", "keyup"), required=True)
    control.add_argument("--key", required=True)

    literal = sub.add_parser("literal")
    literal.add_argument("--ip", required=True)
    literal.add_argument("--port", type=int, default=8060)
    literal.add_argument("--timeout", type=float, default=1.2)
    literal.add_argument("--text", required=True)

    launch_app = sub.add_parser("launch-app")
    launch_app.add_argument("--ip", required=True)
    launch_app.add_argument("--port", type=int, default=8060)
    launch_app.add_argument("--timeout", type=float, default=1.2)
    launch_app.add_argument("--id", required=True)
    launch_app.add_argument("--param", action="append", default=[])

    launch_channel = sub.add_parser("launch-channel")
    launch_channel.add_argument("--ip", required=True)
    launch_channel.add_argument("--port", type=int, default=8060)
    launch_channel.add_argument("--timeout", type=float, default=1.2)
    launch_channel.add_argument("--channel", required=True)

    query = sub.add_parser("query")
    query.add_argument("--ip", required=True)
    query.add_argument("--port", type=int, default=8060)
    query.add_argument("--timeout", type=float, default=1.0)
    query.add_argument("--name", choices=tuple(QUERY_ENDPOINTS), required=True)

    status = sub.add_parser("status")
    status.add_argument("--ip", required=True)
    status.add_argument("--port", type=int, default=8060)
    status.add_argument("--timeout", type=float, default=1.0)

    icon = sub.add_parser("icon-url")
    icon.add_argument("--ip", required=True)
    icon.add_argument("--port", type=int, default=8060)
    icon.add_argument("--id", required=True)

    exit_app = sub.add_parser("exit-app")
    exit_app.add_argument("--ip", required=True)
    exit_app.add_argument("--port", type=int, default=8060)
    exit_app.add_argument("--timeout", type=float, default=1.2)
    exit_app.add_argument("--id", required=True)
    exit_app.add_argument("--force", action="store_true")
    return result


def launch_parameters(values: list[str]) -> dict[str, str]:
    result: dict[str, str] = {}
    for value in values:
        name, separator, content = str(value).partition("=")
        if not separator:
            raise EcpError("Launch parameters must use name=value", kind="invalid")
        result[name] = content
    return result


def main(argv: list[str] | None = None) -> int:
    args = parser().parse_args(argv)
    try:
        if args.command == "discover":
            return json_result(discover_devices(
                args.manual,
                args.timeout,
                args.info_timeout,
                subnet_scan=not args.no_subnet_scan,
                scan_timeout=args.scan_timeout,
            ))
        if args.command == "info":
            return json_result({"ok": True, "device": query_device_info(args.ip, timeout=args.timeout, port=args.port)})
        if args.command == "apps":
            return json_result({"ok": True, "apps": query_apps(args.ip, timeout=args.timeout, port=args.port)})
        if args.command == "endpoint":
            return json_result({"ok": True, "url": ecp_url(args.ip, args.action, args.key, args.port)})
        if args.command == "control":
            return json_result(request_ecp(args.ip, args.action, args.key, timeout=args.timeout, port=args.port))
        if args.command == "literal":
            return json_result(request_literal(args.ip, args.text, timeout=args.timeout, port=args.port))
        if args.command == "launch-app":
            return json_result(request_launch(
                args.ip,
                args.id,
                timeout=args.timeout,
                port=args.port,
                parameters=launch_parameters(args.param),
            ))
        if args.command == "launch-channel":
            return json_result(request_launch(
                args.ip,
                "tvinput.dtv",
                timeout=args.timeout,
                port=args.port,
                channel=args.channel,
            ))
        if args.command == "query":
            return json_result({
                "ok": True,
                **query_endpoint(args.ip, args.name, timeout=args.timeout, port=args.port),
            })
        if args.command == "status":
            return json_result({
                "ok": True,
                **query_status(args.ip, timeout=args.timeout, port=args.port),
            })
        if args.command == "icon-url":
            return json_result({"ok": True, "url": icon_url(args.ip, args.id, port=args.port)})
        if args.command == "exit-app":
            return json_result(request_exit_app(
                args.ip,
                args.id,
                force=args.force,
                timeout=args.timeout,
                port=args.port,
            ))
    except EcpError as exc:
        return json_result(
            {
                "ok": False,
                "reachable": exc.kind in {"unsupported", "http", "forbidden"},
                "unsupported": exc.kind == "unsupported",
                "kind": exc.kind,
                "status": exc.status,
                "error": str(exc),
            },
            3 if exc.kind == "unsupported" else 2,
        )
    return json_result({"ok": False, "error": "Unknown command"}, 2)


if __name__ == "__main__":
    raise SystemExit(main())

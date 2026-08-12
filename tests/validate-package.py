#!/usr/bin/env python3
"""Validate the distributable Omarchy plugin without external dependencies."""

from __future__ import annotations

import argparse
import json
import re
import struct
import subprocess
import sys
from pathlib import Path, PurePosixPath


PLUGIN_DIR = Path(__file__).resolve().parents[1]
MANIFEST_PATH = PLUGIN_DIR / "manifest.json"
KIND_ENTRY_POINTS = {
    "bar": "bar",
    "bar-widget": "barWidget",
    "menu": "menu",
    "overlay": "overlay",
    "panel": "panel",
    "service": "service",
}
REQUIRED_BAR_WIDGET_FIELDS = {
    "displayName": str,
    "description": str,
    "category": str,
    "allowMultiple": bool,
    "defaultSection": str,
}
RELEASE_PLACEHOLDERS = ("YOUR" + "-USER", "Screenshot " + "placeholder", "[TODO" + ":")
PRIVATE_MARKERS = ("Josh" + "ua", "com." + "josh" + "ua", "/home/" + "jay")


def fail(message: str) -> None:
    raise ValueError(message)


def load_manifest() -> dict:
    try:
        value = json.loads(MANIFEST_PATH.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        fail(f"cannot read manifest.json: {error}")
    if not isinstance(value, dict):
        fail("manifest.json must contain an object")
    return value


def validate_manifest(manifest: dict) -> None:
    if manifest.get("schemaVersion") != 1:
        fail("schemaVersion must be the number 1")

    for field in ("id", "name", "version", "author", "description"):
        value = manifest.get(field)
        if not isinstance(value, str) or not value.strip():
            fail(f"manifest field {field!r} must be a non-empty string")

    plugin_id = manifest["id"]
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]*", plugin_id):
        fail(f"invalid plugin id: {plugin_id}")
    if ".." in plugin_id or plugin_id.startswith("omarchy."):
        fail(f"unsafe or reserved plugin id: {plugin_id}")
    if not re.fullmatch(r"\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?", manifest["version"]):
        fail("version must use semantic versioning")

    kinds = manifest.get("kinds")
    if not isinstance(kinds, list) or not kinds or not all(isinstance(kind, str) for kind in kinds):
        fail("kinds must be a non-empty string array")
    if len(kinds) != len(set(kinds)):
        fail("kinds must not contain duplicates")

    entry_points = manifest.get("entryPoints")
    if not isinstance(entry_points, dict):
        fail("entryPoints must be an object")
    for kind in kinds:
        key = KIND_ENTRY_POINTS.get(kind)
        if key and key not in entry_points:
            fail(f"kind {kind!r} requires entryPoints.{key}")

    for key, raw_path in entry_points.items():
        if not isinstance(raw_path, str) or not raw_path:
            fail(f"entryPoints.{key} must be a non-empty string")
        path = PurePosixPath(raw_path)
        if path.is_absolute() or ".." in path.parts:
            fail(f"entryPoints.{key} must stay inside the plugin: {raw_path}")
        if not (PLUGIN_DIR / path).is_file():
            fail(f"entryPoints.{key} does not exist: {raw_path}")

    if "bar-widget" in kinds:
        metadata = manifest.get("barWidget")
        if not isinstance(metadata, dict):
            fail("bar-widget plugins require barWidget metadata")
        for field, expected_type in REQUIRED_BAR_WIDGET_FIELDS.items():
            if type(metadata.get(field)) is not expected_type:
                fail(f"barWidget.{field} must be {expected_type.__name__}")
        if metadata["defaultSection"] not in {"left", "center", "right"}:
            fail("barWidget.defaultSection must be left, center, or right")


def validate_tree() -> None:
    for path in PLUGIN_DIR.rglob("*"):
        if ".git" in path.parts:
            continue
        if path.is_symlink():
            fail(f"symlinks are not allowed in the plugin: {path.relative_to(PLUGIN_DIR)}")

    if (PLUGIN_DIR / ".git").exists():
        result = subprocess.run(
            ["git", "-C", str(PLUGIN_DIR), "ls-files", "-z"],
            check=True,
            capture_output=True,
        )
        tracked = result.stdout.decode("utf-8").split("\0")
        forbidden = [
            path
            for path in tracked
            if path and ("__pycache__" in PurePosixPath(path).parts or path.endswith((".pyc", ".pyo")))
        ]
        if forbidden:
            fail("tracked Python bytecode is not allowed: " + ", ".join(forbidden))


def validate_release_content() -> None:
    text_files: dict[Path, str] = {}
    for path in PLUGIN_DIR.rglob("*"):
        if not path.is_file() or ".git" in path.parts or "__pycache__" in path.parts:
            continue
        try:
            text = path.read_text(encoding="utf-8")
        except UnicodeDecodeError:
            continue
        text_files[path] = text
        for placeholder in RELEASE_PLACEHOLDERS:
            if placeholder in text:
                fail(f"release placeholder {placeholder!r} remains in {path.relative_to(PLUGIN_DIR)}")
        for marker in PRIVATE_MARKERS:
            if marker.lower() in text.lower():
                fail(f"private identity marker remains in {path.relative_to(PLUGIN_DIR)}")
        for email in re.findall(r"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}", text):
            if not email.lower().endswith("@users.noreply.github.com"):
                fail(f"email address remains in {path.relative_to(PLUGIN_DIR)}")

    preview = PLUGIN_DIR / "preview.png"
    if not preview.is_file():
        fail("marketplace preview is missing: preview.png")
    if "preview.png" not in (PLUGIN_DIR / "README.md").read_text(encoding="utf-8"):
        fail("README.md must display preview.png")
    if preview.stat().st_size > 50 * 1024 * 1024:
        fail("preview.png exceeds the marketplace 50 MiB limit")
    header = preview.read_bytes()[:24]
    if len(header) != 24 or header[:8] != b"\x89PNG\r\n\x1a\n":
        fail("preview.png must be a valid PNG")
    width, height = struct.unpack(">II", header[16:24])
    if width < 1 or height < 1 or width * height > 40_000_000:
        fail("preview.png exceeds the marketplace 40-megapixel limit")

    readme = text_files.get(PLUGIN_DIR / "README.md", "")
    plugin_id = load_manifest()["id"]
    for instruction in (
        f"omarchy plugin add https://github.com/Jalv13/omarchy-roku-remote.git --enable",
        f"omarchy plugin remove {plugin_id} --yes",
        ".local/state/omarchy/settings/roku-remote.json",
    ):
        if instruction not in readme:
            fail(f"README.md is missing safe lifecycle instruction: {instruction}")

    for workflow in (PLUGIN_DIR / ".github" / "workflows").glob("*.yml"):
        source = workflow.read_text(encoding="utf-8")
        for action, reference in re.findall(r"uses:\s+(actions/[^@\s]+)@([^\s#]+)", source):
            if not re.fullmatch(r"[0-9a-f]{40}", reference):
                fail(f"{workflow.relative_to(PLUGIN_DIR)} must pin {action} to a full commit SHA")

    qml_text = "\n".join(
        path.read_text(encoding="utf-8")
        for path in PLUGIN_DIR.rglob("*.qml")
    )
    if len(re.findall(r"\bText\s*\{", qml_text)) != qml_text.count("textFormat: Text.PlainText"):
        fail("every plugin Text item must explicitly use Text.PlainText")


def validate_tag(manifest: dict, tag: str) -> None:
    normalized = tag[1:] if tag.startswith("v") else tag
    if normalized != manifest["version"]:
        fail(f"tag {tag!r} does not match manifest version {manifest['version']!r}")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--release", action="store_true", help="also reject publication placeholders")
    parser.add_argument("--tag", default="", help="require this tag (vX.Y.Z or X.Y.Z) to match the manifest")
    args = parser.parse_args()

    try:
        manifest = load_manifest()
        validate_manifest(manifest)
        validate_tree()
        if args.release:
            validate_release_content()
        if args.tag:
            validate_tag(manifest, args.tag)
    except (OSError, subprocess.CalledProcessError, ValueError) as error:
        print(f"validate-package: {error}", file=sys.stderr)
        return 1

    print("Package validation passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

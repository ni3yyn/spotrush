#!/usr/bin/env python3
"""Install the checksum-pinned Godot Deeplink Plugin Android release.

The upstream archive stores the Godot project files below res/addons/.
Only the DeeplinkPlugin folder is installed; SpotRush's existing GMPShared
files are deliberately preserved because Notification Scheduler uses them too.
"""

from __future__ import annotations

import argparse
import hashlib
import re
import shutil
import sys
import tempfile
import urllib.request
import zipfile
from pathlib import Path, PurePosixPath

ROOT = Path(__file__).resolve().parents[1]
PLUGIN_VERSION = "6.0.1"
ARCHIVE_URL = (
    "https://github.com/godot-mobile-plugins/godot-deeplink/releases/download/"
    f"v{PLUGIN_VERSION}/DeeplinkPlugin-Android-v{PLUGIN_VERSION}.zip"
)
ARCHIVE_SHA256 = "a2446bbcb2486561539baf4c1be285f9dbd183bdb453e6de68bf08cc579f4ae1"
PLUGIN_PREFIX = "res/addons/DeeplinkPlugin/"
REQUIRED_ARCHIVE_FILES = (
    "plugin.cfg",
    "DeeplinkPlugin.gd",
    "Deeplink.gd",
    "config/DeeplinkExportConfig.gd",
    "model/DeeplinkUrl.gd",
    "bin/debug/DeeplinkPlugin-debug.aar",
    "bin/release/DeeplinkPlugin-release.aar",
)
REQUIRED_SHARED_FILES = (
    "addons/GMPShared/GmpLogger.gd",
    "addons/GMPShared/SpmDependency.gd",
)


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def download_archive(destination: Path) -> None:
    request = urllib.request.Request(
        ARCHIVE_URL,
        headers={"User-Agent": "SpotRush-Deeplink-Plugin-Installer"},
    )
    with urllib.request.urlopen(request, timeout=120) as response:
        with destination.open("wb") as output:
            shutil.copyfileobj(response, output)


def install_archive(archive_path: Path, project_root: Path = ROOT) -> None:
    archive_path = archive_path.resolve()
    project_root = project_root.resolve()
    if not archive_path.is_file():
        raise FileNotFoundError(f"Plugin archive not found: {archive_path}")

    actual_sha256 = sha256_file(archive_path)
    if actual_sha256.lower() != ARCHIVE_SHA256:
        raise ValueError(
            "Deeplink plugin archive SHA-256 mismatch; refusing to install "
            f"(expected {ARCHIVE_SHA256}, got {actual_sha256})."
        )

    plugin_dir = project_root / "addons" / "DeeplinkPlugin"
    shared_missing = [
        relative for relative in REQUIRED_SHARED_FILES
        if not (project_root / relative).is_file()
    ]

    with zipfile.ZipFile(archive_path) as archive:
        names = set(archive.namelist())
        missing = [
            PLUGIN_PREFIX + relative
            for relative in REQUIRED_ARCHIVE_FILES
            if PLUGIN_PREFIX + relative not in names
        ]
        if missing:
            raise ValueError(
                "Deeplink release archive is incomplete; missing: " + ", ".join(missing)
            )

        cfg_data = archive.read(PLUGIN_PREFIX + "plugin.cfg").decode("utf-8")
        version_match = re.search(
            r'^version\s*=\s*"([^"]+)"\s*$',
            cfg_data,
            flags=re.MULTILINE,
        )
        if version_match is None or version_match.group(1) != PLUGIN_VERSION:
            raise ValueError(
                f"Expected Deeplink plugin version {PLUGIN_VERSION} in plugin.cfg."
            )

        if shared_missing:
            raise FileNotFoundError(
                "SpotRush's shared Godot Mobile Plugin files are missing: "
                + ", ".join(shared_missing)
            )

        plugin_prefix = PurePosixPath(PLUGIN_PREFIX)
        files_to_copy = sorted(
            name for name in names
            if name.startswith(PLUGIN_PREFIX) and not name.endswith("/")
        )

        for name in files_to_copy:
            relative = PurePosixPath(name).relative_to(plugin_prefix)
            if not relative.parts or ".." in relative.parts:
                raise ValueError(f"Unsafe path in Deeplink release archive: {name}")
            # Keep the project-specific export config authored in SpotRush.
            if relative.as_posix() == "export.cfg":
                continue

            destination = plugin_dir.joinpath(*relative.parts)
            destination.parent.mkdir(parents=True, exist_ok=True)
            with archive.open(name) as source, destination.open("wb") as output:
                shutil.copyfileobj(source, output)

    for relative in REQUIRED_ARCHIVE_FILES:
        destination = plugin_dir / relative
        if not destination.is_file() or destination.stat().st_size == 0:
            raise RuntimeError(f"Deeplink plugin installation is incomplete: {destination}")

    print(f"Installed Godot Deeplink Plugin {PLUGIN_VERSION}.")
    print(f"Verified archive SHA-256: {actual_sha256}")
    print(f"Plugin files: {plugin_dir}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--project-root",
        type=Path,
        default=ROOT,
        help="SpotRush project root (defaults to the repository root).",
    )
    parser.add_argument(
        "--archive",
        type=Path,
        help="Use an already downloaded release ZIP instead of downloading it.",
    )
    args = parser.parse_args()

    try:
        if args.archive:
            install_archive(args.archive, args.project_root)
        else:
            with tempfile.TemporaryDirectory(prefix="spotrush-deeplink-") as temp_dir:
                archive = Path(temp_dir) / f"DeeplinkPlugin-Android-v{PLUGIN_VERSION}.zip"
                print(f"Downloading Deeplink Plugin {PLUGIN_VERSION}...")
                download_archive(archive)
                install_archive(archive, args.project_root)
    except (OSError, ValueError, zipfile.BadZipFile) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

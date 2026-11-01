#!/usr/bin/env python3
"""Validate the local EOSG 2.3.1 addon layout without printing credentials.

The Windows + Android package can remain local; this checker is intended to
run from the SpotRush project root before launching the editor or exporting.
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ADDON = Path("addons/epic-online-services-godot")

SHARED_FILES = (
    "plugin.cfg",
    "plugin.gd",
    "export_plugin.gd",
    "base_class.gd",
    "dataclass.gd",
    "eos.gd",
    "eosg.gdextension",
    "runtime.gd",
    "heos/hcredentials.gd",
    "heos/hplatform.gd",
    "heos/hauth.gd",
    "heos/hachievements.gd",
    "heos/hachievement_data.gd",
    "heos/hfriends.gd",
    "heos/hstats.gd",
    "heos/hleaderboards.gd",
    "heos/hlobbies.gd",
    "heos/hlobby.gd",
    "heos/hlobbymember.gd",
    "heos/hsessions.gd",
    "heos/hp2p.gd",
    "heos/hlog.gd",
)

ANDROID_FILES = (
    "bin/android/eossdk-StaticSTDC-release.aar",
    "bin/android/libeosg.android.template_debug.dev.arm64.so",
    "bin/android/libeosg.android.template_release.arm64.so",
    "bin/android/libeosg.android.template_debug.dev.x86_64.so",
    "bin/android/libeosg.android.template_release.x86_64.so",
)

WINDOWS_FILES = (
    "bin/windows/libeosg.windows.template_debug.dev.x86_64.dll",
    "bin/windows/libeosg.windows.template_release.x86_64.dll",
    "bin/windows/EOSSDK-Win64-Shipping.dll",
    "bin/windows/x64/xaudio2_9redist.dll",
)


def check_files(root: Path, names: tuple[str, ...], label: str) -> list[str]:
    missing = [name for name in names if not (root / name).is_file() or (root / name).stat().st_size == 0]
    if missing:
        print(f"FAIL {label}: missing or empty files:")
        for name in missing:
            print(f"  - {ADDON / name}")
    else:
        print(f"PASS {label}: {len(names)} required files present")
    return missing


def check_version(addon_root: Path) -> bool:
    plugin_cfg = addon_root / "plugin.cfg"
    if not plugin_cfg.is_file():
        return False
    text = plugin_cfg.read_text(encoding="utf-8")
    match = re.search(r'^version\s*=\s*"([^"]+)"\s*$', text, re.MULTILINE)
    if match is None or match.group(1) != "2.3.1":
        actual = match.group(1) if match else "not found"
        print(f"FAIL EOSG version: expected 2.3.1, found {actual}")
        return False
    print("PASS EOSG version: 2.3.1")
    return True


# Autoloads supplied by the EOSG 2.3.1 editor plugin.
# Godot may serialize these as either res:// paths or UID references.
EOSG_AUTOLOADS = {
    "EOSGRuntime": "addons/epic-online-services-godot/runtime.gd",
    "HPlatform": "addons/epic-online-services-godot/heos/hplatform.gd",
    "HAuth": "addons/epic-online-services-godot/heos/hauth.gd",
    "HAchievements": "addons/epic-online-services-godot/heos/hachievements.gd",
    "HFriends": "addons/epic-online-services-godot/heos/hfriends.gd",
    "HStats": "addons/epic-online-services-godot/heos/hstats.gd",
    "HLeaderboards": "addons/epic-online-services-godot/heos/hleaderboards.gd",
    "HLobbies": "addons/epic-online-services-godot/heos/hlobbies.gd",
    "HP2P": "addons/epic-online-services-godot/heos/hp2p.gd",
    "HSessions": "addons/epic-online-services-godot/heos/hsessions.gd",
}

# SpotRush autoloads required by online play and invitation routing.
PROJECT_AUTOLOADS = {
    "NetworkSession": "scripts/networking/NetworkSession.gd",
    "DeepLinkRouter": "scripts/networking/DeepLinkRouter.gd",
    "EOSOnline": "scripts/networking/EOSOnline.gd",
}


def _section_body(project_text: str, section_name: str) -> str | None:
    """Return a Godot project section without consuming the next section."""
    match = re.search(
        rf"(?ms)^\[{re.escape(section_name)}\]\s*\n(.*?)(?=^\[|\Z)",
        project_text,
    )
    return match.group(1) if match else None


def _section_assignments(section_text: str) -> dict[str, str]:
    """Read simple key=value assignments while ignoring blank and comment lines."""
    values: dict[str, str] = {}
    for line in section_text.splitlines():
        stripped = line.strip()
        if not stripped or stripped.startswith(";"):
            continue
        match = re.match(r"^([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*?)\s*$", stripped)
        if match:
            values[match.group(1)] = match.group(2)
    return values


def _autoload_reference_error(
    project_root: Path, autoload_name: str, expected_relative_path: str, raw_value: str | None
) -> str | None:
    """Validate an enabled autoload against its expected resource path or UID sidecar."""
    if raw_value is None:
        return f"{autoload_name}: autoload entry is missing"

    value_match = re.fullmatch(r'"([^"]+)"', raw_value)
    if value_match is None:
        return f"{autoload_name}: autoload value is not a quoted resource reference"

    reference = value_match.group(1)
    if not reference.startswith("*"):
        return f"{autoload_name}: autoload is present but not enabled (expected a leading '*')"
    resource = reference[1:]
    expected_path = Path(expected_relative_path)
    resource_file = project_root / expected_path
    if not resource_file.is_file():
        return f"{autoload_name}: expected script is missing ({expected_relative_path})"

    if resource.startswith("res://"):
        actual_relative_path = resource.removeprefix("res://").replace("\\", "/")
        if actual_relative_path != expected_path.as_posix():
            return (
                f"{autoload_name}: points to {resource!r}, "
                f"expected res://{expected_path.as_posix()}"
            )
        return None

    if resource.startswith("uid://"):
        uid_file = Path(str(resource_file) + ".uid")
        if not uid_file.is_file():
            return f"{autoload_name}: UID reference has no sidecar ({uid_file.relative_to(project_root)})"
        expected_uid = uid_file.read_text(encoding="utf-8").strip()
        if resource != expected_uid:
            return (
                f"{autoload_name}: UID {resource!r} does not match "
                f"{uid_file.relative_to(project_root)} ({expected_uid!r})"
            )
        return None

    return f"{autoload_name}: unsupported resource reference {resource!r}"


def check_project_wiring(project_root: Path) -> list[str]:
    project_file = project_root / "project.godot"
    if not project_file.is_file():
        print("FAIL project autoload/plugin wiring: project.godot is missing")
        return ["project.godot"]

    text = project_file.read_text(encoding="utf-8")
    autoload_section = _section_body(text, "autoload")
    editor_plugins_section = _section_body(text, "editor_plugins")
    failures: list[str] = []

    if autoload_section is None:
        failures.append("[autoload] section is missing")
        autoloads: dict[str, str] = {}
    else:
        autoloads = _section_assignments(autoload_section)

    required_autoloads = {**EOSG_AUTOLOADS, **PROJECT_AUTOLOADS}
    for name, expected_path in required_autoloads.items():
        error = _autoload_reference_error(project_root, name, expected_path, autoloads.get(name))
        if error:
            failures.append(error)

    plugin_path = "res://addons/epic-online-services-godot/plugin.cfg"
    if not (project_root / "addons/epic-online-services-godot/plugin.cfg").is_file():
        failures.append("EOSG editor plugin file is missing (addons/epic-online-services-godot/plugin.cfg)")
    elif editor_plugins_section is None or f'"{plugin_path}"' not in editor_plugins_section:
        failures.append(f"EOSG editor plugin is not enabled in [editor_plugins]: {plugin_path}")

    if failures:
        print("FAIL project autoload/plugin wiring:")
        for failure in failures:
            print(f"  - {failure}")
    else:
        print(
            "PASS project autoload/plugin wiring "
            f"({len(required_autoloads)} autoloads; res:// and UID references validated)"
        )
    return failures

def check_local_config(project_root: Path) -> bool:
    config = project_root / "scripts/networking/EOSLocalConfig.gd"
    if not config.is_file():
        print("FAIL local credentials: EOSLocalConfig.gd is missing. Run tools/set_eos_client_secret.ps1.")
        return False
    content = config.read_text(encoding="utf-8")
    secret_match = re.search(r'^\s*var\s+client_secret\s*:\s*String\s*=\s*"([^"]*)"', content, re.MULTILINE)
    key_match = re.search(r'^\s*var\s+encryption_key\s*:\s*String\s*=\s*"([^"]*)"', content, re.MULTILINE)
    if secret_match is None or not secret_match.group(1).strip() or secret_match.group(1).startswith("PASTE_"):
        print("FAIL local credentials: Client Secret is empty or still a placeholder (value not displayed).")
        return False
    if key_match is None or re.fullmatch(r"[0-9A-Fa-f]{64}", key_match.group(1).strip()) is None:
        print("FAIL local credentials: encryption_key must be exactly 64 hexadecimal characters (value not displayed).")
        return False
    print("PASS local credentials: Client Secret and 64-character EOS Encryption Key are present (values hidden)")
    return True


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project-root", type=Path, default=ROOT)
    parser.add_argument("--platform", choices=("android", "windows", "both"), default="both")
    parser.add_argument("--require-local-config", action="store_true")
    args = parser.parse_args()

    project_root = args.project_root.resolve()
    addon_root = project_root / ADDON
    failures: list[str] = []

    if not check_version(addon_root):
        failures.append("EOSG version")
    failures.extend(check_files(addon_root, SHARED_FILES, "shared EOSG addon"))
    eos_api = addon_root / "eos.gd"
    if eos_api.is_file() and "EOSGRuntime." in eos_api.read_text(encoding="utf-8"):
        print("FAIL EOSG autoload scope: run python tools/patch_eosg_autoload_scope.py before opening Godot.")
        failures.append("EOSG autoload scope patch")
    else:
        print("PASS EOSG autoload scope: no compile-time EOSGRuntime references")
    if args.platform in ("android", "both"):
        failures.extend(check_files(addon_root, ANDROID_FILES, "Android EOSG binaries/AAR"))
    if args.platform in ("windows", "both"):
        failures.extend(check_files(addon_root, WINDOWS_FILES, "Windows EOSG binaries"))
    failures.extend(check_project_wiring(project_root))
    if args.require_local_config and not check_local_config(project_root):
        failures.append("local EOS credentials")

    if failures:
        print(f"\nEOSG installation check failed ({len(failures)} issue(s)).")
        return 1
    print("\nEOSG installation structure is valid for the selected platform(s).")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

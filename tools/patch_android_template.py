#!/usr/bin/env python3
"""Idempotently register SpotRush's custom invitation URI in Godot's Android template.

Run after extracting the matching Godot `android_source.zip` into `android/build` and before Android export.
Godot 4.7 Gradle templates place the app manifest under
`android/build/src/main/AndroidManifest.xml`; older/custom templates may place
it at the build root. The script locates the generated manifest without
assuming one layout and never edits `export_presets.cfg` or source assets.
"""

from __future__ import annotations

import argparse
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

ANDROID_NS = "http://schemas.android.com/apk/res/android"
ET.register_namespace("android", ANDROID_NS)


def android_attr(name: str) -> str:
    return f"{{{ANDROID_NS}}}{name}"


def is_launcher_activity(element: ET.Element) -> bool:
    if element.tag not in {"activity", "activity-alias"}:
        return False
    for intent_filter in element.findall("intent-filter"):
        actions = {
            action.get(android_attr("name"), "")
            for action in intent_filter.findall("action")
        }
        categories = {
            category.get(android_attr("name"), "")
            for category in intent_filter.findall("category")
        }
        if (
            "android.intent.action.MAIN" in actions
            and "android.intent.category.LAUNCHER" in categories
        ):
            return True
    return False


def has_spotrush_filter(activity: ET.Element) -> bool:
    for intent_filter in activity.findall("intent-filter"):
        actions = {
            action.get(android_attr("name"), "")
            for action in intent_filter.findall("action")
        }
        categories = {
            category.get(android_attr("name"), "")
            for category in intent_filter.findall("category")
        }
        for data in intent_filter.findall("data"):
            if (
                "android.intent.action.VIEW" in actions
                and "android.intent.category.DEFAULT" in categories
                and "android.intent.category.BROWSABLE" in categories
                and data.get(android_attr("scheme")) == "spotrush"
                and data.get(android_attr("host")) == "join"
            ):
                return True
    return False


def locate_manifest(android_build: Path) -> Path:
    """Locate the generated app manifest across Godot/Gradle template layouts.

    Godot 4.7 templates use src/main/AndroidManifest.xml. Keep compatibility
    with older/custom templates and the former root-level assumption.
    """
    candidates = (
        android_build / "src/main/AndroidManifest.xml",
        android_build / "app/src/main/AndroidManifest.xml",
        android_build / "AndroidManifest.xml",
    )
    existing = [path for path in candidates if path.is_file()]
    if len(existing) == 1:
        return existing[0]
    if len(existing) > 1:
        valid: list[Path] = []
        for candidate in existing:
            try:
                root = ET.parse(candidate).getroot()
            except (OSError, ET.ParseError):
                continue
            launchers = [element for element in root.iter() if is_launcher_activity(element)]
            if len(launchers) == 1:
                valid.append(candidate)
        if len(valid) == 1:
            return valid[0]
        raise RuntimeError(
            "Found multiple generated Android manifests but could not identify one unique "
            f"launcher manifest: {', '.join(str(path) for path in existing)}."
        )

    # Last-resort discovery supports future Godot Gradle layouts, but only if
    # exactly one manifest declares the launcher activity.
    discovered = sorted(android_build.rglob("AndroidManifest.xml")) if android_build.is_dir() else []
    valid = []
    for candidate in discovered:
        try:
            root = ET.parse(candidate).getroot()
        except (OSError, ET.ParseError):
            continue
        launchers = [element for element in root.iter() if is_launcher_activity(element)]
        if len(launchers) == 1:
            valid.append(candidate)
    if len(valid) == 1:
        return valid[0]

    expected = (
        android_build / "src/main/AndroidManifest.xml",
        android_build / "AndroidManifest.xml",
    )
    raise FileNotFoundError(
        "Could not locate one generated Godot Android launcher manifest. Checked: "
        + ", ".join(str(path) for path in expected)
        + ". This is a CI-generated file: run the workflow's "
        "`android_source.zip` extraction step first."
    )


def patch_manifest(path: Path) -> bool:
    if not path.is_file():
        raise FileNotFoundError(
            f"Android manifest not found: {path}. Install the Godot Android build template first."
        )

    parser = ET.XMLParser()
    tree = ET.parse(path, parser=parser)
    root = tree.getroot()
    launchers = [element for element in root.iter() if is_launcher_activity(element)]
    if len(launchers) != 1:
        raise RuntimeError(
            f"Expected exactly one launcher activity in {path}, found {len(launchers)}. "
            "Refusing to guess which activity should receive the invitation filter."
        )

    activity = launchers[0]
    changed = False

    # Deliver a new invitation to the existing Godot Activity when the app is
    # already running. The Java template's onNewIntent() calls setIntent(), so
    # DeepLinkRouter can read the newest URI through AndroidRuntime.getIntent().
    launch_mode = activity.get(android_attr("launchMode"), "")
    if launch_mode != "singleTask":
        activity.set(android_attr("launchMode"), "singleTask")
        changed = True

    if has_spotrush_filter(activity):
        if changed:
            ET.indent(tree, space="    ")
            tree.write(path, encoding="utf-8", xml_declaration=True)
            print(f"Updated launcher launchMode for SpotRush deep links in {path}")
        else:
            print("SpotRush deep-link filter and singleTask launch mode already exist; no change needed.")
        return changed

    intent_filter = ET.SubElement(activity, "intent-filter")
    ET.SubElement(
        intent_filter,
        "action",
        {android_attr("name"): "android.intent.action.VIEW"},
    )
    ET.SubElement(
        intent_filter,
        "category",
        {android_attr("name"): "android.intent.category.DEFAULT"},
    )
    ET.SubElement(
        intent_filter,
        "category",
        {android_attr("name"): "android.intent.category.BROWSABLE"},
    )
    ET.SubElement(
        intent_filter,
        "data",
        {
            android_attr("scheme"): "spotrush",
            android_attr("host"): "join",
        },
    )

    # The file belongs to Godot's generated template, not to the checked-in
    # project. Reformatting this generated XML is safe and keeps the update
    # deterministic for CI and local builds.
    ET.indent(tree, space="    ")
    tree.write(path, encoding="utf-8", xml_declaration=True)
    print(f"Registered spotrush://join deep links and singleTask launch mode in {path}")
    return True


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--android-build",
        type=Path,
        default=Path("android/build"),
        help="Generated Godot Android Gradle template directory (default: android/build).",
    )
    parser.add_argument(
        "--manifest",
        type=Path,
        default=None,
        help="Optional explicit generated AndroidManifest.xml path; otherwise auto-detected.",
    )
    args = parser.parse_args()
    android_build = args.android_build.resolve()
    try:
        manifest = args.manifest.resolve() if args.manifest else locate_manifest(android_build)
        patch_manifest(manifest)
    except (OSError, ET.ParseError, RuntimeError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1
    return 0

if __name__ == "__main__":
    raise SystemExit(main())

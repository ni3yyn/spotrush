#!/usr/bin/env python3
"""Patch EOSG 2.3.1's autoload references for reliable Godot 4.7 import.

EOSG's eos.gd has nested class member defaults that refer directly to the
EOSGRuntime autoload. Depending on project import/autoload registration order,
Godot can report `Identifier "EOSGRuntime" not declared in the current scope`.
This idempotent patch resolves the same runtime node through SceneTree at the
point a default value is evaluated, avoiding compile-time singleton lookup.
"""
from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

DEFAULT_ADDON = Path("addons/epic-online-services-godot/eos.gd")
MARKER = "# SpotRush Godot 4.7 autoload-scope compatibility."
HELPER = '''\n\n# SpotRush Godot 4.7 autoload-scope compatibility.\n# Resolve EOSGRuntime dynamically because EOSG uses it inside nested class\n# default values, where the editor may not expose the autoload symbol yet.\nstatic func _spotrush_runtime_value(property_name: String) -> String:\n\tvar main_loop: MainLoop = Engine.get_main_loop()\n\tif not main_loop is SceneTree:\n\t\treturn ""\n\tvar scene_tree: SceneTree = main_loop as SceneTree\n\tvar runtime_node: Node = scene_tree.root.get_node_or_null("EOSGRuntime")\n\tif runtime_node == null:\n\t\treturn ""\n\treturn str(runtime_node.get(property_name))\n'''


def patch(path: Path) -> bool:
    if not path.is_file():
        raise FileNotFoundError(f"EOSG source not found: {path}")
    text = path.read_text(encoding="utf-8")
    if MARKER in text:
        # Still verify every reference was rewritten; don't silently accept a partial patch.
        if "EOSGRuntime." in text:
            raise RuntimeError("EOSG compatibility marker exists, but unresolved EOSGRuntime references remain.")
        return False

    header = re.search(r"(?m)^class_name\s+EOS\s*\nextends\s+RefCounted\s*$", text)
    if header is None:
        raise RuntimeError("EOSG eos.gd does not match the expected 2.3.1 class header; refusing to patch another version.")

    # Replace only the two runtime properties used throughout EOSG's option wrappers.
    text = text.replace("EOSGRuntime.local_product_user_id", 'EOS._spotrush_runtime_value("local_product_user_id")')
    text = text.replace("EOSGRuntime.local_epic_account_id", 'EOS._spotrush_runtime_value("local_epic_account_id")')
    if "EOSGRuntime." in text:
        remaining = sorted(set(re.findall(r"EOSGRuntime\.[A-Za-z_][A-Za-z0-9_]*", text)))
        raise RuntimeError("Unexpected EOSGRuntime members remain: " + ", ".join(remaining))

    insert_at = header.end()
    text = text[:insert_at] + HELPER + text[insert_at:]
    path.write_text(text, encoding="utf-8", newline="")
    return True


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project-root", type=Path, default=Path(__file__).resolve().parents[1])
    args = parser.parse_args()
    path = args.project_root.resolve() / DEFAULT_ADDON
    try:
        changed = patch(path)
    except (OSError, RuntimeError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1
    print("Patched EOSG nested-class runtime references." if changed else "EOSG runtime-reference patch already applied.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

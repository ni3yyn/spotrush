#!/usr/bin/env python3
"""Create ignored EOSLocalConfig.gd from environment variables without printing them."""
from __future__ import annotations
import os
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CONFIG_DIR = ROOT / "scripts/networking"
TEMPLATE = CONFIG_DIR / "EOSLocalConfig.gd.example"
OUTPUT = CONFIG_DIR / "EOSLocalConfig.gd"


def main() -> int:
    secret = os.environ.get("EOS_CLIENT_SECRET", "").strip()
    encryption_key = os.environ.get("EOS_ENCRYPTION_KEY", "").strip()
    if not secret or "\n" in secret or "\r" in secret:
        print("ERROR: EOS_CLIENT_SECRET is missing or invalid. It must be one line.", file=sys.stderr)
        return 1
    if not re.fullmatch(r"[0-9A-Fa-f]{64}", encryption_key):
        print("ERROR: EOS_ENCRYPTION_KEY must be exactly 64 hexadecimal characters.", file=sys.stderr)
        return 1
    if not TEMPLATE.is_file():
        print(f"ERROR: Missing EOS config template: {TEMPLATE}", file=sys.stderr)
        return 1

    content = TEMPLATE.read_text(encoding="utf-8")
    replacements = {
        "client_secret": secret,
        "encryption_key": encryption_key.lower(),
    }
    for property_name, value in replacements.items():
        escaped = value.replace("\\", "\\\\").replace('"', '\\"')
        replacement = f'var {property_name}: String = "{escaped}"'
        content, count = re.subn(
            rf'^\s*var\s+{property_name}\s*:\s*String\s*=\s*"[^"]*"\s*$',
            replacement,
            content,
            count=1,
            flags=re.MULTILINE,
        )
        if count != 1:
            print(f"ERROR: Template must contain exactly one {property_name} String property.", file=sys.stderr)
            return 1

    OUTPUT.write_text(content, encoding="utf-8", newline="")
    print("Created scripts/networking/EOSLocalConfig.gd (credential values not displayed).")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

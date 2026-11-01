#!/usr/bin/env python3
"""Patch Godot's generated Android Gradle template for EOSG 2.3.1.

Run after `godot --install-android-build-template` and after the EOSG addon has
been installed under addons/epic-online-services-godot. The script modifies
only android/build (the generated export template), never export_presets.cfg.
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ADDON_RELATIVE = Path("addons/epic-online-services-godot")
AAR_RELATIVE = ADDON_RELATIVE / "bin/android/eossdk-StaticSTDC-release.aar"
DEPENDENCIES = (
    "implementation 'androidx.appcompat:appcompat:1.5.1'",
    "implementation 'androidx.constraintlayout:constraintlayout:2.1.4'",
    "implementation 'androidx.security:security-crypto:1.0.0'",
    "implementation 'androidx.browser:browser:1.4.0'",
    "implementation 'androidx.webkit:webkit:1.7.0'",
    "coreLibraryDesugaring 'com.android.tools:desugar_jdk_libs:2.0.3'",
    "implementation files('../../addons/epic-online-services-godot/bin/android/eossdk-StaticSTDC-release.aar')",
)


def _same_indent_closing_brace(text: str, opening: int, header_indent: str, label: str) -> int | None:
    """Fallback for Gradle/Groovy constructs the lightweight lexer cannot tokenize."""
    search_from = text.find("\n", opening)
    if search_from < 0:
        return None
    cursor = search_from + 1
    while cursor < len(text):
        line_end = text.find("\n", cursor)
        if line_end < 0:
            line_end = len(text)
        line = text[cursor:line_end]
        if line.startswith(header_indent) and re.fullmatch(
            re.escape(header_indent) + r"}\s*(?://.*)?", line
        ):
            return cursor + len(header_indent)
        cursor = line_end + 1
    return None


def find_block(text: str, header_pattern: str, label: str) -> tuple[int, int]:
    """Return (opening brace, closing brace) for one unique Gradle block.

    Handles Groovy comments, normal strings and triple-quoted strings. A
    same-indentation fallback is used for generated Godot Gradle templates if
    their Groovy interpolation syntax confuses the lightweight scanner.
    """
    matches = list(re.finditer(header_pattern, text, flags=re.MULTILINE))
    if len(matches) != 1:
        raise RuntimeError(f"Expected exactly one {label} block, found {len(matches)}.")
    opening = text.find("{", matches[0].start(), matches[0].end() + 2)
    if opening < 0:
        raise RuntimeError(f"Could not find opening brace for {label} block.")

    header_line_start = text.rfind("\n", 0, matches[0].start()) + 1
    header_line_end = text.find("\n", header_line_start)
    if header_line_end < 0:
        header_line_end = len(text)
    header_line = text[header_line_start:header_line_end]
    header_indent_match = re.match(r"[ \t]*", header_line)
    header_indent = header_indent_match.group(0) if header_indent_match else ""

    depth = 0
    quote: str | None = None
    triple_quote: str | None = None
    escaped = False
    line_comment = False
    block_comment = False
    index = opening
    while index < len(text):
        char = text[index]
        next_char = text[index + 1] if index + 1 < len(text) else ""

        if line_comment:
            if char == "\n":
                line_comment = False
            index += 1
            continue
        if block_comment:
            if char == "*" and next_char == "/":
                block_comment = False
                index += 2
                continue
            index += 1
            continue
        if triple_quote is not None:
            if text.startswith(triple_quote, index):
                triple_quote = None
                index += 3
                continue
            if char == "\\":
                index += 2
            else:
                index += 1
            continue
        if quote is not None:
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == quote:
                quote = None
            index += 1
            continue

        if char == "/" and next_char == "/":
            line_comment = True
            index += 2
            continue
        if char == "/" and next_char == "*":
            block_comment = True
            index += 2
            continue
        if char in ('"', "'"):
            if text.startswith(char * 3, index):
                triple_quote = char * 3
                index += 3
                continue
            quote = char
            index += 1
            continue
        if char == "{":
            depth += 1
        elif char == "}":
            depth -= 1
            if depth == 0:
                return opening, index
        index += 1

    # The dependencies/defaultConfig blocks in Godot's generated template are
    # top-level (or consistently indented) blocks. Their closing brace is on
    # its own line at the same indentation as the header. This is a safe
    # fallback for Groovy's slashy/interpolated string forms.
    fallback_close = _same_indent_closing_brace(text, opening, header_indent, label)
    if fallback_close is not None:
        return opening, fallback_close

    raise RuntimeError(
        f"Could not locate the closing brace for the {label} block in build.gradle. "
        "The generated template may be modified or incomplete; inspect this block before patching."
    )


def block_body_indent(text: str, opening: int) -> str:
    """Return the generated block's child indentation (header indent + four spaces)."""
    line_start = text.rfind("\n", 0, opening) + 1
    line_end = text.find("\n", line_start)
    if line_end < 0:
        line_end = len(text)
    header_line = text[line_start:line_end]
    header_indent = re.match(r"[ \t]*", header_line).group(0)
    return header_indent + "    "


def insert_lines_before_block_close(
    text: str, opening: int, closing: int, lines: list[str], label: str
) -> str:
    """Insert indented statements before a block's own-line closing brace."""
    if not lines:
        return text
    line_start = text.rfind("\n", opening + 1, closing) + 1
    closing_prefix = text[line_start:closing]
    if closing_prefix.strip():
        raise RuntimeError(
            f"The closing brace for {label} is not on its own line; refusing an unsafe Gradle edit."
        )
    indent = block_body_indent(text, opening)
    insertion = "".join(f"{indent}{line}\n" for line in lines)
    return text[:line_start] + insertion + text[line_start:]


def read_client_id(example_path: Path) -> str:
    if not example_path.is_file():
        raise FileNotFoundError(f"Missing EOS config template: {example_path}")
    content = example_path.read_text(encoding="utf-8")
    match = re.search(r'^\s*var\s+client_id\s*:\s*String\s*=\s*"([^"]+)"', content, re.MULTILINE)
    if match is None:
        raise RuntimeError("Could not read client_id from EOSLocalConfig.gd.example.")
    client_id = match.group(1).strip()
    if not client_id:
        raise RuntimeError("The EOS client_id in EOSLocalConfig.gd.example is empty.")
    return client_id


def patch_gradle(build_gradle: Path, client_id: str, aar_path: Path) -> bool:
    if not build_gradle.is_file():
        raise FileNotFoundError(
            f"Generated Gradle file not found: {build_gradle}. Install Godot's Android build template first."
        )

    text = build_gradle.read_text(encoding="utf-8")
    original = text

    dep_open, dep_close = find_block(text, r"(?m)^\s*dependencies\s*\{", "dependencies")
    dep_body = text[dep_open + 1 : dep_close]
    missing = [line for line in DEPENDENCIES if line not in dep_body]
    if missing:
        dependency_lines = ["// Epic Online Services Android SDK (EOSG 2.3.1)", *missing]
        text = insert_lines_before_block_close(text, dep_open, dep_close, dependency_lines, "dependencies")

    default_open, default_close = find_block(
        text, r"(?m)^\s*defaultConfig\s*\{", "defaultConfig"
    )
    default_body = text[default_open + 1 : default_close]
    indent = block_body_indent(text, default_open)
    client_line = f'String eosClientId = "{client_id}"'
    scheme_line = 'resValue("string", "eos_login_protocol_scheme", "eos." + eosClientId.toLowerCase())'
    dimension_line = "missingDimensionStrategy 'products', 'template'"

    client_pattern = r'(?m)^[ \t]*String\s+eosClientId\s*=\s*"[^"]*"[ \t]*$'
    client_match = re.search(client_pattern, default_body)
    if client_match is not None:
        current_client_line = default_body[client_match.start() : client_match.end()].strip()
        if current_client_line != client_line:
            default_body = re.sub(client_pattern, indent + client_line, default_body, count=1)
            text = text[: default_open + 1] + default_body + text[default_close :]
            # Re-find because the insertion offset is unchanged but the block
            # closing offset may have shifted if the replacement length changed.
            default_open, default_close = find_block(
                text, r"(?m)^\s*defaultConfig\s*\{", "defaultConfig"
            )
            default_body = text[default_open + 1 : default_close]
    else:
        text = insert_lines_before_block_close(
            text, default_open, default_close, [client_line], "defaultConfig"
        )
        default_open, default_close = find_block(
            text, r"(?m)^\s*defaultConfig\s*\{", "defaultConfig"
        )
        default_body = text[default_open + 1 : default_close]

    additions: list[str] = []
    if not re.search(r"(?m)^[ \t]*" + re.escape(dimension_line) + r"[ \t]*$", default_body):
        additions.append(dimension_line)
    if "eos_login_protocol_scheme" not in default_body:
        additions.append(scheme_line)
    if additions:
        text = insert_lines_before_block_close(
            text, default_open, default_close, additions, "defaultConfig"
        )

    # EOSG's bundled AAR metadata explicitly requires core library desugaring.
    # Godot 4.7.2's app/build.gradle already contains one compileOptions block;
    # enable desugaring there so AGP's check<Variant>AarMetadata task can pass.
    compile_open, compile_close = find_block(
        text, r"(?m)^\s*compileOptions\s*\{", "compileOptions"
    )
    compile_body = text[compile_open + 1 : compile_close]
    desugar_flag = "coreLibraryDesugaringEnabled true"
    if not re.search(
        r"(?m)^\s*coreLibraryDesugaringEnabled\s+(?:true|=\s*true)\s*$",
        compile_body,
    ):
        text = insert_lines_before_block_close(
            text, compile_open, compile_close, [desugar_flag], "compileOptions"
        )

    if text != original:
        build_gradle.write_text(text, encoding="utf-8", newline="")
    return text != original


def patch_config_gradle(config_gradle: Path) -> bool:
    if not config_gradle.is_file():
        raise FileNotFoundError(f"Generated Android config.gradle not found: {config_gradle}")
    text = config_gradle.read_text(encoding="utf-8")
    match = re.search(r"(?m)^(\s*minSdk\s*:\s*)(\d+)(\s*,?\s*)$", text)
    if match is None:
        raise RuntimeError("Could not locate minSdk in generated android/build/config.gradle.")
    current = int(match.group(2))
    if current >= 23:
        return False
    text = text[: match.start(2)] + "23" + text[match.end(2) :]
    config_gradle.write_text(text, encoding="utf-8", newline="")
    return True


def find_godot_activity(android_build: Path) -> Path:
    matches: list[Path] = []
    for path in android_build.rglob("*.java"):
        source = path.read_text(encoding="utf-8")
        if re.search(r"\bclass\s+\w+\s+extends\s+GodotActivity\b", source):
            matches.append(path)
    if len(matches) != 1:
        raise RuntimeError(
            f"Expected one generated Java class extending GodotActivity, found {len(matches)}."
        )
    return matches[0]


def patch_java_activity(java_path: Path) -> bool:
    text = java_path.read_text(encoding="utf-8")
    original = text

    if "import com.epicgames.mobile.eossdk.EOSSDK;" not in text:
        package_match = re.search(r"(?m)^package\s+[^;]+;\s*$", text)
        if package_match is None:
            raise RuntimeError(f"Could not locate package declaration in {java_path}.")
        text = text[: package_match.end()] + "\n\nimport com.epicgames.mobile.eossdk.EOSSDK;" + text[package_match.end() :]

    if "import android.content.Intent;" not in text:
        package_match = re.search(r"(?m)^package\s+[^;]+;\s*$", text)
        if package_match is None:
            raise RuntimeError(f"Could not locate package declaration in {java_path}.")
        text = text[: package_match.end()] + "\nimport android.content.Intent;" + text[package_match.end() :]

    class_match = re.search(r"\bclass\s+\w+\s+extends\s+GodotActivity\s*\{", text)
    if class_match is None:
        raise RuntimeError(f"Could not locate GodotActivity class declaration in {java_path}.")
    class_open = text.find("{", class_match.start(), class_match.end())
    class_prefix = text[class_open + 1 :]
    if 'System.loadLibrary("EOSSDK")' not in text:
        text = text[: class_open + 1] + '\n    static {\n        System.loadLibrary("EOSSDK");\n    }\n' + text[class_open + 1 :]

    on_create = re.search(r"void\s+onCreate\s*\(\s*Bundle\s+savedInstanceState\s*\)\s*\{", text)
    if on_create is None:
        raise RuntimeError(f"Could not locate onCreate(Bundle savedInstanceState) in {java_path}.")
    method_open = text.find("{", on_create.start(), on_create.end())
    method_body_start = method_open + 1
    if "EOSSDK.init(getActivity());" not in text:
        text = text[:method_body_start] + "\n        EOSSDK.init(getActivity());" + text[method_body_start:]
    else:
        # Move an existing call to the beginning of onCreate if it was inserted elsewhere.
        text = text.replace("        EOSSDK.init(getActivity());\n", "")
        on_create = re.search(r"void\s+onCreate\s*\(\s*Bundle\s+savedInstanceState\s*\)\s*\{", text)
        method_open = text.find("{", on_create.start(), on_create.end())
        text = text[: method_open + 1] + "\n        EOSSDK.init(getActivity());" + text[method_open + 1 :]

    if "setIntent(" not in text:
        existing_new_intent = re.search(
            r"void\s+onNewIntent\s*\(\s*Intent\s+(\w+)\s*\)\s*\{",
            text,
        )
        if existing_new_intent is not None:
            intent_variable = existing_new_intent.group(1)
            method_open = text.find("{", existing_new_intent.start(), existing_new_intent.end())
            super_call = re.search(
                rf"super\.onNewIntent\s*\(\s*{re.escape(intent_variable)}\s*\)\s*;",
                text[method_open + 1 :],
            )
            insert_at = method_open + 1 + super_call.end() if super_call is not None else method_open + 1
            text = text[:insert_at] + f"\n        setIntent({intent_variable});" + text[insert_at:]
        else:
            method = (
                "\n\n    @Override\n"
                "    protected void onNewIntent(Intent intent) {\n"
                "        super.onNewIntent(intent);\n"
                "        setIntent(intent);\n"
                "    }\n"
            )
            # Generated Godot activity template is a single small class; append before its final class brace.
            closing = text.rfind("}")
            if closing < 0:
                raise RuntimeError(f"Could not locate final class brace in {java_path}.")
            text = text[:closing] + method + text[closing:]

    if text != original:
        java_path.write_text(text, encoding="utf-8", newline="")
        return True
    return False


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--project-root", type=Path, default=ROOT)
    parser.add_argument("--android-build", type=Path, default=None)
    args = parser.parse_args()

    project_root = args.project_root.resolve()
    android_build = args.android_build.resolve() if args.android_build else project_root / "android/build"
    aar_path = project_root / AAR_RELATIVE
    if not aar_path.is_file() or aar_path.stat().st_size == 0:
        print(
            f"ERROR: EOS Android AAR is missing or empty: {aar_path}\n"
            "Install the EOSG 2.3.1 Android package under addons/epic-online-services-godot first.",
            file=sys.stderr,
        )
        return 1

    try:
        client_id = read_client_id(project_root / "scripts/networking/EOSLocalConfig.gd.example")
        build_changed = patch_gradle(android_build / "build.gradle", client_id, aar_path)
        config_changed = patch_config_gradle(android_build / "config.gradle")
        java_path = find_godot_activity(android_build)
        java_changed = patch_java_activity(java_path)
        print(f"EOSG Android template ready. Java activity: {java_path}")
        print(
            "Changes: build.gradle=%s, config.gradle=%s, activity=%s"
            % (build_changed, config_changed, java_changed)
        )
        return 0
    except (OSError, RuntimeError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())

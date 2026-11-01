"""Regression tests for EOS autoload verification (UID and res:// forms)."""
from __future__ import annotations

import contextlib
import io
import tempfile
import unittest
from pathlib import Path

from tools import verify_eos_install as verifier


class VerifyEOSAutoloadTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp_dir = tempfile.TemporaryDirectory()
        self.root = Path(self.temp_dir.name)
        self.autoloads = {**verifier.EOSG_AUTOLOADS, **verifier.PROJECT_AUTOLOADS}
        for relative_path in self.autoloads.values():
            script = self.root / relative_path
            script.parent.mkdir(parents=True, exist_ok=True)
            script.write_text("# test script\n", encoding="utf-8")
            (Path(str(script) + ".uid")).write_text(
                f"uid://test_{script.stem}\n", encoding="utf-8"
            )

        plugin = self.root / "addons/epic-online-services-godot/plugin.cfg"
        plugin.parent.mkdir(parents=True, exist_ok=True)
        plugin.write_text("[plugin]\n", encoding="utf-8")
        self.write_project()

    def tearDown(self) -> None:
        self.temp_dir.cleanup()

    def write_project(
        self,
        overrides: dict[str, str] | None = None,
        *,
        include_plugin: bool = True,
    ) -> None:
        overrides = overrides or {}
        lines = ["[application]", 'config/name="Verifier Test"', "", "[autoload]"]
        for name, relative_path in self.autoloads.items():
            uid = (self.root / (relative_path + ".uid")).read_text(encoding="utf-8").strip()
            lines.append(f'{name}="{overrides.get(name, "*" + uid)}"')
        lines.extend(["", "[editor_plugins]"])
        if include_plugin:
            lines.append(
                'enabled=PackedStringArray("res://addons/epic-online-services-godot/plugin.cfg")'
            )
        (self.root / "project.godot").write_text("\n".join(lines) + "\n", encoding="utf-8")

    def check_quietly(self) -> list[str]:
        with contextlib.redirect_stdout(io.StringIO()):
            return verifier.check_project_wiring(self.root)

    def test_accepts_uid_based_autoloads(self) -> None:
        self.assertEqual(self.check_quietly(), [])

    def test_accepts_res_path_autoloads(self) -> None:
        overrides = {
            name: f"*res://{relative_path}"
            for name, relative_path in self.autoloads.items()
        }
        self.write_project(overrides)
        self.assertEqual(self.check_quietly(), [])

    def test_accepts_mixed_uid_and_res_path_autoloads(self) -> None:
        first_name, first_path = next(iter(self.autoloads.items()))
        self.write_project({first_name: f"*res://{first_path}"})
        self.assertEqual(self.check_quietly(), [])

    def test_rejects_uid_that_does_not_match_sidecar(self) -> None:
        self.write_project({"HPlatform": "*uid://wrong_uid"})
        self.assertTrue(any("HPlatform" in item and "does not match" in item for item in self.check_quietly()))

    def test_rejects_disabled_autoload(self) -> None:
        self.write_project({"HP2P": "uid://test_hp2p"})
        self.assertTrue(any("HP2P" in item and "not enabled" in item for item in self.check_quietly()))

    def test_rejects_missing_autoload(self) -> None:
        project = self.root / "project.godot"
        text = project.read_text(encoding="utf-8")
        text = "\n".join(line for line in text.splitlines() if not line.startswith("HAuth="))
        project.write_text(text + "\n", encoding="utf-8")
        self.assertTrue(any("HAuth" in item and "missing" in item for item in self.check_quietly()))

    def test_rejects_missing_uid_sidecar(self) -> None:
        (self.root / "scripts/networking/EOSOnline.gd.uid").unlink()
        self.assertTrue(any("EOSOnline" in item and "no sidecar" in item for item in self.check_quietly()))

    def test_rejects_disabled_eosg_editor_plugin(self) -> None:
        self.write_project(include_plugin=False)
        self.assertTrue(any("editor plugin is not enabled" in item for item in self.check_quietly()))


if __name__ == "__main__":
    unittest.main()

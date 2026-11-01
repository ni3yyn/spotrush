from __future__ import annotations

import tempfile
import unittest
import zipfile
from pathlib import Path

from tools.install_deeplink_plugin import PLUGIN_PREFIX, install_archive


class InstallDeeplinkPluginTests(unittest.TestCase):
    def _make_archive(self, path: Path, *, include_required: bool = True) -> None:
        files = {
            "plugin.cfg": (
                '[plugin]\nname="Deeplink"\nversion="6.0.1"\n'
                'script="DeeplinkPlugin.gd"\n'
            ),
            "DeeplinkPlugin.gd": "extends EditorPlugin\n",
            "Deeplink.gd": "extends Node\n",
            "config/DeeplinkExportConfig.gd": "class_name DeeplinkExportConfig\n",
            "config/DeeplinkExportConfigItem.gd": "class_name DeeplinkExportConfigItem\n",
            "model/DeeplinkUrl.gd": "class_name DeeplinkUrl\n",
            "bin/debug/DeeplinkPlugin-debug.aar": "debug-aar",
            "bin/release/DeeplinkPlugin-release.aar": "release-aar",
            # This project-owned file must never be replaced by an archive copy.
            "export.cfg": "[WrongConfig]\nscheme = \"wrong\"\n",
        }
        if not include_required:
            files.pop("bin/release/DeeplinkPlugin-release.aar")

        with zipfile.ZipFile(path, "w") as archive:
            for relative, content in files.items():
                archive.writestr(PLUGIN_PREFIX + relative, content)

    def _make_project(self, root: Path) -> None:
        shared = root / "addons" / "GMPShared"
        shared.mkdir(parents=True)
        (shared / "GmpLogger.gd").write_text("class_name GmpLogger\n", encoding="utf-8")
        (shared / "SpmDependency.gd").write_text("class_name SpmDependency\n", encoding="utf-8")

    def test_installs_plugin_and_preserves_project_export_config(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            archive_path = root / "plugin.zip"
            self._make_archive(archive_path)
            self._make_project(root)

            export_cfg = root / "addons" / "DeeplinkPlugin" / "export.cfg"
            export_cfg.parent.mkdir(parents=True)
            export_cfg.write_text(
                '[SpotRushInvite]\nscheme = "spotrush"\nhost = "join"\n',
                encoding="utf-8",
            )

            # Use the pinned digest only after replacing it with the test archive's digest.
            import hashlib
            from unittest.mock import patch

            actual = hashlib.sha256(archive_path.read_bytes()).hexdigest()
            with patch("tools.install_deeplink_plugin.ARCHIVE_SHA256", actual):
                install_archive(archive_path, root)

            plugin_dir = root / "addons" / "DeeplinkPlugin"
            self.assertTrue((plugin_dir / "DeeplinkPlugin.gd").is_file())
            self.assertEqual(
                (plugin_dir / "bin" / "debug" / "DeeplinkPlugin-debug.aar").read_text(),
                "debug-aar",
            )
            self.assertEqual(
                export_cfg.read_text(encoding="utf-8"),
                '[SpotRushInvite]\nscheme = "spotrush"\nhost = "join"\n',
            )
            self.assertTrue((root / "addons" / "GMPShared" / "GmpLogger.gd").is_file())

    def test_rejects_incomplete_archive_before_installing(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            archive_path = root / "plugin.zip"
            self._make_archive(archive_path, include_required=False)
            self._make_project(root)

            import hashlib
            from unittest.mock import patch

            actual = hashlib.sha256(archive_path.read_bytes()).hexdigest()
            with patch("tools.install_deeplink_plugin.ARCHIVE_SHA256", actual):
                with self.assertRaisesRegex(ValueError, "archive is incomplete"):
                    install_archive(archive_path, root)

            self.assertFalse((root / "addons" / "DeeplinkPlugin").exists())

    def test_rejects_wrong_archive_digest(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            archive_path = root / "plugin.zip"
            self._make_archive(archive_path)
            self._make_project(root)

            with self.assertRaisesRegex(ValueError, "SHA-256 mismatch"):
                install_archive(archive_path, root)


if __name__ == "__main__":
    unittest.main()

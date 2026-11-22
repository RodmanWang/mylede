#!/usr/bin/env python3
"""Contract tests for MyUpdate custom sysupgrade keep-path UCI lists."""
from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[2]
BACKEND = ROOT / "luci-app-myupdate/root/usr/share/rpcd/ucode/myupdate.uc"
VIEW = ROOT / "luci-app-myupdate/htdocs/luci-static/resources/view/myupdate/index.js"
BACKUP = ROOT / "luci-app-myupdate/root/usr/libexec/myupdate/prepare-sysupgrade-backup.sh"


class CustomKeepPathsContractTests(unittest.TestCase):
    def test_backend_exposes_lists_and_migrates_legacy_multiline_values(self):
        source = BACKEND.read_text(encoding="utf-8")
        self.assertIn("type(keep_paths) == 'array'", source)
        self.assertIn("split(keep_paths, '\\n')", source)
        self.assertIn("c.set(CONFIG, 'main', 'custom_keep_paths', length(paths) ? paths : '')", source)

    def test_luci_uses_dynamic_list_control(self):
        source = VIEW.read_text(encoding="utf-8")
        self.assertIn("s.option(form.DynamicList, 'custom_keep_paths'", source)
        self.assertIn("return cfg.custom_keep_paths || [];", source)

    def test_sysupgrade_backup_reader_handles_space_separated_uci_lists(self):
        source = BACKUP.read_text(encoding="utf-8")
        self.assertIn("uci -q get myupdate.main.custom_keep_paths", source)
        self.assertIn("tr ' ' '\\n'", source)


if __name__ == "__main__":
    unittest.main()

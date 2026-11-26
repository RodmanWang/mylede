#!/usr/bin/env python3
"""Contract tests for timestamped MyUpdate IPK package versions."""
from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[2]
MAKEFILE = ROOT / "luci-app-myupdate/Makefile"
BUILD_SCRIPT = ROOT / "scripts/build-myupdate-package.sh"
WORKFLOW = ROOT / ".github/workflows/build.yml"


class PackageTimestampVersionTests(unittest.TestCase):
    def test_makefile_overrides_luci_git_revision_with_build_timestamp(self):
        source = MAKEFILE.read_text(encoding="utf-8")
        self.assertIn(
            "MYUPDATE_BUILD_TIMESTAMP ?= $(shell TZ=Asia/Shanghai date +'%y%m%d%H%M%S')",
            source,
        )
        self.assertIn("PKG_VERSION:=0.$(MYUPDATE_BUILD_TIMESTAMP)", source)
        self.assertLess(
            source.index("PKG_VERSION:=0.$(MYUPDATE_BUILD_TIMESTAMP)"),
            source.index("include $(TOPDIR)/feeds/luci/luci.mk"),
        )

    def test_firmware_workflow_exports_one_timestamp_to_all_package_build_steps(self):
        source = WORKFLOW.read_text(encoding="utf-8")
        self.assertIn(
            "BUILD_TIMESTAMP=\"$(TZ=Asia/Shanghai date +'%Y%m%d%H%M%S')\"",
            source,
        )
        self.assertIn('MYUPDATE_BUILD_TIMESTAMP="' + "$" + '{BUILD_TIMESTAMP:2}"', source)
        self.assertIn(
            'echo "MYUPDATE_BUILD_TIMESTAMP=$MYUPDATE_BUILD_TIMESTAMP" >> "$GITHUB_ENV"',
            source,
        )

    def test_standalone_builder_pins_and_selects_only_current_timestamp_packages(self):
        source = BUILD_SCRIPT.read_text(encoding="utf-8")
        self.assertIn("export MYUPDATE_BUILD_TIMESTAMP", source)
        self.assertIn("^[0-9]{12}$", source)
        self.assertIn('luci-app-myupdate_0.' + "$" + '{MYUPDATE_BUILD_TIMESTAMP}*.ipk', source)
        self.assertIn('luci-i18n-myupdate-zh-cn_0.' + "$" + '{MYUPDATE_BUILD_TIMESTAMP}*.ipk', source)
        self.assertIn("luci-app-myupdate_*.ipk", source)
        self.assertIn("luci-i18n-myupdate-zh-cn_*.ipk", source)
        self.assertIn("Do not leave older MyUpdate packages", source)

    def test_new_timestamp_version_sorts_after_legacy_version(self):
        old_version = "0.261126.50465"
        new_version = "0.261126230053"
        old_parts = tuple(int(part) for part in old_version.split("."))
        new_parts = tuple(int(part) for part in new_version.split("."))
        self.assertGreater(new_parts, old_parts)

    def test_timestamp_is_exactly_twelve_digits(self):
        for value in ("261126230053", "000101000000", "991231235959"):
            with self.subTest(value=value):
                self.assertRegex(value, re.compile(r"^[0-9]{12}$"))


if __name__ == "__main__":
    unittest.main()

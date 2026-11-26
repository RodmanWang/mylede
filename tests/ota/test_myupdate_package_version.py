#!/usr/bin/env python3
"""Contract tests for monotonic, compact MyUpdate IPK build versions."""
from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[2]
MAKEFILE = ROOT / "luci-app-myupdate/Makefile"
FIRMWARE_BUILD = ROOT / "scripts/07-build.sh"
PACKAGE_BUILD = ROOT / "scripts/build-myupdate-package.sh"


class MyUpdatePackageVersionTests(unittest.TestCase):
    def test_package_recipe_uses_a_valid_compact_utc_timestamp_as_pkg_version(self):
        source = MAKEFILE.read_text(encoding="utf-8")
        self.assertIn("date -u +%y%m%d%H%M%S", source)
        self.assertIn("PKG_VERSION:=$(MYUPDATE_PACKAGE_VERSION)", source)
        self.assertIn("PKG_RELEASE:=1", source)
        self.assertIn("PKG_PO_VERSION:=$(PKG_VERSION)-r$(PKG_RELEASE)", source)
        # The fallback timestamp still uses a simple date shell call; only the
        # fragile shell-based validation was removed from this Makefile.
        self.assertNotIn("grep -Eq", source)
        self.assertIn("PKG_VERSION:=$(MYUPDATE_PACKAGE_VERSION)", source)

    def test_timestamp_validation_stays_in_build_entry_points(self):
        for path in (FIRMWARE_BUILD, PACKAGE_BUILD):
            source = path.read_text(encoding="utf-8")
            self.assertIn('[[ "$MYUPDATE_PACKAGE_VERSION" =~ ^[0-9]{12}$ ]] ', source)

    def test_firmware_build_pins_one_timestamp_before_defconfig(self):
        source = FIRMWARE_BUILD.read_text(encoding="utf-8")
        self.assertIn('MYUPDATE_PACKAGE_VERSION="${MYUPDATE_PACKAGE_VERSION:-$(date -u +%y%m%d%H%M%S)}"', source)
        self.assertIn("export MYUPDATE_PACKAGE_VERSION", source)
        self.assertLess(source.index("export MYUPDATE_PACKAGE_VERSION"), source.index("make defconfig"))

    def test_standalone_package_build_pins_one_timestamp_before_defconfig(self):
        source = PACKAGE_BUILD.read_text(encoding="utf-8")
        self.assertIn('MYUPDATE_PACKAGE_VERSION="${MYUPDATE_PACKAGE_VERSION:-$(date -u +%y%m%d%H%M%S)}"', source)
        self.assertIn("export MYUPDATE_PACKAGE_VERSION", source)
        self.assertLess(source.index("export MYUPDATE_PACKAGE_VERSION"), source.index("make defconfig"))

    def test_timestamp_format_is_compact_and_chronologically_sortable(self):
        earlier = "261126231923"
        later = "261126231924"
        self.assertRegex(earlier, re.compile(r"^[0-9]{12}$"))
        self.assertRegex(later, re.compile(r"^[0-9]{12}$"))
        self.assertLess(earlier, later)


if __name__ == "__main__":
    unittest.main()

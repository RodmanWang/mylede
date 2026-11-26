#!/usr/bin/env python3
"""Regression tests for preserving the MyUpdate UCI config as an opkg conffile."""

import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
MAKEFILE = ROOT / "luci-app-myupdate" / "Makefile"


class PackageConfigPreservationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.makefile = MAKEFILE.read_text(encoding="utf-8")

    def test_uci_config_is_declared_as_package_conffile(self):
        match = re.search(
            r"(?ms)^define Package/luci-app-myupdate/conffiles\s*\n(.*?)\nendef\s*$",
            self.makefile,
        )
        self.assertIsNotNone(
            match,
            "Package/luci-app-myupdate must declare its conffiles block",
        )
        paths = [
            line.strip()
            for line in match.group(1).splitlines()
            if line.strip() and not line.lstrip().startswith("#")
        ]
        self.assertEqual(paths, ["/etc/config/myupdate"])

    def test_conffile_declaration_is_scoped_to_myupdate_package(self):
        self.assertIn(
            "define Package/luci-app-myupdate/conffiles",
            self.makefile,
        )
        self.assertNotIn(
            "define Package/luci-app-myupdate/files",
            self.makefile,
        )

    def test_runtime_data_and_secrets_are_not_declared_as_conffiles(self):
        match = re.search(
            r"(?ms)^define Package/luci-app-myupdate/conffiles\s*\n(.*?)\nendef\s*$",
            self.makefile,
        )
        self.assertIsNotNone(match)
        declared = match.group(1)
        self.assertNotIn("/etc/myupdate", declared)
        self.assertNotIn("token", declared)


if __name__ == "__main__":
    unittest.main()

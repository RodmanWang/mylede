#!/usr/bin/env python3
"""Contract tests for preserving MyUpdate's administrator UCI configuration."""
from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[2]
PACKAGE_MAKEFILE = ROOT / "luci-app-myupdate/Makefile"


class PackageConfigPreservationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.source = PACKAGE_MAKEFILE.read_text(encoding="utf-8")

    def test_main_uci_file_is_declared_as_a_package_conffile(self):
        self.assertIn(
            "define Package/luci-app-myupdate/conffiles\n"
            "/etc/config/myupdate\n"
            "endef",
            self.source,
        )

    def test_postinst_skips_actions_for_offline_install_root(self):
        postinst = self.source.split(
            "define Package/luci-app-myupdate/postinst\n", 1
        )[1].split("\nendef", 1)[0]
        self.assertIn('[ -n "$${IPKG_INSTROOT}" ] && exit 0', postinst)

    def test_postinst_does_not_replace_the_uci_configuration(self):
        postinst = self.source.split(
            "define Package/luci-app-myupdate/postinst\n", 1
        )[1].split("\nendef", 1)[0]
        self.assertNotIn("cat > /etc/config/myupdate", postinst)
        self.assertNotIn("uci import myupdate", postinst)


if __name__ == "__main__":
    unittest.main()

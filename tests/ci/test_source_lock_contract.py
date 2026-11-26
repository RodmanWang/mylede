#!/usr/bin/env python3
"""Static contracts for local source locking and release provenance."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]


class SourceLockContractTests(unittest.TestCase):
    def test_local_feed_flow_generates_lock_when_actions_lock_is_absent(self):
        script = (ROOT / "scripts/03-update-feeds.sh").read_text(encoding="utf-8")
        self.assertIn('bash "$SCRIPT_DIR/resolve-local-source-lock.sh" "$TOPDIR" "$SOURCE_LOCK"', script)
        self.assertIn('done < "$SOURCE_LOCK"', script)
        self.assertIn('while IFS=$', script)

    def test_local_resolver_uses_package_recipe_urls_and_openclash_ref(self):
        script = (ROOT / "scripts/resolve-local-source-lock.sh").read_text(encoding="utf-8")
        self.assertIn('"PKG_SOURCE_URL"', script)
        self.assertIn('"SMARTDNS_WEBUI_SOURCE_URL"', script)
        self.assertIn('f"refs/heads/{branch}"', script)
        self.assertIn('git", "ls-remote"', script)

    def test_lede_sync_fallback_prefers_configured_upstream(self):
        script = (ROOT / "scripts/02-update-source.sh").read_text(encoding="utf-8")
        self.assertIn("'@{upstream}'", script)
        self.assertIn('LEDE_REMOTE="${LEDE_UPSTREAM%%/*}"', script)
        self.assertIn('git fetch "$LEDE_REMOTE"', script)

    def test_minisign_provenance_is_written_to_signed_manifest(self):
        workflow = (ROOT / ".github/workflows/build.yml").read_text(encoding="utf-8")
        validator = (ROOT / "tests/ota/validate_release.py").read_text(encoding="utf-8")
        self.assertIn('outputs["minisign_version"] = minisign_version', workflow)
        self.assertIn("'minisign_release': {", workflow)
        self.assertIn("'minisign_release': meta['minisign_release']", workflow)
        self.assertIn('manifest.get("minisign_release")', validator)
        self.assertIn('minisign.get("sha256", "")', validator)


if __name__ == "__main__":
    unittest.main()

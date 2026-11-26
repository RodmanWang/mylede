#!/usr/bin/env python3
"""Tests for advancing the standalone Minisign fallback after successful release."""
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
UPDATER = ROOT / "scripts/update-minisign-fallback.py"
INITIAL_HASH = "1" * 64
NEW_HASH = "2" * 64


class MinisignFallbackTests(unittest.TestCase):
    def run_update(self, current_version, current_hash, new_version, new_hash):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        root = Path(temp.name)
        makefile = root / "Makefile"
        manifest = root / "manifest.json"
        makefile.write_text(
            "PKG_VERSION:=" + current_version + "\n"
            "PKG_RELEASE:=1\n"
            "PKG_HASH:=" + current_hash + "\n",
            encoding="utf-8",
        )
        manifest.write_text(json.dumps({
            "minisign_release": {"version": new_version, "sha256": new_hash}
        }), encoding="utf-8")
        result = subprocess.run(
            [sys.executable, str(UPDATER), str(manifest), str(makefile)],
            capture_output=True, text=True,
        )
        return result, makefile.read_text(encoding="utf-8")

    def test_newer_successful_release_updates_version_and_hash(self):
        result, content = self.run_update("0.11", INITIAL_HASH, "0.12", NEW_HASH)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("PKG_VERSION:=0.12", content)
        self.assertIn("PKG_HASH:=" + NEW_HASH, content)

    def test_same_release_is_idempotent(self):
        result, content = self.run_update("0.12", NEW_HASH, "0.12", NEW_HASH)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("PKG_VERSION:=0.12", content)
        self.assertIn("PKG_HASH:=" + NEW_HASH, content)

    def test_older_release_never_downgrades_fallback(self):
        result, content = self.run_update("0.13", NEW_HASH, "0.12", INITIAL_HASH)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("PKG_VERSION:=0.13", content)
        self.assertIn("PKG_HASH:=" + NEW_HASH, content)

    def test_same_version_with_different_hash_is_rejected(self):
        result, content = self.run_update("0.12", INITIAL_HASH, "0.12", NEW_HASH)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("different archive digest", result.stderr)
        self.assertIn("PKG_HASH:=" + INITIAL_HASH, content)

    def test_workflow_updates_fallback_only_after_release_creation(self):
        workflow = (ROOT / ".github/workflows/build.yml").read_text(encoding="utf-8")
        release = workflow.index("gh release create")
        update = workflow.index("scripts/update-minisign-fallback.py")
        commit = workflow.index('git commit -m "ci(build): remember last successful firmware partition layout"')
        self.assertLess(release, update)
        self.assertLess(update, commit)
        self.assertIn("git add build-config/last-successful-partition-layout.json .github/workflows/build.yml minisign/Makefile", workflow)


if __name__ == "__main__":
    unittest.main()

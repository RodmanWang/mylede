import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
UPDATER = ROOT / "scripts/update-build-partition-defaults.py"


class PartitionDefaultsPersistenceTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.manifest = self.root / "manifest.json"
        self.state = self.root / "state.json"
        self.workflow = self.root / "build.yml"
        self.workflow.write_text(
            "on:\n"
            "  workflow_dispatch:\n"
            "    inputs:\n"
            "      kernel_partsize:\n"
            "        description: old kernel hint\n"
            "        type: string\n"
            "        required: false\n"
            "        default: '256'\n"
            "      rootfs_partsize:\n"
            "        description: old rootfs hint\n"
            "        type: string\n"
            "        required: false\n"
            "        default: '4096'\n",
            encoding="utf-8",
        )

    def run_updater(self, manifest):
        self.manifest.write_text(json.dumps(manifest), encoding="utf-8")
        return subprocess.run(
            [sys.executable, str(UPDATER), str(self.manifest), str(self.state), str(self.workflow)],
            text=True,
            capture_output=True,
            check=False,
        )

    def valid_manifest(self):
        return {
            "schema_version": 2,
            "tag": "mylede-v-test",
            "version": "test-version",
            "partition_layout": {
                "kernel_partsize_mib": 384,
                "rootfs_partsize_mib": 6144,
                "uses_boot_part": True,
                "upstream_defaults_mib": {
                    "kernel_partsize": 96,
                    "rootfs_partsize": 512,
                },
            },
        }

    def test_successful_manifest_updates_persisted_sizes_and_dispatch_form(self):
        result = self.run_updater(self.valid_manifest())
        self.assertEqual(result.returncode, 0, result.stderr)

        state = json.loads(self.state.read_text(encoding="utf-8"))
        self.assertEqual(state["kernel_partsize_mib"], 384)
        self.assertEqual(state["rootfs_partsize_mib"], 6144)
        self.assertEqual(state["upstream_defaults_mib"], {
            "kernel_partsize": 96,
            "rootfs_partsize": 512,
        })
        self.assertEqual(state["manifest_tag"], "mylede-v-test")

        workflow = self.workflow.read_text(encoding="utf-8")
        self.assertIn("上游源码默认为 96 MiB（上次成功 Manifest 记录）", workflow)
        self.assertIn("上游源码默认为 512 MiB（上次成功 Manifest 记录）", workflow)
        self.assertIn("default: '384'", workflow)
        self.assertIn("default: '6144'", workflow)

    def test_invalid_manifest_does_not_overwrite_existing_defaults(self):
        original_state = '{"kernel_partsize_mib":256,"rootfs_partsize_mib":4096}'
        self.state.write_text(original_state, encoding="utf-8")
        original_workflow = self.workflow.read_text(encoding="utf-8")
        manifest = self.valid_manifest()
        manifest["partition_layout"]["rootfs_partsize_mib"] = 0
        result = self.run_updater(manifest)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.state.read_text(encoding="utf-8"), original_state)
        self.assertEqual(self.workflow.read_text(encoding="utf-8"), original_workflow)

    def test_schema_v1_or_non_efi_manifest_cannot_update_defaults(self):
        manifest = self.valid_manifest()
        manifest["schema_version"] = 1
        result = self.run_updater(manifest)
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(self.state.exists())

        manifest = self.valid_manifest()
        manifest["partition_layout"]["uses_boot_part"] = False
        result = self.run_updater(manifest)
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(self.state.exists())


if __name__ == "__main__":
    unittest.main()

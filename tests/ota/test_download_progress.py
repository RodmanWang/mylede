#!/usr/bin/env python3
"""Contract tests for live MyUpdate firmware download progress."""
from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[2]
VIEW = ROOT / "luci-app-myupdate/htdocs/luci-static/resources/view/myupdate/index.js"
RPC = ROOT / "luci-app-myupdate/root/usr/share/rpcd/ucode/myupdate.uc"
TASK = ROOT / "luci-app-myupdate/root/usr/libexec/myupdate/task.sh"
DOWNLOADER = ROOT / "luci-app-myupdate/root/usr/libexec/myupdate/github-download-asset.sh"


class DownloadProgressContractTests(unittest.TestCase):
    def test_download_task_passes_manifest_size_to_asset_downloader(self):
        source = TASK.read_text(encoding="utf-8")
        self.assertIn('"$R/firmware.bin" "$SIZE"', source)
        self.assertIn("write_status verifying", source)

    def test_downloader_publishes_atomic_byte_based_progress(self):
        source = DOWNLOADER.read_text(encoding="utf-8")
        self.assertIn('DOWNLOADED="$(wc -c < "$T/file"', source)
        self.assertIn('"percent":%s,"downloaded_bytes":%s,"total_bytes":%s', source)
        self.assertIn('mv "$PROGRESS_TMP" /tmp/myupdate/progress.json', source)
        self.assertIn('printf \'%s\\n\' "$RESULT" > "$T/finished"', source)

    def test_rpc_exposes_progress_and_luci_renders_it(self):
        rpc = RPC.read_text(encoding="utf-8")
        view = VIEW.read_text(encoding="utf-8")
        self.assertIn("status.download_percent = progress.percent", rpc)
        self.assertIn("progressFill.style.width = percent + '%'", view)
        self.assertIn("formatBytes(s.downloaded_bytes)", view)
        self.assertIn("E('h3', _('检测状态'))", view)
        self.assertIn("state-error", view)
        self.assertIn("识别并转换", view)


if __name__ == "__main__":
    unittest.main()

#!/usr/bin/env python3
"""Contract tests for live MyUpdate firmware download progress."""
import io
import json
from pathlib import Path
import sys
import tarfile
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "scripts"))
from validate_minisign_archive import validate_archive


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
        self.assertIn("E('h3', _('更新状态'))", view)
        self.assertIn("myupdate-status-overview", view)
        self.assertIn("myupdate-settings-heading", view)
        self.assertIn("myupdate-actions-final", view)
        self.assertIn("state-error", view)
        self.assertIn("识别并转换", view)


    def test_check_pipeline_reports_stages_and_fetches_manifests_in_parallel(self):
        source = TASK.read_text(encoding="utf-8")
        self.assertIn("Release 已获取，正在并行下载 Manifest 和签名", source)
        self.assertIn("正在验证签名和设备兼容性", source)
        self.assertIn('"$R/manifest.json" &', source)
        self.assertIn('"$R/manifest.minisig" &', source)
        self.assertIn('wait "$MANIFEST_PID"', source)
        self.assertIn('wait "$SIGNATURE_PID"', source)
        self.assertIn("verify-manifest.sh", source)

    def test_metadata_timeouts_are_bounded_without_shortening_firmware_download(self):
        api = (ROOT / "luci-app-myupdate/root/usr/libexec/myupdate/github-api.sh").read_text(encoding="utf-8")
        downloader = (ROOT / "luci-app-myupdate/root/usr/libexec/myupdate/github-download-asset.sh").read_text(encoding="utf-8")
        self.assertIn("--connect-timeout 10 --max-time 35", api)
        self.assertIn("--connect-timeout 10 --max-time 60", downloader)
        self.assertIn("--connect-timeout 10 --max-time 1800", downloader)

    def test_luci_uses_embedded_auto_dismissing_notices(self):
        source = VIEW.read_text(encoding="utf-8")
        self.assertIn("myupdate-inline-notice", source)
        self.assertIn("}, 3000);", source)
        self.assertIn("reportTaskStart(callCheck(), _('检查任务启动失败'), notify)", source)
        self.assertIn("reportTaskStart(callDownload(), _('下载并验证任务启动失败'), notify)", source)
        self.assertIn("reportTaskStart(callUpgrade(), _('升级任务启动失败，请先下载并验证固件'), notify)", source)
        self.assertNotIn("ui.addNotification", source)

    def test_filesystem_browser_is_server_side_and_filters_symlinks_and_virtual_paths(self):
        rpc = RPC.read_text(encoding="utf-8")
        self.assertIn("list_keep_paths: { args: { path: 'String' }", rpc)
        self.assertIn("fs.lsdir(path)", rpc)
        self.assertIn("fs.lstat(child)", rpc)
        self.assertIn("fs.realpath(child) == child", rpc)
        self.assertIn("blocked_keep_path(child)", rpc)
        self.assertIn("info.type != 'directory' && info.type != 'file'", rpc)

    def test_keep_paths_must_exist_and_must_not_resolve_through_symlinks(self):
        rpc = RPC.read_text(encoding="utf-8")
        backup = (ROOT / "luci-app-myupdate/root/usr/libexec/myupdate/prepare-sysupgrade-backup.sh").read_text(encoding="utf-8")
        self.assertIn("info.type != 'file' && info.type != 'directory'", rpc)
        self.assertIn("resolved != path", rpc)
        self.assertIn('[ -L "$path" ]', backup)
        self.assertIn('readlink -f "$path"', backup)
        self.assertIn('Refusing special custom sysupgrade path', backup)

    def test_downgrade_is_a_persisted_checkbox_next_to_upgrade_action(self):
        rpc = RPC.read_text(encoding="utf-8")
        view = VIEW.read_text(encoding="utf-8")
        self.assertIn("args.allow_downgrade != '0' && args.allow_downgrade != '1'", rpc)
        self.assertIn("method: 'set_allow_downgrade'", view)
        self.assertIn("'type': 'checkbox'", view)
        self.assertIn("downgradeLabel", view)
        self.assertNotIn("form.ListValue, 'allow_downgrade'", view)

    def test_keep_path_input_is_two_rows_and_uses_filesystem_browser(self):
        view = VIEW.read_text(encoding="utf-8")
        self.assertIn("'rows': '2'", view)
        self.assertIn("loadDirectory('/')", view)
        self.assertIn("myupdate-browser-entry", view)
        self.assertIn("myupdate-browser-add", view)
        self.assertNotIn("从常用固件目录中选择", view)
        self.assertNotIn("/.uuplugin_uuid", view)


    def test_downgrade_has_a_dedicated_persisted_rpc_and_safe_default(self):
        rpc = RPC.read_text(encoding="utf-8")
        view = VIEW.read_text(encoding="utf-8")
        acl = (ROOT / "luci-app-myupdate/root/usr/share/rpcd/acl.d/luci-app-myupdate.json").read_text(encoding="utf-8")
        self.assertIn("out.allow_downgrade = c.get(CONFIG, 'main', 'allow_downgrade') ?? '0';", rpc)
        self.assertIn("function set_allow_downgrade(args)", rpc)
        self.assertIn("c.commit(CONFIG) !== true", rpc)
        self.assertIn("let verify = cursor();", rpc)
        self.assertIn("String(saved) != value", rpc)
        self.assertIn("verify.load(CONFIG)", rpc)
        self.assertIn("method: 'set_allow_downgrade'", view)
        self.assertIn("return callConfig();", view)
        self.assertIn("降级设置回读不一致", view)
        self.assertIn('"set_allow_downgrade"', acl)
        self.assertIn("'checked': (cfg.allow_downgrade || '0') == '1'", view)
        self.assertIn("myupdate-downgrade-row", view)

    def test_luci_compacts_key_and_keep_path_controls_without_inserting_newlines(self):
        view = VIEW.read_text(encoding="utf-8")
        self.assertIn("replace(/\\r?\\n$/, '')", view)
        self.assertIn("keyInput.addEventListener('blur'", view)
        self.assertIn("max-width:560px", view)
        self.assertIn("overflow-wrap:anywhere", view)
        self.assertIn("max-width:680px", view)
        self.assertIn("function onOutsideBrowserClick(ev)", view)
        self.assertIn("document.addEventListener('click', onOutsideBrowserClick)", view)
        self.assertIn("document.removeEventListener('click', onOutsideBrowserClick)", view)

    def test_upgrade_action_follows_download_and_verify_in_same_primary_row(self):
        view = VIEW.read_text(encoding="utf-8")
        row = view.split("myupdate-actions-primary", 1)[1].split("myupdate-downgrade-row", 1)[0]
        self.assertLess(row.index("下载并验证"), row.index("执行升级"))


    def test_myupdate_hero_does_not_stick_over_scrolled_page_content(self):
        view = VIEW.read_text(encoding="utf-8")
        self.assertIn("E('div', { 'class': 'myupdate-hero' }", view)
        self.assertIn(".myupdate-hero{position:static!important", view)
        self.assertNotIn("#header,#mainmenu,.navbar,.mainmenu{position:relative;z-index:10000}", view)
        self.assertNotIn(".dropdown-menu{z-index:10001}", view)


    def test_allow_downgrade_defaults_to_disabled_in_shipped_uci_and_rpc(self):
        config = (ROOT / "luci-app-myupdate/root/etc/config/myupdate").read_text(encoding="utf-8")
        rpc = RPC.read_text(encoding="utf-8")
        self.assertIn("option allow_downgrade '0'", config)
        self.assertIn("out.allow_downgrade = c.get(CONFIG, 'main', 'allow_downgrade') ?? '0';", rpc)

    def test_partition_layout_is_checked_before_download_and_again_before_upgrade(self):
        task = TASK.read_text(encoding="utf-8")
        verifier = (ROOT / "luci-app-myupdate/root/usr/libexec/myupdate/verify-manifest.sh").read_text(encoding="utf-8")
        checker = (ROOT / "luci-app-myupdate/root/usr/libexec/myupdate/check-partition-layout.sh").read_text(encoding="utf-8")
        self.assertIn("KERNEL_PARTSIZE=\"$(sed -n '6p' \"$R/verified-manifest.txt\")\"", task)
        self.assertGreaterEqual(task.count('check-partition-layout.sh "$KERNEL_PARTSIZE" "$ROOTFS_PARTSIZE"'), 2)
        self.assertIn("get '@.partition_layout.kernel_partsize_mib'", verifier)
        self.assertIn("get '@.partition_layout.rootfs_partsize_mib'", verifier)
        self.assertIn("get '@.partition_layout.uses_boot_part'", verifier)
        self.assertIn('[ "$KERNEL_SECTORS" -ge "$KERNEL_REQUIRED_SECTORS" ]', checker)
        self.assertIn('[ "$ROOTFS_SECTORS" -ge "$ROOTFS_REQUIRED_SECTORS" ]', checker)
        self.assertIn('awk \'$2 == "/rom"', checker)
        self.assertNotIn("\\\\${", checker)

    def test_build_records_upstream_defaults_and_effective_partition_sizes_with_source_commits(self):
        workflow = (ROOT / ".github/workflows/build.yml").read_text(encoding="utf-8")
        validator = (ROOT / "tests/ota/validate_release.py").read_text(encoding="utf-8")
        self.assertIn("上游源码默认为 64 MiB", workflow)
        self.assertIn("上游源码默认为 448 MiB", workflow)
        self.assertIn("id: partition_defaults", workflow)
        self.assertIn('"boot-part" in features.group(1).split()', workflow)
        self.assertIn("'partition_layout': {", workflow)
        self.assertIn("'partition_layout': meta['partition_layout']", workflow)
        self.assertIn("'schema_version': 2", workflow)
        self.assertIn('manifest.get("schema_version") != 2', validator)
        self.assertIn('"uses_boot_part") is not True', validator)


    def test_release_notes_display_effective_partition_layout_from_manifest(self):
        workflow = (ROOT / ".github/workflows/build.yml").read_text(encoding="utf-8")
        self.assertIn("mapfile -t PARTITION_VALUES", workflow)
        self.assertIn("release-input/manifest.json", workflow)
        self.assertIn('layout.get("kernel_partsize_mib")', workflow)
        self.assertIn('layout.get("rootfs_partsize_mib")', workflow)
        self.assertIn("本次固件内核分区大小：${KERNEL_PARTSIZE} MiB", workflow)
        self.assertIn("本次固件根文件系统分区大小：${ROOTFS_PARTSIZE} MiB", workflow)
        self.assertIn("UPSTREAM_KERNEL_PARTSIZE", workflow)
        self.assertIn("UPSTREAM_ROOTFS_PARTSIZE", workflow)

    def test_build_uses_last_successful_partition_values_for_auto_and_manual_runs(self):
        workflow = (ROOT / ".github/workflows/build.yml").read_text(encoding="utf-8")
        state = json.loads((ROOT / "build-config/last-successful-partition-layout.json").read_text(encoding="utf-8"))
        self.assertEqual(state["kernel_partsize_mib"], 256)
        self.assertEqual(state["rootfs_partsize_mib"], 4096)
        self.assertIn("steps.last_partition_defaults.outputs.kernel_partsize", workflow)
        self.assertIn("needs.source_check.outputs.last_kernel_partsize", workflow)
        self.assertIn("needs.source_check.outputs.last_rootfs_partsize", workflow)
        self.assertIn("scripts/update-build-partition-defaults.py", workflow)
        self.assertIn('git push origin "HEAD:${GITHUB_REF}"', workflow)
        self.assertIn("contents: write", workflow)
        self.assertIn("上游源码默认为 64 MiB", workflow)
        self.assertIn("上游源码默认为 448 MiB", workflow)

    def test_generated_partition_state_commit_does_not_invalidate_build_fingerprint(self):
        workflow = (ROOT / ".github/workflows/build.yml").read_text(encoding="utf-8")
        self.assertIn("fetch-depth: 0", workflow)
        self.assertIn("ci(build): remember last successful firmware partition layout", workflow)
        self.assertIn("MYLEDE_BUILD_COMMIT", workflow)


    def test_minisign_release_discovery_uses_git_not_github_rest_api(self):
        workflow = (ROOT / ".github/workflows/build.yml").read_text(encoding="utf-8")
        self.assertIn('git -C "$MINISIGN_REPO" ls-remote --tags --refs origin', workflow)
        self.assertIn('MINISIGN_TAGS="$RUNNER_TEMP/minisign-tags.txt"', workflow)
        self.assertIn('No stable numeric minisign version tags were found via Git.', workflow)
        self.assertNotIn("api.github.com/repos/jedisct1/minisign/releases/latest", workflow)
        self.assertNotIn("MINISIGN_RELEASE_API", workflow)

    def test_minisign_repository_is_initialized_and_origin_added_only_once(self):
        workflow = (ROOT / ".github/workflows/build.yml").read_text(encoding="utf-8")
        self.assertEqual(workflow.count('git init "$MINISIGN_REPO"'), 1)
        self.assertEqual(workflow.count('git -C "$MINISIGN_REPO" remote add origin https://github.com/jedisct1/minisign.git'), 1)
        self.assertIn('git -C "$MINISIGN_REPO" fetch --no-tags --depth=1 origin "refs/tags/${MINISIGN_VERSION}"', workflow)

    def test_minisign_archive_validator_accepts_git_archive_root_directory_entry(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            archive = Path(temp_dir) / "minisign-0.12.tar.gz"
            with tarfile.open(archive, "w:gz") as tar:
                root = tarfile.TarInfo("minisign-0.12")
                root.type = tarfile.DIRTYPE
                tar.addfile(root)
                payload = b"fixture\\n"
                child = tarfile.TarInfo("minisign-0.12/README.md")
                child.size = len(payload)
                tar.addfile(child, io.BytesIO(payload))
            names = validate_archive(str(archive), "0.12")
            self.assertEqual(names[0], "minisign-0.12")
            self.assertIn("minisign-0.12/README.md", names)

    def test_minisign_archive_validator_rejects_entries_outside_release_root(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            archive = Path(temp_dir) / "invalid.tar.gz"
            with tarfile.open(archive, "w:gz") as tar:
                payload = b"unexpected\\n"
                entry = tarfile.TarInfo("other/README.md")
                entry.size = len(payload)
                tar.addfile(entry, io.BytesIO(payload))
            with self.assertRaises(ValueError):
                validate_archive(str(archive), "0.12")

    def test_minisign_archive_is_built_from_git_and_reused_by_firmware_job(self):
        workflow = (ROOT / ".github/workflows/build.yml").read_text(encoding="utf-8")
        self.assertIn('git -C "$MINISIGN_REPO" fetch --no-tags --depth=1 origin "refs/tags/${MINISIGN_VERSION}"', workflow)
        self.assertIn('git -C "$MINISIGN_REPO" archive --format=tar.gz', workflow)
        self.assertNotIn("codeload.github.com/jedisct1/minisign/tar.gz", workflow)
        self.assertNotIn("github.com/jedisct1/minisign/archive/refs/tags/", workflow)
        self.assertIn('source-lock-artifact/source-revisions.tsv', workflow)
        self.assertIn('shutil.copyfile(archive, artifact_dir / archive.name)', workflow)
        self.assertIn('hashlib.sha256(archive.read_bytes()).hexdigest()', workflow)
        self.assertIn('target = download_dir / archive.name', workflow)
        self.assertIn('shutil.copyfile(archive, target)', workflow)
        self.assertLess(workflow.index('path: /home/ubuntu/dl'), workflow.index('已安装并校验预检阶段锁定的 minisign 源码归档'))
        validator = (ROOT / "scripts/validate_minisign_archive.py").read_text(encoding="utf-8")
        self.assertIn(
            'python3 scripts/validate_minisign_archive.py "$MINISIGN_ARCHIVE" "$MINISIGN_VERSION"',
            workflow,
        )
        self.assertIn('tarfile.open(archive, "r:gz")', validator)

    def test_source_lock_validates_git_commits_and_minisign_archive_digest_separately(self):
        workflow = (ROOT / ".github/workflows/build.yml").read_text(encoding="utf-8")
        self.assertIn('expected_length = 64 if name == "MINISIGN_RELEASE" else 40', workflow)
        self.assertIn('rf"[0-9a-f]{{{expected_length}}}"', workflow)
        self.assertIn('kind = "SHA-256 digest" if name == "MINISIGN_RELEASE" else "Git commit SHA"', workflow)

    def test_build_reads_pinned_feeds_config_from_git_not_raw_cdn(self):
        workflow = (ROOT / ".github/workflows/build.yml").read_text(encoding="utf-8")
        self.assertIn('fetch --no-tags --depth=1 origin "$LEDE_COMMIT"', workflow)
        self.assertIn('git -C "$LEDE_PREFLIGHT_REPO" show FETCH_HEAD:feeds.conf.default', workflow)
        self.assertNotIn('https://raw.githubusercontent.com/coolsnowwolf/lede/', workflow)
        self.assertIn("LEDE_PREFLIGHT_REPO", workflow)


if __name__ == "__main__":
    unittest.main()

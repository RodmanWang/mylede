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
        self.assertIn("c.set(CONFIG, 'main', 'custom_keep_paths', paths)", source)
        self.assertIn("c.delete(CONFIG, 'main', 'custom_keep_paths')", source)
        self.assertIn("let saved = type(raw) == 'array' ? raw : [];", source)

    def test_luci_uses_custom_dynamic_list_and_filesystem_browser(self):
        source = VIEW.read_text(encoding="utf-8")
        self.assertIn("s.option(form.DynamicList, 'custom_keep_paths'", source)
        self.assertIn("keepPaths.formvalue = function() { return keepPathValues.slice(); };", source)
        self.assertIn("keepPaths.renderWidget = function(section_id)", source)
        self.assertIn("keepPaths.write = function() { return Promise.resolve(); };", source)
        self.assertIn("persistKeepPaths(paths, successMessage)", source)
        self.assertIn("method: 'save_keep_paths'", source)
        self.assertIn("callSaveKeepPaths(paths.join", source)
        self.assertIn("remove.addEventListener('click', function(ev)", source)
        self.assertIn("'class': 'btn cbi-button myupdate-path-chip-remove'", source)
        self.assertIn("keepPathValues.indexOf(path) < 0", source)
        self.assertIn("var next = keepPathValues.filter(function(item) { return item != path; });", source)
        self.assertNotIn("chips.addEventListener('click'", source)
        self.assertNotIn("ev.target.closest('.myupdate-path-chip-remove')", source)
        self.assertIn("ev.stopPropagation()", source)
        self.assertIn("persistKeepPaths(next, _('已删除路径，配置已保存。'))", source)
        self.assertIn(": c.delete(CONFIG, 'main', 'custom_keep_paths')", (BACKEND).read_text(encoding="utf-8"))
        self.assertIn("persistKeepPaths(next, _('已添加并保存 ')", source)
        self.assertIn("loadDirectory('/')", source)
        self.assertIn("myupdate-browser-entry", source)
        self.assertIn("myupdate-browser-add", source)
        self.assertIn("'disabled': keepPathSaving", source)
        self.assertIn("'rows': '2'", source)
        self.assertNotIn("从常用固件目录中选择", source)
        self.assertNotIn("/.uuplugin_uuid", source)
        self.assertNotIn("E('header', { 'class': 'myupdate-hero' }", source)
        self.assertNotIn("#header,#mainmenu,.navbar,.mainmenu{position:relative", source)
        self.assertIn("myupdate-hero{position:static!important", source)

    def test_browser_rpc_is_exposed_read_only_to_luci(self):
        source = BACKEND.read_text(encoding="utf-8")
        acl = (ROOT / "luci-app-myupdate/root/usr/share/rpcd/acl.d/luci-app-myupdate.json").read_text(encoding="utf-8")
        self.assertIn("list_keep_paths: { args: { path: 'String' }", source)
        self.assertIn('"get_status", "get_config", "list_keep_paths"', acl)
        self.assertIn("fs.lsdir(path)", source)
        self.assertIn("fs.lstat(child)", source)
        self.assertIn("fs.realpath(child) == child", source)
        self.assertIn("blocked_keep_path(child)", source)
        self.assertIn("info.type != 'directory' && info.type != 'file'", source)

    def test_keep_paths_are_server_validated_and_symlink_safe(self):
        source = BACKEND.read_text(encoding="utf-8")
        backup = BACKUP.read_text(encoding="utf-8")
        acl = (ROOT / "luci-app-myupdate/root/usr/share/rpcd/acl.d/luci-app-myupdate.json").read_text(encoding="utf-8")
        self.assertIn("info.type != 'file' && info.type != 'directory'", source)
        self.assertIn("resolved != path", source)
        self.assertIn("function safe_missing_keep_path(path)", source)
        self.assertIn("function save_keep_paths(args)", source)
        save_body = source.split("function save_keep_paths(args)", 1)[1].split("function set_token", 1)[0]
        self.assertLess(save_body.index("let c = cursor();"), save_body.index("current_keep_path_set(c)"))
        self.assertLess(save_body.index("c.load(CONFIG)"), save_body.index("current_keep_path_set(c)"))
        self.assertIn("function current_keep_path_set(c)", source)
        self.assertIn("if (!(path in existing))", source)
        self.assertIn("verify.load(CONFIG)", source)
        self.assertIn('"save_keep_paths"', acl)
        self.assertIn("if (info == null)", source)
        self.assertIn('if [ -L "$path" ]; then', backup)
        self.assertIn('readlink -f "$path"', backup)
        self.assertIn('Refusing special custom sysupgrade path', backup)


    def test_sysupgrade_backup_reader_handles_space_separated_uci_lists(self):
        source = BACKUP.read_text(encoding="utf-8")
        self.assertIn("uci -q get myupdate.main.custom_keep_paths", source)
        self.assertIn("tr ' ' '\\n'", source)


if __name__ == "__main__":
    unittest.main()

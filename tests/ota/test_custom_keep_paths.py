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
        self.assertIn("c.set(CONFIG, 'main', 'custom_keep_paths', length(paths) ? paths : '')", source)

    def test_luci_uses_custom_dynamic_list_and_filesystem_browser(self):
        source = VIEW.read_text(encoding="utf-8")
        self.assertIn("s.option(form.DynamicList, 'custom_keep_paths'", source)
        self.assertIn("var initialKeepPathValues = (cfg.custom_keep_paths || []).slice();", source)
        self.assertIn("var keepPathValues = initialKeepPathValues.slice();", source)
        self.assertIn("keepPaths.cfgvalue = function() { return initialKeepPathValues.slice(); };", source)
        self.assertIn("keepPaths.formvalue = function() { return keepPathValues.slice(); };", source)
        self.assertNotIn("keepPaths.cfgvalue = function() { return keepPathValues.slice(); };", source)
        self.assertIn("keepPaths.renderWidget = function(section_id)", source)
        self.assertNotIn("keepPaths.write =", source)
        self.assertIn("function stageKeepPaths(paths, successMessage)", source)
        self.assertIn("stageKeepPaths(next", source)
        self.assertNotIn("callSaveKeepPaths", source)
        self.assertIn("s.option(form.Flag, 'allow_downgrade'", source)
        self.assertNotIn("callSaveDowngrade", source)
        self.assertIn("chips.addEventListener('click', function(ev)", source)
        self.assertIn("}, true);", source)
        self.assertIn("'data-keep-path': path", source)
        self.assertIn("chip.querySelector('.myupdate-path-chip-remove')", source)
        self.assertNotIn("getBoundingClientRect()", source)
        self.assertNotIn("ev.clientX", source)
        self.assertIn("myupdate-path-chip:hover,.myupdate-path-chip:focus-within", source)
        self.assertIn("z-index:2", source)
        self.assertIn("width:18px;height:18px;min-width:18px", source)
        self.assertIn("min-height:18px;max-height:18px", source)
        self.assertIn("'class': 'btn cbi-button myupdate-path-chip-remove'", source)
        self.assertIn("keepPathValues.indexOf(path) < 0", source)
        self.assertIn("var next = keepPathValues.filter(function(item) { return item != path; });", source)
        self.assertNotIn("ev.target.closest('.myupdate-path-chip-remove')", source)
        self.assertIn("ev.stopPropagation()", source)
        self.assertIn("stageKeepPaths(next, _('已删除路径；点击“保存并应用”后生效。'))", source)
        self.assertIn("已暂存新增 ", source)
        self.assertIn("loadDirectory('/')", source)
        self.assertIn("myupdate-browser-entry", source)
        self.assertIn("myupdate-browser-add", source)
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
        self.assertIn("function save_config(args)", source)
        self.assertIn("if ('custom_keep_paths' in args)", source)
        self.assertIn("allow_downgrade: 1", source)
        self.assertNotIn("function save_keep_paths(args)", source)
        self.assertNotIn("function set_allow_downgrade(args)", source)
        self.assertIn("function current_keep_path_set(c)", source)
        self.assertIn("if (!(path in existing))", source)
        self.assertNotIn('"save_keep_paths"', acl)
        self.assertNotIn('"set_allow_downgrade"', acl)
        self.assertIn("if (info == null)", source)
        self.assertIn('if [ -L "$path" ]; then', backup)
        self.assertIn('readlink -f "$path"', backup)
        self.assertIn('Refusing special custom sysupgrade path', backup)


    def test_luci_standard_form_has_uci_read_and_write_permissions(self):
        acl = (ROOT / "luci-app-myupdate/root/usr/share/rpcd/acl.d/luci-app-myupdate.json").read_text(encoding="utf-8")
        import json
        permissions = json.loads(acl)["luci-app-myupdate"]
        self.assertIn("myupdate", permissions["read"]["uci"])
        self.assertIn("myupdate", permissions["write"]["uci"])

    def test_sysupgrade_backup_reader_handles_space_separated_uci_lists(self):
        source = BACKUP.read_text(encoding="utf-8")
        self.assertIn("uci -q get myupdate.main.custom_keep_paths", source)
        self.assertIn("tr ' ' '\\n'", source)


if __name__ == "__main__":
    unittest.main()

'use strict';

import * as fs from 'fs';
import * as uci from 'uci';

const CONFIG = 'myupdate';
const TOKEN = '/etc/myupdate/token';
const STATUS = '/tmp/myupdate/status.json';
const TASK = '/usr/libexec/myupdate/task.sh';

function cursor() { return uci.cursor(); }
function read_status() {
	let raw = fs.readfile(STATUS);
	if (raw == null || raw == '') return {
		state: 'idle', message: '尚未检查更新', current_version: '', latest_version: '',
		update_available: false, image_ready: false, image_verified: false, busy: false, updated_at: ''
	};
	try { return json(raw); }
	catch (e) { return { state: 'error', message: '状态文件无法解析', busy: false }; }
}
function get_config() {
	let c = cursor(), out = {};
	for (let key in [ 'repo_url', 'repo_owner', 'repo_name', 'repo_visibility', 'release_channel', 'upgrade_mode',
		'check_interval', 'auto_upgrade_time', 'minisign_public_key', 'allow_downgrade', 'custom_keep_paths' ])
		out[key] = c.get(CONFIG, 'main', key) ?? '';
	if (!out.repo_url && out.repo_owner && out.repo_name)
		out.repo_url = 'https://github.com/' + out.repo_owner + '/' + out.repo_name;
	out.token_configured = !!trim(fs.readfile(TOKEN) || '');
	return out;
}
function valid_string(v, max) {
	return type(v) == 'string' && length(v) <= max && index(v, '\n') < 0 && index(v, '\r') < 0;
}
function valid_keep_paths(value) {
	if (type(value) != 'string' || length(value) > 8192 || index(value, '\r') >= 0)
		return false;
	let seen = {};
	for (let path in split(value, '\n')) {
		if (path == '') continue;
		if (!match(path, /^\/[A-Za-z0-9._/@+-]+$/) || path == '/' ||
		    match(path, /(^|\/)\.\.?($|\/)/))
			return false;
		for (let prefix in [ '/proc', '/sys', '/dev', '/tmp', '/rom', '/overlay' ])
			if (path == prefix || substr(path, 0, length(prefix) + 1) == prefix + '/')
				return false;
		if (seen[path]) return false;
		seen[path] = true;
	}
	return true;
}
function save_config(args) {
	let allowed = { repo_owner: 100, repo_name: 100, repo_visibility: 10, release_channel: 10,
		upgrade_mode: 10, check_interval: 6, auto_upgrade_time: 5, minisign_public_key: 256, allow_downgrade: 1 };
	let c = cursor();
	for (let key, max in allowed) {
		if (!(key in args)) continue;
		let value = args[key];
		if (!valid_string(value, max)) return { ok: false, error: '配置字段格式错误：' + key };
		c.set(CONFIG, 'main', key, value);
	}
	if ('custom_keep_paths' in args) {
		if (!valid_keep_paths(args.custom_keep_paths))
			return { ok: false, error: '自定义保留路径格式无效：请使用绝对路径，每行一条，不要填写根目录或虚拟文件系统路径' };
		c.set(CONFIG, 'main', 'custom_keep_paths', args.custom_keep_paths);
	}
	let visibility = args.repo_visibility ?? c.get(CONFIG, 'main', 'repo_visibility');
	let channel = args.release_channel ?? c.get(CONFIG, 'main', 'release_channel');
	let mode = args.upgrade_mode ?? c.get(CONFIG, 'main', 'upgrade_mode');
	let interval = int(args.check_interval ?? c.get(CONFIG, 'main', 'check_interval'));
	let auto_time = args.auto_upgrade_time ?? c.get(CONFIG, 'main', 'auto_upgrade_time') ?? '04:00';
	if (![ 'public', 'private' ].includes(visibility)) return { ok: false, error: '仓库可见性无效' };
	if (channel != 'stable') return { ok: false, error: '更新通道无效' };
	if (!valid_string(auto_time, 5) || !match(auto_time, /^([01][0-9]|2[0-3]):[0-5][0-9]$/))
		return { ok: false, error: '自动升级时间必须为 HH:MM（24 小时制）' };
	c.set(CONFIG, 'main', 'auto_upgrade_time', auto_time);
	if (![ 'manual', 'notify', 'auto' ].includes(mode)) return { ok: false, error: '检查模式无效' };
	if (isNaN(interval) || interval < 900 || interval > 604800) return { ok: false, error: '检查间隔必须为 900 至 604800 秒' };
	if (c.commit(CONFIG) !== true) {
		let reason = uci.error() || '未知 UCI 错误';
		return { ok: false, error: '保存配置失败：' + reason };
	}
	return { ok: true };
}
function set_token(args) {
	let token = args.token;
	if (!valid_string(token, 512) || !/^(github_pat_[A-Za-z0-9_]+|gh[pousr]_[A-Za-z0-9]+)$/.test(token))
		return { ok: false, error: 'Token 格式无效' };
	fs.mkdir('/etc/myupdate', 0o700);
	if (fs.writefile(TOKEN, token + '\n') == null) return { ok: false, error: '无法写入 Token' };
	fs.chmod(TOKEN, 0o600);
	return { ok: true };
}
function start_task(action) {
	if (![ 'check', 'download', 'upgrade' ].includes(action))
		return { ok: false, error: '操作无效' };

	try {
		let command = TASK + ' ' + action + ' >/dev/null 2>&1 &';
		let p = fs.popen(command, 'r');

		if (p == null)
			return { ok: false, error: '无法创建任务进程：' + (fs.error() || '未知进程错误') };

		let rc = p.close();
		if (rc == null)
			return { ok: false, error: '无法确认任务启动状态：' + (fs.error() || '进程句柄关闭失败') };

		return { ok: true };
	}
	catch (e) {
		return { ok: false, error: '启动任务时发生 Ucode 异常：' + e };
	}
}
return { myupdate: {
	get_status: { call: function() { return read_status(); } },
	get_config: { call: function() { return get_config(); } },
	save_config: { args: { repo_owner: 'String', repo_name: 'String', repo_visibility: 'String', release_channel: 'String',
		upgrade_mode: 'String', check_interval: 'String', auto_upgrade_time: 'String', minisign_public_key: 'String', allow_downgrade: 'String',
		custom_keep_paths: 'String' },
		call: function(request) { return save_config(request.args); } },
	set_token: { args: { token: 'String' }, call: function(request) { return set_token(request.args); } },
	start_check: { call: function() { return start_task('check'); } },
	start_download: { call: function() { return start_task('download'); } },
	start_upgrade: { call: function() { return start_task('upgrade'); } }
} };

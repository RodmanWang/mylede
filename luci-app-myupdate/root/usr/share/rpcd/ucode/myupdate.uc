'use strict';

import * as fs from 'fs';
import * as uci from 'uci';

const CONFIG = 'myupdate';
const TOKEN = '/etc/myupdate/token';
const STATUS = '/tmp/myupdate/status.json';
const RUNTIME = '/tmp/myupdate';
const REQUEST = RUNTIME + '/request';
const LOCK = RUNTIME + '/task.lock';

function cursor() { return uci.cursor(); }
function read_status() {
	let raw = fs.readfile(STATUS);
	if (raw == null || raw == '') return {
		state: 'idle', message: '尚未检查更新', current_version: '', latest_version: '',
		update_available: false, image_ready: false, image_verified: false, busy: false, updated_at: ''
	};
	try {
		let status = json(raw);
		let progress_raw = fs.readfile(RUNTIME + '/progress.json');
		if (progress_raw != null && progress_raw != '') {
			try {
				let progress = json(progress_raw);
				status.download_percent = progress.percent ?? 0;
				status.downloaded_bytes = progress.downloaded_bytes ?? 0;
				status.total_bytes = progress.total_bytes ?? 0;
			} catch (e) {}
		}
		return status;
	}
	catch (e) { return { state: 'error', message: '状态文件无法解析', busy: false }; }
}
function get_config() {
	let c = cursor(), out = {};
	for (let key in [ 'repo_url', 'repo_owner', 'repo_name', 'repo_visibility', 'release_channel', 'upgrade_mode',
		'check_interval', 'auto_upgrade_time', 'minisign_public_key', 'allow_downgrade' ])
		out[key] = c.get(CONFIG, 'main', key) ?? '';
	out.allow_downgrade = c.get(CONFIG, 'main', 'allow_downgrade') ?? '0';

	// Return UCI lists as an array for LuCI DynamicList. Convert the legacy
	// newline-delimited scalar to the same shape so existing settings migrate
	// naturally when the user next saves the form.
	let keep_paths = c.get(CONFIG, 'main', 'custom_keep_paths');
	out.custom_keep_paths = [];
	if (type(keep_paths) == 'array')
		out.custom_keep_paths = keep_paths;
	else if (type(keep_paths) == 'string')
		for (let path in split(keep_paths, '\n'))
			if (path != '') out.custom_keep_paths[length(out.custom_keep_paths)] = path;

	if (!out.repo_url && out.repo_owner && out.repo_name)
		out.repo_url = 'https://github.com/' + out.repo_owner + '/' + out.repo_name;
	out.token_configured = !!trim(fs.readfile(TOKEN) || '');
	return out;
}
function valid_string(v, max) {
	return type(v) == 'string' && length(v) <= max && index(v, '\n') < 0 && index(v, '\r') < 0;
}
function parse_keep_paths(value) {
	if (type(value) != 'string' || length(value) > 8192 || index(value, '\r') >= 0)
		return null;
	let paths = [], seen = {};
	for (let path in split(value, '\n')) {
		if (path == '') continue;
		if (!match(path, /^\/[A-Za-z0-9._/@+-]+$/) || path == '/' ||
		    match(path, /(^|\/)\.\.?($|\/)/))
			return null;
		for (let prefix in [ '/proc', '/sys', '/dev', '/tmp', '/rom', '/overlay' ])
			if (path == prefix || substr(path, 0, length(prefix) + 1) == prefix + '/')
				return null;
		let info = fs.lstat(path), resolved = fs.realpath(path);
		if (info == null || (info.type != 'file' && info.type != 'directory') || resolved != path) return null;
		if (seen[path]) return null;
		seen[path] = true;
		paths[length(paths)] = path;
	}
	return paths;
}
function blocked_keep_path(path) {
	for (let prefix in [ '/proc', '/sys', '/dev', '/tmp', '/rom', '/overlay' ])
		if (path == prefix || substr(path, 0, length(prefix) + 1) == prefix + '/') return true;
	return false;
}
function valid_browser_directory(path) {
	if (type(path) != 'string' || length(path) > 512 || substr(path, 0, 1) != '/' ||
	    index(path, '\n') >= 0 || index(path, '\r') >= 0 || index(path, '\\') >= 0 ||
	    index(path, '\t') >= 0 || index(path, '\0') >= 0 || blocked_keep_path(path))
		return false;
	if (path != '/') {
		if (substr(path, 1, 1) == '/' || substr(path, length(path) - 1, 1) == '/')
			return false;
		let first = true;
		for (let part in split(path, '/')) {
			if (first) { first = false; continue; }
			if (part == '' || part == '.' || part == '..') return false;
		}
	}
	let resolved = fs.realpath(path), info = fs.lstat(path);
	return resolved == path && info != null && info.type == 'directory';
}
function list_keep_paths(path) {
	if (!valid_browser_directory(path)) return { ok: false, error: '目录不存在、不可访问或包含不允许的路径组件' };
	let names = fs.lsdir(path);
	if (names == null) return { ok: false, error: '无法读取目录：' + (fs.error() || '权限不足或目录不可访问') };
	let entries = [], truncated = length(names) > 300;
	for (let name in names) {
		if (length(entries) >= 300) break;
		if (name == '.' || name == '..' || index(name, '/') >= 0 || index(name, '\n') >= 0 || index(name, '\r') >= 0)
			continue;
		let child = path == '/' ? '/' + name : path + '/' + name;
		let info = fs.lstat(child);
		if (info == null || (info.type != 'directory' && info.type != 'file' && info.type != 'symlink')) continue;
		let canonical = fs.realpath(child) == child, blocked = blocked_keep_path(child);
		entries[length(entries)] = {
			name: name, path: child, type: info.type,
			can_open: info.type == 'directory' && canonical && !blocked,
			can_add: (info.type == 'directory' || info.type == 'file') && canonical && !blocked && match(child, /^\/[A-Za-z0-9._/@+-]+$/)
		};
	}
	return { ok: true, path: path, entries: entries, truncated: truncated };
}
function save_config(args) {
	let allowed = { repo_url: 200, repo_owner: 100, repo_name: 100, repo_visibility: 10, release_channel: 10,
		upgrade_mode: 10, check_interval: 6, auto_upgrade_time: 5, minisign_public_key: 256, allow_downgrade: 1 };
	let c = cursor();
	for (let key, max in allowed) {
		if (!(key in args)) continue;
		let value = args[key];
		if (!valid_string(value, max)) return { ok: false, error: '配置字段格式错误：' + key };
		c.set(CONFIG, 'main', key, value);
	}
	if ('allow_downgrade' in args && args.allow_downgrade != '0' && args.allow_downgrade != '1')
		return { ok: false, error: '允许降级设置无效，只能为 0 或 1' };
	if ('repo_url' in args && args.repo_url != '' &&
	    !match(args.repo_url, /^https:\/\/github[.]com\/[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+([.]git)?\/?$/))
		return { ok: false, error: 'GitHub 仓库地址无效，请填写 https://github.com/所有者/仓库名' };
	if ('custom_keep_paths' in args) {
		let paths = parse_keep_paths(args.custom_keep_paths);
		if (paths == null)
			return { ok: false, error: '自定义保留路径格式无效：请使用绝对路径，每行一条，不要填写根目录或虚拟文件系统路径' };
		// An array value is serialized by UCI as repeated `list` entries.
		// An empty string removes the option when the user clears the field.
		c.set(CONFIG, 'main', 'custom_keep_paths', length(paths) ? paths : '');
	}
	let visibility = args.repo_visibility ?? c.get(CONFIG, 'main', 'repo_visibility');
	let channel = args.release_channel ?? c.get(CONFIG, 'main', 'release_channel');
	let mode = args.upgrade_mode ?? c.get(CONFIG, 'main', 'upgrade_mode');
	let interval = int(args.check_interval ?? c.get(CONFIG, 'main', 'check_interval'));
	let auto_time = args.auto_upgrade_time ?? c.get(CONFIG, 'main', 'auto_upgrade_time') ?? '04:00';
	if (visibility != 'public' && visibility != 'private') return { ok: false, error: '仓库可见性无效' };
	if (channel != 'stable') return { ok: false, error: '更新通道无效' };
	if (!valid_string(auto_time, 5) || !match(auto_time, /^([01][0-9]|2[0-3]):[0-5][0-9]$/))
		return { ok: false, error: '自动升级时间必须为 HH:MM（24 小时制）' };
	c.set(CONFIG, 'main', 'auto_upgrade_time', auto_time);
	if (mode != 'manual' && mode != 'notify' && mode != 'auto') return { ok: false, error: '检查模式无效' };
	if (isNaN(interval) || interval < 900 || interval > 604800) return { ok: false, error: '检查间隔必须为 900 至 604800 秒' };
	if (c.commit(CONFIG) !== true) {
		let reason = uci.error() || '未知 UCI 错误';
		return { ok: false, error: '保存配置失败：' + reason };
	}
	return { ok: true };
}
function set_allow_downgrade(args) {
	let value = args.allow_downgrade;
	if (value != '0' && value != '1')
		return { ok: false, error: '允许降级设置无效，只能为 0 或 1' };
	let c = cursor();
	c.set(CONFIG, 'main', 'allow_downgrade', value);
	if (c.commit(CONFIG) !== true)
		return { ok: false, error: '保存降级设置失败：' + (uci.error() || '未知 UCI 错误') };
	let saved = c.get(CONFIG, 'main', 'allow_downgrade');
	if (saved != value)
		return { ok: false, error: '降级设置写入后回读不一致' };
	return { ok: true, allow_downgrade: saved };
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
function cleanup_task_request(temp_dir, action_file) {
	if (action_file != null) fs.unlink(action_file);
	if (temp_dir != null) fs.rmdir(temp_dir);
}
function start_task(action) {
	if (action != 'check' && action != 'download' && action != 'upgrade')
		return { ok: false, error: '操作无效' };

	let temp_dir = null, action_file = null, error = null;

	try {
		if (fs.access(RUNTIME) !== true &&
		    fs.mkdir(RUNTIME, 0o700) !== true &&
		    fs.access(RUNTIME) !== true)
			return { ok: false, error: '无法创建 MyUpdate 运行目录：' + (fs.error() || '未知文件系统错误') };

		if (fs.access(LOCK) === true)
			return { ok: false, error: '已有 MyUpdate 任务正在执行，请等待任务完成' };

		if (fs.access(REQUEST) === true)
			return { ok: false, error: '已有任务正在排队，请稍后查看升级状态' };

		// Publish a complete request by atomically renaming a private temporary
		// directory. The rpcd handler never forks or waits for a child process.
		temp_dir = fs.mkdtemp(RUNTIME + '/request.XXXXXX');
		if (temp_dir == null)
			return { ok: false, error: '无法创建任务请求：' + (fs.error() || '未知文件系统错误') };

		action_file = temp_dir + '/action';
		if (fs.writefile(action_file, action + '\n') == null)
			error = '无法写入任务请求：' + (fs.error() || '未知文件系统错误');
		else if (fs.chmod(action_file, 0o600) !== true)
			error = '无法设置任务请求权限：' + (fs.error() || '未知文件系统错误');
		else if (fs.rename(temp_dir, REQUEST) !== true)
			error = '任务队列已被占用或无法发布请求：' + (fs.error() || '未知文件系统错误');
		else {
			temp_dir = null;
			action_file = null;
			return { ok: true, queued: true, message: '任务请求已排队，后台服务将在数秒内执行' };
		}
	}
	catch (e) {
		error = '提交任务请求时发生 Ucode 异常：' + e;
	}

	cleanup_task_request(temp_dir, action_file);
	return { ok: false, error: error || '提交任务请求失败' };
}
return { myupdate: {
	get_status: { call: function() { return read_status(); } },
	get_config: { call: function() { return get_config(); } },
	set_allow_downgrade: { args: { allow_downgrade: 'String' }, call: function(request) { return set_allow_downgrade(request.args); } },
	list_keep_paths: { args: { path: 'String' }, call: function(request) { return list_keep_paths(request.args.path); } },
	save_config: { args: { repo_url: 'String', repo_owner: 'String', repo_name: 'String', repo_visibility: 'String', release_channel: 'String',
		upgrade_mode: 'String', check_interval: 'String', auto_upgrade_time: 'String', minisign_public_key: 'String', allow_downgrade: 'String',
		custom_keep_paths: 'String' },
		call: function(request) { return save_config(request.args); } },
	set_token: { args: { token: 'String' }, call: function(request) { return set_token(request.args); } },
	start_check: { call: function() { return start_task('check'); } },
	start_download: { call: function() { return start_task('download'); } },
	start_upgrade: { call: function() { return start_task('upgrade'); } }
} };

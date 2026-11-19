'use strict';
'require view';
'require rpc';
'require ui';
'require poll';

var callStatus = rpc.declare({ object: 'myupdate', method: 'get_status' });
var callConfig = rpc.declare({ object: 'myupdate', method: 'get_config' });
var callSave = rpc.declare({ object: 'myupdate', method: 'save_config', params: [ 'repo_owner', 'repo_name', 'repo_visibility', 'release_channel', 'upgrade_mode', 'check_interval', 'minisign_public_key', 'allow_downgrade' ] });
var callToken = rpc.declare({ object: 'myupdate', method: 'set_token', params: [ 'token' ] });
var callCheck = rpc.declare({ object: 'myupdate', method: 'start_check' });
var callDownload = rpc.declare({ object: 'myupdate', method: 'start_download' });
var callUpgrade = rpc.declare({ object: 'myupdate', method: 'start_upgrade' });

function field(id, value, type) {
	return E('input', { id: id, 'class': 'cbi-input-text', type: type || 'text', value: value == null ? '' : value });
}
function selectField(id, value, options) {
	var node = E('select', { id: id, 'class': 'cbi-input-select' });
	options.forEach(function(item) { node.appendChild(E('option', { value: item[0], selected: value === item[0] }, item[1])); });
	return node;
}
function row(title, control, description) {
	return E('div', { 'class': 'cbi-value' }, [ E('label', { 'class': 'cbi-value-title', 'for': control.id }, title),
		E('div', { 'class': 'cbi-value-field' }, [ control, description ? E('div', { 'class': 'cbi-value-description' }, description) : '' ]) ]);
}
function showStatus(node, s) {
	var current = s.current_version ? '当前版本：' + s.current_version : '';
	var latest = s.latest_version ? '；最新版本：' + s.latest_version : '';
	node.textContent = (s.message || '尚未检查更新') + (current ? '（' + current + latest + '）' : '');
}
return view.extend({
	load: function() { return Promise.all([ callConfig(), callStatus() ]); },
	render: function(data) {
		var cfg = data[0] || {}, status = data[1] || {};
		var owner = field('myupdate-owner', cfg.repo_owner), repo = field('myupdate-repo', cfg.repo_name);
		var visibility = selectField('myupdate-visibility', cfg.repo_visibility || 'public', [[ 'public', 'Public（公开）' ], [ 'private', 'Private（私有）' ]]);
		var channel = selectField('myupdate-channel', 'stable', [[ 'stable', 'Stable（正式版）' ]]);
		var mode = selectField('myupdate-mode', cfg.upgrade_mode || 'manual', [[ 'manual', '手动检查' ], [ 'notify', '定时检查，有更新时显示状态' ], [ 'auto', '定时检查（不会自动刷写）' ]]);
		var interval = field('myupdate-interval', cfg.check_interval || '21600', 'number');
		var pubkey = field('myupdate-pubkey', cfg.minisign_public_key);
		var downgrade = selectField('myupdate-downgrade', cfg.allow_downgrade || '0', [[ '0', '禁止' ], [ '1', '允许' ]]);
		var token = field('myupdate-token', '', 'password'); token.setAttribute('autocomplete', 'new-password');
		token.setAttribute('placeholder', cfg.token_configured ? '已配置；输入新 Token 可替换' : '仅 Private 仓库需要');
		var statusText = E('p', { id: 'myupdate-status' }); showStatus(statusText, status);
		var statusPanel = E('div', { 'class': 'cbi-section' }, [ E('h3', '升级状态'), statusText,
			E('p', '升级使用 LEDE sysupgrade 默认配置备份与恢复机制。只接受本项目生成的 x86_64 squashfs UEFI combined 镜像。'),
			E('button', { 'class': 'btn cbi-button cbi-button-action', click: function() { return callCheck().then(function(r) { if (!r || !r.ok) ui.addNotification(null, E('p', '检查任务启动失败'), 'error'); }); } }, '检查更新'), ' ',
			E('button', { 'class': 'btn cbi-button cbi-button-positive', click: function() { return callDownload().then(function(r) { if (!r || !r.ok) ui.addNotification(null, E('p', '下载任务启动失败'), 'error'); }); } }, '下载并验证'), ' ',
			E('button', { 'class': 'btn cbi-button cbi-button-negative', click: function() {
				if (!confirm('确定升级吗？设备将执行保留系统配置的升级并自动重启。建议提前备份重要配置，并确保有本地或带外访问方式。')) return;
				return callUpgrade().then(function(r) { if (!r || !r.ok) ui.addNotification(null, E('p', '升级任务启动失败，请先下载并验证固件'), 'error'); });
			} }, '执行升级')
		]);
		var configPanel = E('div', { 'class': 'cbi-section' }, [ E('h3', 'GitHub Release 设置'), row('仓库所有者', owner), row('仓库名称', repo),
			row('仓库可见性', visibility), row('更新通道', channel), row('检查模式', mode), row('自动检查间隔（秒）', interval),
			row('Minisign 公钥', pubkey, '必须填写与 GitHub Actions MINISIGN_SECRET_KEY 对应的公钥。'),
			row('允许降级', downgrade) ]);
		var tokenPanel = E('div', { 'class': 'cbi-section' }, [ E('h3', '访问令牌'),
			E('p', '私有仓库使用 Fine-grained PAT，并授予目标仓库 Contents: Read-only。公开仓库不需要 Token。'), row('GitHub Token', token),
			E('button', { 'class': 'btn cbi-button cbi-button-action', click: function() { if (!token.value) return;
				return callToken(token.value).then(function(r) { if (r && r.ok) { token.value = ''; ui.addNotification(null, E('p', 'Token 已保存')); }
				else ui.addNotification(null, E('p', r.error || '保存 Token 失败'), 'error'); }); } }, '保存 Token') ]);
		var save = E('button', { 'class': 'btn cbi-button cbi-button-save', click: function() {
			return callSave(owner.value, repo.value, visibility.value, channel.value, mode.value, interval.value, pubkey.value, downgrade.value).then(function(r) {
				if (r && r.ok) ui.addNotification(null, E('p', '配置已保存')); else ui.addNotification(null, E('p', r.error || '保存配置失败'), 'error');
			}); } }, '保存设置');
		poll.add(function() { return callStatus().then(function(s) { showStatus(statusText, s || {}); }); }, 3);
		return E('div', { 'class': 'cbi-map' }, [ E('h2', '固件在线升级'), configPanel, tokenPanel, statusPanel, E('div', { 'class': 'cbi-page-actions' }, [ save ]) ]);
	}
});

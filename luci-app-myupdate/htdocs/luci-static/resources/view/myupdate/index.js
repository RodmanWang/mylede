'use strict';
'require view';
'require form';
'require rpc';
'require ui';
'require poll';

var callStatus = rpc.declare({ object: 'myupdate', method: 'get_status' });
var callConfig = rpc.declare({ object: 'myupdate', method: 'get_config' });
var callToken = rpc.declare({ object: 'myupdate', method: 'set_token', params: [ 'token' ] });
var callCheck = rpc.declare({ object: 'myupdate', method: 'start_check' });
var callDownload = rpc.declare({ object: 'myupdate', method: 'start_download' });
var callUpgrade = rpc.declare({ object: 'myupdate', method: 'start_upgrade' });

function showStatus(node, s) {
	var current = s.current_version ? '当前版本：' + s.current_version : '';
	var latest = s.latest_version ? '；最新版本：' + s.latest_version : '';
	node.textContent = (s.message || '尚未检查更新') + (current ? '（' + current + latest + '）' : '');
}

function reportTaskStart(promise, fallback) {
	return promise.then(function(result) {
		if (!result || !result.ok)
			ui.addNotification(null, E('p', result && result.error ? result.error : fallback), 'error');
	}).catch(function(error) {
		var message = error && error.message ? error.message : String(error || fallback);
		ui.addNotification(null, E('p', message), 'error');
	});
}

return view.extend({
	load: function() {
		return Promise.all([ callConfig(), callStatus() ]);
	},
	render: function(data) {
		var cfg = data[0] || {}, status = data[1] || {};
		var m = new form.Map('myupdate');
		var s = m.section(form.NamedSection, 'main', 'myupdate');
		s.addremove = false;

		var repo = s.option(form.Value, 'repo_url', _('GitHub 仓库地址'));
		repo.placeholder = 'https://github.com/OWNER/REPO';
		repo.description = _('填写仓库完整 HTTPS 地址，例如 https://github.com/OWNER/REPO。不要填写 Release 页面或其他子路径。');
		repo.rmempty = false;
		repo.cfgvalue = function() {
			return cfg.repo_url || '';
		};
		repo.validate = function(section_id, value) {
			if (!/^https:\/\/github\.com\/[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+\/?(?:\.git)?$/.test(value || ''))
				return _('请输入有效的 GitHub 仓库地址，例如 https://github.com/OWNER/REPO');
			return true;
		};

		var visibility = s.option(form.ListValue, 'repo_visibility', _('仓库可见性'));
		visibility.value('public', _('公开'));
		visibility.value('private', _('私有'));
		visibility.default = 'public';
		visibility.description = _('公开仓库无需访问令牌；选择私有后，需要在下方配置 GitHub Token。');

		var token = s.option(form.Value, '_github_token', _('GitHub Token'));
		token.password = true;
		token.rmempty = true;
		token.optional = true;
		token.depends('repo_visibility', 'private');
		token.placeholder = cfg.token_configured ? _('已配置；留空则保持当前 Token') : _('私有仓库必填');
		token.description = _('建议使用 Fine-grained PAT，仅授予目标仓库 Contents: Read-only。Token 单独以仅 root 可读的权限保存，不写入 UCI 配置。');
		token.cfgvalue = function() { return ''; };
		token.validate = function(section_id, value) {
			if (visibility.formvalue(section_id) == 'private' && !value && !cfg.token_configured)
				return _('私有仓库尚未配置 GitHub Token，请在此输入 Token。');
			return true;
		};
		token.write = function(section_id, value) {
			if (!value) return Promise.resolve();
			return callToken(value).then(function(result) {
				if (!result || !result.ok)
					throw new Error(result && result.error ? result.error : _('GitHub Token 保存失败'));
			});
		};

		var mode = s.option(form.ListValue, 'upgrade_mode', _('检查模式'));
		mode.value('manual', _('手动检查'));
		mode.value('notify', _('定时检查，有更新时显示状态'));
		mode.value('auto', _('每天定时检查并自动下载、验证和升级'));
		mode.default = 'manual';

		var interval = s.option(form.Value, 'check_interval', _('检查间隔（秒）'));
		interval.datatype = 'uinteger';
		interval.default = '86400';
		interval.rmempty = false;
		interval.validate = function(section_id, value) {
			var n = Number(value);
			if (!Number.isInteger(n) || n < 900 || n > 604800)
				return _('检查间隔必须为 900 至 604800 秒。86400 秒为一天。');
			return true;
		};
		interval.description = _('用于定时检查模式；默认 86400 秒（一天）。');

		var autoTime = s.option(form.Value, 'auto_upgrade_time', _('每天自动升级时间（路由器本地时间）'));
		autoTime.default = '04:00';
		autoTime.datatype = 'time';
		autoTime.description = _('仅在选择自动升级模式时生效；每天最多自动执行一次。');

		var pubkey = s.option(form.Value, 'minisign_public_key', _('Minisign 公钥'));
		pubkey.description = _('填写 Base64 格式的公钥主体（以 RW 开头），不要填写 minisign.pub 文件中的 untrusted comment 行；该公钥必须与 GitHub Actions 的 MINISIGN_SECRET_KEY 配对。');

		var downgrade = s.option(form.ListValue, 'allow_downgrade', _('允许降级'));
		downgrade.value('0', _('禁止'));
		downgrade.value('1', _('允许'));
		downgrade.default = '0';

		var keepPaths = s.option(form.TextValue, 'custom_keep_paths', _('自定义文件保留路径'));
		keepPaths.rows = 8;
		keepPaths.description = _('每行填写一个路由器上的绝对路径。不要填写 /、/proc、/sys、/dev、/tmp、/rom 或 /overlay。');

		var statusText = E('p', { id: 'myupdate-status' });
		showStatus(statusText, status);
		var statusPanel = E('div', { 'class': 'cbi-section' }, [
			E('h3', _('升级状态')),
			statusText,
			E('p', _('自动升级会在设定时间检查更新；如发现新版本，将自动下载并验证签名、兼容性和 SHA256，通过 sysupgrade -T 后执行 sysupgrade -v 并重启。升级使用 LEDE 默认配置备份与恢复机制。只接受本项目生成的 x86_64 squashfs UEFI combined 镜像。')),
			E('button', { 'class': 'btn cbi-button cbi-button-action', click: function() {
				return reportTaskStart(callCheck(), _('检查任务启动失败'));
			} }, _('检查更新')), ' ',
			E('button', { 'class': 'btn cbi-button cbi-button-positive', click: function() {
				return reportTaskStart(callDownload(), _('下载任务启动失败'));
			} }, _('下载并验证')), ' ',
			E('button', { 'class': 'btn cbi-button cbi-button-negative', click: function() {
				if (!confirm(_('确定升级吗？设备将执行保留系统配置的升级并自动重启。建议提前备份重要配置，并确保有本地或带外访问方式。'))) return;
				return reportTaskStart(callUpgrade(), _('升级任务启动失败，请先下载并验证固件'));
			} }, _('执行升级'))
		]);

		poll.add(function() {
			return callStatus().then(function(st) { showStatus(statusText, st || {}); });
		}, 3);

		return m.render().then(function(mapNode) {
			return E('div', { 'class': 'cbi-map' }, [
				E('h2', _('固件在线升级')),
				statusPanel,
				mapNode
			]);
		});
	}
});

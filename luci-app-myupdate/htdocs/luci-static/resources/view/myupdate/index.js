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

function formatBytes(value) {
	var n = Number(value || 0);
	if (n >= 1073741824) return (n / 1073741824).toFixed(2) + ' GiB';
	if (n >= 1048576) return (n / 1048576).toFixed(1) + ' MiB';
	if (n >= 1024) return (n / 1024).toFixed(0) + ' KiB';
	return n + ' B';
}

function showStatus(node, s, progressFill, progressLabel, progressPanel) {
	var state = s.state || 'idle';
	var current = s.current_version ? '当前版本：' + s.current_version : '';
	var latest = s.latest_version ? '最新版本：' + s.latest_version : '';
	var details = [ current, latest ].filter(Boolean).join('　');
	node.textContent = (s.message || '尚未检测更新') + (details ? '　｜　' + details : '');
	node.className = 'myupdate-status-message state-' + state;
	var downloading = state == 'downloading';
	progressPanel.style.display = downloading ? '' : 'none';
	if (downloading) {
		var percent = Math.max(0, Math.min(99, Number(s.download_percent || 0)));
		progressFill.style.width = percent + '%';
		progressLabel.textContent = percent + '%　' + formatBytes(s.downloaded_bytes) + ' / ' + formatBytes(s.total_bytes);
	}
}

function reportTaskStart(promise, fallback) {
	return promise.then(function(result) {
		if (!result || !result.ok)
			ui.addNotification(null, E('p', result && result.error ? result.error : fallback), 'error');
		else if (result.queued)
			ui.addNotification(null, E('p', result.message || _('任务请求已排队，后台服务将在数秒内执行。')), 'info');
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
			if (!/^https:\/\/github\.com\/[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+(?:\.git)?\/?$/.test(value || ''))
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

		var pubkey = s.option(form.TextValue, 'minisign_public_key', _('Minisign 公钥'));
		pubkey.rows = 2;
		pubkey.monospace = true;
		pubkey.description = _('公钥必须与 GitHub Actions 的 MINISIGN_SECRET_KEY 配对。支持粘贴 minisign.pub 完整两行内容，或直接填写 Base64 公钥主体。');
		pubkey.validate = function(section_id, value) {
			var key = (value || '').trim();
			if (!/^RW[A-Za-z0-9+/]{54}$/.test(key))
				return _('公钥格式不正确。请填写 56 位 Base64 公钥主体；若使用 minisign.pub 两行格式，请先点击“识别并转换”。');
			return true;
		};

		var convertKey = E('button', {
			'class': 'btn cbi-button cbi-button-action',
			click: function() {
				var widget = pubkey.getUIElement('main');
				if (!widget) {
					ui.addNotification(null, E('p', _('找不到公钥输入框，请刷新页面后重试。')), 'error');
					return;
				}
				var raw = (widget.getValue() || '').trim();
				var lines = raw.split(/\\r?\\n/).map(function(line) { return line.trim(); }).filter(Boolean);
				var candidates = lines.filter(function(line) { return /^RW/.test(line); });
				if (lines.length == 1 && /^RW[A-Za-z0-9+/]{54}$/.test(lines[0])) {
					ui.addNotification(null, E('p', _('当前公钥已经是正确的 Base64 格式，无需转换。')), 'info');
					return;
				}
				if (candidates.length != 1 || !/^RW[A-Za-z0-9+/]{54}$/.test(candidates[0])) {
					ui.addNotification(null, E('p', _('无法识别公钥格式。请粘贴 minisign.pub 的完整两行内容，或直接填写以 RW 开头的 56 位 Base64 公钥主体。')), 'error');
					return;
				}
				widget.setValue(candidates[0]);
				widget.node.firstElementChild.dispatchEvent(new Event('change', { bubbles: true }));
				ui.addNotification(null, E('p', _('公钥已转换并自动填入。请检查内容后点击“保存并应用”。')), 'info');
			}
		}, _('识别并转换'));

		var downgrade = s.option(form.ListValue, 'allow_downgrade', _('允许降级'));
		downgrade.value('0', _('禁止'));
		downgrade.value('1', _('允许'));
		downgrade.default = '0';

		var keepPaths = s.option(form.DynamicList, 'custom_keep_paths', _('自定义文件保留路径'));
		keepPaths.optional = true;
		keepPaths.rmempty = true;
		keepPaths.cfgvalue = function() {
			return cfg.custom_keep_paths || [];
		};
		keepPaths.description = _('每项填写一个路由器上的绝对路径；点击“添加”增加路径。保存后会以 UCI list 格式逐项保存。不要填写 /、/proc、/sys、/dev、/tmp、/rom 或 /overlay。');

		var statusText = E('div', { id: 'myupdate-status', 'class': 'myupdate-status-message' });
		var progressFill = E('div', { 'class': 'myupdate-progress-fill' });
		var progressLabel = E('div', { 'class': 'myupdate-progress-label' }, '0%');
		var progressPanel = E('div', { 'class': 'myupdate-progress', style: 'display:none' }, [
			E('div', { 'class': 'myupdate-progress-track' }, [ progressFill ]),
			progressLabel
		]);
		var statusPanel = E('section', { 'class': 'myupdate-status-panel' }, [
			E('div', { 'class': 'myupdate-status-heading' }, [
				E('h3', _('检测状态')),
				E('span', { 'class': 'myupdate-status-caption' }, _('固件检查、下载与验证进度'))
			]),
			statusText,
			progressPanel,
			E('div', { 'class': 'myupdate-status-note' }, _('自动升级会按设定时间检查更新；发现新版本后可下载并验证签名、设备兼容性和 SHA256。验证通过后，需手动确认才会执行 sysupgrade 并重启。升级使用 LEDE 默认配置备份与恢复机制。仅接受本项目生成的 x86_64 squashfs UEFI combined 镜像。')),
			E('div', { 'class': 'myupdate-actions' }, [
				E('button', { 'class': 'btn cbi-button cbi-button-action', click: function() {
					return reportTaskStart(callCheck(), _('检查任务启动失败'));
				} }, _('检查更新')),
				E('button', { 'class': 'btn cbi-button cbi-button-positive', click: function() {
					return reportTaskStart(callDownload(), _('下载并验证任务启动失败'));
				} }, _('下载并验证')),
				E('button', { 'class': 'btn cbi-button cbi-button-negative', click: function() {
					if (!confirm(_('确定升级吗？设备将执行保留系统配置的升级并自动重启。建议提前备份重要配置，并确保有本地或带外访问方式。'))) return;
					return reportTaskStart(callUpgrade(), _('升级任务启动失败，请先下载并验证固件'));
				} }, _('执行升级'))
			])
		]);
		showStatus(statusText, status, progressFill, progressLabel, progressPanel);

		poll.add(function() {
			return callStatus().then(function(st) { showStatus(statusText, st || {}, progressFill, progressLabel, progressPanel); });
		}, 3);

		return m.render().then(function(mapNode) {
			var style = E('style', {}, `
				.myupdate-status-panel{border:1px solid #c8d4df;border-left:4px solid #64748b;border-radius:8px;background:var(--background-color-high,#fff);padding:18px 20px;margin:12px 0 24px;box-shadow:0 2px 8px rgba(0,0,0,.045)}
				.myupdate-status-heading{display:flex;align-items:center;justify-content:space-between;gap:12px;margin-bottom:12px}
				.myupdate-status-heading h3{margin:0;font-size:1.2rem}
				.myupdate-status-caption{font-size:.9em;color:var(--gray-color-medium,#777)}
				.myupdate-status-message{padding:12px 14px;border-radius:6px;background:#f1f5f9;color:#334155;font-weight:600;line-height:1.65}
				.myupdate-status-message.state-checked,.myupdate-status-message.state-downloaded,.myupdate-status-message.state-current{background:#ecfdf3;color:#166534;border-left:4px solid #16a34a}
				.myupdate-status-message.state-downloading,.myupdate-status-message.state-running{background:#eff6ff;color:#1d4ed8;border-left:4px solid #3b82f6}
				.myupdate-status-message.state-error{background:#fef2f2;color:#b91c1c;border-left:4px solid #dc2626}
				.myupdate-status-message.state-upgrading{background:#fff7ed;color:#c2410c;border-left:4px solid #f97316}
				.myupdate-status-note{margin:12px 0;color:var(--gray-color-medium,#666);font-size:.92em;line-height:1.7}
				.myupdate-actions{display:flex;flex-wrap:wrap;gap:10px;padding-top:12px;border-top:1px solid var(--border-color-medium,#ddd)}
				.myupdate-progress{margin-top:14px}
				.myupdate-progress-track{height:13px;border-radius:10px;background:#e2e8f0;overflow:hidden}
				.myupdate-progress-fill{height:100%;width:0;background:linear-gradient(90deg,#2563eb,#16a34a);border-radius:10px;transition:width .35s ease}
				.myupdate-progress-label{margin-top:6px;text-align:right;font-size:.9em;color:var(--gray-color-medium,#555);font-variant-numeric:tabular-nums}
				#myupdate-status{min-width:0}
				#myupdate-status + div{margin-top:8px}
				.cbi-value-description .myupdate-key-tools{display:flex;align-items:center;justify-content:space-between;gap:12px;flex-wrap:wrap}
				.cbi-value-description .myupdate-key-tools span{flex:1;min-width:240px}
				textarea[name="cbid.myupdate.main.minisign_public_key"]{min-height:3.6em!important;height:3.6em!important}
				@media(max-width:767px){.myupdate-status-heading{align-items:flex-start;flex-direction:column}.myupdate-actions .btn{flex:1}.myupdate-status-panel{padding:14px}}
			`);
			var keyDescription = pubkey.description;
			pubkey.description = E('div', { 'class': 'myupdate-key-tools' }, [
				E('span', {}, keyDescription),
				convertKey
			]);
			return E('div', { 'class': 'cbi-map myupdate-page' }, [
				style,
				E('h2', _('固件在线升级')),
				statusPanel,
				mapNode
			]);
		});
	}
});

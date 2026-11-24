'use strict';
'require view';
'require form';
'require rpc';
'require poll';

var callStatus = rpc.declare({ object: 'myupdate', method: 'get_status' });
var callConfig = rpc.declare({ object: 'myupdate', method: 'get_config' });
var callListKeepPaths = rpc.declare({ object: 'myupdate', method: 'list_keep_paths', params: [ 'path' ] });
var callSaveKeepPaths = rpc.declare({ object: 'myupdate', method: 'save_config', params: [ 'custom_keep_paths' ] });
var callSaveDowngrade = rpc.declare({ object: 'myupdate', method: 'set_allow_downgrade', params: [ 'allow_downgrade' ] });
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

function createInlineNotifier(node) {
	var timer = null;
	return function(message, type) {
		if (timer) clearTimeout(timer);
		node.textContent = message;
		node.className = 'myupdate-inline-notice notice-' + (type || 'info');
		node.style.display = '';
		timer = setTimeout(function() {
			node.style.display = 'none';
			node.textContent = '';
			timer = null;
		}, 3000);
	};
}

function reportTaskStart(promise, fallback, notify) {
	return promise.then(function(result) {
		if (!result || !result.ok)
			notify(result && result.error ? result.error : fallback, 'error');
		else if (result.queued)
			notify(result.message || _('任务请求已排队，后台服务将在数秒内执行。'), 'info');
	}).catch(function(error) {
		var message = error && error.message ? error.message : String(error || fallback);
		notify(message, 'error');
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

		function addSettingsHeading(id, title, description) {
			var heading = s.option(form.DummyValue, id, title);
			heading.cfgvalue = function() { return ''; };
			heading.renderWidget = function() {
				return E('div', { 'class': 'myupdate-settings-heading' }, [
					E('h3', {}, title),
					E('p', {}, description)
				]);
			};
		}

		addSettingsHeading('_heading_repository', _('仓库与访问权限'), _('配置固件来源，以及访问公开或私有 GitHub 仓库所需的凭据。'));
		var noticeNode = E('div', { 'class': 'myupdate-inline-notice', role: 'status', 'aria-live': 'polite', style: 'display:none' });
		var notify = createInlineNotifier(noticeNode);

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

		addSettingsHeading('_heading_schedule', _('更新策略'), _('选择检查方式，并设置定时任务的执行频率与时间。'));
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

		addSettingsHeading('_heading_verification', _('固件验证'), _('使用与发布流程匹配的 Minisign 公钥验证固件来源，验证通过后才允许继续升级。'));
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
					notify(_('找不到公钥输入框，请刷新页面后重试。'), 'error');
					return;
				}
				var raw = (widget.getValue() || '').trim();
				var lines = raw.split(/\r?\n/).map(function(line) { return line.trim(); }).filter(Boolean);
				var candidates = lines.filter(function(line) { return /^RW/.test(line); });
				if (lines.length == 1 && /^RW[A-Za-z0-9+/]{54}$/.test(lines[0])) {
					notify(_('当前公钥已经是正确的 Base64 格式，无需转换。'), 'info');
					return;
				}
				if (candidates.length != 1 || !/^RW[A-Za-z0-9+/]{54}$/.test(candidates[0])) {
					notify(_('无法识别公钥格式。请粘贴 minisign.pub 的完整两行内容，或直接填写以 RW 开头的 56 位 Base64 公钥主体。'), 'error');
					return;
				}
				widget.setValue(candidates[0]);
				var inputNode = widget.node || widget;
				if (inputNode && inputNode.dispatchEvent)
					inputNode.dispatchEvent(new Event('change', { bubbles: true }));
				notify(_('公钥已转换并自动填入。请检查内容后点击“保存并应用”。'), 'info');
			}
		}, _('识别并转换'));

		addSettingsHeading('_heading_backup', _('配置保留'), _('选择升级后需要恢复的文件或目录；请只添加确实需要跨版本保留的数据。'));
		var keepPathValues = (cfg.custom_keep_paths || []).slice();
		var keepPaths = s.option(form.DynamicList, 'custom_keep_paths', _('自定义文件保留路径'));
		keepPaths.optional = true;
		keepPaths.rmempty = true;
		keepPaths.cfgvalue = function() { return keepPathValues.slice(); };
		keepPaths.formvalue = function() { return keepPathValues.slice(); };
		keepPaths.write = function(section_id, values) {
			var paths = Array.isArray(values) ? values : keepPathValues;
			return callSaveKeepPaths(paths.join('\n')).then(function(result) {
				if (!result || !result.ok)
					throw new Error(result && result.error ? result.error : _('自定义保留路径保存失败。'));
			});
		};
		keepPaths.validate = function(section_id, values) {
			var paths = Array.isArray(values) ? values : keepPathValues;
			for (var i = 0; i < paths.length; i++) {
				var path = String(paths[i] || '').trim();
				if (!/^\/[A-Za-z0-9._/@+-]+$/.test(path) || path == '/' || /(^|\/)\.\.?($|\/)/.test(path))
					return _('路径格式无效：请填写已存在的绝对文件或目录路径。');
				if (/^\/(proc|sys|dev|tmp|rom|overlay)(\/|$)/.test(path))
					return _('不能保留系统虚拟目录或临时目录中的路径。');
			}
			return true;
		};
		keepPaths.description = _('可手动输入绝对路径，也可展开设备文件浏览器逐层选择文件或目录。符号链接、特殊文件和系统虚拟目录不会加入保留列表。');
		keepPaths.renderWidget = function(section_id) {
			var input = E('textarea', { 'class': 'myupdate-path-batch-input', 'placeholder': _('手动输入绝对路径，每行一条'), 'rows': '2' });
			var chips = E('div', { 'class': 'myupdate-path-chips' });
			var message = E('div', { 'class': 'myupdate-path-hint', 'aria-live': 'polite' });
			var browserToggle = E('button', { 'type': 'button', 'class': 'btn cbi-button myupdate-browser-toggle' }, _('浏览设备文件…'));
			var browserPanel = E('div', { 'class': 'myupdate-file-browser', style: 'display:none' });
			var browserPath = E('div', { 'class': 'myupdate-browser-path' }, '/');
			var browserList = E('div', { 'class': 'myupdate-browser-list' });
			var browserHint = E('div', { 'class': 'myupdate-browser-hint', 'aria-live': 'polite' });
			var currentPath = '/', browserLoaded = false, browserBusy = false;

			function renderChips() {
				while (chips.firstChild) chips.removeChild(chips.firstChild);
				keepPathValues.forEach(function(path, index) {
					chips.appendChild(E('span', { 'class': 'myupdate-path-chip' }, [
						E('span', { 'class': 'myupdate-path-chip-text' }, path),
						E('button', { 'type': 'button', 'class': 'myupdate-path-chip-remove', 'aria-label': _('删除 ') + path,
							click: function() { keepPathValues.splice(index, 1); renderChips(); } }, '×')
					]));
				});
			}
			function allowedPath(path) {
				return /^\/[A-Za-z0-9._/@+-]+$/.test(path) && path != '/' &&
					!/(^|\/)\.\.?($|\/)/.test(path) &&
					!/^\/(proc|sys|dev|tmp|rom|overlay)(\/|$)/.test(path);
			}
			function addPaths(raw) {
				var items = String(raw || '').split(/[\n,，]+/).map(function(v) { return v.trim(); }).filter(Boolean);
				var added = 0, invalid = [];
				items.forEach(function(path) {
					if (!allowedPath(path)) { invalid.push(path); return; }
					if (keepPathValues.indexOf(path) < 0) { keepPathValues.push(path); added++; }
				});
				renderChips();
				message.textContent = invalid.length ? _('以下路径格式无效或不允许保留：') + ' ' + invalid.join(', ') :
					(added ? _('已添加 ') + added + _(' 个路径。') : _('没有新增路径（可能已存在或输入为空）。'));
				if (!invalid.length) input.value = '';
			}
			function renderBrowser(entries, truncated) {
				while (browserList.firstChild) browserList.removeChild(browserList.firstChild);
				if (!entries || !entries.length) {
					browserList.appendChild(E('div', { 'class': 'myupdate-browser-empty' }, _('此目录没有可浏览的普通文件或目录。')));
					return;
				}
				entries.forEach(function(entry) {
					var nameNode = entry.type == 'directory' && entry.can_open ?
						E('button', { 'type': 'button', 'class': 'myupdate-browser-name myupdate-browser-directory',
							click: function() { loadDirectory(entry.path); } }, [
							E('span', { 'class': 'myupdate-browser-icon', 'aria-hidden': 'true' }, '📁'),
							E('span', {}, entry.name)
						]) :
						E('span', { 'class': 'myupdate-browser-name' }, [
							E('span', { 'class': 'myupdate-browser-icon', 'aria-hidden': 'true' }, entry.type == 'directory' ? '📁' : (entry.type == 'symlink' ? '🔗' : '📄')),
							E('span', {}, entry.name)
						]);
					var add = entry.can_add ?
						E('button', { 'type': 'button', 'class': 'btn cbi-button cbi-button-add myupdate-browser-add',
							click: function() { addPaths(entry.path); } }, _('添加')) :
						E('span', { 'class': 'myupdate-browser-restricted' }, entry.type == 'symlink' ? _('符号链接不可添加') : _('不可添加'));
					browserList.appendChild(E('div', { 'class': 'myupdate-browser-entry' }, [ nameNode, add ]));
				});
				if (truncated) browserHint.textContent = _('目录项目较多，仅显示前 300 项；可进入子目录继续选择。');
			}
			function loadDirectory(path) {
				if (browserBusy) return;
				browserBusy = true;
				browserPath.textContent = path;
				browserList.textContent = _('正在读取目录…');
				browserHint.textContent = '';
				callListKeepPaths(path).then(function(result) {
					if (!result || !result.ok) throw new Error(result && result.error ? result.error : _('无法读取该目录。'));
					currentPath = result.path;
					browserPath.textContent = currentPath;
					browserLoaded = true;
					renderBrowser(result.entries || [], result.truncated);
				}).catch(function(error) {
					browserList.textContent = '';
					browserHint.textContent = error && error.message ? error.message : String(error);
				}).then(function() { browserBusy = false; });
			}
			var upButton = E('button', { 'type': 'button', 'class': 'btn cbi-button myupdate-browser-up',
				click: function() {
					if (currentPath == '/') return;
					loadDirectory(currentPath.substring(0, currentPath.lastIndexOf('/')) || '/');
				} }, _('上一级'));
			function closeBrowser() {
				browserPanel.style.display = 'none';
				browserToggle.textContent = _('浏览设备文件…');
				document.removeEventListener('click', onOutsideBrowserClick);
			}
			function onOutsideBrowserClick(ev) {
				if (!browserPanel.contains(ev.target) && !browserToggle.contains(ev.target))
					closeBrowser();
			}
			browserToggle.addEventListener('click', function() {
				var opening = browserPanel.style.display == 'none';
				if (!opening) { closeBrowser(); return; }
				browserPanel.style.display = '';
				browserToggle.textContent = _('收起文件浏览器');
				document.addEventListener('click', onOutsideBrowserClick);
				if (!browserLoaded) loadDirectory('/');
			});
			var addButton = E('button', { 'type': 'button', 'class': 'btn cbi-button cbi-button-add myupdate-path-manual-add',
				click: function() { addPaths(input.value); } }, _('添加'));
			input.addEventListener('keydown', function(ev) {
				if ((ev.ctrlKey || ev.metaKey) && ev.key == 'Enter') { ev.preventDefault(); addPaths(input.value); }
			});
			browserPanel.appendChild(E('div', { 'class': 'myupdate-browser-toolbar' }, [ upButton, browserPath ]));
			browserPanel.appendChild(browserList);
			browserPanel.appendChild(browserHint);
			renderChips();
			return E('div', { 'class': 'myupdate-path-editor' }, [
				E('div', { 'class': 'myupdate-path-entry-row' }, [ input, addButton ]),
				browserToggle, browserPanel, chips, message
			]);
		};

		var statusText = E('div', { id: 'myupdate-status', 'class': 'myupdate-status-message' });
		var progressFill = E('div', { 'class': 'myupdate-progress-fill' });
		var progressLabel = E('div', { 'class': 'myupdate-progress-label' }, '0%');
		var progressPanel = E('div', { 'class': 'myupdate-progress', style: 'display:none' }, [
			E('div', { 'class': 'myupdate-progress-track' }, [ progressFill ]),
			progressLabel
		]);
		var downgradeCheckbox = E('input', {
			'type': 'checkbox',
			'checked': (cfg.allow_downgrade || '0') == '1',
			'aria-label': _('允许降级'),
			change: function(ev) {
				var control = ev.target, previous = (cfg.allow_downgrade || '0') == '1';
				var value = control.checked ? '1' : '0';
				control.disabled = true;
				callSaveDowngrade(value).then(function(result) {
					if (!result || !result.ok) throw new Error(result && result.error ? result.error : _('保存降级设置失败。'));
					cfg.allow_downgrade = result.allow_downgrade || value;
					control.checked = cfg.allow_downgrade == '1';
					notify(value == '1' ? _('已启用降级；执行升级时将允许安装低于当前版本的固件。') : _('已关闭降级；执行升级时不允许安装低于当前版本的固件。'), 'info');
				}).catch(function(error) {
					control.checked = previous;
					notify(error && error.message ? error.message : String(error), 'error');
				}).then(function() { control.disabled = false; });
			}
		});
		var downgradeLabel = E('label', { 'class': 'myupdate-downgrade-toggle' }, [ downgradeCheckbox, E('span', {}, _('允许降级')) ]);

		var statusPanel = E('section', { 'class': 'myupdate-status-panel' }, [
			E('div', { 'class': 'myupdate-status-heading' }, [
				E('div', { 'class': 'myupdate-status-title' }, [
					E('span', { 'class': 'myupdate-status-kicker' }, _('UPDATE CENTER')),
					E('h3', _('更新状态'))
				]),
				E('span', { 'class': 'myupdate-status-caption' }, _('检查 · 下载 · 验证 · 升级'))
			]),
			noticeNode,
			E('div', { 'class': 'myupdate-status-overview' }, [
				statusText,
				E('p', { 'class': 'myupdate-status-note' }, _('固件下载完成后会验证 Minisign 签名、设备兼容性和 SHA256。只有验证通过，才可确认执行 sysupgrade。升级会重启设备，并按 LEDE 默认机制恢复配置备份。仅接受本项目生成的 x86_64 squashfs UEFI combined 镜像。'))
			]),
			progressPanel,
			E('div', { 'class': 'myupdate-actions' }, [
				E('div', { 'class': 'myupdate-actions-primary' }, [
					E('button', { 'class': 'btn cbi-button cbi-button-action', click: function() {
						return reportTaskStart(callCheck(), _('检查任务启动失败'), notify);
					} }, _('检查更新')),
					E('button', { 'class': 'btn cbi-button cbi-button-positive', click: function() {
						return reportTaskStart(callDownload(), _('下载并验证任务启动失败'), notify);
					} }, _('下载并验证')),
					E('button', { 'class': 'btn cbi-button cbi-button-negative myupdate-upgrade-button', click: function() {
						if (!confirm(_('确定升级吗？设备将执行保留系统配置的升级并自动重启。建议提前备份重要配置，并确保有本地或带外访问方式。'))) return;
						return reportTaskStart(callUpgrade(), _('升级任务启动失败，请先下载并验证固件'), notify);
					} }, _('执行升级'))
				]),
				E('div', { 'class': 'myupdate-downgrade-row' }, [
					downgradeLabel,
					E('span', { 'class': 'myupdate-downgrade-hint' }, _('默认关闭。启用后，执行升级时允许安装低于当前版本的固件。'))
				])
			])
		]);
		showStatus(statusText, status, progressFill, progressLabel, progressPanel);

		poll.add(function() {
			return callStatus().then(function(st) { showStatus(statusText, st || {}, progressFill, progressLabel, progressPanel); });
		}, 3);

			var originalPubkeyRender = pubkey.renderWidget;
			pubkey.renderWidget = function(section_id, option_index, cfgvalue) {
				var inputWidget = originalPubkeyRender.apply(this, arguments);
				var keyInput = inputWidget.tagName == 'TEXTAREA' ? inputWidget :
					(inputWidget.querySelector ? inputWidget.querySelector('textarea') : null);
				if (keyInput) keyInput.addEventListener('blur', function() {
					var normalized = keyInput.value.replace(/\\r?\\n$/, '');
					if (normalized != keyInput.value) {
						keyInput.value = normalized;
						keyInput.dispatchEvent(new Event('input', { bubbles: true }));
						keyInput.dispatchEvent(new Event('change', { bubbles: true }));
					}
				});
				return E('div', { 'class': 'myupdate-key-input-row' }, [
					E('div', { 'class': 'myupdate-key-input' }, [ inputWidget ]),
					E('div', { 'class': 'myupdate-key-convert' }, [ convertKey ])
				]);
			};
		return m.render().then(function(mapNode) {
			var style = E('style', {}, `
				.myupdate-page{max-width:1180px;margin:0 auto;padding-bottom:32px}
				.myupdate-hero{display:flex;align-items:center;gap:18px;margin:4px 0 22px;padding:22px 24px;border:1px solid var(--border-color-medium,#d7dee7);border-radius:12px;background:linear-gradient(115deg,var(--background-color-high,#fff),var(--background-color,#f5f7fa));}
				.myupdate-hero-mark{display:flex;align-items:center;justify-content:center;flex:0 0 58px;height:58px;border-radius:14px;background:var(--primary-color,#2563eb);color:#fff;font-size:17px;font-weight:800;letter-spacing:.04em;box-shadow:0 5px 16px rgba(37,99,235,.18)}
				.myupdate-hero-copy{min-width:0}
				.myupdate-hero-eyebrow,.myupdate-status-kicker{display:block;margin-bottom:4px;color:var(--gray-color-medium,#778397);font-size:10px;font-weight:800;letter-spacing:.14em}
				.myupdate-hero h2{margin:0;color:var(--text-color-high,#1f2937);font-size:1.65rem;font-weight:750;letter-spacing:-.025em}
				.myupdate-hero p{margin:5px 0 0;color:var(--gray-color-medium,#697586);line-height:1.55}
				.myupdate-status-panel{border:1px solid var(--border-color-medium,#d5dce5);border-radius:12px;background:var(--background-color-high,#fff);padding:20px 22px;margin:0 0 28px;box-shadow:0 5px 18px rgba(15,23,42,.045)}
				.myupdate-status-heading{display:flex;align-items:center;justify-content:space-between;gap:12px;margin-bottom:16px}
				.myupdate-status-title h3{margin:0;font-size:1.18rem;font-weight:750}
				.myupdate-status-kicker{margin-bottom:3px}
				.myupdate-status-caption{font-size:.85em;color:var(--gray-color-medium,#778397)}
				.myupdate-inline-notice{margin:0 0 14px;padding:10px 13px;border-radius:7px;font-weight:600;line-height:1.55;overflow-wrap:anywhere}
				.myupdate-inline-notice.notice-info{background:var(--info-bg,#eff6ff);color:var(--info-color,#1d4ed8);border:1px solid rgba(59,130,246,.22)}
				.myupdate-inline-notice.notice-error{background:var(--error-bg,#fef2f2);color:var(--error-color,#b91c1c);border:1px solid rgba(220,38,38,.22)}
				.myupdate-status-overview{display:grid;grid-template-columns:minmax(0,1.15fr) minmax(250px,.85fr);gap:18px;align-items:stretch}
				.myupdate-status-message{display:flex;align-items:center;min-height:72px;padding:15px 17px;border:1px solid var(--border-color-medium,#e0e6ed);border-left:4px solid #94a3b8;border-radius:8px;background:var(--background-color,#f7f9fc);color:var(--text-color-high,#334155);font-weight:650;line-height:1.65;overflow-wrap:anywhere}
				.myupdate-status-message.state-checked,.myupdate-status-message.state-downloaded,.myupdate-status-message.state-current{background:rgba(22,163,74,.07);color:var(--success-color,#166534);border-left-color:#16a34a}
				.myupdate-status-message.state-downloading,.myupdate-status-message.state-running,.myupdate-status-message.state-verifying{background:rgba(37,99,235,.07);color:var(--info-color,#1d4ed8);border-left-color:#3b82f6}
				.myupdate-status-message.state-error{background:rgba(220,38,38,.07);color:var(--error-color,#b91c1c);border-left-color:#dc2626}
				.myupdate-status-message.state-upgrading{background:rgba(234,88,12,.08);color:var(--warning-color,#c2410c);border-left-color:#f97316}
				.myupdate-status-note{display:flex;align-items:center;margin:0;padding:13px 15px;border:1px solid var(--border-color-low,#e7ebf0);border-radius:8px;background:var(--background-color,#fafbfc);color:var(--gray-color-medium,#687385);font-size:.9em;line-height:1.7}
				.myupdate-actions{display:flex;flex-direction:column;gap:12px;margin-top:18px;padding-top:16px;border-top:1px solid var(--border-color-low,#e6eaf0)}
				.myupdate-actions-primary,.myupdate-actions-final{display:flex;align-items:center;flex-wrap:wrap;gap:10px}
				.myupdate-actions-primary .btn{min-width:142px}
				.myupdate-actions-final{justify-content:flex-end}
				.myupdate-downgrade-row{display:flex;align-items:center;flex-wrap:wrap;gap:10px;padding-top:10px;border-top:1px solid var(--border-color-low,#edf0f4)}
				.myupdate-downgrade-toggle{margin:0;padding:6px 9px;border-color:rgba(217,119,6,.28);background:rgba(217,119,6,.045)}
				.myupdate-downgrade-hint{font-size:.86em;color:var(--gray-color-medium,#778397)}
				.myupdate-actions .btn{min-height:38px;border-radius:6px;font-weight:650}
				.myupdate-actions .cbi-button-action{box-shadow:0 2px 5px rgba(37,99,235,.13)}
				.myupdate-actions .myupdate-upgrade-button{min-width:124px}
				.myupdate-downgrade-toggle{display:inline-flex;align-items:center;gap:8px;margin-right:auto;padding:8px 11px;border:1px solid var(--border-color-medium,#d5dce5);border-radius:7px;background:var(--background-color,#fafbfc);font-size:.9em;font-weight:600;cursor:pointer}
				.myupdate-downgrade-toggle input{margin:0;accent-color:var(--primary-color,#2563eb)}
				.myupdate-progress{margin-top:15px;padding:13px 15px;border:1px solid var(--border-color-low,#e4e9ef);border-radius:8px;background:var(--background-color,#fafbfc)}
				.myupdate-progress-track{height:9px;border-radius:20px;background:var(--border-color-low,#e5eaf0);overflow:hidden}
				.myupdate-progress-fill{height:100%;width:0;background:linear-gradient(90deg,#2563eb,#0d9488);border-radius:20px;transition:width .35s ease}
				.myupdate-progress-label{margin-top:8px;text-align:right;font-size:.85em;color:var(--gray-color-medium,#64748b);font-variant-numeric:tabular-nums}
				.myupdate-settings-intro{margin:0 0 8px;padding:0 2px}
				.myupdate-settings-intro h3{margin:0;font-size:1.2rem;font-weight:750}
				.myupdate-settings-intro p{margin:4px 0 0;color:var(--gray-color-medium,#6b7280);font-size:.92em;line-height:1.6}
				.myupdate-page .cbi-section{margin-top:10px;padding:12px 20px 18px;border:1px solid var(--border-color-medium,#d8dee7);border-radius:11px;background:var(--background-color-high,#fff);box-shadow:0 3px 12px rgba(15,23,42,.025)}
				.myupdate-page .cbi-value{padding:13px 0;border-bottom:1px solid var(--border-color-low,#edf0f4)}
				.myupdate-page .cbi-value:last-child{border-bottom:0}
				.myupdate-page .cbi-value-title{padding-top:7px;color:var(--text-color-high,#344054);font-weight:650}
				.myupdate-page .cbi-value-field{min-width:0}
				.myupdate-page input:not([type=checkbox]),.myupdate-page select,.myupdate-page textarea{border-radius:6px}
				.myupdate-page input:focus,.myupdate-page select:focus,.myupdate-page textarea:focus{outline:2px solid rgba(37,99,235,.18);outline-offset:1px}
				.myupdate-page .cbi-value-description{margin-top:6px;color:var(--gray-color-medium,#748094);font-size:.88em;line-height:1.55}
				.myupdate-page .cbi-value:has(.myupdate-settings-heading){padding:18px 0 8px;border-bottom:0}
				.myupdate-page .cbi-value:has(.myupdate-settings-heading) .cbi-value-title{display:none}
				.myupdate-settings-heading{padding:0 0 10px;border-bottom:1px solid var(--border-color-medium,#dce2e9)}
				.myupdate-settings-heading h3{margin:0;color:var(--text-color-high,#253246);font-size:1.02rem;font-weight:750}
				.myupdate-settings-heading p{margin:4px 0 0;color:var(--gray-color-medium,#748094);font-size:.88em;line-height:1.5}
				#myupdate-status{min-width:0}
				#myupdate-status + div{margin-top:8px}
				.myupdate-key-input-row{display:flex;align-items:stretch;gap:10px;width:min(100%,620px)}
				.myupdate-key-input{flex:0 1 560px;max-width:560px;min-width:0}
				.myupdate-key-input textarea{width:100%;min-height:3.6em!important;height:3.6em!important;max-width:560px;white-space:pre-wrap;overflow-wrap:anywhere;word-break:break-all;resize:vertical}
				.myupdate-key-convert{display:flex;align-items:center;flex:0 0 auto}
				.myupdate-path-editor{width:min(100%,760px);max-width:760px}
				.myupdate-path-entry-row{display:flex;align-items:stretch;gap:8px;max-width:760px}
				.myupdate-path-batch-input{flex:1;min-width:0;width:100%;height:4.2em!important;min-height:4.2em!important;resize:vertical}
				.myupdate-path-manual-add{align-self:flex-end;min-width:0;padding:5px 12px}
				.myupdate-browser-toggle{margin-top:8px}
				.myupdate-file-browser{width:100%;max-width:760px;box-sizing:border-box;margin-top:8px;border:1px solid var(--border-color-medium,#d8dee7);border-radius:8px;padding:10px;background:var(--background-color,#fafbfc)}
				.myupdate-browser-toolbar{display:flex;align-items:center;gap:10px;padding-bottom:8px;border-bottom:1px solid var(--border-color-low,#e6eaf0);font-size:.9em}
				.myupdate-browser-path{min-width:0;overflow-wrap:anywhere;font-family:monospace;color:var(--text-color-high,#344054)}
				.myupdate-browser-list{max-height:320px;overflow:auto}
				.myupdate-browser-entry{display:flex;align-items:center;justify-content:space-between;gap:10px;padding:7px 3px;border-bottom:1px solid var(--border-color-low,#edf0f4)}
				.myupdate-browser-name{display:inline-flex;align-items:center;gap:8px;min-width:0;overflow-wrap:anywhere;text-align:left}
				.myupdate-browser-directory{border:0;background:transparent;color:var(--link-color,#1769aa);cursor:pointer;padding:4px 0;font-weight:600}
				.myupdate-browser-icon{flex:0 0 auto}
				.myupdate-browser-add{flex:0 0 auto;min-width:0;padding:4px 10px;border-radius:5px}
				.myupdate-browser-restricted,.myupdate-browser-empty,.myupdate-browser-hint{font-size:.88em;color:var(--gray-color-medium,#778397)}
				.myupdate-browser-hint{padding-top:6px}
				.myupdate-path-chips{display:flex;flex-wrap:wrap;gap:8px;margin-top:8px}
				.myupdate-path-hint{min-height:1.5em;margin-top:8px;color:var(--gray-color-medium,#778397);font-size:.9em}
				.myupdate-path-chip{display:inline-flex;align-items:center;gap:7px;max-width:100%;padding:7px 10px;border-radius:6px;background:var(--background-color,#f6f8fa);border:1px solid var(--border-color-medium,#dce2e9)}
				.myupdate-path-chip-text{overflow-wrap:anywhere;font-size:.92em}
				.myupdate-path-chip-remove{border:0;background:transparent;color:var(--gray-color-high,#555);font-size:1.25em;line-height:1;cursor:pointer;padding:0 1px}
				.myupdate-path-chip-remove:hover{color:#dc2626}
				@media(max-width:767px){
					.myupdate-page{padding-bottom:20px}
					.myupdate-hero{align-items:flex-start;gap:12px;padding:16px}
					.myupdate-hero-mark{flex-basis:46px;height:46px;border-radius:11px;font-size:14px}
					.myupdate-hero h2{font-size:1.35rem}
					.myupdate-status-panel{padding:15px}
					.myupdate-status-heading{align-items:flex-start;flex-direction:column;gap:4px}
					.myupdate-status-overview{grid-template-columns:1fr;gap:9px}
					.myupdate-actions-primary{display:grid;grid-template-columns:repeat(3,minmax(0,1fr))}
					.myupdate-actions-primary .btn{min-width:0;width:100%;white-space:normal}
					.myupdate-actions-primary .btn{min-width:0;padding-left:7px;padding-right:7px}
					.myupdate-downgrade-row{align-items:flex-start;flex-direction:column;gap:5px}
					.myupdate-page .cbi-section{padding:8px 12px 12px}
					.myupdate-page .cbi-value{display:block;padding:11px 0}
					.myupdate-page .cbi-value-title{display:block;padding:0 0 5px}
					.myupdate-key-input-row,.myupdate-path-entry-row{flex-direction:row}
					.myupdate-key-convert .btn{width:auto}
					.myupdate-path-manual-add{align-self:flex-end}
					.myupdate-browser-toolbar{align-items:flex-start;flex-direction:column}
				}
				@media(max-width:420px){
					.myupdate-hero-mark{display:none}
					.myupdate-actions-primary{grid-template-columns:1fr}

					.myupdate-key-input-row{flex-direction:column}
					.myupdate-key-convert .btn{width:100%}
					.myupdate-path-entry-row{align-items:flex-end}
					.myupdate-path-batch-input{min-width:0}
				}
			`);
			return E('div', { 'class': 'cbi-map myupdate-page' }, [
				style,
				E('header', { 'class': 'myupdate-hero' }, [
					E('div', { 'class': 'myupdate-hero-mark', 'aria-hidden': 'true' }, 'OTA'),
					E('div', { 'class': 'myupdate-hero-copy' }, [
						E('span', { 'class': 'myupdate-hero-eyebrow' }, _('SYSTEM MAINTENANCE')),
						E('h2', _('固件在线升级')),
						E('p', _('管理固件更新、完整性验证与升级后的配置恢复。'))
					])
				]),
				statusPanel,
				E('div', { 'class': 'myupdate-settings-intro' }, [
					E('h3', _('升级设置')),
					E('p', _('配置更新来源、检查策略、验证密钥与配置保留规则。修改完成后，请使用页面底部的“保存并应用”提交设置。'))
				]),
				mapNode
			]);
		});
	}
});

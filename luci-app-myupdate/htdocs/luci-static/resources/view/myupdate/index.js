'use strict';
'require view';
'require form';
'require rpc';
'require poll';

var callStatus = rpc.declare({ object: 'myupdate', method: 'get_status' });
var callConfig = rpc.declare({ object: 'myupdate', method: 'get_config' });
var callListKeepPaths = rpc.declare({ object: 'myupdate', method: 'list_keep_paths', params: [ 'path' ] });
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

		var noticeNode = E('div', { 'class': 'myupdate-inline-notice', role: 'status', 'aria-live': 'polite', style: 'display:none' });
		var notify = createInlineNotifier(noticeNode);

		var repo = s.option(form.Value, 'repo_url', _('GitHub 仓库地址'));
		repo.placeholder = 'https://github.com/OWNER/REPO';
		repo.description = _('可留空；留空时不会保存仓库地址。点击“检查更新”时才检查地址是否有效；需要填写仓库完整 HTTPS 地址，例如 https://github.com/OWNER/REPO。');
		repo.optional = true;
		repo.rmempty = true;
		repo.cfgvalue = function() {
			return cfg.repo_url || '';
		};
		var originalRepoRender = repo.renderWidget;
		repo.renderWidget = function() {
			var inputWidget = originalRepoRender.apply(this, arguments);
			return E('div', { 'class': 'myupdate-repo-input' }, [ inputWidget ]);
		};

		var visibility = s.option(form.ListValue, 'repo_visibility', _('仓库可见性'));
		visibility.value('public', _('公开'));
		visibility.value('private', _('私有'));
		visibility.default = 'public';
		visibility.description = _('公开仓库无需 Token；私有仓库请填写下方访问令牌。');
		var originalVisibilityRender = visibility.renderWidget;
		visibility.renderWidget = function() { return E('div', { 'class': 'myupdate-field-visibility' }, [ originalVisibilityRender.apply(this, arguments) ]); };

		var token = s.option(form.Value, '_github_token', _('GitHub Token'));
		token.password = true;
		token.rmempty = true;
		token.optional = true;
		token.depends('repo_visibility', 'private');
		token.placeholder = cfg.token_configured ? _('已配置；留空则保持当前 Token') : _('私有仓库必填');
		token.description = _('建议使用 Fine-grained PAT，仅授予目标仓库 Contents: Read-only。Token 单独以仅 root 可读的权限保存，不写入 UCI 配置；留空保持已有 Token。格式和访问权限在检查私有仓库时验证，不影响保存其他设置。');
		token.cfgvalue = function() { return ''; };
		var originalTokenRender = token.renderWidget;
		token.renderWidget = function() { return E('div', { 'class': 'myupdate-field-token' }, [ originalTokenRender.apply(this, arguments) ]); };
		token.write = function(section_id, value) {
			if (!value) return Promise.resolve();
			return callToken(value).then(function(result) {
				if (!result || !result.ok)
					throw new Error(result && result.error ? result.error : _('GitHub Token 保存失败'));
			});
		};

		var mode = s.option(form.ListValue, 'upgrade_mode', _('升级模式'));
		mode.value('manual', _('手动'));
		mode.value('notify', _('定时提醒'));
		mode.value('auto', _('自动升级'));
		mode.default = 'manual';
		mode.description = _('手动不执行定时任务；定时提醒每天检查一次；自动升级每天检查、下载、验证并在设定时间升级。');
		var originalModeRender = mode.renderWidget;
		mode.renderWidget = function() { return E('div', { 'class': 'myupdate-field-mode' }, [ originalModeRender.apply(this, arguments) ]); };

		var autoTime = s.option(form.Value, 'auto_upgrade_time', _('升级时间'));
		autoTime.default = '03:30';
		autoTime.datatype = 'time';
		autoTime.description = _('路由器本地时间；仅自动升级模式生效，每天执行一次。');
		var originalAutoTimeRender = autoTime.renderWidget;
		autoTime.renderWidget = function() { return E('div', { 'class': 'myupdate-field-time' }, [ originalAutoTimeRender.apply(this, arguments) ]); };

		var pubkey = s.option(form.TextValue, 'minisign_public_key', _('Minisign 公钥'));
		pubkey.rows = 2;
		pubkey.monospace = true;
		pubkey.optional = true;
		pubkey.rmempty = true;
		pubkey.description = _('输入匹配的 Minisign 公钥验证，验证通过后才允许继续升级；如为 minisign.pub 两行内容，点击“识别并转换”按钮后保存。');

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
		var initialKeepPathValues = (cfg.custom_keep_paths || []).slice();
		var keepPathValues = initialKeepPathValues.slice();
		var keepPaths = s.option(form.DynamicList, 'custom_keep_paths', _('自定义文件保留路径'));
		keepPaths.optional = true;
		keepPaths.rmempty = true;
		// Keep the original UCI value immutable for LuCI's dirty-state comparison.
		// formvalue() below returns the staged value, while cfgvalue() must keep
		// returning the value loaded when the page was rendered.
		keepPaths.cfgvalue = function() { return initialKeepPathValues.slice(); };
		keepPaths.formvalue = function() { return keepPathValues.slice(); };
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
		keepPaths.description = _('输入绝对路径后点击“添加”，或通过设备文件浏览器选择。📁 表示目录，📄 表示文件；悬停标签可查看完整路径。新增和删除仅暂存，点击底部“保存并应用”后生效。');
		keepPaths.renderWidget = function(section_id) {
			var input = E('textarea', { 'class': 'myupdate-path-batch-input', 'placeholder': _('手动输入绝对路径，每行一条'), 'rows': '2' });
			var chipsHeading = E('div', { 'class': 'myupdate-path-chips-heading' }, _('已添加保留项'));
			var chips = E('div', { 'class': 'myupdate-path-chips' });
			var message = E('div', { 'class': 'myupdate-path-hint', 'aria-live': 'polite' });
			var keepPathTypes = {};
			var browserToggle = E('button', { 'type': 'button', 'class': 'btn cbi-button myupdate-browser-toggle' }, _('浏览设备文件…'));
			var browserPanel = E('div', { 'class': 'myupdate-file-browser', style: 'display:none' });
			var browserPath = E('div', { 'class': 'myupdate-browser-path' }, '/');
			var browserList = E('div', { 'class': 'myupdate-browser-list' });
			var browserHint = E('div', { 'class': 'myupdate-browser-hint', 'aria-live': 'polite' });
			var currentPath = '/', browserLoaded = false, browserBusy = false;

			function stageKeepPaths(paths, successMessage) {
				keepPathValues = paths.slice();
				renderChips();
				refreshKeepPathTypes();
				message.textContent = successMessage || _('路径修改已暂存；点击“保存并应用”后才会写入配置。');
			}

			function renderChips() {
				while (chips.firstChild) chips.removeChild(chips.firstChild);
				keepPathValues.forEach(function(path) {
					var icon = keepPathTypes[path] == 'directory' ? '📁' : '📄';
					var remove = E('button', {
						'type': 'button',
						'class': 'btn cbi-button myupdate-path-chip-remove',
						'aria-label': _('删除 ') + path,
						'data-keep-path': path,
					}, '×');
					chips.appendChild(E('span', { 'class': 'myupdate-path-chip', 'title': path }, [
						E('span', { 'class': 'myupdate-path-chip-icon', 'aria-hidden': 'true' }, icon),
						E('span', { 'class': 'myupdate-path-chip-text' }, path.substring(path.lastIndexOf('/') + 1) || path),
						remove
					]));
				});
			}

			function refreshKeepPathTypes() {
				var parents = [];
				keepPathValues.forEach(function(path) {
					if (keepPathTypes[path]) return;
					var slash = path.lastIndexOf('/');
					var parent = slash <= 0 ? '/' : path.substring(0, slash);
					if (parents.indexOf(parent) < 0) parents.push(parent);
				});
				parents.forEach(function(parent) {
					callListKeepPaths(parent).then(function(result) {
						if (!result || !result.ok) return;
						(result.entries || []).forEach(function(entry) {
							keepPathTypes[entry.path] = entry.type;
						});
						renderChips();
					}).catch(function() {});
				});
			}
			// Capture the click on the chip container instead of relying on LuCI's
			// dynamically-created button event binding.
			chips.addEventListener('click', function(ev) {
				var chip = ev.target;
				while (chip && chip != chips && !(chip.classList && chip.classList.contains('myupdate-path-chip')))
					chip = chip.parentNode;
				if (!chip || chip == chips) return;
				var remove = chip.querySelector('.myupdate-path-chip-remove');
				if (!remove) return;
				var hitRemove = ev.target == remove || remove.contains(ev.target);
				if (!hitRemove) return;
				ev.preventDefault();
				ev.stopPropagation();
				var path = remove.getAttribute('data-keep-path');
				if (!path || keepPathValues.indexOf(path) < 0) return;
				var next = keepPathValues.filter(function(item) { return item != path; });
				stageKeepPaths(next, _('已删除路径；点击“保存并应用”后生效。'));
			}, true);
			function allowedPath(path) {
				return /^\/[A-Za-z0-9._/@+-]+$/.test(path) && path != '/' &&
					!/(^|\/)\.\.?($|\/)/.test(path) &&
					!/^\/(proc|sys|dev|tmp|rom|overlay)(\/|$)/.test(path);
			}
			function addPaths(raw) {
				var items = String(raw || '').split(/[\n,，]+/).map(function(v) { return v.trim(); }).filter(Boolean);
				var next = keepPathValues.slice(), added = 0, invalid = [];
				items.forEach(function(path) {
					if (!allowedPath(path)) { invalid.push(path); return; }
					if (next.indexOf(path) < 0) { next.push(path); added++; }
				});
				if (invalid.length) {
					message.textContent = _('以下路径格式无效或不允许保留：') + ' ' + invalid.join(', ');
					return;
				}
				if (!added) {
					message.textContent = _('没有新增路径（可能已存在或输入为空）。');
					return;
				}
				stageKeepPaths(next, _('已暂存新增 ') + added + _(' 个路径；点击“保存并应用”后生效。'));
				input.value = '';
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
							click: function(ev) {
								ev.preventDefault();
								ev.stopPropagation();
								browserPanel.style.display = '';
								browserToggle.textContent = _('收起文件浏览器');
								loadDirectory(entry.path);
							} }, [
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
				browserPanel.style.display = '';
				browserToggle.textContent = _('收起文件浏览器');
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
			browserPanel.addEventListener('click', function(ev) { ev.stopPropagation(); });
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
			var leftPane = E('div', { 'class': 'myupdate-path-left' }, [
				E('div', { 'class': 'myupdate-path-entry-row' }, [ input, addButton ]),
				browserToggle,
				browserPanel
			]);
			var rightPane = E('div', { 'class': 'myupdate-path-right' }, [
				chipsHeading,
				chips,
				message
			]);
			var editor = E('div', { 'class': 'myupdate-path-editor' }, [ leftPane, rightPane ]);
			refreshKeepPathTypes();
			return editor;
		};

		var statusText = E('div', { id: 'myupdate-status', 'class': 'myupdate-status-message' });
		var progressFill = E('div', { 'class': 'myupdate-progress-fill' });
		var progressLabel = E('div', { 'class': 'myupdate-progress-label' }, '0%');
		var progressPanel = E('div', { 'class': 'myupdate-progress', style: 'display:none' }, [
			E('div', { 'class': 'myupdate-progress-track' }, [ progressFill ]),
			progressLabel
		]);
		var downgrade = s.option(form.Flag, 'allow_downgrade', _('允许降级'));
		downgrade.default = '0';
		downgrade.rmempty = false;
		downgrade.description = _('默认关闭；开启后允许安装低于当前版本的固件。点击“保存并应用”后生效。');

		var statusPanel = E('section', { 'class': 'myupdate-status-panel' }, [
			E('div', { 'class': 'myupdate-status-heading' }, [ statusText ]),
			noticeNode,
			E('div', { 'class': 'myupdate-status-overview' }, [
				E('p', { 'class': 'myupdate-status-note' }, _('固件下载后验证 Minisign 签名、设备兼容和 SHA256。验证通过可升级，并按配置恢复，仅接受本项目生成的镜像。'))
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
					} }, _('执行升级')),
				]),
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
					var normalized = keyInput.value.replace(/\r?\n$/, '');
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
			var downgradeRow = mapNode.querySelector('.cbi-value:has([name*="allow_downgrade"])');
			var actionRow = statusPanel.querySelector('.myupdate-actions-primary');
			var actionSettings = E('div', { 'class': 'myupdate-action-settings' });
			var actionContainer = statusPanel.querySelector('.myupdate-actions');
			if (actionContainer) actionContainer.appendChild(actionSettings);
			if (downgradeRow && actionSettings) actionSettings.appendChild(downgradeRow);
			var modeRow = mapNode.querySelector('.cbi-value:has(.myupdate-field-mode)');
			var timeRow = mapNode.querySelector('.cbi-value:has(.myupdate-field-time)');
			if (modeRow && actionSettings) actionSettings.appendChild(modeRow);
			if (timeRow && actionSettings) actionSettings.appendChild(timeRow);
			var style = E('style', {}, `
				.myupdate-page{max-width:1440px;margin:0 auto;padding-bottom:18px}
				.myupdate-hero{position:static!important;top:auto!important;z-index:auto!important}
				.myupdate-hero{display:flex;align-items:center;gap:14px;margin:2px 0 10px;padding:12px 16px;border:1px solid var(--border-color-medium,#d7dee7);border-radius:12px;background:linear-gradient(115deg,var(--background-color-high,#fff),var(--background-color,#f5f7fa));}
				.myupdate-hero-mark{display:flex;align-items:center;justify-content:center;flex:0 0 58px;height:58px;border-radius:14px;background:var(--primary-color,#2563eb);color:#fff;font-size:17px;font-weight:800;letter-spacing:.04em;box-shadow:0 5px 16px rgba(37,99,235,.18)}
				.myupdate-hero-copy{min-width:0}
				.myupdate-hero-eyebrow,.myupdate-status-kicker{display:block;margin-bottom:4px;color:var(--gray-color-medium,#778397);font-size:10px;font-weight:800;letter-spacing:.14em}
				.myupdate-hero h2{margin:0;color:var(--text-color-high,#1f2937);font-size:1.65rem;font-weight:750;letter-spacing:-.025em}
				.myupdate-hero p{margin:5px 0 0;color:var(--gray-color-medium,#697586);line-height:1.55}
				.myupdate-status-panel{border:1px solid var(--border-color-medium,#d5dce5);border-radius:10px;background:var(--background-color-high,#fff);padding:12px 16px;margin:0 0 10px;box-shadow:0 5px 18px rgba(15,23,42,.045)}
				.myupdate-status-heading{display:flex;align-items:center;gap:12px;margin-bottom:8px}
				.myupdate-status-title h3{flex:0 0 auto}
				.myupdate-status-message{min-width:0;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;line-height:1.35}
				.myupdate-status-overview{display:block}
				.myupdate-status-note{margin:0 0 8px;padding:5px 8px;line-height:1.35}
				.myupdate-actions-primary .cbi-value{display:inline-flex;align-items:center;margin:0;padding:0;border:0}
				.myupdate-actions-primary .cbi-value-title{display:none}
				.myupdate-actions-primary .cbi-value-field{padding:0}
				.myupdate-actions-primary .cbi-value-description{display:none}
				.myupdate-actions-primary .cbi-value label{margin:0}
				.myupdate-status-title h3{margin:0;font-size:1.18rem;font-weight:750}
				.myupdate-status-kicker{margin-bottom:3px}
				.myupdate-status-caption{font-size:.85em;color:var(--gray-color-medium,#778397)}
				.myupdate-inline-notice{margin:0 0 14px;padding:10px 13px;border-radius:7px;font-weight:600;line-height:1.55;overflow-wrap:anywhere}
				.myupdate-inline-notice.notice-info{background:var(--info-bg,#eff6ff);color:var(--info-color,#1d4ed8);border:1px solid rgba(59,130,246,.22)}
				.myupdate-inline-notice.notice-error{background:var(--error-bg,#fef2f2);color:var(--error-color,#b91c1c);border:1px solid rgba(220,38,38,.22)}
				.myupdate-status-overview{display:grid;grid-template-columns:minmax(0,1.15fr) minmax(220px,.85fr);gap:12px;align-items:stretch}
				.myupdate-status-message{display:flex;align-items:center;min-height:48px;padding:9px 12px;border:1px solid var(--border-color-medium,#e0e6ed);border-left:4px solid #94a3b8;border-radius:8px;background:var(--background-color,#f7f9fc);color:var(--text-color-high,#334155);font-weight:650;line-height:1.65;overflow-wrap:anywhere}
				.myupdate-status-message.state-checked,.myupdate-status-message.state-downloaded,.myupdate-status-message.state-current{background:rgba(22,163,74,.07);color:var(--success-color,#166534);border-left-color:#16a34a}
				.myupdate-status-message.state-downloading,.myupdate-status-message.state-running,.myupdate-status-message.state-verifying{background:rgba(37,99,235,.07);color:var(--info-color,#1d4ed8);border-left-color:#3b82f6}
				.myupdate-status-message.state-error{background:rgba(220,38,38,.07);color:var(--error-color,#b91c1c);border-left-color:#dc2626}
				.myupdate-status-message.state-upgrading{background:rgba(234,88,12,.08);color:var(--warning-color,#c2410c);border-left-color:#f97316}
				.myupdate-status-note{display:flex;align-items:center;margin:0;padding:8px 10px;border:1px solid var(--border-color-low,#e7ebf0);border-radius:8px;background:var(--background-color,#fafbfc);color:var(--gray-color-medium,#687385);font-size:.9em;line-height:1.7}
				.myupdate-actions{display:flex;flex-direction:column;gap:8px;margin-top:10px;padding-top:9px;border-top:1px solid var(--border-color-low,#e6eaf0)}
				.myupdate-actions-primary,.myupdate-actions-final{display:flex;align-items:center;flex-wrap:wrap;gap:10px}
				.myupdate-actions-primary .btn{min-width:118px;min-height:32px;padding-top:5px;padding-bottom:5px}
				.myupdate-actions-final{justify-content:flex-end}
				.myupdate-downgrade-row{display:flex;align-items:center;flex-wrap:wrap;gap:10px;padding:0 0 2px;border:0}
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
				.myupdate-settings-intro{margin:0 0 4px;padding:0 2px}
				.myupdate-settings-intro h3{margin:0;font-size:1.2rem;font-weight:750}
				.myupdate-settings-intro p{margin:4px 0 0;color:var(--gray-color-medium,#6b7280);font-size:.92em;line-height:1.6}
				.myupdate-page .cbi-section{margin-top:6px;padding:8px 14px 10px;border:1px solid var(--border-color-medium,#d8dee7);border-radius:11px;background:var(--background-color-high,#fff);box-shadow:0 3px 12px rgba(15,23,42,.025)}
				.myupdate-page .cbi-value{padding:8px 0;border-bottom:1px solid var(--border-color-low,#edf0f4)}
				.myupdate-page .cbi-value:last-child{border-bottom:0}
				.myupdate-page .cbi-value-title{padding-top:5px;color:var(--text-color-high,#344054);font-weight:650}
				.myupdate-page .cbi-value-field{min-width:0}
				.myupdate-page input:not([type=checkbox]),.myupdate-page select,.myupdate-page textarea{border-radius:6px}
				.myupdate-page input:focus,.myupdate-page select:focus,.myupdate-page textarea:focus{outline:2px solid rgba(37,99,235,.18);outline-offset:1px}
				.myupdate-page .cbi-value-description{margin-top:5px;color:var(--gray-color-medium,#748094);font-size:.88em;line-height:1.5}
				.myupdate-page .cbi-value:has(.myupdate-settings-heading){padding:10px 0 5px;border-bottom:0}
				.myupdate-page .cbi-value:has(.myupdate-settings-heading) .cbi-value-title{display:none}
				.myupdate-repo-input{width:min(100%,680px);max-width:680px}
				.myupdate-repo-input input{width:100%;max-width:100%;box-sizing:border-box}
				.myupdate-field-token input{width:150%;max-width:480px;box-sizing:border-box}
				.myupdate-action-settings{display:flex;align-items:flex-start;flex-wrap:wrap;gap:8px 18px;margin-top:8px;padding-top:9px;border-top:1px solid var(--border-color-low,#edf0f4)}
				.myupdate-action-settings>.cbi-value:has(.myupdate-field-downgrade){display:block;flex:0 0 100%;width:100%;margin:0;padding:0}
				.myupdate-action-settings>.cbi-value:has(.myupdate-field-mode){display:inline-flex;align-items:flex-start;flex:0 1 260px;width:auto;margin:0;padding:0}
				.myupdate-action-settings>.cbi-value:has(.myupdate-field-time){display:inline-flex;align-items:flex-start;flex:0 1 220px;width:auto;margin:0;padding:0}
				.myupdate-action-settings .cbi-value-title{padding-top:4px}
				.myupdate-action-settings .cbi-value-field{min-width:0}
				.myupdate-action-settings .cbi-value-description{display:none}
				.myupdate-key-input-row{display:flex;align-items:center;gap:10px;width:min(100%,620px)}
				.myupdate-key-input textarea{min-height:2.5em!important;height:2.5em!important}
				.myupdate-key-input{flex:0 1 560px;max-width:560px;min-width:0}
				.myupdate-key-input textarea{width:100%;min-height:3.6em!important;height:3.6em!important;max-width:560px;white-space:pre-wrap;overflow-wrap:anywhere;word-break:break-all;resize:vertical}
				.myupdate-key-convert{display:flex;align-items:center;align-self:center;flex:0 0 auto}
				.myupdate-settings-heading{padding:0 0 6px;border-bottom:1px solid var(--border-color-medium,#dce2e9)}
				.myupdate-settings-heading h3{margin:0;color:var(--text-color-high,#253246);font-size:1.02rem;font-weight:750}
				.myupdate-settings-heading p{margin:4px 0 0;color:var(--gray-color-medium,#748094);font-size:.88em;line-height:1.5}
				#myupdate-status{min-width:0}
				#myupdate-status + div{margin-top:8px}
				.myupdate-repo-input{width:100%;max-width:293px}
				.myupdate-page .cbi-value:has(.myupdate-repo-input){display:inline-block;vertical-align:top;width:34%;padding-right:10px;box-sizing:border-box}
				.myupdate-page .cbi-value:has(.myupdate-field-visibility){display:inline-block;vertical-align:top;width:16%;padding-right:10px;box-sizing:border-box}
				.myupdate-page .cbi-value:has(.myupdate-field-token){display:inline-block;vertical-align:top;width:49%;box-sizing:border-box}
				.myupdate-page .cbi-value:has(.myupdate-field-mode){display:inline-block;vertical-align:top;width:34%;padding-right:10px;box-sizing:border-box}
				.myupdate-page .cbi-value:has(.myupdate-field-time){display:inline-block;vertical-align:top;width:30%;box-sizing:border-box}
				.myupdate-page .cbi-value:has(.myupdate-field-mode) .cbi-value-description,.myupdate-page .cbi-value:has(.myupdate-field-time) .cbi-value-description{display:none}
				.myupdate-page .cbi-value:has(.myupdate-key-input-row){padding-top:2px}
				.myupdate-page .cbi-value:has(.myupdate-key-input-row) .cbi-value-title{padding-top:0}
				.myupdate-field-visibility select{width:100%;max-width:72px}
				.myupdate-field-mode select{width:100%;max-width:96px}
				.myupdate-field-time input{width:100%;max-width:92px}
				.myupdate-field-downgrade .cbi-value-description{margin-top:3px}
				.myupdate-field-downgrade input{margin-right:7px}
				.myupdate-repo-input input{width:100%;max-width:100%;box-sizing:border-box}
				.myupdate-key-input-row{display:flex;align-items:center;gap:10px;width:min(100%,620px)}
				.myupdate-key-input{flex:0 1 560px;max-width:560px;min-width:0}
				.myupdate-key-input textarea{width:100%;min-height:3.6em!important;height:3.6em!important;max-width:560px;white-space:pre-wrap;overflow-wrap:anywhere;word-break:break-all;resize:vertical}
				.myupdate-key-convert{display:flex;align-items:center;align-self:center;flex:0 0 auto}
				.myupdate-path-editor{display:grid;grid-template-columns:minmax(0,1fr) minmax(0,1fr);gap:18px;width:100%;max-width:none;box-sizing:border-box;align-items:start}
				.myupdate-path-left,.myupdate-path-right{min-width:0}
				.myupdate-path-entry-row{display:flex;align-items:center;gap:8px;width:100%;max-width:none;box-sizing:border-box}
				.myupdate-path-batch-input{flex:1;min-width:0;width:100%;height:4.2em!important;min-height:4.2em!important;resize:vertical}
				.myupdate-path-manual-add{align-self:center;min-width:0;padding:5px 12px}
				.myupdate-browser-toggle{margin-top:8px}
				.myupdate-file-browser{width:100%;max-width:680px;box-sizing:border-box;margin-top:8px;border:1px solid var(--border-color-medium,#d8dee7);border-radius:8px;padding:10px;background:var(--background-color,#fafbfc)}
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
				.myupdate-path-chips-heading{margin:0 0 8px;font-weight:650;color:var(--text-color-high,#344054)}
				.myupdate-path-chips{display:flex;flex-wrap:wrap;align-content:flex-start;align-items:flex-start;gap:7px;margin:0;width:100%;box-sizing:border-box}
				.myupdate-path-hint{min-height:1.5em;margin-top:8px;color:var(--gray-color-medium,#778397);font-size:.9em}
				.myupdate-path-chip{position:relative;display:inline-flex;align-items:center;gap:5px;flex:0 1 auto;width:auto;max-width:100%;box-sizing:border-box;padding:5px 7px;border-radius:6px;background:var(--background-color,#f6f8fa);border:1px solid var(--border-color-medium,#dce2e9);transition:background-color .15s ease,border-color .15s ease,box-shadow .15s ease}
				.myupdate-path-chip:hover,.myupdate-path-chip:focus-within{background:var(--background-color-high,#fff);border-color:var(--primary-color,#2563eb);box-shadow:0 0 0 2px rgba(37,99,235,.10)}
				.myupdate-path-chip-text{flex:0 1 auto;min-width:0;max-width:150px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;font-size:.92em}
				.myupdate-path-chip-icon{flex:0 0 auto}
				.myupdate-path-chip-remove{position:relative;z-index:2;display:inline-flex;align-items:center;justify-content:center;flex:0 0 18px;width:18px;height:18px;min-width:18px;min-height:18px;max-height:18px;box-sizing:border-box;margin:0;padding:0;border:0;border-radius:5px;background:transparent;color:var(--gray-color-high,#555);font-size:1.05em;line-height:1;cursor:pointer;pointer-events:auto;touch-action:manipulation;transition:background-color .15s ease,color .15s ease}
				.myupdate-path-chip-remove:hover,.myupdate-path-chip-remove:focus-visible{background:rgba(220,38,38,.12);color:#dc2626;outline:2px solid rgba(220,38,38,.18);outline-offset:1px}
				.myupdate-path-chip-remove:disabled{cursor:wait;opacity:.55}
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
					.myupdate-page .cbi-value{display:block;padding:8px 0}
					.myupdate-page .cbi-value-title{display:block;padding:0 0 5px}
					.myupdate-key-input-row,.myupdate-path-entry-row{flex-direction:row}
					.myupdate-field-token input{width:100%;max-width:100%}
					.myupdate-action-settings{gap:8px 12px}
					.myupdate-path-editor{grid-template-columns:minmax(0,1fr) minmax(0,1fr);gap:12px}
					.myupdate-key-convert .btn{width:auto}
					.myupdate-path-manual-add{align-self:center}
					.myupdate-browser-toolbar{align-items:flex-start;flex-direction:column}
				}
				@media(max-width:420px){
					.myupdate-hero-mark{display:none}
					.myupdate-actions-primary{grid-template-columns:1fr}

					.myupdate-key-input-row{flex-direction:column}
					.myupdate-key-convert .btn{width:100%}
					.myupdate-path-editor{grid-template-columns:1fr}
					.myupdate-path-entry-row{align-items:center}
					.myupdate-path-batch-input{min-width:0}
				}
			`);
			return E('div', { 'class': 'cbi-map myupdate-page' }, [
				style,
				E('div', { 'class': 'myupdate-hero' }, [
					E('div', { 'class': 'myupdate-hero-mark', 'aria-hidden': 'true' }, 'OTA'),
					E('div', { 'class': 'myupdate-hero-copy' }, [
						E('span', { 'class': 'myupdate-hero-eyebrow' }, _('SYSTEM MAINTENANCE')),
						E('h2', _('固件在线升级')),
						E('p', _('固件下载后验证 Minisign 签名、设备兼容和 SHA256。验证通过可升级，并按配置恢复，仅接受本项目生成的镜像。'))
					])
				]),
				statusPanel,
				mapNode
			]);
		});
	}
});

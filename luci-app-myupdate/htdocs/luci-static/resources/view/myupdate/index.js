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

		addSettingsHeading('_heading_repo', _('仓库与访问设置'), _('填写 GitHub 仓库地址；公开仓库无需 Token，私有仓库才需要访问令牌。'));
		var repo = s.option(form.Value, 'repo_url', _('GitHub 仓库地址'));
		repo.placeholder = 'https://github.com/OWNER/REPO';
		repo.description = _('HTTPS 地址，例如 github.com/OWNER/REPO。');
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
		visibility.description = _('公开无需 Token；私有仓库需填写。');
		var originalVisibilityRender = visibility.renderWidget;
		visibility.renderWidget = function() { return E('div', { 'class': 'myupdate-field-visibility' }, [ originalVisibilityRender.apply(this, arguments) ]); };

		var token = s.option(form.Value, '_github_token', _('GitHub Token'));
		token.password = true;
		token.rmempty = true;
		token.optional = true;
		// Token visibility is managed by the fixed three-column layout.
		token.placeholder = cfg.token_configured ? _('已配置；留空则保持当前 Token') : _('私有仓库必填');
		token.description = _('建议使用 Fine-grained PAT，仅授予目标仓库 Contents: Read-only。');
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

		addSettingsHeading('_heading_verify', _('固件签名验证'), _('配置项目对应的 Minisign 公钥；只有签名、设备兼容性和 SHA256 校验通过才允许升级。'));
		var pubkey = s.option(form.TextValue, 'minisign_public_key', _('Minisign 公钥'));
		pubkey.rows = 2;
		pubkey.monospace = true;
		pubkey.optional = true;
		pubkey.rmempty = true;
		pubkey.description = _('粘贴 Minisign 公钥；两行格式可点“识别并转换”。');

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
		keepPaths.description = _('手动输入绝对路径或浏览选择；📁 为目录、📄 为文件，悬停标签查看完整路径。增删后统一点击底部“保存并应用”。');
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
				E('div', { 'class': 'myupdate-path-left-heading' }, _('自定义文件保留路径')),
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
		downgrade.description = _('默认关闭；开启后允许安装低于当前版本的固件。');
		var originalDowngradeRender = downgrade.renderWidget;
		downgrade.renderWidget = function() {
			return E('div', { 'class': 'myupdate-field-downgrade' }, [ originalDowngradeRender.apply(this, arguments) ]);
		};

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
					} }, _('下载验证')),
					E('button', { 'class': 'btn cbi-button cbi-button-negative myupdate-upgrade-button', click: function() {
						if (!confirm(_('确定升级吗？设备将执行保留系统配置的升级并自动重启。建议提前备份重要配置，并确保有本地或带外访问方式。'))) return;
						return reportTaskStart(callUpgrade(), _('升级任务启动失败，请先下载并验证固件'), notify);
					} }, _('执行升级')),
					E('div', { 'class': 'myupdate-action-controls' }),
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
			// Keep every staged CBI control inside LuCI's original form. Moving
			// rows into a sibling status panel detaches them from form submission.
			var mapForm = mapNode.tagName == 'FORM' ? mapNode : mapNode.querySelector('form');
			var formContainer = mapForm || mapNode;
			var firstSection = formContainer.querySelector('.cbi-section');
			if (firstSection && firstSection.parentNode == formContainer)
				formContainer.insertBefore(statusPanel, firstSection);
			else
				formContainer.insertBefore(statusPanel, formContainer.firstChild);

			var primaryActions = statusPanel.querySelector('.myupdate-actions-primary');
			var actionControls = statusPanel.querySelector('.myupdate-action-controls');
			var downgradeWidget = mapNode.querySelector('.myupdate-field-downgrade');
			var downgradeRow = downgradeWidget && downgradeWidget.closest('.cbi-value');
			var modeRow = mapNode.querySelector('.cbi-value:has(.myupdate-field-mode)');
			var timeRow = mapNode.querySelector('.cbi-value:has(.myupdate-field-time)');
			if (primaryActions && actionControls) {
				var downgradeControls = E('div', { 'class': 'myupdate-downgrade-controls' });
				var scheduleControls = E('div', { 'class': 'myupdate-schedule-controls' });
				actionControls.appendChild(downgradeControls);
				actionControls.appendChild(scheduleControls);
				if (downgradeRow && formContainer.contains(downgradeRow)) {
					downgradeRow.classList.add('myupdate-downgrade-row');
					downgradeControls.appendChild(downgradeRow);
				}
				[ modeRow, timeRow ].forEach(function(row) {
					if (!row || !formContainer.contains(row)) return;
					row.classList.add('myupdate-inline-control');
					scheduleControls.appendChild(row);
				});
			}

			var repoRow = mapNode.querySelector('.cbi-value:has(.myupdate-repo-input)');
			var visibilityRow = mapNode.querySelector('.cbi-value:has(.myupdate-field-visibility)');
			var tokenRow = mapNode.querySelector('.cbi-value:has(.myupdate-field-token)');
			if (repoRow && visibilityRow && tokenRow && repoRow.parentNode == visibilityRow.parentNode && repoRow.parentNode == tokenRow.parentNode) {
				var repoGrid = E('div', { 'class': 'myupdate-repo-grid' });
				repoRow.parentNode.insertBefore(repoGrid, repoRow);
				[ repoRow, visibilityRow, tokenRow ].forEach(function(row) {
					row.classList.add('myupdate-repo-grid-cell');
					repoGrid.appendChild(row);
				});
			}

			var visibilitySelect = mapNode.querySelector('.myupdate-field-visibility select');
			if (visibilitySelect && tokenRow) {
				var syncTokenVisibility = function() {
					var isPrivate = visibilitySelect.value == 'private';
					tokenRow.classList.toggle('myupdate-token-visible', isPrivate);
					tokenRow.classList.toggle('myupdate-token-hidden', !isPrivate);
					tokenRow.setAttribute('aria-hidden', isPrivate ? 'false' : 'true');
				};
				visibilitySelect.addEventListener('change', syncTokenVisibility);
				visibilitySelect.addEventListener('input', syncTokenVisibility);
				syncTokenVisibility();
			}
			var style = E('style', {}, `
				.myupdate-page{max-width:1440px;margin:0 auto;padding-bottom:18px}
				.myupdate-hero{position:static!important;display:flex;align-items:center;gap:14px;margin:2px 0 10px;padding:12px 16px;border:1px solid var(--border-color-medium,#d7dee7);border-radius:12px;background:linear-gradient(115deg,var(--background-color-high,#fff),var(--background-color,#f5f7fa))}
				.myupdate-hero-mark{display:flex;align-items:center;justify-content:center;flex:0 0 58px;height:58px;border-radius:14px;background:var(--primary-color,#2563eb);color:#fff;font-size:17px;font-weight:800;letter-spacing:.04em;box-shadow:0 5px 16px rgba(37,99,235,.18)}
				.myupdate-hero-copy{min-width:0}
				.myupdate-hero-eyebrow{display:block;margin-bottom:4px;color:var(--gray-color-medium,#778397);font-size:10px;font-weight:800;letter-spacing:.14em}
				.myupdate-hero h2{margin:0;color:var(--text-color-high,#1f2937);font-size:1.65rem;font-weight:750;letter-spacing:-.025em}
				.myupdate-hero p{margin:5px 0 0;color:var(--gray-color-medium,#697586);line-height:1.55}
				.myupdate-status-panel{margin:0 0 10px;padding:12px 16px;border:1px solid var(--border-color-medium,#d5dce5);border-radius:10px;background:var(--background-color-high,#fff);box-shadow:0 5px 18px rgba(15,23,42,.045)}
				.myupdate-status-heading{display:flex;align-items:center;gap:12px;margin-bottom:8px}
				.myupdate-status-message{display:flex;align-items:center;min-width:0;min-height:42px;padding:8px 11px;border:1px solid var(--border-color-medium,#e0e6ed);border-left:4px solid #94a3b8;border-radius:8px;background:var(--background-color,#f7f9fc);color:var(--text-color-high,#334155);font-weight:650;line-height:1.5;overflow-wrap:anywhere}
				.myupdate-status-message.state-checked,.myupdate-status-message.state-downloaded,.myupdate-status-message.state-current{background:rgba(22,163,74,.07);color:var(--success-color,#166534);border-left-color:#16a34a}
				.myupdate-status-message.state-downloading,.myupdate-status-message.state-running,.myupdate-status-message.state-verifying{background:rgba(37,99,235,.07);color:var(--info-color,#1d4ed8);border-left-color:#3b82f6}
				.myupdate-status-message.state-error{background:rgba(220,38,38,.07);color:var(--error-color,#b91c1c);border-left-color:#dc2626}
				.myupdate-status-message.state-upgrading{background:rgba(234,88,12,.08);color:var(--warning-color,#c2410c);border-left-color:#f97316}
				.myupdate-status-note{display:flex;align-items:center;margin:0;padding:6px 9px;border:1px solid var(--border-color-low,#e7ebf0);border-radius:7px;background:var(--background-color,#fafbfc);color:var(--gray-color-medium,#687385);font-size:.88em;line-height:1.45}
				.myupdate-inline-notice{margin:0 0 10px;padding:9px 12px;border-radius:7px;font-weight:600;line-height:1.5;overflow-wrap:anywhere}
				.myupdate-inline-notice.notice-info{background:var(--info-bg,#eff6ff);color:var(--info-color,#1d4ed8);border:1px solid rgba(59,130,246,.22)}
				.myupdate-inline-notice.notice-error{background:var(--error-bg,#fef2f2);color:var(--error-color,#b91c1c);border:1px solid rgba(220,38,38,.22)}
				.myupdate-actions{display:block;margin-top:9px;padding-top:8px;border-top:1px solid var(--border-color-low,#e6eaf0)}
				.myupdate-actions-primary{display:flex;align-items:flex-end;flex-wrap:wrap;gap:8px}
				.myupdate-actions-final{display:flex;justify-content:flex-end}
				.myupdate-actions-primary>.btn{flex:0 0 auto;min-width:104px;min-height:38px;padding:6px 13px;border:0;border-radius:7px;font-weight:700;box-shadow:0 2px 5px rgba(15,23,42,.12)}.myupdate-actions-primary>.cbi-button-action{background:#1673e6!important;color:#fff!important}.myupdate-actions-primary>.cbi-button-positive{background:#16a34a!important;color:#fff!important}.myupdate-actions-primary>.myupdate-upgrade-button{background:#ef5548!important;color:#fff!important}
				.myupdate-action-controls{display:flex;flex:1 1 100%;flex-direction:column;align-items:stretch;min-width:0;gap:8px;margin:8px 0 0}
				.myupdate-downgrade-controls{display:block;width:100%;padding:2px 0 5px;border-bottom:1px solid var(--border-color-low,#edf0f4)}
				.myupdate-downgrade-row{display:flex!important;align-items:center;gap:10px;width:100%;margin:0!important;padding:0!important;border:0!important}
				.myupdate-downgrade-row .cbi-value-title{display:block!important;float:none!important;flex:0 0 auto;width:auto!important;margin:0!important;padding:0!important;color:var(--text-color-high,#344054);font-size:.9em;font-weight:700;line-height:1.3;white-space:nowrap}
				.myupdate-downgrade-row .cbi-value-field{display:flex!important;flex:1 1 auto;align-items:center;flex-wrap:wrap;gap:8px;width:auto!important;min-width:0;margin:0!important;padding:0!important}
				.myupdate-downgrade-row .myupdate-field-downgrade{display:inline-flex;align-items:center;margin:0}
				.myupdate-downgrade-row .myupdate-field-downgrade input{margin:0;width:17px;height:17px}
				.myupdate-downgrade-row .cbi-value-description{display:block;flex:1 1 260px;min-width:200px;margin:0!important;padding:0!important;color:var(--gray-color-medium,#778397);font-size:.8em;line-height:1.35}
				.myupdate-schedule-controls{display:flex;align-items:flex-start;flex-wrap:wrap;gap:18px;width:100%}
				.myupdate-schedule-controls>.myupdate-inline-control{display:flex!important;flex:0 0 auto!important;flex-direction:column;align-items:flex-start;gap:4px;width:auto!important;min-width:0;max-width:none;margin:0!important;padding:0 2px!important;border:0!important}
				.myupdate-schedule-controls>.myupdate-inline-control .cbi-value-title{display:block!important;float:none!important;width:auto!important;margin:0!important;padding:0 0 3px!important;color:var(--text-color-high,#344054);font-size:.9em;font-weight:700;line-height:1.25;white-space:nowrap;text-align:left}
				.myupdate-schedule-controls>.myupdate-inline-control .cbi-value-field{display:block!important;float:none!important;width:auto!important;min-width:0;margin:0!important;padding:0!important}
				.myupdate-schedule-controls>.myupdate-inline-control .cbi-value-description{display:none}
				.myupdate-schedule-controls>.myupdate-inline-control .cbi-value-field select,.myupdate-schedule-controls>.myupdate-inline-control .cbi-value-field input{height:36px;min-height:36px;border:1px solid var(--border-color-medium,#cbd5e1);border-radius:7px;padding:5px 9px;background:var(--background-color-high,#fff);box-shadow:inset 0 1px 2px rgba(15,23,42,.04)}
				.myupdate-field-mode select{width:112px;max-width:112px}
				.myupdate-field-time input{width:100px;max-width:100px}
				.myupdate-field-downgrade input{margin:0}
				.myupdate-progress{margin-top:12px;padding:12px 14px;border:1px solid var(--border-color-low,#e4e9ef);border-radius:8px;background:var(--background-color,#fafbfc)}
				.myupdate-progress-track{height:9px;border-radius:20px;background:var(--border-color-low,#e5eaf0);overflow:hidden}
				.myupdate-progress-fill{height:100%;width:0;background:linear-gradient(90deg,#2563eb,#0d9488);border-radius:20px;transition:width .35s ease}
				.myupdate-progress-label{margin-top:7px;text-align:right;font-size:.85em;color:var(--gray-color-medium,#64748b);font-variant-numeric:tabular-nums}
				.myupdate-page .cbi-section{margin-top:7px;padding:8px 14px 10px;border:1px solid var(--border-color-medium,#d8dee7);border-radius:11px;background:var(--background-color-high,#fff);box-shadow:0 3px 12px rgba(15,23,42,.025)}
				.myupdate-page .cbi-value{padding:7px 0;border-bottom:1px solid var(--border-color-low,#edf0f4)}
				.myupdate-page .cbi-value:last-child{border-bottom:0}
				.myupdate-page .cbi-value-title{padding-top:4px;color:var(--text-color-high,#344054);font-weight:650}
				.myupdate-page .cbi-value-field{min-width:0}
				.myupdate-page input:not([type=checkbox]),.myupdate-page select,.myupdate-page textarea{border-radius:6px}
				.myupdate-page input:focus,.myupdate-page select:focus,.myupdate-page textarea:focus{outline:2px solid rgba(37,99,235,.18);outline-offset:1px}
				.myupdate-page .cbi-value-description{margin-top:4px;color:var(--gray-color-medium,#748094);font-size:.82em;line-height:1.4}
				.myupdate-page .cbi-value:has(.myupdate-settings-heading){display:block;width:100%;margin:0;padding:9px 0 6px;border-bottom:0}
				.myupdate-page .cbi-value:has(.myupdate-settings-heading) .cbi-value-title{display:none}
				.myupdate-page .cbi-value:has(.myupdate-settings-heading) .cbi-value-field{display:block;width:100%;margin:0;padding:0}
				.myupdate-settings-heading{padding:0 0 6px;border-bottom:1px solid var(--border-color-medium,#dce2e9)}
				.myupdate-settings-heading h3{margin:0;color:var(--text-color-high,#253246);font-size:1.02rem;font-weight:750}
				.myupdate-settings-heading p{margin:4px 0 0;color:var(--gray-color-medium,#748094);font-size:.86em;line-height:1.4}
				.myupdate-repo-grid{display:grid;grid-template-columns:minmax(0,18fr) minmax(110px,10fr) minmax(0,72fr);gap:14px;width:100%;align-items:start}
				.myupdate-repo-grid>.cbi-value{display:block;width:auto;min-width:0;margin:0;padding:0 0 8px;border-bottom:1px solid var(--border-color-low,#edf0f4)}
				.myupdate-repo-grid>.cbi-value .cbi-value-title{display:block;float:none;width:auto;margin:0;padding:0 0 5px;text-align:left;white-space:nowrap}
				.myupdate-repo-grid>.cbi-value .cbi-value-field{display:block;float:none;width:100%;min-width:0;margin:0;padding:0}
				.myupdate-repo-grid>.cbi-value .cbi-value-description{margin-top:4px;font-size:.76em;line-height:1.25;white-space:nowrap}
				.myupdate-repo-grid>.cbi-value .myupdate-repo-input,.myupdate-repo-grid>.cbi-value .myupdate-field-token{display:block;width:100%;max-width:none}
				.myupdate-repo-grid>.cbi-value .myupdate-repo-input input,.myupdate-repo-grid>.cbi-value .myupdate-field-token input{display:block;width:100%;max-width:none;box-sizing:border-box}
				.myupdate-repo-grid>.myupdate-token-hidden{visibility:hidden}
				.myupdate-field-visibility select{width:100%;max-width:100px}
				.myupdate-key-input-row{display:flex;align-items:center;gap:10px;width:min(100%,620px);max-width:680px}
				.myupdate-key-input{flex:0 1 560px;max-width:560px;min-width:0}
				.myupdate-key-input textarea{width:100%;min-height:3.6em!important;height:3.6em!important;max-width:560px;white-space:pre-wrap;overflow-wrap:anywhere;word-break:break-all;resize:vertical}
				.myupdate-key-convert{display:flex;align-items:center;align-self:center;flex:0 0 auto}
				.myupdate-page .cbi-value:has(.myupdate-key-input-row){display:block;width:100%;padding-top:4px}
				.myupdate-page .cbi-value:has(.myupdate-key-input-row) .cbi-value-title{display:block;float:none;width:auto;padding:0 0 5px;text-align:left}
				.myupdate-page .cbi-value:has(.myupdate-key-input-row) .cbi-value-field{display:block;width:100%;margin:0;padding:0}
				.myupdate-repo-input{display:block;width:100%;max-width:none}
				.myupdate-field-token{display:block;width:100%;max-width:none}
				.myupdate-page .cbi-value:has(.myupdate-path-editor){display:block;width:100%;margin:0;padding:0}
				.myupdate-page .cbi-value:has(.myupdate-path-editor) .cbi-value-title{display:none}
				.myupdate-page .cbi-value:has(.myupdate-path-editor) .cbi-value-field{display:block;width:100%;margin:0;padding:0}
				.myupdate-path-editor{display:grid;grid-template-columns:minmax(0,calc(31% + 80px)) minmax(0,1fr);gap:12px;width:100%;max-width:none;box-sizing:border-box;align-items:start}
				.myupdate-path-left,.myupdate-path-right{min-width:0}
				.myupdate-path-left-heading{margin:0 0 7px;color:var(--text-color-high,#344054);font-weight:700;line-height:1.35}
				.myupdate-path-entry-row{display:flex;align-items:center;gap:8px;width:100%;max-width:none;box-sizing:border-box}
				.myupdate-path-batch-input{flex:1 1 auto;min-width:0;width:100%;height:4.2em!important;min-height:4.2em!important;resize:vertical}
				.myupdate-path-manual-add{flex:0 0 auto;align-self:center;min-width:0;padding:5px 12px}
				.myupdate-browser-toggle{margin-top:8px}
				.myupdate-file-browser{display:block;width:100%;max-width:none;box-sizing:border-box;margin-top:8px;padding:10px;border:1px solid var(--border-color-medium,#d8dee7);border-radius:8px;background:var(--background-color,#fafbfc)}
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
				.myupdate-path-chips-heading{margin:0 0 8px;color:var(--text-color-high,#344054);font-weight:650}
				.myupdate-path-chips{display:grid;grid-template-columns:repeat(auto-fill,168px);align-content:flex-start;justify-content:start;gap:7px;margin:0;width:100%;box-sizing:border-box}
				.myupdate-path-hint{min-height:1.5em;margin-top:8px;color:var(--gray-color-medium,#778397);font-size:.88em}
				.myupdate-path-chip{position:relative;display:inline-flex;align-items:center;gap:5px;flex:0 0 168px;width:168px;min-width:168px;max-width:168px;box-sizing:border-box;padding:5px 7px;border:1px solid var(--border-color-medium,#dce2e9);border-radius:6px;background:var(--background-color,#f6f8fa);transition:background-color .15s ease,border-color .15s ease,box-shadow .15s ease}
				.myupdate-path-chip:hover,.myupdate-path-chip:focus-within{background:var(--background-color-high,#fff);border-color:var(--primary-color,#2563eb);box-shadow:0 0 0 2px rgba(37,99,235,.10)}
				.myupdate-path-chip-text{flex:1 1 auto;min-width:0;max-width:none;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;font-size:.92em}
				.myupdate-path-chip-icon{flex:0 0 auto}
				.myupdate-path-chip-remove{position:relative;z-index:2;display:inline-flex;align-items:center;justify-content:center;flex:0 0 18px;width:18px;height:18px;min-width:18px;min-height:18px;max-height:18px;box-sizing:border-box;margin:0;padding:0;border:0;border-radius:5px;background:transparent;color:var(--gray-color-high,#555);font-size:1.05em;line-height:1;cursor:pointer;pointer-events:auto;touch-action:manipulation;transition:background-color .15s ease,color .15s ease}
				.myupdate-path-chip-remove:hover,.myupdate-path-chip-remove:focus-visible{background:rgba(220,38,38,.12);color:#dc2626;outline:2px solid rgba(220,38,38,.18);outline-offset:1px}
				.myupdate-path-chip-remove:disabled{cursor:wait;opacity:.55}
				@media(max-width:1000px){
					.myupdate-repo-grid{grid-template-columns:minmax(0,1fr) 120px}
					.myupdate-repo-grid>.cbi-value:has(.myupdate-field-token){grid-column:1/-1}
					.myupdate-repo-grid>.myupdate-token-hidden{display:none}
				}
				@media(max-width:767px){
					.myupdate-page{padding-bottom:20px}
					.myupdate-hero{align-items:flex-start;gap:12px;padding:14px}
					.myupdate-hero-mark{flex-basis:46px;height:46px;border-radius:11px;font-size:14px}
					.myupdate-hero h2{font-size:1.35rem}
					.myupdate-status-panel{padding:12px}
					.myupdate-actions-primary{align-items:flex-end;flex-wrap:wrap}.myupdate-action-controls{flex:1 1 100%;margin:8px 0 0}
					.myupdate-actions-primary>.btn{min-width:0}
					.myupdate-action-controls>.myupdate-inline-control:has(.myupdate-field-downgrade){padding-top:0!important}
					.myupdate-repo-grid{grid-template-columns:minmax(0,1fr)}
					.myupdate-repo-grid>.cbi-value:has(.myupdate-field-token){grid-column:auto}
					.myupdate-path-editor{grid-template-columns:minmax(0,1fr);gap:14px}
					.myupdate-path-chips{grid-template-columns:repeat(auto-fill,168px)}
					.myupdate-key-input-row,.myupdate-path-entry-row{flex-direction:row}
				}
				@media(max-width:420px){
					.myupdate-hero-mark{display:none}
					.myupdate-actions-primary{align-items:stretch;flex-wrap:wrap}.myupdate-action-controls{flex:1 1 100%;flex-wrap:wrap;margin:8px 0 0}
					.myupdate-actions-primary>.btn{flex:1 1 100%}
					.myupdate-path-entry-row{align-items:center}
					.myupdate-path-batch-input{min-width:0}
					.myupdate-key-input-row{flex-direction:column;align-items:stretch}
					.myupdate-key-convert .btn{width:100%}
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
				mapNode
			]);
		});
	}
});

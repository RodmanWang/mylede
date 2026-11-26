# LuCI MyUpdate

针对本项目发布的 x86_64 LEDE squashfs UEFI 固件的 GitHub Release 更新管理器。

## 支持范围

- 固件文件必须为 `openwrt-x86-64-generic-squashfs-combined-efi.img.gz`。
- 设备必须运行 x86/64、x86_64 架构、squashfs 根文件系统，并以 UEFI 启动。
- 使用 Release 中的 `manifest.json` 和 `manifest.minisig`。
- 下载前验证 Minisign 签名、设备兼容性、版本、资产名和大小；下载后验证文件大小及 SHA256。
- 新的分区容量保护要求 Manifest schema v2。旧 schema v1 Release 未记录编译分区大小，无法安全判断容量，因此不会被自动升级；安装支持 v2 的插件后，需要等待/发布带有分区元数据的新固件 Release。
- OTA Manifest 同时记录本次固件实际采用的内核/根文件系统分区大小、上游 x86 Kconfig 默认值、`USES_BOOT_PART` 状态及各源码仓库 commit。
- 下载固件前和执行升级前，均读取当前设备 `/rom` 对应的 x86 GPT 分区 1/2 实际容量；只有当前内核分区和根文件系统分区分别不小于目标固件要求时才允许继续。无法可靠识别当前分区布局时按不安全处理并拒绝自动刷写。
- 刷写前再次校验 SHA256，并执行 `sysupgrade -T`。
- 正式升级执行 `sysupgrade -v`，使用 LEDE 默认配置备份与恢复机制。实际恢复的文件取决于设备的 sysupgrade 配置备份规则。
- 手动模式：仅由用户点击按钮检查、下载和升级。
- 定时提示模式：按检查间隔自动检查更新，不自动下载或刷写。
- 自动升级模式：按路由器本地时间每天执行一次；发现新版本后自动检查、下载、验签、校验 SHA256、执行 `sysupgrade -T`，通过后执行 `sysupgrade -v` 并重启。默认计划时间为凌晨 04:00。

## 自定义文件保留

首次安装本固件后，可以在 LuCI「系统 → 固件在线升级」的自定义文件保留区域配置需要跨 OTA 升级保留的绝对路径。可以手动逐行输入，也可以展开设备文件浏览器，从根目录开始逐层浏览；每个普通文件或目录旁均提供独立的“添加”操作。符号链接、特殊文件及系统虚拟目录不会加入保留列表。

保存后，MyUpdate 会在执行 OTA 前将这些路径写入 `/etc/sysupgrade.conf` 的独立管理区块。随后仍由 OpenWrt/LEDE 的 `sysupgrade` 生成配置备份，并在新固件刷写后按官方备份恢复流程还原；不备份整个根目录。配置保留路径本身保存在 `/etc/config/myupdate`，使配置持续生效。

注意事项：

- 路径必须是绝对路径；每项一条。UCI 配置中会保存为多条 `list custom_keep_paths`，而不是一个包含换行符的 `option` 字符串。旧版本保存的多行字符串会在页面显示为多个项目，下次保存时转换为 UCI list。
只会把旧系统中实际存在的文件或目录加入本次备份。
- 不允许根目录及 `/proc`、`/sys`、`/dev`、`/tmp`、`/rom`、`/overlay` 等运行时或虚拟文件系统路径。
- 只应选择确实需要跨版本保留的自定义文件。若路径与新固件自带文件冲突，sysupgrade 的备份恢复可能覆盖新固件中的同路径文件。
- 此设置从首次安装并配置 MyUpdate 后开始生效；首次刷入固件时，MyUpdate 无法从原系统追溯尚未配置的自定义路径。
- `/etc/uci-defaults/` 中的脚本若被列入保留路径，会作为文件恢复；是否执行仍由系统的 uci-defaults 启动机制决定。不要假设旧脚本会自动再次执行。


## 测试状态

CI 会测试版本排序、Tag/Manifest 一致性、Minisign 正反向验签、x86_64 UEFI/squashfs 兼容性及分区容量边界；发布前会校验固件资产名、大小、SHA256、分区布局元数据和源码 SHA。GitHub API 实际下载、设备上的 `sysupgrade -T`、真实刷写与重启尚未在用户设备上验证。首次使用必须先在可恢复的测试设备上验证。

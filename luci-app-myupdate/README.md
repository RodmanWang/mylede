# LuCI MyUpdate

针对本项目发布的 x86_64 LEDE squashfs UEFI 固件的 GitHub Release 更新管理器。

## 支持范围

- 固件文件必须为 `openwrt-x86-64-generic-squashfs-combined-efi.img.gz`。
- 设备必须运行 x86/64、x86_64 架构、squashfs 根文件系统，并以 UEFI 启动。
- 使用 Release 中的 `manifest.json` 和 `manifest.minisig`。
- 下载前验证 Minisign 签名、设备兼容性、版本、资产名和大小；下载后验证文件大小及 SHA256。
- OTA Manifest 同时记录本次固件实际采用的内核/根文件系统分区大小、上游 x86 Kconfig 默认值、`USES_BOOT_PART` 状态及各源码仓库 commit。
- 下载固件前和执行升级前，均读取当前设备 `/rom` 对应的 x86 GPT 分区 1/2 实际容量；只有当前内核分区和根文件系统分区分别不小于目标固件要求时才允许继续。无法可靠识别当前分区布局时按不安全处理并拒绝自动刷写。
- 刷写前再次校验 SHA256，并执行 `sysupgrade -T`。
- 正式升级执行 `sysupgrade -v`，使用 LEDE 默认配置备份与恢复机制。实际恢复的文件取决于设备的 sysupgrade 配置备份规则。
- 手动模式：仅由用户点击按钮检查、下载和升级。
- 定时提示模式：按检查间隔自动检查更新，不自动下载或刷写。
- 自动升级模式：按路由器本地时间每天执行一次；发现新版本后自动检查、下载、验签、校验 SHA256、执行 `sysupgrade -T`，通过后执行 `sysupgrade -v` 并重启。默认计划时间为凌晨 04:00。

## 独立编译 IPK（用于单独安装测试）

本插件位于仓库的 `luci-app-myupdate/`，构建脚本会将它软链接到 LEDE 的 `package/lean/luci-app-myupdate`。由于它不在 LuCI feed 的 `applications/` 目录下，Makefile 必须从 `$(TOPDIR)/feeds/luci/luci.mk` 加载 LuCI 打包规则。

在已经完成 feeds 初始化、并具备 LEDE 编译工具链的构建机上执行：

```bash
cd /home/ubuntu
bash scripts/01-check-env.sh
TOPDIR=/home/ubuntu/lede bash scripts/build-myupdate-package.sh
```

编译脚本会单独构建 `luci-app-myupdate`，不编译固件镜像；生成的主插件 IPK 和简体中文语言包（如果构建系统生成）会复制到：

```
/home/ubuntu/lede/myupdate-ipk/
```

将 IPK 复制到路由器后安装。推荐先把文件传到 `/tmp`，再执行：

```sh
opkg install /tmp/luci-app-myupdate_*.ipk
opkg install /tmp/luci-i18n-myupdate-zh-cn_*.ipk
```

如果设备使用 APK 包管理器而不是 opkg，应使用设备对应的 APK 安装命令。插件依赖（例如 `rpcd-mod-ucode`、`curl`、`minisign`）也必须先满足。安装后刷新 LuCI 页面，检查「系统 → 固件在线升级」菜单。

## 必需的构建版本标记

编译工作流必须在执行 `bd.sh` 之前写入：

`/home/ubuntu/files/etc/myupdate/build-version`

文件内容必须与 Release `manifest.json` 的 `version` 字段完全相同，例如 `2026.11.22.123.1`。本仓库配套的 Actions 工作流会将日期、构建序号和重试序号写入该文件，并在 Release manifest 中使用同一版本号。没有此标记时，插件会将当前版本视为未知，并允许显示更新，但无法准确判断是否已经是最新版本。

## 安装与配置

1. 将本目录放入 LEDE 的本地软件包目录，并选择 `luci-app-myupdate` 编译。
2. 在 LuCI「系统 → 固件在线升级」填写完整 GitHub 仓库地址（例如 `https://github.com/OWNER/REPO`）和 Minisign 公钥。
3. 公开仓库无需 Token；私有仓库需要只读 Fine-grained PAT。
4. 默认使用手动模式。若要启用无人值守升级，在「检查模式」选择「每天定时检查并自动下载、验证和升级」，设置每天的升级时间（路由器本地时间，默认 04:00），然后保存设置。
5. 自动升级每天最多触发一次；如果当天计划时间已过，启用后会在调度器下一轮检查时执行。没有新版本时不会下载或刷写。

## 安全边界

- 不执行 `dd`，不自行写入磁盘分区；由 LEDE 自带 `sysupgrade` 平台升级机制处理 x86 combined 镜像。
- 只支持当前明确配置的 squashfs + UEFI x86_64 镜像，不接受 BIOS、ext4、其他架构或其他资产名。
- `sysupgrade -T` 失败时拒绝刷写。
- 自动升级时间使用路由器本地时区；调度器会将当天触发日期写入 `/etc/myupdate/last-auto-upgrade-date`，避免服务重启后同一天重复启动无人值守升级。
- 自动升级失败后当天不自动重试；可通过 LuCI 手动检查并处理。
- 不使用 `sysupgrade -n`；升级时由系统默认配置备份与恢复机制处理配置。配置保留范围取决于 `/etc/sysupgrade.conf`、MyUpdate 中配置的自定义保留路径及系统识别的配置文件列表；这不等于保留已安装软件包或整个 overlay。
- 刷写中断、电源故障或底层存储故障仍可能导致设备无法启动；该插件不提供硬件级回滚保证。远程升级应确保有本地/带外恢复手段。

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

## Release Manifest

```json
{
  "schema_version": 2,
  "version": "2026.11.22.123.1",
  "tag": "v2026.11.22.123.1",
  "channel": "stable",
  "partition_layout": {
    "kernel_partsize_mib": 256,
    "rootfs_partsize_mib": 4096,
    "uses_boot_part": true,
    "upstream_defaults_mib": {
      "kernel_partsize": 64,
      "rootfs_partsize": 448
    }
  },
  "compatibility": {
    "target": "x86",
    "subtarget": "64",
    "arch": "x86_64",
    "device_policy": "target",
    "devices": []
  },
  "image": {
    "asset": "openwrt-x86-64-generic-squashfs-combined-efi.img.gz",
    "sha256": "64 位十六进制 SHA256",
    "size": 12345678
  }
}
```

## 测试状态

CI 会测试版本排序、Tag/Manifest 一致性、Minisign 正反向验签、x86_64 UEFI/squashfs 兼容性及分区容量边界；发布前会校验固件资产名、大小、SHA256、分区布局元数据和源码 SHA。GitHub API 实际下载、设备上的 `sysupgrade -T`、真实刷写与重启尚未在用户设备上验证。首次使用必须先在可恢复的测试设备上验证。

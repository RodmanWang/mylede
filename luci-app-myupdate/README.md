# LuCI MyUpdate

针对本项目发布的 x86_64 LEDE squashfs UEFI 固件的 GitHub Release 更新管理器。

## 支持范围

- 固件文件必须为 `openwrt-x86-64-generic-squashfs-combined-efi.img.gz`。
- 设备必须运行 x86/64、x86_64 架构、squashfs 根文件系统，并以 UEFI 启动。
- 使用 Release 中的 `manifest.json` 和 `manifest.minisig`。
- 下载前验证 Minisign 签名、设备兼容性、版本、资产名和大小；下载后验证文件大小及 SHA256。
- 刷写前再次校验 SHA256，并执行 `sysupgrade -T`。
- 正式升级执行 `sysupgrade -v`，使用 LEDE 默认配置备份与恢复机制。实际恢复的文件取决于设备的 sysupgrade 配置备份规则。
- 自动模式只自动检查，不会无人值守自动刷写。

## 必需的构建版本标记

编译工作流必须在执行 `bd.sh` 之前写入：

`/home/ubuntu/files/etc/myupdate/build-version`

文件内容必须与 Release `manifest.json` 的 `version` 字段完全相同，例如 `2026.11.22.123.1`。本仓库配套的 Actions 工作流会将日期、构建序号和重试序号写入该文件，并在 Release manifest 中使用同一版本号。没有此标记时，插件会将当前版本视为未知，并允许显示更新，但无法准确判断是否已经是最新版本。

## 安装与配置

1. 将本目录放入 LEDE 的 LuCI 应用包目录，并选择 `luci-app-myupdate` 编译。
2. 在 LuCI「系统 → 固件在线升级」填写 GitHub 仓库所有者、仓库名和 Minisign 公钥。
3. 公开仓库无需 Token；私有仓库需要只读 Fine-grained PAT。
4. 先点击「检查更新」，再点击「下载并验证」，最后人工确认「执行升级」。

## 安全边界

- 不执行 `dd`，不自行写入磁盘分区；由 LEDE 自带 `sysupgrade` 平台升级机制处理 x86 combined 镜像。
- 只支持当前明确配置的 squashfs + UEFI x86_64 镜像，不接受 BIOS、ext4、其他架构或其他资产名。
- `sysupgrade -T` 失败时拒绝刷写。
- 不使用 `sysupgrade -n`；升级时由系统默认配置备份与恢复机制处理配置。配置保留范围取决于 `/etc/sysupgrade.conf`、MyUpdate 中配置的自定义保留路径及系统识别的配置文件列表；这不等于保留已安装软件包或整个 overlay。
- 刷写中断、电源故障或底层存储故障仍可能导致设备无法启动；该插件不提供硬件级回滚保证。远程升级应确保有本地/带外恢复手段。

## 自定义文件保留

首次安装本固件后，可以在 LuCI「系统 → 固件在线升级 → 自定义文件保留」中配置需要跨 OTA 升级保留的绝对路径。每行填写一个文件或目录，例如：

```text
/etc/config/myservice
/root/scripts
/usr/share/my-custom-data
```

保存后，MyUpdate 会在执行 OTA 前将这些路径写入 `/etc/sysupgrade.conf` 的独立管理区块。随后仍由 OpenWrt/LEDE 的 `sysupgrade` 生成配置备份，并在新固件刷写后按官方备份恢复流程还原；不备份整个根目录。配置保留路径本身保存在 `/etc/config/myupdate`，后续升级继续生效。

注意事项：

- 路径必须是绝对路径；每行一条。只会把旧系统中实际存在的文件或目录加入本次备份。
- 不允许根目录及 `/proc`、`/sys`、`/dev`、`/tmp`、`/rom`、`/overlay` 等运行时或虚拟文件系统路径。
- 只应选择确实需要跨版本保留的自定义文件。若路径与新固件自带文件冲突，sysupgrade 的备份恢复可能覆盖新固件中的同路径文件。
- 此设置从首次安装并配置 MyUpdate 后开始生效；首次刷入固件时，MyUpdate 无法从原系统追溯尚未配置的自定义路径。
- `/etc/uci-defaults/` 中的脚本若被列入保留路径，会作为文件恢复；是否执行仍由系统的 uci-defaults 启动机制决定。不要假设旧脚本会自动再次执行。

## Release Manifest

```json
{
  "schema_version": 1,
  "version": "2026.11.22.123.1",
  "tag": "v2026.11.22.123.1",
  "channel": "stable",
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

CI 会测试版本排序、Tag/Manifest 一致性、Minisign 正反向验签及 x86_64 UEFI/squashfs 兼容性；发布前会校验固件资产名、大小、SHA256 和源码 SHA。GitHub API 实际下载、设备上的 `sysupgrade -T`、真实刷写与重启尚未在用户设备上验证。首次使用必须先在可恢复的测试设备上验证。

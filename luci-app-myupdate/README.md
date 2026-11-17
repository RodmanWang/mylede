# LuCI MyUpdate

针对本项目发布的 x86_64 LEDE squashfs UEFI 固件的 GitHub Release 更新管理器。

## 支持范围

- 固件文件必须为 `openwrt-x86-64-generic-squashfs-combined-efi.img.gz`。
- 设备必须运行 x86/64、x86_64 架构、squashfs 根文件系统，并以 UEFI 启动。
- 使用 Release 中的 `manifest.json` 和 `manifest.minisig`。
- 下载前验证 Minisign 签名、设备兼容性、版本、资产名和大小；下载后验证文件大小及 SHA256。
- 刷写前再次校验 SHA256，并执行 `sysupgrade -T`。
- 正式升级固定执行 `sysupgrade -n -v`，不保留旧系统配置。不保留旧配置，也不提供旧 overlay 内的伪备份。
- 自动模式只自动检查，不会无人值守自动刷写。

## 必需的构建版本标记

编译工作流必须在执行 `bd.sh` 之前写入：

`/home/ubuntu/files/etc/myupdate/build-version`

文件内容必须与 Release `manifest.json` 的 `version` 字段完全相同，例如 `2026.11.123`。本仓库配套的 Actions 工作流应在编译前生成该文件，并在 Release manifest 中使用同一版本号。没有此标记时，插件会将当前版本视为未知，并允许显示更新，但无法准确判断是否已经是最新版本。

## 安装与配置

1. 将本目录放入 LEDE 的 LuCI 应用包目录，并选择 `luci-app-myupdate` 编译。
2. 在 LuCI「系统 → 固件在线升级」填写 GitHub 仓库所有者、仓库名和 Minisign 公钥。
3. 公开仓库无需 Token；私有仓库需要只读 Fine-grained PAT。
4. 先点击「检查更新」，再点击「下载并验证」，最后人工确认「执行升级」。

## 安全边界

- 不执行 `dd`，不自行写入磁盘分区；由 LEDE 自带 `sysupgrade` 平台升级机制处理 x86 combined 镜像。
- 只支持当前明确配置的 squashfs + UEFI x86_64 镜像，不接受 BIOS、ext4、其他架构或其他资产名。
- `sysupgrade -T` 失败时拒绝刷写。
- 使用 `sysupgrade -n`，旧配置不会恢复；`backup_config=1` 时只在升级前保存一份备份。
- 刷写中断、电源故障或底层存储故障仍可能导致设备无法启动；该插件不提供硬件级回滚保证。远程升级应确保有本地/带外恢复手段。

## Release Manifest

```json
{
  "schema_version": 1,
  "version": "2026.11.123",
  "tag": "v2026.11.123-r1",
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

已进行源代码静态检查及 Shell/JSON 语法检查；尚未在用户实际 LEDE 设备上完成安装、GitHub API 联调、`sysupgrade -T` 和真实刷写验证。首次使用必须先在可恢复的测试设备上验证。

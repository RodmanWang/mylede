# 自用自定义 x86 固件

本仓库用于自用自定义 x86 固件编译，不保证其他人使用。

## 固件源码

固件源码基于：

- [coolsnowwolf/lede](https://github.com/coolsnowwolf/lede)

同时使用该源码仓库所引用的外部插件及相关依赖。

## 额外添加的插件

除 LEDE 源码自带的软件包及插件外，本仓库还添加了以下插件：

### 1. OpenClash

源码仓库：[vernesong/OpenClash](https://github.com/vernesong/OpenClash/tree/dev)

使用 `dev` 分支，编译时自动拉取源码仓库最新提交，并参与固件编译。

### 2. SmartDNS

源码仓库：[pymumu/smartdns](https://github.com/pymumu/smartdns)

编译时自动拉取源码仓库最新提交，包含 WebUI 相关功能。

### 3. LuCI App SmartDNS

源码仓库：[pymumu/luci-app-smartdns](https://github.com/pymumu/luci-app-smartdns)

编译时自动拉取源码仓库最新提交，并参与固件编译。

## 固件分区大小的下次默认值

Actions 固件编译工作流会在成功发布签名 Release 后，从本次最终 `manifest.json` 读取并保存内核分区、根文件系统分区的实际大小，以及该 Manifest 记录的上游 x86 分区默认值。

- 下一次定时自动编译会沿用上次成功发布的实际分区大小。
- 下一次手动运行 Actions 时，两个分区输入框的默认值会更新为上次成功固件的实际分区大小；不修改输入值即可沿用，手动填写其他数值则本次按填写值编译。
- 输入项说明会同步更新为 Manifest 记录的上游默认值，例如“上游源码默认为 64 MiB”。这里显示的是上游 Kconfig 默认值，不是本次固件实际分区大小。
- 如果编译或 Release 发布失败，不更新持久化默认值；不会把失败任务中途的参数当作下一次默认值。
- 首次启用持久化机制时，初始回退值为内核 256 MiB、根文件系统 4096 MiB；首次成功发布 schema v2 Manifest 后，自动切换为该 Manifest 记录的实际值和上游默认值。

持久化记录位于 `build-config/last-successful-partition-layout.json`。自动更新只发生在固件 Release 成功发布后，由 Actions 机器人提交配置记录和表单默认值，不需要人工修改仓库源码。

## 致谢与声明

感谢以上源码作者，以及 LEDE 源码和相关插件所引用的其他开源项目及其作者。

本仓库仅供个人学习和自用，不得商业用途。

如有侵权或其他不妥之处，请联系告知，会及时处理或删除相关内容。

再次感谢所有开源项目作者的贡献！

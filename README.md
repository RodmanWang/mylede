# 自用自定义 x86 固件

本仓库用于个人自用自定义 x86 固件编译，不保证其他人使用。

## 固件源码

固件源码基于：

- [coolsnowwolf/lede](https://github.com/coolsnowwolf/lede)

同时使用该源码仓库所引用的外部插件及相关依赖。

## 额外添加的插件

除 LEDE 源码自带的软件包及插件外，本仓库还添加了以下插件：

### 1. OpenClash

源码仓库：[vernesong/OpenClash]([https://github.com/vernesong/OpenClash/tree/dev)]

使用 `dev` 分支，编译时自动拉取源码仓库最新提交，并参与固件编译。

### 2. SmartDNS

源码仓库：[pymumu/smartdns](https://github.com/pymumu/smartdns)

编译时自动拉取源码仓库最新提交，包含 WebUI 相关功能。

### 3. LuCI App SmartDNS

源码仓库：[pymumu/luci-app-smartdns](https://github.com/pymumu/luci-app-smartdns)

编译时自动拉取源码仓库最新提交，并参与固件编译。

## 致谢与声明

感谢以上源码作者，以及 LEDE 源码和相关插件所引用的其他开源项目及其作者。

本仓库仅供个人学习和自用，不提供商业用途。

如有侵权或其他不妥之处，请联系告知，我会及时处理或删除相关内容。

再次感谢所有开源项目作者的贡献！


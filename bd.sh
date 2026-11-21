
#!/usr/bin/env bash
set -Eeuo pipefail

# ==================================================
# bd.sh
# 固件编译主控脚本
# 负责按顺序调用各个功能模块。
# ==================================================

trap 'status=$?; echo "错误：主控脚本在第 ${LINENO} 行执行失败（退出码：${status}），已停止后续操作。" >&2; exit "$status"' ERR

# ==================================================
# 一、定义目录
# ==================================================

BASE_DIR="/home/ubuntu"

TOPDIR="$BASE_DIR/lede"
SCRIPT_DIR="$BASE_DIR/scripts"

SMARTDNS_SRC="$BASE_DIR/smartdns"
LUCI_SRC="$BASE_DIR/luci-app-smartdns"
MYUPDATE_SRC="$BASE_DIR/luci-app-myupdate"
DL_SRC="$BASE_DIR/dl"
FILES_SRC="$BASE_DIR/files"

# ==================================================
# 二、导出路径变量
# ==================================================

export BASE_DIR
export TOPDIR
export SCRIPT_DIR

export SMARTDNS_SRC
export LUCI_SRC
export MYUPDATE_SRC
export DL_SRC
export FILES_SRC

# ==================================================
# 三、执行普通功能模块
# ==================================================

run_step() {
    local script="$1"
    local script_name

    script_name="$(basename "$script")"

    if [[ ! -f "$script" ]]; then
        echo "错误：找不到脚本：$script" >&2
        exit 1
    fi

    echo
    echo "=================================================="
    echo "开始执行：$script_name"
    echo "=================================================="

    bash "$script"

    echo "完成：$script_name"
}

# ==================================================
# 四、按原编译流程顺序执行
# ==================================================

echo
echo "##################################################"
echo "#             固件自动编译流程开始               #"
echo "##################################################"

# 1. 检查自定义软件包目录并建立软链接。
run_step "$SCRIPT_DIR/01-check-env.sh"

# 2. 更新 LEDE 主源码。
run_step "$SCRIPT_DIR/02-update-source.sh"

# 3. 更新 feeds 并安装软件包。
run_step "$SCRIPT_DIR/03-update-feeds.sh"

# 4. 应用系统配置、自动选择最高可用内核及分区大小。
run_step "$SCRIPT_DIR/04-configure.sh"

# 5. 对 OpenClash 自定义规则和配置文件进行修改。
run_step "$SCRIPT_DIR/05-openclash.sh"

# 6. 清理旧的 SmartDNS 编译产物。
run_step "$SCRIPT_DIR/06-clean-build.sh"

# 7. 清理临时配置、生成 defconfig 并正式编译。
run_step "$SCRIPT_DIR/07-build.sh"

# ==================================================
# 五、全部完成
# ==================================================

echo
echo "##################################################"
echo "#               固件编译全部完成                 #"
echo "##################################################"

echo
echo "固件输出目录：$TOPDIR/bin/targets/x86/64"
echo "编译流程已全部执行完毕。"

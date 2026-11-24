
#!/usr/bin/env bash
set -Eeuo pipefail

trap 'status=$?; echo "错误：源码更新在第 ${LINENO} 行执行失败（退出码：${status}）。" >&2; exit "$status"' ERR

TOPDIR="${TOPDIR:-/home/ubuntu/lede}"
SMARTDNS_SRC="${SMARTDNS_SRC:-/home/ubuntu/smartdns}"
LUCI_SRC="${LUCI_SRC:-/home/ubuntu/luci-app-smartdns}"
MYUPDATE_SRC="${MYUPDATE_SRC:-/home/ubuntu/luci-app-myupdate}"
DL_SRC="${DL_SRC:-/home/ubuntu/dl}"
FILES_SRC="${FILES_SRC:-/home/ubuntu/files}"

cd "$TOPDIR"

retry_git() {
    local max_retries=2
    local max_attempts=$((max_retries + 1))
    local delay_seconds=3
    local attempt=1
    local status=0

    while (( attempt <= max_attempts )); do
        echo "Git 操作第 ${attempt}/${max_attempts} 次：$*"

        if "$@"; then
            return 0
        else
            status=$?
            echo "警告：Git 操作失败（退出码：${status}）。" >&2
        fi

        if (( attempt < max_attempts )); then
            echo "${delay_seconds} 秒后重试..." >&2
            sleep "$delay_seconds"
        fi

        ((attempt += 1))
    done

    echo "错误：Git 操作连续尝试 ${max_attempts} 次：$*" >&2
    return "$status"
}

ensure_link() {
    local link="$1"
    local target="$2"
    local required="$3"

    if [[ ! -d "$target" ]]; then
        if [[ "$required" == "yes" ]]; then
            echo "错误：必需的本地源码目录不存在：$target" >&2
            exit 1
        fi

        echo "可选目录不存在，跳过：$target"
        return 0
    fi

    mkdir -p "$(dirname "$link")"

    if [[ -L "$link" ]]; then
        if [[ "$(readlink -f "$link")" == "$target" ]]; then
            echo "软链接正确：$link"
            return 0
        fi

        echo "错误：软链接指向错误位置：$link" >&2
        echo "当前指向：$(readlink "$link")" >&2
        echo "预期指向：$target" >&2
        exit 1
    fi

    if [[ -e "$link" ]]; then
        echo "错误：目标路径已存在，但不是软链接：$link" >&2
        exit 1
    fi

    ln -s "$target" "$link"
    echo "已创建软链接：$link -> $target"
}

echo "========== 2/7 更新 LEDE 主源码 =========="

if ! retry_git git pull; then
    echo "警告：git pull 失败，将尝试同步到 origin/master。"
    echo "注意：git reset --hard 会丢弃 LEDE Git 跟踪文件中的本地未提交修改。"
    echo "注意：git clean -df 会清理未跟踪文件/目录（指定目录已设置排除项）。"

    if retry_git git fetch origin; then
        :
    else
        FETCH_STATUS=$?
        echo "错误：初次尝试及 2 次重试后仍无法获取 LEDE 远程仓库。" >&2
        exit "$FETCH_STATUS"
    fi

    git rev-parse --verify origin/master >/dev/null || {
        echo "错误：找不到 origin/master，停止操作。" >&2
        exit 1
    }

    git reset --hard origin/master

    git clean -df \
        -e /files \
        -e /dl \
        -e /package/smartdns \
        -e /package/lean/luci-app-smartdns \
        -e /package/lean/luci-app-myupdate

    ensure_link "$TOPDIR/package/smartdns" "$SMARTDNS_SRC" yes
    ensure_link "$TOPDIR/package/lean/luci-app-smartdns" "$LUCI_SRC" yes
    ensure_link "$TOPDIR/dl" "$DL_SRC" no
    ensure_link "$TOPDIR/files" "$FILES_SRC" no
fi

# 无论 git pull 成功还是执行回退同步，都确保自定义插件软链接存在。
ensure_link "$TOPDIR/package/lean/luci-app-myupdate" "$MYUPDATE_SRC" yes

echo "========== 2/7 LEDE 主源码更新完成 =========="

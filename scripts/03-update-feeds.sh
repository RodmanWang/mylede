
#!/usr/bin/env bash
set -Eeuo pipefail

# ============================================================
# 基础配置
# ============================================================

TOPDIR="${TOPDIR:-/home/ubuntu/lede}"

OPENCLASH_FEED='src-git OpenClash https://github.com/vernesong/OpenClash.git;dev'
OPENCLASH_DIR="$TOPDIR/feeds/OpenClash"
OPENCLASH_BRANCH="dev"

MAX_RETRIES=3
RETRY_DELAY=3

# ============================================================
# 错误处理
# ============================================================

trap 'status=$?; echo "错误：feeds 更新脚本在第 ${LINENO} 行执行失败（退出码：${status}）。" >&2; exit "$status"' ERR

FEEDS_LOG=""

cleanup() {
    if [[ -n "${FEEDS_LOG:-}" && -f "$FEEDS_LOG" ]]; then
        rm -f -- "$FEEDS_LOG" || true
    fi
}

trap cleanup EXIT

show_error_log() {
    if [[ -s "$FEEDS_LOG" ]]; then
        echo
        echo "========== feeds 错误日志（最后 100 行） ==========" >&2
        tail -n 100 "$FEEDS_LOG" >&2
        echo "========== 错误日志结束 ==========" >&2
    fi
}

# ============================================================
# 检查运行环境
# ============================================================

cd "$TOPDIR"

FEEDS_CONF="$TOPDIR/feeds.conf.default"

[[ -f "$FEEDS_CONF" ]] || {
    echo "错误：找不到 feeds 配置文件：$FEEDS_CONF" >&2
    exit 1
}

for cmd in git python3 script tee grep tail awk; do
    command -v "$cmd" >/dev/null 2>&1 || {
        echo "错误：缺少必要命令：$cmd" >&2
        exit 127
    }
done

echo "========== 3/7 配置 feeds 并安装所需软件包 =========="

# ============================================================
# 配置 OpenClash feed
# ============================================================

python3 - "$FEEDS_CONF" "$OPENCLASH_FEED" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
entry = sys.argv[2].encode()

data = path.read_bytes()
lines = data.splitlines()

if entry in lines:
    print("OpenClash feed 已存在，无需重复添加。")
else:
    if data and not data.endswith(b"\n"):
        data += b"\n"

    data += entry + b"\n"
    path.write_bytes(data)

    print("已添加 OpenClash dev feed。")
PY

# ============================================================
# 初始化日志
# ============================================================

FEEDS_LOG="$(mktemp "${TMPDIR:-/tmp}/lede-feeds.XXXXXX")"

# ============================================================
# Git 冲突识别
# ============================================================

is_git_conflict() {
    grep -Eiq \
        'Diverging branches|divergent branches|can.t be fast-forwarded|unable to fast-forward|fatal:.*fast-forward|local changes.*overwritten|would be overwritten|Please commit your changes|unstaged changes|Your local changes|本地修改将被合并操作覆盖|请在合并前提交或储藏|本地修改.*覆盖|无法快进|不能快进|分支发生分歧' \
        "$FEEDS_LOG"
}

# ============================================================
# Git 操作重试
# ============================================================

retry_git() {
    local attempt=1
    local status=0

    while (( attempt <= MAX_RETRIES )); do

        echo "Git 操作第 ${attempt}/${MAX_RETRIES} 次：$*"

        if "$@"; then
            return 0
        else
            status=$?
            echo "警告：Git 操作失败，退出码：$status" >&2
        fi

        if (( attempt < MAX_RETRIES )); then
            echo "${RETRY_DELAY} 秒后重试..." >&2
            sleep "$RETRY_DELAY"
        fi

        ((attempt += 1))
    done

    echo "错误：Git 操作连续失败 ${MAX_RETRIES} 次。" >&2

    return "$status"
}

# ============================================================
# 执行 feeds 更新
# ============================================================

run_feeds_update() {
    local attempt=1
    local status=0

    while (( attempt <= MAX_RETRIES )); do

        echo
        echo "========== feeds 更新第 ${attempt}/${MAX_RETRIES} 次 =========="

        if script -q -e -c './scripts/feeds update -a' /dev/null 2>&1 |
            tee -a "$FEEDS_LOG"; then

            return 0

        else
            status=$?

            echo "警告：feeds 更新失败，退出码：$status" >&2
        fi

        # 如果已经确认是 Git 本地修改或分支冲突，
        # 不再重复执行相同操作，直接交给强制同步处理。
        if is_git_conflict; then
            echo "检测到 Git 本地修改或分支冲突。"
            return "$status"
        fi

        if (( attempt < MAX_RETRIES )); then
            echo "暂未发现明确的 Git 冲突，${RETRY_DELAY} 秒后重试..." >&2
            sleep "$RETRY_DELAY"
        fi

        ((attempt += 1))
    done

    return "$status"
}

# ============================================================
# 强制同步所有 feeds 仓库
# ============================================================

force_sync_all_feeds() {

    local feed_dir
    local remote
    local remote_url
    local branch
    local upstream
    local current_branch
    local remote_head

    local total=0
    local success=0
    local failed=0

    echo
    echo "============================================================"
    echo "       开始强制同步所有 feeds 仓库"
    echo "============================================================"

    echo
    echo "警告：此操作会丢弃所有 feeds 仓库中的本地修改。"
    echo "同时会删除 Git 未跟踪且未被忽略的文件。"
    echo "被 .gitignore 忽略的文件会保留。"
    echo

    for feed_dir in "$TOPDIR"/feeds/*; do

        [[ -d "$feed_dir" ]] || continue

        # 跳过不是 Git 仓库的目录
        if ! git -C "$feed_dir" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
            continue
        fi

        ((total += 1))

        echo
        echo "------------------------------------------------------------"
        echo "检查 feeds 仓库：$feed_dir"
        echo "------------------------------------------------------------"

        # OpenClash 固定使用 origin/dev
        if [[ "$feed_dir" == "$OPENCLASH_DIR" ]]; then

            remote="origin"
            branch="$OPENCLASH_BRANCH"

        else

            # 优先获取当前分支配置的上游远程分支
            upstream="$(
                git -C "$feed_dir" \
                    rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' \
                    2>/dev/null || true
            )"

            if [[ -n "$upstream" ]]; then

                remote="${upstream%%/*}"
                branch="${upstream#*/}"

            else

                # 没有上游配置时，使用当前本地分支
                current_branch="$(
                    git -C "$feed_dir" branch --show-current 2>/dev/null || true
                )"

                remote="origin"

                if [[ -n "$current_branch" ]]; then

                    branch="$current_branch"

                else

                    # Detached HEAD 时，尝试使用 origin/HEAD
                    remote_head="$(
                        git -C "$feed_dir" \
                            symbolic-ref --short refs/remotes/origin/HEAD \
                            2>/dev/null || true
                    )"

                    if [[ -n "$remote_head" ]]; then

                        branch="${remote_head#origin/}"

                    else

                        # 最后尝试查询远程默认分支
                        remote_head="$(
                            git -C "$feed_dir" ls-remote --symref "$remote" HEAD 2>/dev/null |
                                awk '$1 == "ref:" && $3 == "HEAD" {
                                    sub("refs/heads/", "", $2)
                                    print $2
                                    exit
                                }' || true
                        )"

                        if [[ -n "$remote_head" ]]; then
                            branch="$remote_head"
                        else
                            echo "错误：无法确定仓库的远程分支。" >&2
                            ((failed += 1))
                            continue
                        fi
                    fi
                fi
            fi
        fi

        # 检查远程地址
        remote_url="$(
            git -C "$feed_dir" remote get-url "$remote" 2>/dev/null || true
        )"

        if [[ -z "$remote_url" ]]; then
            echo "错误：找不到远程仓库 $remote，跳过。" >&2
            ((failed += 1))
            continue
        fi

        echo "远程仓库：$remote"
        echo "远程地址：$remote_url"
        echo "目标分支：$branch"

        # 获取远程最新提交
        if ! retry_git git -C "$feed_dir" fetch --prune "$remote" "$branch"; then

            echo "错误：获取远程分支失败：$feed_dir" >&2
            ((failed += 1))
            continue

        fi

        # 强制将本地仓库重置为远程最新提交
        if ! git -C "$feed_dir" reset --hard FETCH_HEAD; then

            echo "错误：Git reset 执行失败：$feed_dir" >&2
            ((failed += 1))
            continue

        fi

        # 清理未跟踪文件及目录
        if ! git -C "$feed_dir" clean -fd; then

            echo "错误：Git clean 执行失败：$feed_dir" >&2
            ((failed += 1))
            continue

        fi

        echo "成功：仓库已与远程分支保持一致。"

        ((success += 1))

    done

    echo
    echo "============================================================"
    echo "             feeds 强制同步统计"
    echo "============================================================"

    echo "检测到的 Git 仓库：$total"
    echo "同步成功：$success"
    echo "同步失败：$failed"

    echo "============================================================"

    if (( failed > 0 )); then
        echo "错误：部分 feeds 仓库未能完成同步。" >&2
        return 1
    fi

    echo "所有 feeds 仓库强制同步完成。"

    return 0
}

# ============================================================
# 第一次执行 feeds 更新
# ============================================================

echo
echo "========== 开始更新所有 feeds =========="

if run_feeds_update; then

    echo
    echo "所有 feeds 更新成功。"

else

    FEEDS_STATUS=$?

    echo
    echo "========== feeds 更新失败 =========="

    # 只在确认属于 Git 冲突时进行破坏性同步
    if is_git_conflict; then

        echo "检测到 Git 本地修改或分支冲突。"
        echo "准备强制同步所有 feeds 仓库。"

        if ! force_sync_all_feeds; then

            echo "错误：无法完成所有 feeds 仓库的强制同步。" >&2
            show_error_log
            exit 1

        fi

        # 清除旧错误日志，重新记录第二次更新
        : > "$FEEDS_LOG"

        echo
        echo "========== 强制同步完成，重新更新所有 feeds =========="

        if run_feeds_update; then

            echo
            echo "强制同步后，所有 feeds 更新成功。"

        else

            FEEDS_STATUS=$?

            echo "错误：强制同步后 feeds 仍然更新失败。" >&2
            show_error_log

            exit "$FEEDS_STATUS"

        fi

    else

        echo "错误：feeds 更新失败，但未检测到明确的 Git 本地修改冲突。" >&2
        echo "为避免误删本地数据，本次不执行强制同步。" >&2

        show_error_log

        exit "$FEEDS_STATUS"

    fi

fi

# ============================================================
# 将所有 feed 固定到 source_check 预检得到的精确 commit
# ============================================================

SOURCE_LOCK="${MYLEDE_SOURCE_LOCK:-/home/ubuntu/source-revisions.tsv}"
if [[ -n "${MYLEDE_SOURCE_LOCK:-}" ]]; then
    [[ -s "$SOURCE_LOCK" ]] || {
        echo "错误：源码锁定文件不存在或为空：$SOURCE_LOCK" >&2
        exit 1
    }

    echo
    echo "========== 按预检 SHA 固定 feeds 源码 =========="
    while IFS=$'\t' read -r source_name source_url source_ref source_commit; do
        [[ "$source_name" == feed:* || "$source_name" == OpenClash ]] || continue
        [[ "$source_commit" =~ ^[0-9a-f]{40}$ ]] || { echo "错误：无效的锁定 SHA：$source_name" >&2; exit 1; }
        feed_name="${source_name#feed:}"
        feed_dir="$TOPDIR/feeds/$feed_name"
        [[ -d "$feed_dir" ]] || { echo "错误：预检 feed 不存在：$feed_dir" >&2; exit 1; }
        actual_url="$(git -C "$feed_dir" remote get-url origin)"
        normalize_url() { printf '%s' "$1" | sed -E 's#^https?://github.com/#https://github.com/#; s#\.git$##'; }
        [[ "$(normalize_url "$actual_url")" == "$(normalize_url "$source_url")" ]] || { echo "错误：$feed_name 的 origin 与预检地址不一致：$actual_url" >&2; exit 1; }
        echo "固定 $feed_name -> $source_commit"
        git -C "$feed_dir" fetch --no-tags origin "$source_commit"
        git -C "$feed_dir" reset --hard "$source_commit"
        [[ "$(git -C "$feed_dir" rev-parse HEAD)" == "$source_commit" ]] || { echo "错误：$feed_name 未固定到预检 SHA" >&2; exit 1; }
    done < "$SOURCE_LOCK"
fi

# ============================================================

echo
echo
echo "========== 动态发现并移除与自定义包冲突的上游源码 =========="

python3 - "$TOPDIR" <<'PY'
from pathlib import Path
import os
import re
import shutil
import sys

topdir = Path(sys.argv[1]).resolve()
feeds_root = topdir / "feeds"
installed_root = topdir / "package" / "feeds"

# Package source paths are discovered from the checked-out feed Makefiles.
# Do not assume that LuCI or packages keeps a particular directory layout.
targets = {
    "luci-app-openclash": {"exclude_feeds": {"OpenClash"}},
    "luci-app-smartdns": {"exclude_feeds": set()},
    "smartdns": {"exclude_feeds": set()},
}

package_patterns = {
    name: re.compile(
        rb"^[ \t]*(?:define[ \t]+Package/" + re.escape(name.encode()) +
        rb"(?:/[A-Za-z0-9_.+-]+)?[ \t]*$|PKG_NAME[ \t]*[:?+]?=[ \t]*" +
        re.escape(name.encode()) + rb"[ \t]*$)",
        re.MULTILINE,
    )
    for name in targets
}

matches = {name: [] for name in targets}
for current_root, directories, filenames in os.walk(feeds_root, followlinks=False):
    directories[:] = [name for name in directories if name != ".git"]
    if "Makefile" not in filenames:
        continue
    makefile = Path(current_root) / "Makefile"
    relative = makefile.relative_to(feeds_root)
    if not relative.parts:
        continue
    feed_name = relative.parts[0]
    content = makefile.read_bytes()
    for package_name, settings in targets.items():
        if feed_name in settings["exclude_feeds"]:
            continue
        if package_patterns[package_name].search(content):
            matches[package_name].append(makefile.parent.absolute())

for package_name, directories in matches.items():
    unique = sorted(set(directories))
    print(f"{package_name}: 动态发现 {len(unique)} 个上游包目录")
    for package_dir in unique:
        # Remove only feed-install symlinks that resolve to this exact source.
        if installed_root.exists():
            for link in installed_root.rglob(package_name):
                if not link.is_symlink():
                    continue
                if os.path.realpath(link) == os.path.realpath(package_dir):
                    print(f"移除 feed 安装链接：{link}")
                    link.unlink()
        if package_dir.is_symlink():
            print(f"移除上游源码软链接：{package_dir}")
            package_dir.unlink()
        elif package_dir.is_dir():
            print(f"移除上游重复源码目录：{package_dir}")
            shutil.rmtree(package_dir)
        elif package_dir.exists():
            raise SystemExit(f"上游包路径不是目录，拒绝删除：{package_dir}")

# Keep the custom OpenClash feed intact; only duplicate copies from other
# feeds are removed. The explicit install below selects that configured feed.
PY


echo "========== 安装所有 feeds 软件包 =========="

echo "提示：开始安装所有 feeds 中的软件包链接。"

./scripts/feeds install -a

echo
echo "提示：确保从 OpenClash feed 安装 luci-app-openclash。"

./scripts/feeds install -p OpenClash luci-app-openclash

# ============================================================
# 完成
# ============================================================

echo
echo "============================================================"
echo "       3/7 feeds 更新及软件包安装全部完成"
echo "============================================================"


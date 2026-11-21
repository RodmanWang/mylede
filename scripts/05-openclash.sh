
#!/usr/bin/env bash
set -Eeuo pipefail

# ==================================================
# OpenClash 自定义配置修改脚本
# GitHub dev 源码自动同步版
# ==================================================

ROOT="${1:-/home/ubuntu/lede/feeds/OpenClash}"
CONF_DIR="${ROOT}/luci-app-openclash/root/etc/openclash/custom"

# ==================================================
# 基础检查
# ==================================================

if [[ ! -d "$CONF_DIR" ]]; then
    echo "错误：配置目录不存在：$CONF_DIR" >&2
    exit 1
fi

FILES=(
    openclash_custom_chnroute6_pass.list
    openclash_custom_chnroute_pass.list
    openclash_custom_fake_filter.list
    openclash_custom_fallback_filter.yaml
    openclash_custom_proxy_server_dns_policy.list
    openclash_custom_rules.list
    openclash_custom_rules_2.list
)

for f in "${FILES[@]}"; do
    if [[ ! -f "$CONF_DIR/$f" ]]; then
        echo "错误：缺少文件：$CONF_DIR/$f" >&2
        exit 1
    fi
done

command -v python3 >/dev/null 2>&1 || {
    echo "错误：找不到 python3。" >&2
    exit 127
}

echo "=================================================="
echo "OpenClash 自定义配置检查及修改"
echo "=================================================="
echo "配置目录：$CONF_DIR"
echo "GitHub 源码：OpenClash/dev"
echo "本次运行不创建备份文件。"
echo

# ==================================================
# Python 文件处理
# ==================================================

python3 - "$CONF_DIR" <<'PY'
from pathlib import Path
import hashlib
import os
import sys
import tempfile
import urllib.request

base = Path(sys.argv[1])

# staged 保存：
# 文件名 -> [原始内容, 修改后的内容]
staged = {}


# ==================================================
# GitHub 源码地址
# ==================================================

GITHUB_BASE = (
    "https://raw.githubusercontent.com/"
    "vernesong/OpenClash/dev/"
    "luci-app-openclash/root/etc/openclash/custom/"
)


# ==================================================
# 基础文件操作
# ==================================================

def sha256(data):
    return hashlib.sha256(data).hexdigest()


def read(name):

    path = base / name

    if not path.is_file():
        raise RuntimeError(f"找不到文件：{path}")

    if name not in staged:

        data = path.read_bytes()
        staged[name] = [data, data]

    return staged[name][1]


def write(name, data):

    if name not in staged:
        original = read(name)
        staged[name] = [original, original]

    staged[name][1] = data


def newline_of(data):
    """识别文件换行格式。"""
    return b"\r\n" if b"\r\n" in data else b"\n"


def split_lines(data):
    """保留原始换行符。"""
    return data.splitlines(keepends=True)


def line_body(line):
    """去除换行符，不影响其他内容。"""
    return line.rstrip(b"\r\n")


# ==================================================
# 下载 GitHub 源码
# ==================================================

def download_github(name):

    url = GITHUB_BASE + name

    print(f"[下载源码] {name}")

    request = urllib.request.Request(
        url,
        headers={
            "User-Agent": "OpenClash-Custom-Config-Sync"
        }
    )

    try:

        with urllib.request.urlopen(
            request,
            timeout=30
        ) as response:

            source = response.read()

    except Exception as e:

        raise RuntimeError(
            f"GitHub 源码下载失败：{name}\n{e}"
        )

    if not source:

        raise RuntimeError(
            f"GitHub 源码为空：{name}"
        )

    try:

        source.decode("utf-8")

    except UnicodeDecodeError as e:

        raise RuntimeError(
            f"{name}：源码不是有效 UTF-8 文件。\n{e}"
        )

    print(
        f"[下载成功] {name}：{len(source)} 字节"
    )

    return source


# ==================================================
# 原子写入
# ==================================================

def atomic_write(path, data):

    original_mode = path.stat().st_mode & 0o777

    fd, temp_name = tempfile.mkstemp(
        prefix=f".{path.name}.",
        suffix=".tmp",
        dir=path.parent
    )

    try:

        with os.fdopen(fd, "wb") as f:

            f.write(data)
            f.flush()
            os.fsync(f.fileno())

        os.chmod(temp_name, original_mode)

        os.replace(temp_name, path)

    except Exception:

        try:
            os.unlink(temp_name)
        except FileNotFoundError:
            pass

        raise


# ==================================================
# 统一提交
# 只写入内容真正发生变化的文件
# ==================================================

def commit_changes():

    modified = 0
    unchanged = 0

    print()
    print("=" * 50)
    print("文件检查及修改结果")
    print("=" * 50)

    for name, (original, updated) in staged.items():

        path = base / name

        if updated == original:

            unchanged += 1

            print(f"[无需修改] {name}")
            continue

        old_hash = sha256(original)
        new_hash = sha256(updated)

        atomic_write(path, updated)

        modified += 1

        print(f"[已修改] {name}")
        print(f"  修改前 SHA256：{old_hash}")
        print(f"  修改后 SHA256：{new_hash}")

    print()
    print("=" * 50)
    print(f"检查文件：{len(staged)}")
    print(f"实际修改：{modified}")
    print(f"无需修改：{unchanged}")
    print("=" * 50)

    return modified


# ==================================================
# 通用规则追加
# ==================================================

def append_missing(name, rules):

    data = read(name)
    nl = newline_of(data)

    existing = set(data.splitlines())

    missing = []
    seen = set()

    for rule in rules:

        encoded = rule.encode("utf-8")

        if encoded in existing or encoded in seen:
            continue

        missing.append(encoded)
        seen.add(encoded)

    if not missing:

        print(
            f"[检查通过] {name}："
            "所有规则均已存在。"
        )

        return

    if data and not data.endswith((b"\n", b"\r")):
        data += nl

    data += nl.join(missing) + nl

    write(name, data)

    print(
        f"[待修改] {name}："
        f"新增 {len(missing)} 条规则。"
    )


# ==================================================
# 一、fake_filter
#
# 完整同步 GitHub 源码
# 自定义规则唯一保留
# 统一放在文件顶部
# ==================================================

def sync_fake_filter(name):

    print()
    print("========== fake_filter 源码同步 ==========")

    source = download_github(name)

    nl = newline_of(source)

    block = [
        "#代码",
        "github.com",
        "#路由器",
        "*.asusrouter.com",
        "#自建域名",
        "*.goota.top",
        "#三星智能家居",
        "+.samsungihp.cn",
        "#小米",
        "+.mi.com",
        "#科沃斯",
        "+.ecouser.net",
        "#松下",
        "+.psmartcloud.com",
        "#自选NTP",
        "ntp.ntsc.ac.cn",
    ]

    block_bytes = [
        item.encode("utf-8")
        for item in block
    ]

    block_set = set(block_bytes)

    lines = split_lines(source)

    # 删除远程源码中已有的自定义规则
    rest = [
        line for line in lines
        if line_body(line) not in block_set
    ]

    # 自定义规则统一放在顶部
    prefix = nl.join(block_bytes) + nl

    updated = prefix + b"".join(rest)

    local = read(name)

    if updated != local:

        write(name, updated)

        print(
            f"[待修改] {name}："
            "GitHub 源码已同步，"
            "自定义规则已统一整理到顶部。"
        )

    else:

        print(
            f"[检查通过] {name}："
            "远程源码及顶部自定义规则均一致。"
        )


# ==================================================
# 二、fallback_filter.yaml
#
# 完整同步 GitHub 源码
# 确保 github.com 位于 githubusercontent 上一行
# ==================================================

def sync_fallback_filter(name):

    print()
    print("========== fallback_filter 源码同步 ==========")

    source = download_github(name)

    lines = split_lines(source)

    nl = newline_of(source)

    github_rule = b'- "+.github.com"'
    githubusercontent_rule = b'- "+.githubusercontent.com"'

    target_indices = [
        i for i, line in enumerate(lines)
        if line_body(line).strip() == githubusercontent_rule
    ]

    if len(target_indices) != 1:

        raise RuntimeError(
            f"{name}："
            '远程源码中 "- \\"+.githubusercontent.com\\"" '
            f"出现 {len(target_indices)} 次，"
            "无法唯一确定位置，停止修改。"
        )

    target_index = target_indices[0]

    if target_index == 0:

        raise RuntimeError(
            f"{name}：githubusercontent 规则位于第一行，"
            "无法插入上一行。"
        )

    # 获取目标规则缩进
    target_line = lines[target_index]

    target_body = line_body(target_line)

    indent = target_body[
        :len(target_body) - len(target_body.lstrip())
    ]

    expected_github = indent + github_rule

    # 检查上一行是否正确
    previous_body = line_body(
        lines[target_index - 1]
    )

    if previous_body == expected_github:

        print(
            f"[检查通过] {name}："
            "两条 GitHub 规则已经相邻，"
            "缩进和格式正确。"
        )

    else:

        lines.insert(
            target_index,
            expected_github + nl
        )

        print(
            f"[待修改] {name}："
            "已在 githubusercontent 规则上一行"
            "添加 github.com 规则。"
        )

    updated = b"".join(lines)

    local = read(name)

    if updated != local:

        write(name, updated)

        print(
            f"[待修改] {name}："
            "GitHub 源码同步及规则整理完成。"
        )

    else:

        print(
            f"[检查通过] {name}："
            "远程源码和本地内容完全一致。"
        )


# ==================================================
# 三、proxy_server_dns_policy.list
#
# 完整同步 GitHub 源码
# 自定义 DNS 策略追加到文件末尾
# 自动去重
# ==================================================

def sync_dns_policy(name, rules):

    print()
    print("========== DNS 策略源码同步 ==========")

    source = download_github(name)

    nl = newline_of(source)

    # 远程源码作为完整基础
    updated = source

    # 确保源码末尾有换行符
    if updated and not updated.endswith((b"\n", b"\r")):
        updated += nl

    # 检查远程源码已有规则
    existing = set(updated.splitlines())

    missing = []
    seen = set()

    for rule in rules:

        encoded = rule.encode("utf-8")

        if encoded in existing or encoded in seen:
            continue

        missing.append(encoded)
        seen.add(encoded)

    if missing:

        updated += nl.join(missing) + nl

        print(
            f"[追加规则] {name}："
            f"新增 {len(missing)} 条 DNS 策略。"
        )

    else:

        print(
            f"[检查通过] {name}："
            "所有自定义 DNS 策略均已存在。"
        )

    local = read(name)

    if updated != local:

        write(name, updated)

        print(
            f"[待修改] {name}："
            "GitHub 源码同步及 DNS 策略整理完成。"
        )

    else:

        print(
            f"[检查通过] {name}："
            "远程源码和自定义 DNS 策略均一致。"
        )


# ==================================================
# 四、rules.list
#
# 同步 GitHub 源码至最后一行注释
# 锚点之后添加自定义直连规则
# ==================================================

def sync_github_and_append(name, rules):

    print()
    print(f"========== 同步 {name} ==========")

    source = download_github(name)

    source_lines = split_lines(source)

    # 找到源码最后一行注释
    anchor_index = None

    for i in range(len(source_lines) - 1, -1, -1):

        body = line_body(source_lines[i]).strip()

        if body.startswith(b"#"):

            anchor_index = i
            break

    if anchor_index is None:

        raise RuntimeError(
            f"{name}：源码中没有找到注释锚点。"
        )

    anchor = line_body(
        source_lines[anchor_index]
    )

    print(
        f"[源码锚点] {anchor.decode('utf-8')}"
    )

    # 只取源码第一行至最后注释锚点
    upstream = b"".join(
        source_lines[:anchor_index + 1]
    )

    local = read(name)

    local_lines = split_lines(local)

    local_anchor_index = None

    for i in range(len(local_lines) - 1, -1, -1):

        if line_body(local_lines[i]) == anchor:

            local_anchor_index = i
            break

    if local_anchor_index is not None:

        local_prefix = b"".join(
            local_lines[:local_anchor_index + 1]
        )

    else:

        local_prefix = b""

    if local_prefix == upstream:

        print(
            f"[源码一致] {name}："
            "本地源码部分与 GitHub 完全一致。"
        )

    else:

        print(
            f"[源码更新] {name}："
            "本地源码部分与 GitHub 不一致，"
            "准备完整替换。"
        )

    # 以 GitHub 源码作为最终基础
    nl = newline_of(upstream)

    updated = upstream

    if updated and not updated.endswith((b"\n", b"\r")):
        updated += nl

    # 追加自定义规则
    existing = set(updated.splitlines())

    missing = []
    seen = set()

    for rule in rules:

        encoded = rule.encode("utf-8")

        if encoded in existing or encoded in seen:
            continue

        missing.append(encoded)
        seen.add(encoded)

    if missing:

        updated += nl.join(missing) + nl

        print(
            f"[追加规则] {name}："
            f"新增 {len(missing)} 条自定义规则。"
        )

    else:

        print(
            f"[规则检查] {name}："
            "自定义规则均已存在，无需重复添加。"
        )

    if updated != local:

        write(name, updated)

        print(
            f"[待修改] {name}："
            "源码同步及自定义规则整理完成。"
        )

    else:

        print(
            f"[检查通过] {name}："
            "源码及自定义规则均无需修改。"
        )


# ==================================================
# 五、清理两个 chnroute 文件
# 仅保留注释行和空行
# ==================================================

print()
print("========== 一、清理 chnroute 文件 ==========")

for name in (
    "openclash_custom_chnroute6_pass.list",
    "openclash_custom_chnroute_pass.list",
):

    data = read(name)

    kept = []

    for line in split_lines(data):

        stripped = line_body(line).strip()

        if not stripped or stripped.startswith(b"#"):
            kept.append(line)

    updated = b"".join(kept)

    if updated != data:

        write(name, updated)

        print(
            f"[待修改] {name}："
            "已发现需要清理的非注释内容。"
        )

    else:

        print(f"[检查通过] {name}：内容符合要求。")


# ==================================================
# 六、同步 fake_filter
# ==================================================

print()
print("========== 二、同步 fake_filter ==========")

sync_fake_filter(
    "openclash_custom_fake_filter.list"
)


# ==================================================
# 七、同步 fallback_filter
# ==================================================

print()
print("========== 三、同步 fallback_filter.yaml ==========")

sync_fallback_filter(
    "openclash_custom_fallback_filter.yaml"
)


# ==================================================
# 八、同步 DNS 策略并添加自定义规则
# ==================================================

print()
print("========== 四、同步 DNS 策略 ==========")

sync_dns_policy(
    "openclash_custom_proxy_server_dns_policy.list",
    [
        '"dmitxiogkydg00fgyniqj6atx73qyafzrwe8ca3.goota.top": \'127.0.0.1:5335\'',
        '"bwgl4470zjq2660fa16xezt45r5680i3o53l6kf.goota.top": \'127.0.0.1:5335\'',
        '"geosite:google": [127.0.0.1:5335]',
        '"geosite:youtube": [127.0.0.1:5335]',
        '"geosite:telegram": [127.0.0.1:5335]',
        '"geosite:twitter": [127.0.0.1:5335]',
        '"geosite:facebook": [127.0.0.1:5335]',
        '"geosite:instagram": [127.0.0.1:5335]',
        '"geosite:reddit": [127.0.0.1:5335]',
        '"geosite:discord": [127.0.0.1:5335]',
        '"geosite:github": [127.0.0.1:5335]',
        '"geosite:google-cn": [127.0.0.1:5335]',
        '"geosite:netflix": [127.0.0.1:5335]',
        '"geosite:spotify": [127.0.0.1:5335]',
        '"geosite:tiktok": [127.0.0.1:5335]',
        '"geosite:openai": [127.0.0.1:5335]',
    ],
)


# ==================================================
# 九、同步 rules.list 并添加直连规则
# ==================================================

print()
print("========== 五、同步源码及添加直连规则 ==========")

sync_github_and_append(
    "openclash_custom_rules.list",
    [
        "##",
        "##",
        "##MY DODMAIN",
        "- DOMAIN-SUFFIX,goota.top,DIRECT",
        "##MY ROUTER",
        r"- DOMAIN,www\.asusrouter.com,DIRECT",
        "##VPS",
        "##DMIT",
        "- IP-CIDR,179.255.104.106/32,DIRECT",
        "- IP-CIDR6,2605:52c0:2:1b2c:1c51:1aff:fed4:f7cf/64,DIRECT",
        "##BWG",
        "- IP-CIDR,144.34.227.211/32,DIRECT",
        "##",
    ],
)


# ==================================================
# 十、同步 rules_2.list 并添加代理及自定义规则
# ==================================================

print()
print("========== 六、同步源码及添加自定义规则 ==========")

sync_github_and_append(
    "openclash_custom_rules_2.list",
    [
        "##",
        "##",
        "##GEOIP rules",
        "- GEOIP,CN,DIRECT",
        "##",
        "##MATCH rules ",
        '- "MATCH,🐟Other"',
        "##",
    ],
)


# ==================================================
# 十一、统一提交
# ==================================================

print()
print("========== 七、提交实际修改 ==========")

modified = commit_changes()

print()

if modified == 0:

    print(
        "所有文件均符合要求，"
        "本次没有写入任何文件。"
    )

else:

    print(
        f"完成：本次实际修改了 {modified} 个文件。"
    )

print()
print("OpenClash 自定义规则处理完成。")

PY

echo
echo "=================================================="
echo "OpenClash 自定义配置处理完成"
echo "=================================================="


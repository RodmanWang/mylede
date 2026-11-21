
#!/usr/bin/env bash
set -Eeuo pipefail

trap 'status=$?; echo "错误：源码配置在第 ${LINENO} 行执行失败（退出码：${status}）。" >&2; exit "$status"' ERR

TOPDIR="${TOPDIR:-/home/ubuntu/lede}"
CHANGE_LAN_IP="${CHANGE_LAN_IP:-false}"
LAN_IP="${LAN_IP:-192.168.1.1}"
export TOPDIR CHANGE_LAN_IP LAN_IP
cd "$TOPDIR"

echo "========== 4/7 应用自定义源码配置 =========="
echo "提示：配置脚本只修改预先指定的配置项；若目标结构不符合预期会报错停止。"

python3 - <<'PY'
from pathlib import Path
import re
import os
import ipaddress

root = Path(os.environ.get("TOPDIR", "/home/ubuntu/lede"))
change_lan_ip = os.environ.get("CHANGE_LAN_IP", "false").lower() == "true"
lan_ip = os.environ.get("LAN_IP", "192.168.1.1").strip()

if change_lan_ip:
    try:
        parsed_ip = ipaddress.IPv4Address(lan_ip)
    except ipaddress.AddressValueError as exc:
        raise SystemExit(f"LAN 地址不是合法 IPv4 地址：{lan_ip}") from exc
    private_networks = tuple(ipaddress.ip_network(value) for value in (
        "10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16"
    ))
    if not any(parsed_ip in network for network in private_networks):
        raise SystemExit("LAN 地址必须属于 RFC1918 私有 IPv4 地址范围")
    if parsed_ip.packed[-1] in (0, 255):
        raise SystemExit("LAN 地址不能使用 .0 或 .255 主机地址")

# 暂存所有配置修改，全部检查通过后再统一写入，避免中途报错造成部分文件已修改。
staged = {}

def load(rel):
    path = root / rel
    if not path.is_file():
        raise RuntimeError(f"找不到文件：{path}")

    if path not in staged:
        data = path.read_bytes()
        staged[path] = [data, data]

    return path, staged[path][1]

def save_if_changed(path, old, new):
    if path not in staged:
        staged[path] = [old, old]

    if staged[path][1] != old:
        raise RuntimeError(f"{path} 的暂存内容与待修改内容不一致，停止写入。")

    staged[path][1] = new

def commit_changes():
    for path, (original, updated) in staged.items():
        if updated != original:
            path.write_bytes(updated)
            print(f"已修改：{path}")
        else:
            print(f"无需修改：{path}")

# --------------------------------------------------
# 一、config/Config-images.in
# --------------------------------------------------

path, original = load("config/Config-images.in")
lines = original.splitlines(keepends=True)

def set_x86_default(lines, name, value):
    pattern = re.compile(
        rb"^[ \t]*config[ \t]+" + name.encode() + rb"[ \t]*(?:\r?\n)?$"
    )
    starts = [i for i, line in enumerate(lines) if pattern.match(line)]

    if len(starts) != 1:
        raise RuntimeError(
            f"{name} 的 config 定义数量不是 1，停止修改。"
        )

    start = starts[0]
    end = next(
        (
            i for i in range(start + 1, len(lines))
            if re.match(rb"^[ \t]*(?:config|menuconfig)[ \t]+", lines[i])
        ),
        len(lines),
    )

    candidates = []
    for i in range(start + 1, end):
        active_line = lines[i].partition(b"#")[0]
        if (
            re.match(rb"^[ \t]*default[ \t]+", active_line)
            and re.search(rb"\bTARGET_x86\b", active_line)
        ):
            candidates.append(i)

    if len(candidates) != 1:
        raise RuntimeError(
            f"{name} 中明确包含 TARGET_x86 的 default 数量为 "
            f"{len(candidates)}，停止修改以避免误改。"
        )

    i = candidates[0]
    updated, count = re.subn(
        rb"^([ \t]*default[ \t]+)[0-9]+",
        lambda m: m.group(1) + str(value).encode(),
        lines[i],
        count=1,
    )

    if count != 1:
        raise RuntimeError(f"无法安全修改 {name} 的默认值。")

    lines[i] = updated

set_x86_default(lines, "TARGET_KERNEL_PARTSIZE", 256)
set_x86_default(lines, "TARGET_ROOTFS_PARTSIZE", 4096)

save_if_changed(path, original, b"".join(lines))

# --------------------------------------------------
# 二、include/target.mk
# --------------------------------------------------

path, original = load("include/target.mk")
lines = original.splitlines(keepends=True)

starts = [
    i for i, line in enumerate(lines)
    if re.match(rb"^[ \t]*DEFAULT_PACKAGES\.router[ \t]*:?=", line)
]

if len(starts) != 1:
    raise RuntimeError(
        "DEFAULT_PACKAGES.router 定义数量不是 1，停止修改。"
    )

start = starts[0]
end = start + 1

while end < len(lines) and lines[end - 1].rstrip(b"\r\n").endswith(b"\\"):
    end += 1

allowed = {
    b"luci-app-ddns",
    b"luci-app-upnp",
    b"luci-app-nlbwmon",
    b"luci-theme-design",
    b"luci-app-turboacc",
}

for i in range(start, end):
    line = lines[i]
    body, marker, comment = line.partition(b"#")

    matches = list(
        re.finditer(
            rb"(?<!\S)(?:luci-app-[A-Za-z0-9_.+-]+|coremark)(?!\S)",
            body
        )
    )

    for match in reversed(matches):
        token = match.group()

        if token in allowed:
            continue

        a, b = match.span()

        if b < len(body) and body[b:b + 1] in (b" ", b"\t"):
            b += 1
        elif a > 0 and body[a - 1:a] in (b" ", b"\t"):
            a -= 1

        body = body[:a] + body[b:]

    lines[i] = body + marker + comment

for i in range(end - 1, start - 1, -1):
    line = lines[i]
    body = line.rstrip(b"\r\n")
    if re.fullmatch(rb"[ \t]*\\[ \t]*", body):
        del lines[i]
        end -= 1

section = b"\n".join(
    line.partition(b"#")[0] for line in lines[start:end]
)

missing = [
    package for package in sorted(allowed)
    if not re.search(
        rb"(?<![A-Za-z0-9_.+-])" + re.escape(package) +
        rb"(?![A-Za-z0-9_.+-])",
        section,
    )
]

if missing:
    i = end - 1
    line = lines[i]

    if line.endswith(b"\r\n"):
        ending, body = b"\r\n", line[:-2]
    elif line.endswith(b"\n"):
        ending, body = b"\n", line[:-1]
    else:
        ending, body = b"", line

    if body.rstrip().endswith(b"\\"):
        pos = body.rfind(b"\\")
        prefix, suffix = body[:pos], body[pos:]

        if prefix and prefix[-1:] not in (b" ", b"\t"):
            prefix += b" "

        body = prefix + b" ".join(missing) + b" " + suffix
    else:
        if body and body[-1:] not in (b" ", b"\t"):
            body += b" "

        body += b" ".join(missing)

    lines[i] = body + ending

save_if_changed(path, original, b"".join(lines))

# --------------------------------------------------
# 三、默认系统描述
# --------------------------------------------------

path, original = load(
    "package/lean/default-settings/files/zzz-default-settings"
)

new = original.replace(
    b"DISTRIB_DESCRIPTION='LEDE '",
    b"DISTRIB_DESCRIPTION='OpenWRT '",
)

new = new.replace(
    b'OPENWRT_RELEASE="LEDE R@BUILD_DATE@"',
    b'OPENWRT_RELEASE="OpenWRT R@BUILD_DATE@"',
)

if (
    b"DISTRIB_DESCRIPTION='OpenWRT '" not in new
    or b'OPENWRT_RELEASE="OpenWRT R@BUILD_DATE@"' not in new
):
    raise RuntimeError(
        "系统描述配置无法确认已正确设置；停止操作，请检查文件内容。"
    )

save_if_changed(path, original, new)

# --------------------------------------------------
# 四、可选修改默认 LAN 管理地址
# --------------------------------------------------

if change_lan_ip:
    rel = "package/base-files/files/bin/config_generate"
    path, original = load(rel)
    lines = original.splitlines(keepends=True)

    lan_pattern = re.compile(
        rb'^[ \t]*lan\) ipad=\$\{ipaddr:-"192\.168\.1\.1"\} ;;[ \t]*(?:\r?\n)?$'
    )
    other_pattern = re.compile(
        rb'^[ \t]*\*\) ipad=\$\{ipaddr:-"192\.168\.\$\(\(addr_offset\+\+\)\)\.1"\} ;;[ \t]*(?:\r?\n)?$'
    )
    lan_hits = [i for i, line in enumerate(lines) if lan_pattern.match(line)]
    other_hits = [i for i, line in enumerate(lines) if other_pattern.match(line)]

    if len(lan_hits) != 1 or len(other_hits) != 1:
        raise RuntimeError(
            f"{rel} 中 LAN 地址模板匹配数量异常："
            f"lan 模板 {len(lan_hits)} 处，其他接口模板 {len(other_hits)} 处"
        )

    lan_index, other_index = lan_hits[0], other_hits[0]
    if other_index <= lan_index:
        raise RuntimeError(f"{rel} 中 LAN 地址模板顺序异常")

    prefix = ".".join(lan_ip.split(".")[:2])
    for index, value in ((lan_index, lan_ip), (other_index, prefix + ".$((addr_offset++)).1")):
        ending = b"\r\n" if lines[index].endswith(b"\r\n") else b"\n"
        indent = re.match(rb"^([ \t]*)", lines[index]).group(1)
        if index == lan_index:
            body = f'lan) ipad=${{ipaddr:-"{value}"}} ;;'.encode()
        else:
            body = f'*) ipad=${{ipaddr:-"{value}"}} ;;'.encode()
        lines[index] = indent + body + ending

    save_if_changed(path, original, b"".join(lines))
    print(f"默认 LAN 地址已设置为 {lan_ip}")
else:
    print("LAN 地址保持 LEDE 上游默认值 192.168.1.1")

# --------------------------------------------------
# 五、target/linux/x86/Makefile
# --------------------------------------------------

path, original = load("target/linux/x86/Makefile")
lines = original.splitlines(keepends=True)

required = [
    b"luci-app-samba4",
    b"luci-app-smartdns",
    b"luci-app-myupdate",
    b"luci-app-openclash",
    b"luci-proto-wireguard",
    b"luci-app-uugamebooster",
    b"ipv6helper",
    b"open-vm-tools",
    b"ddns-scripts-cloudflare",
    b"iptables-mod-conntrack-extra",
    b"iptables-mod-hashlimit",
    b"iptables-mod-iprange",
    b"iptables-mod-filter",
    b"iptables-mod-ipopt",
    b"iptables-mod-nflog",
    b"iptables-mod-nfqueue",
    b"iptables-mod-trace",
    b"kmod-nft-queue",
    b"kmod-nft-tproxy",
    b"kmod-nft-fib",
    b"kmod-nft-socket",
    b"kmod-nft-netdev",
    b"kmod-nft-compat",
    b"conntrack",
    b"tcpdump",
    b"nmap",
    b"ncat",
    b"nping",
    b"socat",
    b"mtr-nojson",
    b"iperf3",
    b"tc-full",
    b"ss",
    b"nstat",
]

def has_token(data, token):
    return re.search(
        rb"(?<![A-Za-z0-9_.+-])" + re.escape(token) +
        rb"(?![A-Za-z0-9_.+-])",
        data,
    ) is not None

starts = [
    i for i, line in enumerate(lines)
    if re.match(rb"^[ \t]*DEFAULT_PACKAGES[ \t]*\+=", line)
]

if len(starts) != 1:
    raise RuntimeError(
        "target/linux/x86/Makefile 中 DEFAULT_PACKAGES += "
        f"定义数量为 {len(starts)}，不是 1，停止修改。"
    )

start = starts[0]
end = start + 1

while (
    end < len(lines)
    and lines[end - 1].rstrip(b"\r\n").endswith(b"\\")
):
    end += 1

section = b"\n".join(
    line.partition(b"#")[0] for line in lines[start:end]
)

missing = [
    package for package in required
    if not has_token(section, package)
]

if missing:
    i = end - 1
    line = lines[i]

    if line.endswith(b"\r\n"):
        ending, body = b"\r\n", line[:-2]
    elif line.endswith(b"\n"):
        ending, body = b"\n", line[:-1]
    else:
        ending, body = b"", line

    body = body.rstrip()

    if not body.endswith(b"\\"):
        body += b" \\"

    if not ending:
        ending = b"\r\n" if b"\r\n" in original else b"\n"

    lines[i] = body + ending

    max_line_length = 170
    additions = []
    current_line = b""

    for package in missing:
        if not current_line:
            current_line = package
        elif len(current_line) + 1 + len(package) <= max_line_length:
            current_line += b" " + package
        else:
            additions.append(current_line + b" \\" + ending)
            current_line = package

    if current_line:
        additions.append(current_line + ending)

    lines[end:end] = additions

    print(
        f"新增 {len(missing)} 个默认软件包，"
        "按照原 Makefile 格式自动换行。"
    )
else:
    print("x86 默认软件包均已存在，无需添加。")

save_if_changed(path, original, b"".join(lines))

# --------------------------------------------------
# 六、关闭 Rclone / SSR-Plus 的二级功能默认启用项
# --------------------------------------------------

def disable_named_config_defaults(rel, names):
    path, original = load(rel)
    lines = original.splitlines(keepends=True)

    starts = [
        i for i, line in enumerate(lines)
        if re.match(rb"^[ \t]*(?:config|menuconfig)[ \t]+", line)
    ]

    if not starts:
        raise RuntimeError(
            f"{rel} 中找不到 config/menuconfig 配置段，停止修改。"
        )

    boundaries = starts + [len(lines)]
    section_map = {name: [] for name in names}
    changed = 0

    for pos, section_start in enumerate(starts):
        section_end = boundaries[pos + 1]
        config_header = lines[section_start].lower()

        for name in names:
            if name.lower() in config_header:
                section_map[name].append((section_start, section_end))

    for name, matches in section_map.items():
        if len(matches) != 1:
            raise RuntimeError(
                f"{rel} 中 {name.decode()} 对应的配置段数量为 "
                f"{len(matches)}，不是 1，停止修改。"
            )

    for matches in section_map.values():
        section_start, section_end = matches[0]

        for i in range(section_start, section_end):
            updated, count = re.subn(
                rb"^([ \t]*default[ \t]+)y(?=([ \t]|$))",
                rb"\1n",
                lines[i],
                count=1,
                flags=re.IGNORECASE,
            )

            if count:
                lines[i] = updated
                changed += count

    if changed == 0:
        print(f"提示：{rel} 指定子功能没有 default y，无需修改。")

    save_if_changed(path, original, b"".join(lines))

    print(
        f"{rel}：已将 {changed} 个指定子功能的 default y 改为 default n。"
    )

disable_named_config_defaults(
    "feeds/luci/applications/luci-app-rclone/Makefile",
    [b"rclone-webui", b"rclone-ng"],
)

def disable_ssr_x86_64_defaults(rel):
    path, original = load(rel)
    lines = original.splitlines(keepends=True)

    changed = 0

    for i, line in enumerate(lines):
        active_line = line.partition(b"#")[0]

        if (
            re.match(rb"^[ \t]*default[ \t]+y\b", active_line, re.IGNORECASE)
            and re.search(
                rb"(?<![A-Za-z0-9_])x86_64(?![A-Za-z0-9_])",
                active_line,
                re.IGNORECASE
            )
        ):
            lines[i], count = re.subn(
                rb"^(\s*default\s+)y\b",
                rb"\1n",
                line,
                count=1,
                flags=re.IGNORECASE,
            )
            changed += count

    if changed == 0:
        print(f"提示：{rel} 未发现包含 x86_64 的 default y 配置项。")
    else:
        print(f"{rel}：已将 {changed} 个 x86_64 条件默认启用项改为 default n。")

    save_if_changed(path, original, b"".join(lines))

disable_ssr_x86_64_defaults(
    "feeds/helloworld/luci-app-ssr-plus/Makefile"
)

# --------------------------------------------------
# 七、自动同步 x86 最高可用内核版本
# --------------------------------------------------

x86_dir = root / "target/linux/x86"
versions = []

for item in x86_dir.iterdir():
    match = re.fullmatch(r"config-(\d+(?:\.\d+)+)", item.name)

    if match and item.is_file():
        version = match.group(1)
        versions.append(
            (tuple(int(part) for part in version.split(".")), version)
        )

if not versions:
    raise RuntimeError("找不到 target/linux/x86/config-版本文件。")

max_version = max(versions)[1]
print(f"x86 最高内核配置版本：{max_version}")

path, original = load("target/linux/x86/Makefile")
lines = original.splitlines(keepends=True)

for variable in (b"KERNEL_PATCHVER", b"KERNEL_TESTING_PATCHVER"):
    pattern = re.compile(
        rb"^([ \t]*" + variable + rb"[ \t]*:?=[ \t]*)"
        rb"([0-9]+(?:\.[0-9]+)+)"
        rb"([ \t]*(?:\#.*)?)"
        rb"(\r?\n)?$"
    )

    matches = [
        i for i, line in enumerate(lines)
        if pattern.match(line)
    ]

    if len(matches) != 1:
        raise RuntimeError(
            f"{variable.decode()} 的有效定义数量不是 1，"
            "停止修改，不擅自添加或重排变量。"
        )

    i = matches[0]
    match = pattern.match(lines[i])

    lines[i] = (
        match.group(1)
        + max_version.encode()
        + match.group(3)
        + (match.group(4) or b"")
    )

save_if_changed(path, original, b"".join(lines))

# 所有目标文件均检查通过后，统一写入实际文件。
commit_changes()
print("自定义配置检查完成。")
PY

echo "========== 4/7 源码配置完成 =========="

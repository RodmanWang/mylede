#!/usr/bin/env bash
set -Eeuo pipefail
trap 'status=$?; echo "错误：源码配置在第 ${LINENO} 行执行失败（退出码：${status}）。" >&2; exit "$status"' ERR

TOPDIR="${TOPDIR:-/home/ubuntu/lede}"
KERNEL_VERSION="${KERNEL_VERSION:-}"
CHANGE_LAN_IP="${CHANGE_LAN_IP:-false}"
LAN_IP="${LAN_IP:-192.168.1.1}"
export TOPDIR KERNEL_VERSION CHANGE_LAN_IP LAN_IP
cd "$TOPDIR"

echo "========== 4/6 应用保留的上游设置和 x86 软件包选择 =========="

python3 - <<'PYCODE'
from pathlib import Path
import ipaddress, os, re

root = Path(os.environ.get("TOPDIR", "/home/ubuntu/lede"))
kernel_version = os.environ.get("KERNEL_VERSION", "").strip()
change_lan_ip = os.environ.get("CHANGE_LAN_IP", "false").lower() == "true"
lan_ip = os.environ.get("LAN_IP", "192.168.1.1").strip()

RFC1918 = tuple(ipaddress.ip_network(x) for x in (
    "10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16"
))
if change_lan_ip:
    try:
        parsed = ipaddress.IPv4Address(lan_ip)
    except ipaddress.AddressValueError as exc:
        raise SystemExit(f"LAN 地址不是合法 IPv4 地址：{lan_ip}") from exc
    if not any(parsed in network for network in RFC1918):
        raise SystemExit(f"LAN 地址必须属于 RFC1918 私有地址范围：{lan_ip}")
    if parsed.packed[-1] in (0, 255):
        raise SystemExit("LAN 地址不能使用 .0 或 .255 主机地址")

staged = {}
def read(rel):
    path = root / rel
    if not path.is_file():
        raise RuntimeError(f"找不到 LEDE 上游文件：{rel}")
    data = path.read_bytes()
    staged[path] = [data, data]
    return path, data

# 1. 保留 include/target.mk 中原有的路由器默认 LuCI 插件。
path, original = read("include/target.mk")
lines = original.splitlines(keepends=True)
starts = [i for i, line in enumerate(lines)
          if re.match(rb"^[ \t]*DEFAULT_PACKAGES\.router[ \t]*(?::|\?)?=", line)]
keep = [b"luci-app-ddns", b"luci-app-upnp", b"luci-app-nlbwmon",
        b"luci-theme-design", b"luci-app-turboacc"]
# Upstream may split the variable across multiple assignments or change the
# assignment operator. Process every recognized block; if absent, preserve
# upstream defaults rather than failing because the file layout changed.
blocks = []
for start in starts:
    end = start + 1
    while end < len(lines) and lines[end - 1].rstrip(b"\r\n").endswith(b"\\"):
        end += 1
    blocks.append((start, end))
for start, end in reversed(blocks):
    for i in range(start, end):
        body, marker, comment = lines[i].partition(b"#")
        tokens = list(re.finditer(rb"(?<![A-Za-z0-9_.+-])(?:luci-app-[A-Za-z0-9_.+-]+|coremark)(?![A-Za-z0-9_.+-])", body))
        for match in reversed(tokens):
            if match.group() in keep:
                continue
            left, right = match.span()
            if right < len(body) and body[right:right+1] in (b" ", b"\t"):
                right += 1
            elif left and body[left-1:left] in (b" ", b"\t"):
                left -= 1
            body = body[:left] + body[right:]
        lines[i] = body + marker + comment
    for i in range(end - 1, start, -1):
        if re.fullmatch(rb"[ \t]*\\[ \t]*(?:\r?\n)?", lines[i]):
            del lines[i]

if starts:
    # Recalculate ranges after removing empty continuation lines, then append
    # missing preserved packages once. Never duplicate them per assignment.
    current_blocks = []
    current_starts = [
        i for i, line in enumerate(lines)
        if re.match(rb"^[ \t]*DEFAULT_PACKAGES\.router[ \t]*(?::|\?)?=", line)
    ]
    for start in current_starts:
        end = start + 1
        while end < len(lines) and lines[end - 1].rstrip(b"\r\n").endswith(b"\\"):
            end += 1
        current_blocks.append((start, end))
    section = b"\n".join(
        line.partition(b"#")[0]
        for start, end in current_blocks
        for line in lines[start:end]
    )
    missing = [
        package for package in keep
        if not re.search(rb"(?<![A-Za-z0-9_.+-])" + re.escape(package) + rb"(?![A-Za-z0-9_.+-])", section)
    ]
    if missing:
        if lines and not lines[-1].endswith((b"\n", b"\r")):
            lines[-1] += b"\n"
        lines.extend([
            b"\n",
            b"# MyLEDE preserved router packages; appended independently of upstream layout.\n",
            b"DEFAULT_PACKAGES.router += " + b" ".join(missing) + b"\n",
        ])
if not starts:
    print("上游已不再定义 DEFAULT_PACKAGES.router，保留上游默认包配置")
staged[path][1] = b"".join(lines)

# 2. 保留 x86 Makefile 的内核版本选择逻辑；默认选当前源码最高可用版本。
x86_dir = root / "target/linux/x86"
if not (x86_dir / "Makefile").is_file():
    raise RuntimeError("缺少 target/linux/x86/Makefile；当前工作流只接通 x86_64")
versions = []
for item in x86_dir.glob("config-*"):
    match = re.fullmatch(r"config-(\d+(?:\.\d+)+)", item.name)
    if match and item.is_file():
        versions.append((tuple(int(x) for x in match.group(1).split(".")), match.group(1)))
if not versions:
    raise RuntimeError("target/linux/x86 下找不到 config-内核版本文件")
selected = kernel_version or max(versions)[1]
if not re.fullmatch(r"\d+(?:\.\d+)+", selected):
    raise RuntimeError(f"内核版本格式错误：{selected}")
if not (x86_dir / f"config-{selected}").is_file():
    supported = ", ".join(v for _, v in sorted(versions))
    raise RuntimeError(f"x86 不支持内核版本 {selected}；当前可选：{supported}")
path, original = read("target/linux/x86/Makefile")
lines = original.splitlines(keepends=True)
for variable in (b"KERNEL_PATCHVER", b"KERNEL_TESTING_PATCHVER"):
    pattern = re.compile(rb"^([ \t]*" + variable + rb"[ \t]*(?::|\?)?=[ \t]*)[0-9]+(?:\.[0-9]+)+(.*?)(\r?\n)?$")
    matches = [i for i, line in enumerate(lines) if pattern.match(line)]
    if not matches and variable == b"KERNEL_TESTING_PATCHVER":
        print("上游未定义 KERNEL_TESTING_PATCHVER，保留其当前内核测试版本设置")
        continue
    if len(matches) != 1:
        raise RuntimeError(f"{variable.decode()} 定义数量为 {len(matches)}，无法安全地唯一定位")
    i = matches[0]
    match = pattern.match(lines[i])
    lines[i] = match.group(1) + selected.encode() + match.group(2) + (match.group(3) or b"")
staged[path][1] = b"".join(lines)
print(f"x86 内核版本：{selected}（{'Actions 指定' if kernel_version else '源码最高可用版本'}）")

# 3. 只有显式开启时才修改基础系统实际使用的 config_generate。
if change_lan_ip:
    rel = "package/base-files/files/bin/config_generate"
    path, original = read(rel)
    lines = original.splitlines(keepends=True)
    # Match the LAN address default independently of its current IPv4 value.
    # Identify the fallback by addr_offset semantics, not a fixed 192.168.x.x literal.
    lan_pattern = re.compile(
        rb'^([ \t]*lan\) ipad=\$\{ipaddr:-")((?:[0-9]{1,3}\.){3}[0-9]{1,3})("\} ;;[ \t]*)(\r?\n)?$'
    )
    other_pattern = re.compile(
        rb'^([ \t]*\*\) ipad=\$\{ipaddr:-")([^"]*\$\(\(addr_offset\+\+\)\)[^"]*)("\} ;;[ \t]*)(\r?\n)?$'
    )
    lan_hits = [(i, lan_pattern.match(line)) for i, line in enumerate(lines)]
    lan_hits = [(i, match) for i, match in lan_hits if match]
    other_hits = [(i, other_pattern.match(line)) for i, line in enumerate(lines)]
    other_hits = [(i, match) for i, match in other_hits if match]
    if len(lan_hits) != 1 or len(other_hits) != 1:
        raise RuntimeError(
            f"{rel} 中无法唯一识别 LAN 默认地址和 addr_offset 回退模板："
            f"lan 模板 {len(lan_hits)} 处，回退模板 {len(other_hits)} 处；拒绝修改。"
        )
    a, lan_match = lan_hits[0]
    b, other_match = other_hits[0]
    if b <= a:
        raise RuntimeError(f"{rel} 中 LAN 模板与回退模板顺序异常，拒绝修改")
    prefix = ".".join(lan_ip.split(".")[:2])
    lines[a] = lan_match.group(1) + lan_ip.encode() + lan_match.group(3) + (lan_match.group(4) or b"")
    fallback = f'{prefix}.$((addr_offset++)).1'.encode()
    lines[b] = other_match.group(1) + fallback + other_match.group(3) + (other_match.group(4) or b"")
    staged[path] = [original, b"".join(lines)]
    print(f"LAN 地址已设置为 {lan_ip}；其他静态接口将使用 {prefix}.<offset>.1")
else:
    print("LAN 地址保持 LEDE 上游默认 192.168.1.1")


# 4. x86 专用软件包统一写入 target/linux/x86/Makefile 的 DEFAULT_PACKAGES。
packages = [
    "luci-app-smartdns", "luci-app-myupdate", "luci-app-openclash",
    "luci-proto-wireguard", "luci-app-uugamebooster", "luci-app-samba4",
    "open-vm-tools", "ddns-scripts-cloudflare", "iptables-mod-conntrack-extra",
    "iptables-mod-hashlimit", "iptables-mod-iprange", "iptables-mod-filter",
    "iptables-mod-ipopt", "iptables-mod-nflog", "iptables-mod-nfqueue",
    "iptables-mod-trace", "kmod-nft-queue", "kmod-nft-tproxy", "kmod-nft-fib",
    "kmod-nft-socket", "kmod-nft-netdev", "kmod-nft-compat", "conntrack",
    "tcpdump", "nmap", "ncat", "nping", "socat", "mtr-nojson", "iperf3",
    "tc-full", "ss", "nstat", "ipv6helper", "minisign"
]

if len(packages) != len(set(packages)):
    raise RuntimeError("x86 软件包列表存在重复项")

makefile = x86_dir / "Makefile"
if makefile not in staged:
    raise RuntimeError("x86 Makefile 未进入待修改队列")

make_lines = staged[makefile][1].splitlines(keepends=True)

# Read existing DEFAULT_PACKAGES values without assuming a single += line.
# Upstream has used different assignment operators and continuation layouts.
assignment = re.compile(rb"^[ \t]*DEFAULT_PACKAGES[ \t]*(?::|\?)?=")
existing = set()
i = 0
while i < len(make_lines):
    if not assignment.match(make_lines[i]):
        i += 1
        continue
    block = []
    while i < len(make_lines):
        raw = make_lines[i].partition(b"#")[0]
        block.append(raw)
        continued = raw.rstrip(b"\r\n").rstrip().endswith(b"\\")
        i += 1
        if not continued:
            break
    for index, raw in enumerate(block):
        body = raw.strip().rstrip(b"\\").strip()
        if index == 0:
            body = re.sub(rb"^[ \t]*DEFAULT_PACKAGES[ \t]*(?::|\?)?=", b"", body).strip()
        existing.update(token.decode("ascii") for token in re.findall(rb"[A-Za-z0-9_.+-]+", body))

missing = [package for package in packages if package not in existing]
if missing:
    if make_lines and not make_lines[-1].endswith((b"\n", b"\r")):
        make_lines[-1] += b"\n"
    make_lines.extend([
        b"\n",
        b"# MyLEDE packages; appended independently of upstream DEFAULT_PACKAGES layout.\n",
        b"DEFAULT_PACKAGES += \\\n",
    ])
    for index, package in enumerate(missing):
        suffix = b" \\\n" if index < len(missing) - 1 else b"\n"
        make_lines.append(b"\t" + package.encode("ascii") + suffix)
    print(f"动态追加 x86 软件包：{len(missing)} 个")
else:
    print(f"{len(packages)} 个指定软件包已包含在上游 DEFAULT_PACKAGES 中")

staged[makefile][1] = b"".join(make_lines)

print("x86 Makefile 软件包检查通过：")
print(f"  指定软件包总数：{len(packages)}")
print(f"  本次新增数量：{len(missing)}")
print("  上游 DEFAULT_PACKAGES 原有定义未被重写")


# 5. 所有上游源码修改均在检查完成后统一写入。
for path, (old, new) in staged.items():
    if old != new:
        path.write_bytes(new)
        print(f"已修改：{path.relative_to(root)}")
    else:
        print(f"无需修改：{path.relative_to(root)}")
PYCODE

echo "========== 4/6 配置完成 =========="

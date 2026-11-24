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
          if re.match(rb"^[ \t]*DEFAULT_PACKAGES\.router[ \t]*:?=", line)]
if len(starts) != 1:
    raise RuntimeError("include/target.mk 的 DEFAULT_PACKAGES.router 定义不唯一")
start = starts[0]
end = start + 1
while end < len(lines) and lines[end - 1].rstrip(b"\r\n").endswith(b"\\"):
    end += 1
keep = [b"luci-app-ddns", b"luci-app-upnp", b"luci-app-nlbwmon",
        b"luci-theme-design", b"luci-app-turboacc"]
for i in range(start, end):
    body, marker, comment = lines[i].partition(b"#")
    tokens = list(re.finditer(rb"(?<![A-Za-z0-9_.+-])(?:luci-app-[A-Za-z0-9_.+-]+|coremark)(?![A-Za-z0-9_.+-])", body))
    for match in reversed(tokens):
        if match.group() in keep:
            continue
        a, b = match.span()
        if b < len(body) and body[b:b+1] in (b" ", b"\t"):
            b += 1
        elif a and body[a-1:a] in (b" ", b"\t"):
            a -= 1
        body = body[:a] + body[b:]
    lines[i] = body + marker + comment
for i in range(end - 1, start, -1):
    if re.fullmatch(rb"[ \t]*\\[ \t]*(?:\r?\n)?", lines[i]):
        del lines[i]
        end -= 1
section = b"\n".join(line.partition(b"#")[0] for line in lines[start:end])
missing = [p for p in keep if not re.search(rb"(?<![A-Za-z0-9_.+-])" + re.escape(p) + rb"(?![A-Za-z0-9_.+-])", section)]
if missing:
    idx = end - 1
    line = lines[idx]
    ending = b"\r\n" if line.endswith(b"\r\n") else (b"\n" if line.endswith(b"\n") else b"")
    body = line[:-len(ending)] if ending else line
    body = body.rstrip()
    if not ending:
        ending = b"\n"
    if not body:
        if idx > start:
            previous = lines[idx - 1]
            previous_ending = b"\r\n" if previous.endswith(b"\r\n") else (b"\n" if previous.endswith(b"\n") else b"")
            previous_body = previous[:-len(previous_ending)] if previous_ending else previous
            if not previous_body.rstrip().endswith(b"\\"):
                previous_body = previous_body.rstrip() + b" \\"
            lines[idx - 1] = previous_body + (previous_ending or ending)
        lines[idx] = b"\t" + b" ".join(missing) + ending
    else:
        if not body.endswith(b"\\"):
            body += b" \\"
        lines[idx] = body + ending
        lines.insert(end, b"\t" + b" ".join(missing) + ending)
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
    pattern = re.compile(rb"^([ \t]*" + variable + rb"[ \t]*:?=[ \t]*)[0-9]+(?:\.[0-9]+)+(.*?)(\r?\n)?$")
    matches = [i for i, line in enumerate(lines) if pattern.match(line)]
    if len(matches) != 1:
        raise RuntimeError(f"{variable.decode()} 定义数量不是 1，拒绝修改")
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
            f"{rel} 中预期的两条 LAN 地址模板匹配数量异常："
            f"lan 模板 {len(lan_hits)} 处，其他接口模板 {len(other_hits)} 处；拒绝修改。"
        )
    a, b = lan_hits[0], other_hits[0]
    if b <= a:
        raise RuntimeError(f"{rel} 中两条 LAN 地址模板顺序异常，拒绝修改")
    prefix = ".".join(lan_ip.split(".")[:2])
    nl1 = b"\r\n" if lines[a].endswith(b"\r\n") else b"\n"
    nl2 = b"\r\n" if lines[b].endswith(b"\r\n") else b"\n"
    indent1 = re.match(rb"^([ \t]*)", lines[a]).group(1)
    indent2 = re.match(rb"^([ \t]*)", lines[b]).group(1)
    lines[a] = indent1 + f'lan) ipad=${{ipaddr:-"{lan_ip}"}} ;;'.encode() + nl1
    lines[b] = indent2 + f'*) ipad=${{ipaddr:-"{prefix}.$((addr_offset++)).1"}} ;;'.encode() + nl2
    staged[path] = [original, b"".join(lines)]
    print(f"LAN 地址已设置为 {lan_ip}；其他静态接口将使用 {prefix}.<offset>.1")
else:
    print("LAN 地址保持 LEDE 上游默认 192.168.1.1")


# 4. x86 专用软件包统一写入 target/linux/x86/Makefile 的 DEFAULT_PACKAGES。
packages = [
    "luci-app-smartdns", "luci-app-myupdate", "luci-app-openclash",
    "luci-proto-wireguard", "luci-app-uugamebooster", "luci-app-samba4",
    "minisign",
    "open-vm-tools", "ddns-scripts-cloudflare", "iptables-mod-conntrack-extra",
    "iptables-mod-hashlimit", "iptables-mod-iprange", "iptables-mod-filter",
    "iptables-mod-ipopt", "iptables-mod-nflog", "iptables-mod-nfqueue",
    "iptables-mod-trace", "kmod-nft-queue", "kmod-nft-tproxy", "kmod-nft-fib",
    "kmod-nft-socket", "kmod-nft-netdev", "kmod-nft-compat", "conntrack",
    "tcpdump", "nmap", "ncat", "nping", "socat", "mtr-nojson", "iperf3",
    "tc-full", "ss", "nstat", "ipv6helper"
]

if len(packages) != len(set(packages)):
    raise RuntimeError("x86 软件包列表存在重复项")

makefile = x86_dir / "Makefile"
if makefile not in staged:
    raise RuntimeError("x86 Makefile 未进入待修改队列")

make_lines = staged[makefile][1].splitlines(keepends=True)

assignment = re.compile(rb"^[ \t]*DEFAULT_PACKAGES[ \t]*\+=")
starts = [
    i for i, line in enumerate(make_lines)
    if assignment.match(line)
]

if len(starts) != 1:
    raise RuntimeError(
        f"target/linux/x86/Makefile 中 DEFAULT_PACKAGES += "
        f"定义数量为 {len(starts)}，拒绝修改"
    )

start = starts[0]
end = start + 1

while (
    end < len(make_lines)
    and make_lines[end - 1].rstrip(b"\r\n").rstrip().endswith(b"\\")
):
    end += 1

# 先统一修正整个 DEFAULT_PACKAGES 区块的续行格式。
# 所有续行顶格，不允许行首 Tab 或多余空格。
for i in range(start + 1, end):
    line = make_lines[i]

    if line.endswith(b"\r\n"):
        ending = b"\r\n"
        body = line[:-2]
    elif line.endswith(b"\n"):
        ending = b"\n"
        body = line[:-1]
    else:
        ending = b""
        body = line

    make_lines[i] = body.lstrip(b" \t") + ending

# 提取当前 DEFAULT_PACKAGES 区块中的全部软件包。
block_lines = make_lines[start:end]
existing = set()

for i, line in enumerate(block_lines):
    body = line.partition(b"#")[0].strip()

    if i == 0:
        if b"+=" not in body:
            raise RuntimeError("DEFAULT_PACKAGES += 格式异常")
        body = body.split(b"+=", 1)[1].strip()

    body = body.rstrip(b"\\").strip()

    for token in re.findall(rb"[A-Za-z0-9_.+-]+", body):
        existing.add(token)

# 只追加尚未存在的软件包。
missing = [
    package for package in packages
    if package.encode("ascii") not in existing
]

# 统计整个 DEFAULT_PACKAGES 区块的原始软件包行宽。
# 第一行去掉 DEFAULT_PACKAGES += 前缀后再参与计算。
valid_lines = []

for i in range(start, end):
    body = make_lines[i].partition(b"#")[0].strip()

    if i == start:
        if b"+=" not in body:
            raise RuntimeError("DEFAULT_PACKAGES += 格式异常")
        body = body.split(b"+=", 1)[1].strip()

    body = body.rstrip(b"\\").rstrip()

    if body:
        valid_lines.append(len(body))

max_width = max(valid_lines, default=120)

print(f"x86 软件包原有最大行宽：{max_width} 字符")

# 无论是否有缺失包，都保留格式修正结果。
added_line_count = 0

if missing:
    last = make_lines[end - 1]

    if last.endswith(b"\r\n"):
        ending = b"\r\n"
        body = last[:-2]
    elif last.endswith(b"\n"):
        ending = b"\n"
        body = last[:-1]
    else:
        ending = b"\n"
        body = last

    body = body.rstrip()

    if body.endswith(b"\\"):
        body = body[:-1].rstrip()

    make_lines[end - 1] = body + b" \\" + ending

    # 新增包全部顶格，按照原有行宽排列。
    new_lines = []
    current = b""

    for package in missing:
        token = package.encode("ascii")
        candidate = token if not current else current + b" " + token

        if current and len(candidate) > max_width:
            new_lines.append(current + b" \\" + ending)
            current = token
        else:
            current = candidate

    if current:
        new_lines.append(current + ending)

    # 这里记录实际新增的 Makefile 行数，而不是软件包数量。
    added_line_count = len(new_lines)

    make_lines[end:end] = new_lines

    print(
        f"新增 x86 软件包：{len(missing)} 个，"
        f"新增 Makefile 行数：{added_line_count} 行"
    )
else:
    print(f"{len(packages)} 个指定软件包已经全部存在，不重复添加")

# 正确计算最终 DEFAULT_PACKAGES 区块的结束位置。
final_end = end + added_line_count

# 只检查 DEFAULT_PACKAGES 区块内的续行。
for i in range(start + 1, final_end):
    line = make_lines[i]

    if not line.strip() or line.lstrip().startswith(b"#"):
        continue

    if line.startswith((b" ", b"\t")):
        raise RuntimeError(
            f"x86 Makefile 第 {i + 1} 行仍存在行首空格或 Tab"
        )

# 检查指定软件包是否全部存在。
final_block = b"".join(make_lines[start:final_end])

final_tokens = set(
    re.findall(rb"[A-Za-z0-9_.+-]+", final_block)
)

not_found = [
    package for package in packages
    if package.encode("ascii") not in final_tokens
]

if not_found:
    raise RuntimeError(
        "以下软件包写入后仍未找到：" + ", ".join(not_found)
    )

staged[makefile][1] = b"".join(make_lines)

print("x86 Makefile 软件包检查通过：")
print(f"  指定软件包总数：{len(packages)}")
print(f"  本次新增数量：{len(missing)}")
print(f"  实际新增行数：{added_line_count}")
print("  续行格式：全部顶格")
print("  重复追加：已避免")


# 5. 所有上游源码修改均在检查完成后统一写入。
for path, (old, new) in staged.items():
    if old != new:
        path.write_bytes(new)
        print(f"已修改：{path.relative_to(root)}")
    else:
        print(f"无需修改：{path.relative_to(root)}")
PYCODE

echo "========== 4/6 配置完成 =========="

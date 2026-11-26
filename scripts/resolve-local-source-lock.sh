#!/usr/bin/env bash
set -Eeuo pipefail

TOPDIR="${1:-/home/ubuntu/lede}"
OUTPUT="${2:-/home/ubuntu/source-revisions.tsv}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

command -v git >/dev/null 2>&1 || { echo "错误：缺少 git。" >&2; exit 127; }
command -v python3 >/dev/null 2>&1 || { echo "错误：缺少 python3。" >&2; exit 127; }
[[ -d "$TOPDIR/.git" ]] || { echo "错误：LEDE 源码目录不是 Git 工作树：$TOPDIR" >&2; exit 1; }

python3 - "$TOPDIR" "$REPO_ROOT" "$OUTPUT" <<'PY'
import re
import subprocess
import sys
from pathlib import Path

topdir, repo_root, output = map(Path, sys.argv[1:])
def git(*args, cwd=None):
    return subprocess.check_output(["git", *args], cwd=cwd, text=True).strip()

def make_value(path, variable):
    text = path.read_text(encoding="utf-8")
    pattern = re.compile(
        rf"^[ \t]*{re.escape(variable)}[ \t]*(?:\+|:|\?)?=[ \t]*([^ \t#]+)",
        re.MULTILINE,
    )
    values = pattern.findall(text)
    if len(values) != 1:
        raise SystemExit(f"{path}: expected exactly one {variable} assignment, found {len(values)}")
    return values[0]

def git_url(url, label):
    match = re.fullmatch(r"https://github\.com/([^/]+/[^/]+?)(?:\.git)?", url)
    if not match:
        raise SystemExit(f"{label}: unsupported GitHub repository URL: {url}")
    return f"https://github.com/{match.group(1)}.git"

def resolve(url, ref, label):
    result = subprocess.check_output(["git", "ls-remote", url, ref], text=True)
    for line in result.splitlines():
        fields = line.split()
        if len(fields) == 2 and fields[1] == ref and re.fullmatch(r"[0-9a-f]{40}", fields[0]):
            return fields[0]
    raise SystemExit(f"无法解析 {label}：{url} {ref}")

rows = []
for name, path, variable in (
    ("plugin:smartdns", repo_root / "smartdns/Makefile", "PKG_SOURCE_URL"),
    ("plugin:smartdns_webui", repo_root / "smartdns/Makefile", "SMARTDNS_WEBUI_SOURCE_URL"),
    ("plugin:luci_app_smartdns", repo_root / "luci-app-smartdns/Makefile", "PKG_SOURCE_URL"),
):
    url = git_url(make_value(path, variable), name)
    commit = resolve(url, "HEAD", name)
    rows.append((name, url, "HEAD", commit))

feeds_script = (repo_root / "scripts/03-update-feeds.sh").read_text(encoding="utf-8")
match = re.search(r"""OPENCLASH_FEED=['"]src-git[ \t]+([^ \t'"]+)[ \t]+([^'"]+)['"]""", feeds_script)
if not match:
    raise SystemExit("无法从 scripts/03-update-feeds.sh 解析 OPENCLASH_FEED")
feed_name, feed_source = match.groups()
if ";" in feed_source:
    feed_url, branch = feed_source.rsplit(";", 1)
    ref = f"refs/heads/{branch}"
else:
    feed_url, ref = feed_source, "HEAD"
commit = resolve(feed_url, ref, f"feed:{feed_name}")
rows.append((f"feed:{feed_name}", feed_url, ref, commit))

lede_url = git("remote", "get-url", "origin", cwd=topdir)
lede_commit = git("rev-parse", "HEAD", cwd=topdir)
branch = git("branch", "--show-current", cwd=topdir)
lede_ref = f"refs/heads/{branch}" if branch else "HEAD"
rows.append(("LEDE", lede_url, lede_ref, lede_commit))

output.parent.mkdir(parents=True, exist_ok=True)
temporary = output.with_suffix(output.suffix + ".tmp")
temporary.write_text("".join("\t".join(row) + "\n" for row in sorted(rows)), encoding="utf-8")
temporary.replace(output)
print(f"已生成本地源码锁定文件：{output}")
for name, url, ref, commit in rows:
    print(f"{name}: {commit} ({url}, {ref})")
PY

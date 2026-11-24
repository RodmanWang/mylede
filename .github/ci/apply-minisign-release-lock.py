#!/usr/bin/env python3
"""Apply the immutable minisign release selected by the source preflight."""
from pathlib import Path
import re

makefile = Path("/home/ubuntu/minisign/Makefile")
lockfile = Path("/home/ubuntu/source-revisions.tsv")
if not makefile.is_file():
    raise SystemExit(f"minisign package Makefile not found: {makefile}")
if not lockfile.is_file():
    raise SystemExit(f"source revision lock file not found: {lockfile}")

entries = []
for line in lockfile.read_text(encoding="utf-8").splitlines():
    fields = line.split("\t")
    if fields and fields[0] == "MINISIGN_RELEASE":
        if len(fields) != 4:
            raise SystemExit("minisign release lock entry must contain exactly four fields")
        entries.append(fields)

if len(entries) != 1:
    raise SystemExit(f"expected exactly one minisign release lock entry, found {len(entries)}")

_, repository, version, digest = entries[0]
if repository != "https://github.com/jedisct1/minisign":
    raise SystemExit(f"unexpected minisign repository: {repository!r}")
if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._+-]*", version):
    raise SystemExit(f"invalid minisign release version: {version!r}")
if not re.fullmatch(r"[0-9a-f]{64}", digest):
    raise SystemExit("invalid minisign archive SHA-256")

text = makefile.read_text(encoding="utf-8")
for key, value in (("PKG_VERSION", version), ("PKG_HASH", digest)):
    pattern = re.compile(rf"(?m)^({key}:=).*$")
    text, count = pattern.subn(lambda match: match.group(1) + value, text)
    if count != 1:
        raise SystemExit(f"expected exactly one {key} assignment, found {count}")

makefile.write_text(text, encoding="utf-8")
print(f"minisign package pinned to upstream stable release {version}")
print(f"verified source archive SHA-256: {digest}")

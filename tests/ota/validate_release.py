#!/usr/bin/env python3
"""Validate the exact signed-release payload before publishing it."""
import hashlib
import json
import re
import sys
from pathlib import Path

manifest_path, image_path = map(Path, sys.argv[1:3])
manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
version = manifest.get("version", "")
if not re.fullmatch(r"\d{14}", version):
    raise SystemExit(f"invalid firmware version: {version!r}")
if manifest.get("tag") != f"mylede-v{version}":
    raise SystemExit("manifest tag does not match its version")
if manifest.get("schema_version") != 2 or manifest.get("channel") != "stable":
    raise SystemExit("unsupported manifest schema or channel")
minisign = manifest.get("minisign_release") or {}
if not re.fullmatch(r"v?(0|[1-9][0-9]*)(?:\.(0|[1-9][0-9]*))+(?:\.(0|[1-9][0-9]*))*", minisign.get("version", "")):
    raise SystemExit("invalid Minisign release version metadata")
if not re.fullmatch(r"https://github\.com/[^/]+/[^/]+(?:\.git)?", minisign.get("url", "")):
    raise SystemExit("invalid Minisign source repository URL metadata")
if not re.fullmatch(r"[0-9a-f]{64}", minisign.get("sha256", "")):
    raise SystemExit("invalid Minisign source archive SHA-256 metadata")
image = manifest.get("image") or {}
if image.get("asset") != image_path.name:
    raise SystemExit("manifest asset name does not match the release image")
digest = hashlib.sha256(image_path.read_bytes()).hexdigest()
if digest != image.get("sha256"):
    raise SystemExit("manifest SHA256 does not match the release image")
if image_path.stat().st_size != image.get("size"):
    raise SystemExit("manifest size does not match the release image")
layout = manifest.get("partition_layout") or {}
for field in ("kernel_partsize_mib", "rootfs_partsize_mib"):
    value = layout.get(field)
    if not isinstance(value, int) or isinstance(value, bool) or value <= 0:
        raise SystemExit(f"invalid partition layout field {field}: {value!r}")
if layout.get("uses_boot_part") is not True:
    raise SystemExit("x86 EFI firmware must declare uses_boot_part=true")
upstream = layout.get("upstream_defaults_mib") or {}
for field in ("kernel_partsize", "rootfs_partsize"):
    value = upstream.get(field)
    if not isinstance(value, int) or isinstance(value, bool) or value <= 0:
        raise SystemExit(f"invalid upstream partition default {field}: {value!r}")
compat = manifest.get("compatibility") or {}
if (compat.get("target"), compat.get("subtarget"), compat.get("arch")) != ("x86", "64", "x86_64"):
    raise SystemExit("unexpected firmware compatibility metadata")
for name, source in (manifest.get("sources") or {}).items():
    commit = source.get("commit", "")
    if not re.fullmatch(r"(?:[0-9a-f]{7}|[0-9a-f]{40})", commit):
        raise SystemExit(f"invalid source commit SHA for {name}: {commit!r}")
print(f"Release payload contract passed: {version} ({manifest['tag']})")

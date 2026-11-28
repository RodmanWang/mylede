#!/usr/bin/env python3
"""Update Minisign's standalone fallback only from a successful build manifest."""
import json
import re
import sys
from pathlib import Path


VERSION_RE = re.compile(r"v?(0|[1-9][0-9]*)(?:\.(0|[1-9][0-9]*))+(?:\.(0|[1-9][0-9]*))*")
SHA256_RE = re.compile(r"[0-9a-f]{64}")


def version_key(value: str) -> tuple[int, ...]:
    if not VERSION_RE.fullmatch(value):
        raise ValueError(f"invalid stable Minisign version: {value!r}")
    return tuple(int(part) for part in value.removeprefix("v").split("."))


def replace_once(text: str, pattern: str, replacement: str, label: str) -> str:
    updated, count = re.subn(pattern, replacement, text, count=1, flags=re.MULTILINE)
    if count != 1:
        raise ValueError(f"expected exactly one {label} assignment, found {count}")
    return updated


def main() -> int:
    if len(sys.argv) != 3:
        raise SystemExit("usage: update-minisign-fallback.py MANIFEST.json minisign/Makefile")

    manifest_path, makefile_path = map(Path, sys.argv[1:])
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    release = manifest.get("minisign_release")
    if not isinstance(release, dict):
        raise ValueError("manifest is missing minisign_release metadata")

    new_version = release.get("version")
    new_sha256 = release.get("sha256")
    if not isinstance(new_version, str) or not VERSION_RE.fullmatch(new_version):
        raise ValueError(f"invalid Minisign release version in manifest: {new_version!r}")
    if not isinstance(new_sha256, str) or not SHA256_RE.fullmatch(new_sha256):
        raise ValueError(f"invalid Minisign archive SHA-256 in manifest: {new_sha256!r}")

    original = makefile_path.read_text(encoding="utf-8")
    # Only the literal standalone-build fallback is mutable. The later
    # PKG_VERSION:=$(MINISIGN_LOCK_VERSION) and PKG_HASH:=$(MINISIGN_LOCK_HASH)
    # assignments are intentional CI overrides and must remain untouched.
    version_pattern = r"(?m)^(PKG_VERSION:=)(v?(?:0|[1-9][0-9]*)(?:\.(?:0|[1-9][0-9]*))+)\s*$"
    hash_pattern = r"(?m)^(PKG_HASH:=)([0-9a-f]{64})\s*$"
    version_matches = re.findall(version_pattern, original)
    hash_matches = re.findall(hash_pattern, original)
    if len(version_matches) != 1 or len(hash_matches) != 1:
        raise ValueError(
            "minisign/Makefile must contain exactly one literal PKG_VERSION and PKG_HASH fallback"
        )

    current_version = version_matches[0][1].strip()
    current_hash = hash_matches[0][1].strip()
    current_key = version_key(current_version)
    new_key = version_key(new_version)

    if new_key < current_key:
        print(
            f"保留较新的托底版本：当前 {current_version}，本次成功构建 {new_version}；不执行降级。"
        )
        return 0
    if new_key == current_key:
        if new_sha256 != current_hash:
            raise ValueError(
                f"Minisign tag {new_version} has a different archive digest from the existing fallback; "
                "refusing to silently replace a same-version source."
            )
        if current_version != new_version:
            updated = replace_once(
                original, version_pattern, rf"\g<1>{new_version}", "PKG_VERSION"
            )
            makefile_path.write_text(updated, encoding="utf-8")
            print(f"已规范化 Minisign 托底版本标签：{current_version} -> {new_version}")
        else:
            print(f"Minisign 托底版本已是 {new_version}，无需更新。")
        return 0

    updated = replace_once(
        original, r"(?m)^(PKG_VERSION:=).*$", rf"\g<1>{new_version}", "PKG_VERSION"
    )
    updated = replace_once(
        updated, hash_pattern, rf"\g<1>{new_sha256}", "PKG_HASH"
    )
    makefile_path.write_text(updated, encoding="utf-8")
    print(
        f"已更新 Minisign 托底版本：{current_version} -> {new_version}\n"
        f"PKG_HASH：{current_hash} -> {new_sha256}"
    )
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, ValueError, json.JSONDecodeError) as error:
        raise SystemExit(f"Minisign fallback update failed: {error}")

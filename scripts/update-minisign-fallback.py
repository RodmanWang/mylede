#!/usr/bin/env python3
"""Update Minisign fallback metadata after a successful firmware release."""
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


def read_literal_fallback(makefile: Path) -> tuple[str, str, str]:
    original = makefile.read_text(encoding="utf-8")
    version_pattern = r"(?m)^(PKG_VERSION:=)(v?(?:0|[1-9][0-9]*)(?:\.(?:0|[1-9][0-9]*))+)\\s*$"
    hash_pattern = r"(?m)^(PKG_HASH:=)([0-9a-f]{64})\\s*$"
    versions = re.findall(version_pattern, original)
    hashes = re.findall(hash_pattern, original)
    if len(versions) != 1 or len(hashes) != 1:
        raise ValueError("minisign/Makefile must contain exactly one literal PKG_VERSION and PKG_HASH fallback")
    return original, versions[0][1], hashes[0][1]


def update_versions_file(path: Path, version: str, digest: str) -> str:
    original = path.read_text(encoding="utf-8")
    version_pattern = r"(?m)^(PKG_VERSION:=).*$"
    hash_pattern = r"(?m)^(PKG_HASH:=).*$"
    if len(re.findall(version_pattern, original)) != 1:
        raise ValueError("minisign/versions.mk must contain exactly one PKG_VERSION assignment")
    if len(re.findall(hash_pattern, original)) != 1:
        raise ValueError("minisign/versions.mk must contain exactly one PKG_HASH assignment")
    updated = replace_once(original, version_pattern, rf"\g<1>{version}", "versions.mk PKG_VERSION")
    return replace_once(updated, hash_pattern, rf"\g<1>{digest}", "versions.mk PKG_HASH")


def main() -> int:
    if len(sys.argv) != 4:
        raise SystemExit("usage: update-minisign-fallback.py MANIFEST.json minisign/Makefile minisign/versions.mk")

    manifest_path, makefile_path, versions_path = map(Path, sys.argv[1:])
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

    # Validate both destinations before writing either one. The literal Makefile
    # fallback remains distinct from the immutable CI lock overrides below it.
    makefile_original, current_version, current_hash = read_literal_fallback(makefile_path)
    current_key = version_key(current_version)
    new_key = version_key(new_version)

    if new_key < current_key:
        target_version, target_hash = current_version, current_hash
        print(f"保留较新的托底版本：当前 {current_version}，本次成功构建 {new_version}；不执行降级。")
    elif new_key == current_key:
        if new_sha256 != current_hash:
            raise ValueError(
                f"Minisign tag {new_version} has a different archive digest from the existing fallback; "
                "refusing to silently replace a same-version source."
            )
        target_version, target_hash = new_version, new_sha256
    else:
        target_version, target_hash = new_version, new_sha256

    makefile_updated = makefile_original
    if target_version != current_version or target_hash != current_hash:
        version_pattern = r"(?m)^(PKG_VERSION:=).*$"
        hash_pattern = r"(?m)^(PKG_HASH:=).*$"
        makefile_updated = replace_once(
            makefile_updated, version_pattern, rf"\g<1>{target_version}", "Makefile PKG_VERSION"
        )
        makefile_updated = replace_once(
            makefile_updated, hash_pattern, rf"\g<1>{target_hash}", "Makefile PKG_HASH"
        )

    versions_updated = update_versions_file(versions_path, target_version, target_hash)

    # Write only after all validation and transformation has succeeded.
    if makefile_updated != makefile_original:
        makefile_path.write_text(makefile_updated, encoding="utf-8")
    if versions_updated != versions_path.read_text(encoding="utf-8"):
        versions_path.write_text(versions_updated, encoding="utf-8")

    print(
        f"Minisign fallback metadata synchronized: {target_version} "
        f"(PKG_HASH: {target_hash})"
    )
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, ValueError, json.JSONDecodeError) as error:
        raise SystemExit(f"Minisign fallback update failed: {error}")

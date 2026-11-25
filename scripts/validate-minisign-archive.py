#!/usr/bin/env python3
"""Validate the top-level layout of a minisign Git source archive."""
from pathlib import PurePosixPath
import sys
import tarfile


def validate_archive(archive: str, version: str) -> list[str]:
    root = f"minisign-{version}"
    with tarfile.open(archive, "r:gz") as tar:
        names = tar.getnames()

    # git archive emits an explicit root-directory entry without a trailing
    # slash, followed by files/directories beneath that root.
    if not names or any(
        PurePosixPath(name).is_absolute()
        or not PurePosixPath(name).parts
        or PurePosixPath(name).parts[0] != root
        or ".." in PurePosixPath(name).parts
        for name in names
    ):
        raise ValueError("minisign Git archive has an unexpected top-level path")
    return names


def main() -> None:
    archive, version = sys.argv[1:]
    names = validate_archive(archive, version)
    print(f"已从锁定 Git tag 生成归档：{version}（{len(names)} 个条目）")


if __name__ == "__main__":
    main()

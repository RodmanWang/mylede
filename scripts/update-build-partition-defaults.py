#!/usr/bin/env python3
"""Persist the last successfully published firmware partition layout."""
import json
import re
import sys
from pathlib import Path


def main() -> None:
    if len(sys.argv) != 4:
        raise SystemExit(
            "usage: update-build-partition-defaults.py MANIFEST STATE_JSON WORKFLOW_YML"
        )

    manifest_path, state_path, workflow_path = map(Path, sys.argv[1:])
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    layout = manifest.get("partition_layout") or {}
    upstream = layout.get("upstream_defaults_mib") or {}
    fields = {
        "kernel_partsize_mib": layout.get("kernel_partsize_mib"),
        "rootfs_partsize_mib": layout.get("rootfs_partsize_mib"),
        "upstream_kernel": upstream.get("kernel_partsize"),
        "upstream_rootfs": upstream.get("rootfs_partsize"),
    }
    for name, value in fields.items():
        if not isinstance(value, int) or isinstance(value, bool) or value <= 0:
            raise SystemExit(
                f"Manifest partition field is invalid; refusing to update defaults: "
                f"{name}={value!r}"
            )
    if manifest.get("schema_version") != 2:
        raise SystemExit("Only signed Manifest schema v2 can update persistent defaults")
    if layout.get("uses_boot_part") is not True:
        raise SystemExit("Manifest does not declare x86 boot-part; refusing to update defaults")

    state = {
        "schema_version": 1,
        "kernel_partsize_mib": fields["kernel_partsize_mib"],
        "rootfs_partsize_mib": fields["rootfs_partsize_mib"],
        "upstream_defaults_mib": {
            "kernel_partsize": fields["upstream_kernel"],
            "rootfs_partsize": fields["upstream_rootfs"],
        },
        "manifest_tag": manifest.get("tag"),
        "manifest_version": manifest.get("version"),
        "manifest_schema_version": manifest.get("schema_version"),
    }
    state_path.write_text(
        json.dumps(state, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )

    workflow = workflow_path.read_text(encoding="utf-8")
    field_updates = [
        (
            re.compile(
                r"(^      kernel_partsize:\n"
                r"        description: )[^\n]*"
                r"(\n        type: string\n"
                r"        required: false\n"
                r"        default: ')[^']+(')",
                re.MULTILINE,
            ),
            (
                f"内核分区大小（MiB）；上游源码默认为 "
                f"{fields['upstream_kernel']} MiB（上次成功 Manifest 记录）",
                str(fields["kernel_partsize_mib"]),
            ),
        ),
        (
            re.compile(
                r"(^      rootfs_partsize:\n"
                r"        description: )[^\n]*"
                r"(\n        type: string\n"
                r"        required: false\n"
                r"        default: ')[^']+(')",
                re.MULTILINE,
            ),
            (
                f"根文件系统分区大小（MiB）；上游源码默认为 "
                f"{fields['upstream_rootfs']} MiB（上次成功 Manifest 记录）",
                str(fields["rootfs_partsize_mib"]),
            ),
        ),
    ]
    for pattern, (description, default_value) in field_updates:
        def replace_field(match: re.Match[str]) -> str:
            return (
                match.group(1)
                + description
                + match.group(2)
                + default_value
                + match.group(3)
            )

        workflow, count = pattern.subn(replace_field, workflow, count=1)
        if count != 1:
            raise SystemExit(
                f"Could not uniquely update workflow_dispatch field: {pattern.pattern}"
            )
    workflow_path.write_text(workflow, encoding="utf-8")

    print(
        "Persisted next build defaults: kernel={} MiB, rootfs={} MiB".format(
            fields["kernel_partsize_mib"], fields["rootfs_partsize_mib"]
        )
    )
    print(
        "Updated Actions form upstream hints: kernel={} MiB, rootfs={} MiB".format(
            fields["upstream_kernel"], fields["upstream_rootfs"]
        )
    )


if __name__ == "__main__":
    main()

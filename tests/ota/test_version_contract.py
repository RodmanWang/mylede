#!/usr/bin/env python3
"""Contract tests for the MyLEDE OTA version protocol."""
import re
import unittest


VERSION_RE = re.compile(r"^\\d{4}\\.\\d{2}\\.\\d{2}\\.\\d+\\.\\d+$")


def parse_version(value: str) -> tuple[int, ...]:
    if not VERSION_RE.fullmatch(value):
        raise ValueError(f"invalid MyLEDE version: {value!r}")
    return tuple(int(part) for part in value.split("."))


def is_newer(candidate: str, current: str) -> bool:
    return parse_version(candidate) > parse_version(current)


class VersionContractTests(unittest.TestCase):
    def test_workflow_tag_is_the_manifest_version(self):
        version = "2026.11.22.123.1"
        tag = f"v{version}"
        self.assertEqual(tag[1:], version)
        self.assertEqual(parse_version(tag[1:]), (2026, 11, 22, 123, 1))

    def test_same_day_later_run_is_newer(self):
        self.assertTrue(is_newer("2026.11.22.124.1", "2026.11.22.123.1"))

    def test_retry_attempt_is_ordered(self):
        self.assertTrue(is_newer("2026.11.22.123.2", "2026.11.22.123.1"))

    def test_older_run_is_not_newer(self):
        self.assertFalse(is_newer("2026.11.22.122.9", "2026.11.22.123.1"))

    def test_invalid_tag_suffix_is_not_a_version(self):
        for value in ("2026.11.22-run123-r1", "v2026.11.22.123.1", "", "2026.11.22.123"):
            with self.subTest(value=value):
                with self.assertRaises(ValueError):
                    parse_version(value)


if __name__ == "__main__":
    unittest.main()

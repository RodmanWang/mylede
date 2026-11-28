#!/usr/bin/env python3
"""Contract tests for explicit cleanup of tags belonging to expired releases."""
from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[2]
WORKFLOW = ROOT / ".github/workflows/manual-history-reset.yml"


class HistoryResetReleaseTagTests(unittest.TestCase):
    def test_expired_release_is_deleted_before_its_tag_ref(self):
        source = WORKFLOW.read_text(encoding="utf-8")
        release_delete = 'gh release delete "$tag" --repo "$GITHUB_REPOSITORY" --yes'
        tag_delete = 'gh api --method DELETE "repos/$GITHUB_REPOSITORY/git/refs/$encoded_ref"'
        self.assertIn(release_delete, source)
        self.assertIn(tag_delete, source)
        self.assertLess(source.index(release_delete), source.index(tag_delete))
        self.assertNotIn("--cleanup-tag", source)

    def test_tag_ref_is_url_encoded_and_deletion_is_reported(self):
        source = WORKFLOW.read_text(encoding="utf-8")
        self.assertIn('urllib.parse.quote("tags/" + sys.argv[1], safe="")', source)
        self.assertIn('TAG_DELETED=$((TAG_DELETED + 1))', source)
        self.assertIn('echo "- 删除对应 Git 标签：$TAG_DELETED 个"', source)
        self.assertIn('echo "已删除 Release 及其对应 tag：$tag"', source)


if __name__ == "__main__":
    unittest.main()

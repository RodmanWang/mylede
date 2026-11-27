#!/usr/bin/env python3
"""Static contracts for local source locking and release provenance."""
from pathlib import Path
import hashlib
import os
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


class SourceLockContractTests(unittest.TestCase):
    def test_local_feed_flow_generates_lock_when_actions_lock_is_absent(self):
        script = (ROOT / "scripts/03-update-feeds.sh").read_text(encoding="utf-8")
        self.assertIn('bash "$SCRIPT_DIR/resolve-local-source-lock.sh" "$TOPDIR" "$SOURCE_LOCK"', script)
        self.assertIn('done < "$SOURCE_LOCK"', script)
        self.assertIn('while IFS=$', script)

    def test_local_resolver_uses_package_recipe_urls_and_openclash_ref(self):
        script = (ROOT / "scripts/resolve-local-source-lock.sh").read_text(encoding="utf-8")
        self.assertIn('"PKG_SOURCE_URL"', script)
        self.assertIn('"SMARTDNS_WEBUI_SOURCE_URL"', script)
        self.assertIn('f"refs/heads/{branch}"', script)
        self.assertIn('"MINISIGN_RELEASE"', script)
        self.assertIn('"--tags", "--refs"', script)
        self.assertIn('"sha256sum"', script)
        self.assertIn('"$(PKG_VERSION)"', script)
        self.assertIn('git", "ls-remote"', script)

    def test_local_resolver_writes_plugin_feed_and_minisign_locks(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            (root / "scripts").mkdir()
            (root / "smartdns").mkdir()
            (root / "luci-app-smartdns").mkdir()
            (root / "minisign").mkdir()
            lede = root / "lede"
            (lede / ".git").mkdir(parents=True)
            (root / "scripts/resolve-local-source-lock.sh").write_text(
                (ROOT / "scripts/resolve-local-source-lock.sh").read_text(encoding="utf-8"),
                encoding="utf-8",
            )
            (root / "scripts/03-update-feeds.sh").write_text(
                "OPENCLASH_FEED='src-git OpenClash https://github.com/vernesong/OpenClash.git;dev'\n",
                encoding="utf-8",
            )
            (root / "smartdns/Makefile").write_text(
                "PKG_SOURCE_URL:=https://github.com/pymumu/smartdns.git\n"
                "SMARTDNS_WEBUI_SOURCE_URL:=https://github.com/pymumu/smartdns-webui.git\n",
                encoding="utf-8",
            )
            (root / "luci-app-smartdns/Makefile").write_text(
                "PKG_SOURCE_URL:=https://github.com/pymumu/luci-app-smartdns.git\n",
                encoding="utf-8",
            )
            (root / "minisign/Makefile").write_text(
                "PKG_SOURCE_URL:=https://github.com/jedisct1/minisign/archive/refs/tags/$(PKG_VERSION)\n",
                encoding="utf-8",
            )

            fake_bin = root / "bin"
            fake_bin.mkdir()
            git_script = fake_bin / "git"
            git_script.write_text("""#!/usr/bin/env python3
import sys
args = sys.argv[1:]
sha = 'a' * 40
if args[:2] == ['remote', 'get-url']:
    print('https://github.com/coolsnowwolf/lede.git')
elif args[:2] == ['rev-parse', 'HEAD']:
    print(sha)
elif args[:2] == ['branch', '--show-current']:
    print('main')
elif args and args[0] == 'ls-remote':
    if args[1:3] == ['--tags', '--refs']:
        print('b' * 40 + '\trefs/tags/0.11')
        print('c' * 40 + '\trefs/tags/0.12')
    else:
        print(sha + '\\t' + args[2])
else:
    raise SystemExit('unexpected git arguments: ' + repr(args))
""", encoding="utf-8")
            git_script.chmod(0o755)
            curl_script = fake_bin / "curl"
            curl_script.write_text("""#!/usr/bin/env python3
import pathlib, sys
args = sys.argv[1:]
out = pathlib.Path(args[args.index('-o') + 1])
out.write_bytes(b'fixture minisign archive')
""", encoding="utf-8")
            curl_script.chmod(0o755)

            output = root / "source-revisions.tsv"
            env = dict(os.environ)
            env["PATH"] = str(fake_bin) + os.pathsep + env["PATH"]
            result = subprocess.run(
                ["bash", str(root / "scripts/resolve-local-source-lock.sh"), str(lede), str(output)],
                check=False, env=env, capture_output=True, text=True,
            )
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            rows = [line.split("\t") for line in output.read_text(encoding="utf-8").splitlines()]
            locked = {row[0]: row[1:] for row in rows}
            self.assertEqual(locked["plugin:smartdns"][1], "HEAD")
            self.assertEqual(locked["plugin:smartdns_webui"][1], "HEAD")
            self.assertEqual(locked["plugin:luci_app_smartdns"][1], "HEAD")
            self.assertEqual(locked["feed:OpenClash"][1], "refs/heads/dev")
            self.assertEqual(locked["MINISIGN_RELEASE"][1], "0.12")
            self.assertEqual(locked["MINISIGN_RELEASE"][2], hashlib.sha256(b"fixture minisign archive").hexdigest())

    def test_lede_sync_fallback_prefers_configured_upstream(self):
        script = (ROOT / "scripts/02-update-source.sh").read_text(encoding="utf-8")
        self.assertIn("'@{upstream}'", script)
        self.assertIn('LEDE_REMOTE="${LEDE_UPSTREAM%%/*}"', script)
        self.assertIn('git fetch "$LEDE_REMOTE"', script)

    def test_minisign_provenance_is_written_to_signed_manifest(self):
        workflow = (ROOT / ".github/workflows/build.yml").read_text(encoding="utf-8")
        validator = (ROOT / "tests/ota/validate_release.py").read_text(encoding="utf-8")
        self.assertIn('outputs["minisign_version"] = minisign_version', workflow)
        self.assertIn("'minisign_release': {", workflow)
        self.assertIn("'minisign_release': meta['minisign_release']", workflow)
        self.assertIn('manifest.get("minisign_release")', validator)
        self.assertIn('minisign.get("sha256", "")', validator)


if __name__ == "__main__":
    unittest.main()

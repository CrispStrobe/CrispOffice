"""Offline checks for the AyaSpell bundle's integrity and publication scope."""

from __future__ import annotations

import contextlib
import fnmatch
import hashlib
import importlib.util
import io
import json
from pathlib import Path
import sys
import tempfile
import types
import unittest
from unittest.mock import patch


_SPEC = importlib.util.spec_from_file_location(
    "ayaspell_build_bundle", Path(__file__).with_name("build_bundle.py")
)
assert _SPEC is not None and _SPEC.loader is not None
bundle = importlib.util.module_from_spec(_SPEC)
_SPEC.loader.exec_module(bundle)


class BundleTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.payloads = {
            name: f"fixture bytes for {name}\n".encode("utf-8")
            for name in bundle.FILES
        }
        self.licence = b"licence fixture\n"
        self.calls = []
        self.remote = {}
        self.bad_download = None
        self.bad_readback = None
        self.hub = types.ModuleType("huggingface_hub")
        self.hub.HfApi = lambda: self

    def create_repo(self, *args, **kwargs):
        self.calls.append(("create_repo", args, kwargs))

    def upload_folder(self, **kwargs):
        self.calls.append(("upload_folder", (), kwargs))
        out = Path(kwargs["folder_path"])
        patterns = kwargs.get("allow_patterns", ["*"])
        self.remote = {
            path.relative_to(out).as_posix(): path.read_bytes()
            for path in out.rglob("*")
            if path.is_file()
            and any(
                fnmatch.fnmatchcase(path.relative_to(out).as_posix(), pattern)
                for pattern in patterns
            )
        }
        return types.SimpleNamespace(oid="immutable-test-revision")

    def fetch(self, url):
        if url == bundle.MPL[0]:
            name, data = "MPL-1.1.txt", self.licence
        elif url.startswith(bundle.BASE):
            name = url.removeprefix(bundle.BASE)
            data = self.payloads[name]
        else:
            prefix = "https://huggingface.co/test/ayaspell/resolve/immutable-test-revision/"
            self.assertTrue(url.startswith(prefix), url)
            name = url.removeprefix(prefix)
            data = self.remote[name]
            return b"corrupt" if name == self.bad_readback else data
        if self.bad_download is not None and name == self.bad_download[0]:
            return b"corrupt" if self.bad_download[1] == "length" else b"!" + data[1:]
        return data

    def run_bundle(self, out: Path, *, publish: bool = False) -> int:
        fixture_pins = {
            name: (hashlib.sha256(data).hexdigest(), len(data))
            for name, data in self.payloads.items()
        }
        argv = ["build_bundle.py", "--output", str(out)]
        if publish:
            argv.extend(["--publish", "test/ayaspell"])
        with (
            patch.object(bundle, "FILES", fixture_pins),
            patch.object(
                bundle, "MPL", (bundle.MPL[0], hashlib.sha256(self.licence).hexdigest())
            ),
            patch.object(bundle, "fetch", self.fetch),
            patch.object(sys, "argv", argv),
            patch.dict(sys.modules, {"huggingface_hub": self.hub}),
            contextlib.redirect_stdout(io.StringIO()),
            contextlib.redirect_stderr(io.StringIO()),
        ):
            return bundle.main()

    def test_build_is_deterministic_and_does_not_publish(self):
        first, second = self.root / "one", self.root / "two"
        self.assertEqual(0, self.run_bundle(first))
        self.assertEqual(0, self.run_bundle(second))
        self.assertEqual([], self.calls)
        expected = set(self.payloads) | {"MPL-1.1.txt", "README.md", "manifest.json"}
        self.assertEqual(expected, {path.name for path in first.iterdir()})
        for name in expected:
            self.assertEqual((first / name).read_bytes(), (second / name).read_bytes())
        manifest = json.loads((first / "manifest.json").read_text())
        self.assertEqual(expected - {"manifest.json"}, set(manifest["files"]))
        for name, entry in manifest["files"].items():
            data = (first / name).read_bytes()
            self.assertEqual(entry["sha256"], hashlib.sha256(data).hexdigest())
            self.assertEqual(entry["bytes"], len(data))
        card = (first / "README.md").read_text(encoding="utf-8")
        self.assertIn("license: other\n", card)
        self.assertIn("license_name: mpl-1.1\n", card)
        self.assertIn("license_link: https://www.mozilla.org/en-US/MPL/1.1/", card)
        self.assertIn("Hunspell adapter and in-app download integration are planned", card)

    def test_publish_excludes_unrelated_files_and_includes_manifest(self):
        out = self.root / "existing"
        extras = {
            "notes.txt": b"unrelated local notes",
            "private/ar.aff": b"unrelated nested file",
            ".env": b"HF_TOKEN=not-for-publication\n",
            "private-key.txt": b"not-for-publication\n",
            "backup/ar.aff": b"old dictionary\n",
            "nested/manifest.json": b"old manifest\n",
        }
        for name, data in extras.items():
            target = out / name
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(data)
        self.assertEqual(0, self.run_bundle(out, publish=True))
        expected = set(self.payloads) | {"MPL-1.1.txt", "README.md", "manifest.json"}
        self.assertEqual(expected, set(self.remote))
        self.assertEqual(
            (out / "manifest.json").read_bytes(), self.remote["manifest.json"]
        )
        uploads = [call for call in self.calls if call[0] == "upload_folder"]
        self.assertEqual(1, len(uploads))
        self.assertEqual(sorted(expected), uploads[0][2]["allow_patterns"])
        manifest = json.loads(self.remote["manifest.json"])
        self.assertEqual(expected - {"manifest.json"}, set(manifest["files"]))
        for name, entry in manifest["files"].items():
            self.assertEqual(entry["bytes"], len(self.remote[name]))
            self.assertEqual(entry["sha256"], bundle.sha256(self.remote[name]))
        for name, data in extras.items():
            self.assertEqual(data, (out / name).read_bytes())

    def test_bad_dictionary_size_stops_before_remote_mutation(self):
        self.bad_download = ("ar.aff", "length")
        self.assertEqual(1, self.run_bundle(self.root / "bad-size", publish=True))
        self.assertEqual([], self.calls)

    def test_bad_dictionary_digest_stops_before_remote_mutation(self):
        self.bad_download = ("ar.dic", "hash")
        self.assertEqual(1, self.run_bundle(self.root / "bad-digest", publish=True))
        self.assertEqual([], self.calls)

    def test_bad_licence_stops_before_remote_mutation(self):
        self.bad_download = ("MPL-1.1.txt", "hash")
        self.assertEqual(1, self.run_bundle(self.root / "bad-licence", publish=True))
        self.assertEqual([], self.calls)

    def test_changed_file_readback_fails(self):
        self.bad_readback = "ar.dic"
        self.assertEqual(1, self.run_bundle(self.root / "readback", publish=True))
        self.assertEqual(1, len([call for call in self.calls if call[0] == "upload_folder"]))

    def test_changed_manifest_readback_fails(self):
        self.bad_readback = "manifest.json"
        self.assertEqual(1, self.run_bundle(self.root / "manifest", publish=True))
        self.assertEqual(1, len([call for call in self.calls if call[0] == "upload_folder"]))


if __name__ == "__main__":
    unittest.main()

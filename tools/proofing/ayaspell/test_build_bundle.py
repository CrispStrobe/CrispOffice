"""Offline checks for AyaSpell reproducibility, integrity and publication scope."""

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
from types import ModuleType, SimpleNamespace
import unittest
from unittest.mock import patch


BUILDER_PATH = Path(__file__).with_name("build_bundle.py")


def load_builder() -> ModuleType:
    spec = importlib.util.spec_from_file_location("ayaspell_builder", BUILDER_PATH)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class BundleBuilderTest(unittest.TestCase):
    def setUp(self) -> None:
        self.builder = load_builder()
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.output = Path(self.temp.name)
        self.payloads = {
            name: f"fixture bytes for {name}\n".encode("utf-8")
            for name in self.builder.FILES
        }
        self.payloads["ar.dic"] = "1\nكتاب\n".encode("utf-8")
        self.licence = b"fixture licence\n"
        self.builder.FILES = {
            name: (hashlib.sha256(data).hexdigest(), len(data))
            for name, data in self.payloads.items()
        }
        self.builder.MPL = (
            self.builder.MPL[0], hashlib.sha256(self.licence).hexdigest()
        )
        self.uploaded: dict[str, bytes] = {}
        self.create_calls: list[dict[str, object]] = []
        self.upload_calls: list[dict[str, object]] = []
        self.bad_download: tuple[str, str] | None = None
        self.corrupt_readback: str | None = None

    def fetch(self, url: str) -> bytes:
        if url == self.builder.MPL[0]:
            name, data = "MPL-1.1.txt", self.licence
        elif url.startswith(self.builder.BASE):
            name = url.removeprefix(self.builder.BASE)
            data = self.payloads[name]
        else:
            prefix = "https://huggingface.co/test/bundle/resolve/revision123/"
            self.assertTrue(url.startswith(prefix), url)
            name = url.removeprefix(prefix)
            data = self.uploaded[name]
            return data + b"corrupt" if name == self.corrupt_readback else data
        if self.bad_download is not None and name == self.bad_download[0]:
            if self.bad_download[1] == "length":
                return data + b"extra"
            return b"!" + data[1:]  # Same size, different digest.
        return data

    def fake_api(self) -> SimpleNamespace:
        def create_repo(repo_id: str, **kwargs: object) -> None:
            self.create_calls.append({"repo_id": repo_id, **kwargs})

        def upload_folder(**kwargs: object) -> SimpleNamespace:
            self.upload_calls.append(kwargs)
            folder = Path(str(kwargs["folder_path"]))
            patterns = kwargs.get("allow_patterns")
            for path in folder.rglob("*"):
                if not path.is_file():
                    continue
                name = path.relative_to(folder).as_posix()
                if patterns is None or any(fnmatch.fnmatchcase(name, p) for p in patterns):
                    self.uploaded[name] = path.read_bytes()
            return SimpleNamespace(oid="revision123")

        return SimpleNamespace(create_repo=create_repo, upload_folder=upload_folder)

    def run_builder(self, output: Path, *, publish: bool = False) -> int:
        argv = [str(BUILDER_PATH), "--output", str(output)]
        if publish:
            argv.extend(["--publish", "test/bundle"])
        hub = ModuleType("huggingface_hub")
        hub.HfApi = self.fake_api
        with (
            patch.object(sys, "argv", argv),
            patch.object(self.builder, "fetch", side_effect=self.fetch),
            patch.dict(sys.modules, {"huggingface_hub": hub}),
            contextlib.redirect_stdout(io.StringIO()),
            contextlib.redirect_stderr(io.StringIO()),
        ):
            return self.builder.main()

    def test_local_build_is_deterministic_without_publication(self) -> None:
        first, second = self.output / "first", self.output / "second"
        self.assertEqual(self.run_builder(first), 0)
        self.assertEqual(self.run_builder(second), 0)
        self.assertEqual(self.create_calls, [])
        self.assertEqual(self.upload_calls, [])
        expected = set(self.payloads) | {"MPL-1.1.txt", "README.md", "manifest.json"}
        self.assertEqual({path.name for path in first.iterdir()}, expected)
        self.assertEqual({path.name for path in second.iterdir()}, expected)
        for name in expected:
            self.assertEqual((first / name).read_bytes(), (second / name).read_bytes())
        manifest = json.loads((first / "manifest.json").read_text(encoding="utf-8"))
        self.assertEqual(set(manifest["files"]), expected - {"manifest.json"})
        for name, entry in manifest["files"].items():
            data = (first / name).read_bytes()
            self.assertEqual(entry["bytes"], len(data))
            self.assertEqual(entry["sha256"], hashlib.sha256(data).hexdigest())
        card = (first / "README.md").read_text(encoding="utf-8")
        self.assertTrue(card.startswith(
            "---\nlicense: other\nlicense_name: mpl-1.1\n"
            "license_link: https://www.mozilla.org/en-US/MPL/1.1/\n"
        ))
        self.assertIn("optional Hunspell adapter package is implemented", card)
        self.assertIn("Studio offers an explicit", card)
        self.assertIn("dictionary download/install dialog", card)
        self.assertIn("No dictionary is downloaded automatically", card)

    def test_publish_excludes_unrelated_existing_output_files(self) -> None:
        # These must stay local even when the caller reuses a populated directory.
        extras = {
            ".env": b"HF_TOKEN=not-for-publication\n",
            "private-key.txt": b"not-for-publication\n",
            "notes.txt": b"unrelated local notes\n",
            "private/ar.aff": b"old dictionary\n",
            "nested/manifest.json": b"old manifest\n",
        }
        for name, data in extras.items():
            path = self.output / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(data)

        self.assertEqual(self.run_builder(self.output, publish=True), 0)
        expected = set(self.payloads) | {"MPL-1.1.txt", "README.md", "manifest.json"}
        self.assertEqual(set(self.uploaded), expected)
        self.assertEqual(len(self.create_calls), 1)
        self.assertEqual(len(self.upload_calls), 1)
        self.assertEqual(self.upload_calls[0]["allow_patterns"], sorted(expected))
        self.assertEqual(
            self.uploaded["manifest.json"], (self.output / "manifest.json").read_bytes()
        )
        for name in expected:
            self.assertEqual(self.uploaded[name], (self.output / name).read_bytes())
        for name, data in extras.items():
            self.assertEqual((self.output / name).read_bytes(), data)

    def test_bad_source_or_licence_stops_before_remote_mutation(self) -> None:
        for name, mode in (
            ("ar.aff", "length"),
            ("ar.dic", "hash"),
            ("MPL-1.1.txt", "hash"),
        ):
            with self.subTest(name=name, mode=mode):
                self.bad_download = (name, mode)
                self.assertEqual(self.run_builder(self.output / name, publish=True), 1)
                self.assertEqual(self.create_calls, [])
                self.assertEqual(self.upload_calls, [])

    def test_content_readback_mismatch_is_rejected(self) -> None:
        self.corrupt_readback = "ar.dic"
        self.assertEqual(self.run_builder(self.output, publish=True), 1)
        self.assertEqual(len(self.upload_calls), 1)

    def test_manifest_readback_mismatch_is_rejected(self) -> None:
        self.corrupt_readback = "manifest.json"
        self.assertEqual(self.run_builder(self.output, publish=True), 1)
        self.assertEqual(len(self.upload_calls), 1)


if __name__ == "__main__":
    unittest.main()

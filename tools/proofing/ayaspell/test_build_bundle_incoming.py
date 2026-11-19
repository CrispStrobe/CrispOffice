"""Preserved PR #177 offline controls; card assertion follows current wording.

Imported from c268ce3bceb05f92b7868e90ba8ce7b9a5bbbe1e. The filename and
adapter/host-scope wording assertion are adapted; the seven controls remain.
"""

from __future__ import annotations

import contextlib
import fnmatch
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
        self.sources = {
            "fixture://ar.aff": b"SET UTF-8\n",
            "fixture://ar.dic": "1\nكتاب\n".encode("utf-8"),
            "fixture://licence": b"fixture licence\n",
        }
        self.builder.BASE = "fixture://"
        self.builder.FILES = {
            name: (self.builder.sha256(self.sources[f"fixture://{name}"]),
                   len(self.sources[f"fixture://{name}"]))
            for name in ("ar.aff", "ar.dic")
        }
        self.builder.MPL = (
            "fixture://licence",
            self.builder.sha256(self.sources["fixture://licence"]),
        )
        self.uploaded: dict[str, bytes] = {}
        self.create_calls: list[dict[str, object]] = []
        self.upload_calls: list[dict[str, object]] = []
        self.corrupt_readback: str | None = None

    def fetch(self, url: str) -> bytes:
        prefix = "https://huggingface.co/test/bundle/resolve/revision123/"
        if url.startswith(prefix):
            name = url[len(prefix):]
            data = self.uploaded[name]
            return data + b"corrupt" if name == self.corrupt_readback else data
        return self.sources[url]

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
                if patterns is None or any(fnmatch.fnmatch(name, p) for p in patterns):
                    self.uploaded[name] = path.read_bytes()
            return SimpleNamespace(oid="revision123")

        return SimpleNamespace(create_repo=create_repo, upload_folder=upload_folder)

    def run_builder(self, *, publish: bool = True) -> int:
        argv = [str(BUILDER_PATH), "--output", str(self.output)]
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

    def test_publish_excludes_unrelated_existing_output_files(self) -> None:
        # These must stay local even when the caller reuses a populated directory.
        extras = {
            ".env": b"HF_TOKEN=not-for-publication\n",
            "private-key.txt": b"not-for-publication\n",
            "backup/ar.aff": b"old dictionary\n",
            "nested/manifest.json": b"old manifest\n",
        }
        for name, data in extras.items():
            path = self.output / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(data)

        self.assertEqual(self.run_builder(), 0)
        expected = {"ar.aff", "ar.dic", "MPL-1.1.txt", "README.md", "manifest.json"}
        self.assertEqual(set(self.uploaded), expected)
        self.assertEqual(self.upload_calls[0]["allow_patterns"], sorted(expected))
        manifest = json.loads(self.uploaded["manifest.json"])
        self.assertEqual(set(manifest["files"]), expected - {"manifest.json"})
        for name, entry in manifest["files"].items():
            self.assertEqual(entry["bytes"], len(self.uploaded[name]))
            self.assertEqual(entry["sha256"], self.builder.sha256(self.uploaded[name]))
        for name, data in extras.items():
            self.assertEqual((self.output / name).read_bytes(), data)

    def test_bad_dictionary_digest_stops_before_remote_mutation(self) -> None:
        self.sources["fixture://ar.aff"] = b"SET UTF-9\n"  # Same size, different digest.
        self.assertEqual(self.run_builder(), 1)
        self.assertEqual(self.create_calls, [])
        self.assertEqual(self.upload_calls, [])

    def test_bad_dictionary_size_stops_before_remote_mutation(self) -> None:
        self.sources["fixture://ar.aff"] += b"extra\n"
        self.assertEqual(self.run_builder(), 1)
        self.assertEqual(self.create_calls, [])
        self.assertEqual(self.upload_calls, [])

    def test_bad_licence_stops_before_remote_mutation(self) -> None:
        self.sources["fixture://licence"] = b"unverified licence\n"
        self.assertEqual(self.run_builder(), 1)
        self.assertEqual(self.create_calls, [])
        self.assertEqual(self.upload_calls, [])

    def test_content_readback_mismatch_is_rejected(self) -> None:
        self.corrupt_readback = "ar.dic"
        self.assertEqual(self.run_builder(), 1)
        self.assertEqual(len(self.upload_calls), 1)

    def test_manifest_readback_mismatch_is_rejected(self) -> None:
        self.corrupt_readback = "manifest.json"
        self.assertEqual(self.run_builder(), 1)
        self.assertEqual(len(self.upload_calls), 1)

    def test_local_build_does_not_publish(self) -> None:
        self.assertEqual(self.run_builder(publish=False), 0)
        self.assertEqual(self.create_calls, [])
        self.assertEqual(self.upload_calls, [])
        card = (self.output / "README.md").read_text(encoding="utf-8")
        self.assertIn("optional dictionary download workflow in Studio", " ".join(card.split()))
        self.assertIn("Nothing is downloaded by default", " ".join(card.split()))


if __name__ == "__main__":
    unittest.main()

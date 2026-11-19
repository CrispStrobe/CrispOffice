"""Offline controls for the optional backend's receipt-verified host copies."""
from __future__ import annotations

from contextlib import redirect_stderr
import hashlib
import importlib.util
import io
import json
from pathlib import Path
import tempfile
import unittest
from unittest import mock


_SPEC = importlib.util.spec_from_file_location(
    "quds_hunspell_build_under_test", Path(__file__).with_name("build.py")
)
assert _SPEC is not None and _SPEC.loader is not None
build = importlib.util.module_from_spec(_SPEC)
_SPEC.loader.exec_module(build)


class HostPackagingTests(unittest.TestCase):
    def setUp(self) -> None:
        temporary = tempfile.TemporaryDirectory(prefix="hunspell-packaging-")
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.output = self.root / "built"
        self.output.mkdir()

    def receipt(self, files: dict[str, bytes]) -> Path:
        for name, data in files.items():
            path = self.output / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(data)
        receipt = self.output / "build-receipt.json"
        receipt.write_text(
            json.dumps({
                "files": {
                    name: hashlib.sha256(data).hexdigest()
                    for name, data in files.items()
                }
            }, sort_keys=True) + "\n",
            encoding="utf-8",
        )
        return receipt

    def test_copies_only_declared_files_for_selected_backend(self) -> None:
        self.receipt({
            "web/engine.mjs": b"declared module",
            "web/engine.wasm": b"declared binary",
            "native/engine.so": b"another declared backend",
        })
        (self.output / "web/stale-worker.mjs").write_bytes(b"old output")
        destination = self.root / "host"

        result = build.install(self.output, "web", destination, licenses=False)

        self.assertEqual(
            {path.name: path.read_bytes() for path in destination.iterdir()},
            {"engine.mjs": b"declared module", "engine.wasm": b"declared binary"},
        )
        self.assertEqual(result["kind"], "web")
        self.assertEqual(result["destination"], str(destination.resolve()))
        self.assertEqual(set(result["files"]), {"web/engine.mjs", "web/engine.wasm"})

    def test_tampered_artifact_rejects_before_any_destination_write(self) -> None:
        self.receipt({
            "web/a-good.mjs": b"unchanged module",
            "web/z-changed.wasm": b"original binary",
        })
        (self.output / "web/z-changed.wasm").write_bytes(b"changed binary")
        destination = self.root / "host"

        with self.assertRaisesRegex(SystemExit, "changed build artifact: web/z-changed.wasm"):
            build.install(self.output, "web", destination, licenses=False)

        self.assertFalse(destination.exists())

    def test_install_flags_require_their_backend_before_fetch(self) -> None:
        for flag, required in (
            ("--install-native", "--native"),
            ("--install-web", "--wasm"),
            ("--install-android", "--android"),
        ):
            with self.subTest(flag=flag), mock.patch.object(build, "fetch_source") as fetch:
                errors = io.StringIO()
                with mock.patch.object(
                    build.sys, "argv", ["build.py", flag, str(self.root / "host")]
                ), redirect_stderr(errors), self.assertRaises(SystemExit) as rejected:
                    build.main()
                self.assertEqual(rejected.exception.code, 2)
                self.assertIn(f"{flag} requires {required}", errors.getvalue())
                fetch.assert_not_called()
                self.assertFalse((self.root / "host").exists())

    def test_host_notices_sources_and_receipt_are_exact_copies(self) -> None:
        receipt = self.receipt({"web/engine.mjs": b"declared module"})
        destination = self.root / "host"

        build.install(self.output, "web", destination, licenses=True)

        expected = {
            path.name: path.read_bytes()
            for path in (build.LICENSES / "upstream").iterdir()
        }
        expected.update({
            name: (build.LICENSES / name).read_bytes()
            for name in ("manifest.json", "hunspell-1.7.2-library-sources.tar.gz")
        })
        expected["LICENSE.adapter"] = (build.PACKAGE / "LICENSE").read_bytes()
        expected["build-receipt.json"] = receipt.read_bytes()
        copied = destination / "licenses/hunspell"
        self.assertEqual(
            {path.name: path.read_bytes() for path in copied.iterdir()}, expected
        )
        self.assertEqual((destination / "engine.mjs").read_bytes(), b"declared module")


if __name__ == "__main__":
    unittest.main()

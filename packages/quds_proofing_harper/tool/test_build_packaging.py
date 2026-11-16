"""Host packages must contain the audited runtime, not stale generated files."""
import hashlib
import json
from pathlib import Path
import tempfile
import unittest

from build import install


class HostPackagingTest(unittest.TestCase):
    def make_distribution(self, root):
        output = root / "build"
        names = ["web/harper_worker.mjs", "web/quds_proofing_harper.js",
                 "web/quds_proofing_harper_bg.wasm", "licenses/manifest.json",
                 "licenses/notices-and-mpl-sources.tar.gz"]
        hashes = {}
        for name in names:
            path = output / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(name.encode())
            hashes[name] = hashlib.sha256(path.read_bytes()).hexdigest()
        (output / "build-receipt.json").write_text(json.dumps({"files": hashes}))
        return output

    def test_only_audited_runtime_and_notices_are_installed(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            output = self.make_distribution(root)
            (output / "web" / "stale-worker.mjs").write_text("stale")
            (output / "web" / "quds_proofing_harper.d.ts").write_text("types")
            destination = root / "host"
            install(output, "web", destination)
            self.assertEqual(
                {path.relative_to(destination).as_posix()
                 for path in destination.rglob("*") if path.is_file()},
                {"harper_worker.mjs", "quds_proofing_harper.js",
                 "quds_proofing_harper_bg.wasm", "build-receipt.json",
                 "licenses/manifest.json", "licenses/notices-and-mpl-sources.tar.gz"},
            )
            self.assertEqual((destination / "harper_worker.mjs").read_bytes(),
                             (output / "web" / "harper_worker.mjs").read_bytes())

    def test_changed_runtime_or_notices_fail_before_host_writes(self):
        for changed in ("web/harper_worker.mjs", "licenses/notices-and-mpl-sources.tar.gz"):
            with self.subTest(changed=changed), tempfile.TemporaryDirectory() as temporary:
                root = Path(temporary)
                output = self.make_distribution(root)
                (output / changed).write_bytes(b"changed after build")
                destination = root / "host"
                with self.assertRaisesRegex(ValueError, "Changed build artifact"):
                    install(output, "web", destination)
                self.assertFalse(destination.exists())


if __name__ == "__main__":
    unittest.main()

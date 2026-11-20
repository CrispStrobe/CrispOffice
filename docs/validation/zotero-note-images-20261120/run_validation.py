#!/usr/bin/env python3
"""Use the unchanged strict Zotero runner with this increment's selections.

Source the verified Flutter/PUB_CACHE environment, then pass a cohort name,
--repo, a fresh --output directory and --expected-head. --list is read-only.
The adapter preserves every source, runtime, coverage and event-audit guard.
"""
from __future__ import annotations

import hashlib
import importlib.util
import json
from pathlib import Path
import re
import sys

HERE = Path(__file__).resolve().parent
RUNNER = HERE.parent / "zotero-research-materials-20261120/run_validation.py"
EXPECTED_RUNNER_SHA256 = "4d01ed59729abaa64e3ab643e8ebcb2f7136dd2d9f02cc4b07b81a06fbb919bf"

if hashlib.sha256(RUNNER.read_bytes()).hexdigest() != EXPECTED_RUNNER_SHA256:
    raise RuntimeError("The historical strict runner changed; review it before qualification.")
spec = importlib.util.spec_from_file_location("zotero_strict_runner", RUNNER)
runner = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(runner)
runner.COHORTS = json.loads((HERE / "selection.json").read_text())["cohorts"]


class CurrentInputs(runner.Inputs):
    """Also bind the adapter and the renamed cohorts' optional host fonts."""

    def source(self):
        records = super().source()
        for name in ("run_validation.py", "selection.json", "run_static.py", "run_image_portable.py"):
            path = HERE / name
            if path.is_file():
                records[str(path.relative_to(self.repo))] = runner.file_record(path)
        return dict(sorted(records.items()))

    def snapshot(self):
        result = super().snapshot()
        # The historical runner fingerprints these fonts only for its original
        # engine-rendering name. This continuation renames that cohort and also
        # runs Studio paths that can discover optional installed Office faces.
        # Record both presence and absence; installed-font fixture tests use
        # explicit temporary directories and committed fixture bytes instead.
        paths = {
            Path("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"),
            Path("/usr/share/fonts/truetype/noto/NotoNaskhArabic-Regular.ttf"),
        }
        catalog = self.repo / "packages/quds_office_editor/lib/src/embed/office_system_fonts_io.dart"
        for filename in re.findall(r"\('([^']+\.ttf)',", catalog.read_text()):
            for directory in ("/usr/share/fonts/truetype/msttcorefonts", "/usr/share/fonts"):
                paths.add(Path(directory) / filename)
        result["host_fonts"].update({
            str(path): {"present": path.is_file(), **(runner.file_record(path) if path.is_file() else {})}
            for path in sorted(paths)
        })
        return result


runner.Inputs = CurrentInputs

if __name__ == "__main__":
    sys.exit(runner.main())

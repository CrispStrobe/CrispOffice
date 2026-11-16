#!/usr/bin/env python3
"""Create rebased copies of the exact native acceptance scripts and fixtures."""
import argparse
import re
from pathlib import Path

RECORDED_WORKSPACE = "/workspace/scratch/7b8555dd0115"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--workspace", required=True, type=Path)
    args = parser.parse_args()
    workspace = args.workspace.expanduser().resolve()
    evidence = Path(__file__).resolve().parent
    for required in ("quds_office_suite", "zotero-toolchain"):
        if not (workspace / required).is_dir():
            parser.error(f"Missing required workspace directory: {required}")
    # Originals include shell assignments and Dart string literals. Limit
    # paths to inert characters when rebasing those exact recorded scripts.
    if not re.fullmatch(r"[A-Za-z0-9_./-]+", str(workspace)):
        parser.error("Use a workspace path with letters, digits, slash, dot, underscore, or hyphen")
    target = workspace / "zotero-native-acceptance"
    if target.exists():
        parser.error(f"Refusing to replace existing acceptance data: {target}")
    target.mkdir()
    for sub in ("profile", "data", "logs", "binary"):
        (target / sub).mkdir()
    for source in (evidence / "scripts").iterdir():
        text = source.read_text().replace(RECORDED_WORKSPACE, str(workspace))
        (target / source.name).write_text(text)
    settings = (evidence / "fixtures/isolated-profile-user.js").read_text()
    (target / "profile/user.js").write_text(
        settings.replace(RECORDED_WORKSPACE, str(workspace))
    )
    (target / "synthetic-sources.bib").write_bytes(
        (evidence / "fixtures/synthetic-sources.bib").read_bytes()
    )
    print(f"Prepared isolated synthetic acceptance files: {target}")
    print("Download the official archive and pinned CSL as described in README.md.")
    print("Launch and run the scripts from the native desktop terminal.")


if __name__ == "__main__":
    main()

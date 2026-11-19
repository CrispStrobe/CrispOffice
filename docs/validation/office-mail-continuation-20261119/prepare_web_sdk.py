#!/usr/bin/env python3
"""Prepare a separate pinned Flutter web compiler component before freezing.

The component is downloaded from Flutter's official engine-specific artifact
URL and checked against web-sdk.json. The existing verified Dart/Flutter runtime
is read only; a sibling symlink supplies the layout expected by libraries.json.
This is preparation, not a test or a browser runtime acceptance result.
"""

from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path, PurePosixPath
import stat
import urllib.request
import zipfile


def digest(path: Path) -> str:
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def verify(root: Path, runtime: Path, identity: dict) -> dict:
    archive = root / "flutter-web-sdk.zip"
    if archive.stat().st_size != identity["archive_bytes"] or digest(archive) != identity["archive_sha256"]:
        raise RuntimeError("Downloaded component differs from its pinned archive")
    sdk = root / identity["sdk_directory"]
    files = {p.relative_to(sdk).as_posix(): p for p in sdk.rglob("*") if p.is_file()}
    if set(files) != set(identity["files"]):
        raise RuntimeError("The web SDK has missing or unexpected files")
    for name, path in files.items():
        expected = identity["files"][name]
        if path.is_symlink() or path.stat().st_size != expected["bytes"] or digest(path) != expected["sha256"]:
            raise RuntimeError("Changed web SDK input: " + name)
    target = runtime / "flutter/bin/cache/dart-sdk"
    if (root / identity["dart_sdk_link"]).resolve() != target.resolve():
        raise RuntimeError("The web component must reference the verified Dart SDK")
    return {"verified": True, "archive_sha256": identity["archive_sha256"],
            "file_count": len(files), "dart_sdk": str(target.resolve())}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--runtime", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--verify-only", action="store_true")
    args = parser.parse_args()
    directory = Path(__file__).resolve().parent
    identity_path = directory / "web-sdk.json"
    identity = json.loads(identity_path.read_text())
    runtime, root = args.runtime.resolve(), args.output.resolve()
    runtime_identity = json.loads((runtime / "runtime.json").read_text())
    if (runtime_identity.get("status") != "ready"
            or not runtime_identity.get("archive", {}).get("verified")
            or runtime_identity["runtime"]["engineRevision"] != identity["engine_revision"]):
        raise RuntimeError("A verified matching native/Node runtime is required first")
    if root == runtime or runtime in root.parents or root in runtime.parents:
        raise RuntimeError("Keep the web component outside the verified runtime")
    if not args.verify_only:
        if root.exists() and any(root.iterdir()):
            raise RuntimeError("Choose an empty output directory or use --verify-only")
        root.mkdir(parents=True, exist_ok=True)
        archive = root / "flutter-web-sdk.zip"
        total = 0
        with urllib.request.urlopen(identity["url"], timeout=45) as response, archive.open("wb") as stream:
            while chunk := response.read(2 * 1024 * 1024):
                total += len(chunk)
                if total > identity["archive_bytes"]:
                    raise RuntimeError("Component download exceeded its pinned size")
                stream.write(chunk)
        if total != identity["archive_bytes"] or digest(archive) != identity["archive_sha256"]:
            raise RuntimeError("Official web component archive identity differs")
        sdk = root / identity["sdk_directory"]
        with zipfile.ZipFile(archive) as bundle:
            names = set()
            for member in bundle.infolist():
                name = PurePosixPath(member.filename)
                mode = stat.S_IFMT(member.external_attr >> 16)
                if (name.is_absolute() or ".." in name.parts or member.is_dir()
                        or mode not in (0, stat.S_IFREG) or member.filename in names
                        or member.filename not in identity["files"]):
                    raise RuntimeError("Unexpected web SDK archive member")
                names.add(member.filename)
                expected = identity["files"][member.filename]
                if member.file_size != expected["bytes"]:
                    raise RuntimeError("Web SDK member size differs")
                data = bundle.read(member)
                if hashlib.sha256(data).hexdigest() != expected["sha256"]:
                    raise RuntimeError("Web SDK member bytes differ")
                target = sdk / member.filename
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(data)
            if names != set(identity["files"]):
                raise RuntimeError("Web SDK archive member list differs")
        (root / identity["dart_sdk_link"]).symlink_to(
            runtime / "flutter/bin/cache/dart-sdk", target_is_directory=True,
        )
    result = verify(root, runtime, identity)
    result.update(checked_at_utc=datetime.now(timezone.utc).isoformat(),
                  manifest_sha256=digest(identity_path),
                  preparation_script_sha256=digest(Path(__file__)),
                  verified_runtime_modified=False)
    if not args.verify_only:
        (root / "preparation.json").write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps(result, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

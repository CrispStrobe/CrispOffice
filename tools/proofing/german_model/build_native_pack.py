#!/usr/bin/env python3
"""Assemble/verify the exact qualified Linux GECToR development pack, offline.

The checked-in evidence is the trust root. Pack manifests cannot admit a new
model, binary, recipe or license claim. This tool never loads the inference library.
"""

from __future__ import annotations

import argparse
import ctypes
from dataclasses import dataclass
import gzip
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import shutil
import stat
import sys
import tempfile


class PackError(ValueError):
    """An input or output does not match the frozen development-pack contract."""


@dataclass(frozen=True)
class Pin:
    bytes: int
    sha256: str


@dataclass(frozen=True)
class Entry:
    path: str
    pin: Pin
    source_kind: str
    source_name: str


@dataclass(frozen=True)
class Policy:
    entries: tuple[Entry, ...]
    metadata: dict
    evidence_directory: Path


# Exact archived receipts, not caller-supplied "qualified" flags. A new build
# needs a reviewed evidence/pin update; there is deliberately no override flag.
_EVIDENCE_PINS = {
    "artifacts.json": Pin(3428, "ffbdbaf01be47fe7b09b4e893460b1b0acbfb16e6b22a67571bd14884f617bb0"),
    "gector-de-mixed-q4_k.gguf.manifest.json": Pin(49612, "db4ec2b79cdc3fb56c201f19fee58ad681f90182922c3725f77061e0e9efc630"),
    "qualification-mixed-q4_k-policy-v2.json.gz": Pin(94270, "1e11276c6a437336717225032731ed310c6f128561e422710357e980a2355c50"),
    "native-build-v2.json": Pin(29775, "48996f283c24dbbf57590cf0314f4ec51d7e4076f4e14b9f99172e36f542dddf"),
    "native-build-and-licenses.json": Pin(22078, "b27cf614ff09b6049b63c34e990d0bfd81252b396b4f770693d8d36ed65fc4e1"),
}
_MODEL_PIN = Pin(82756896, "549ee3a5272726d48608cebdb435aaea6a984f3f53508b20b3194a7175a5ef5b")
_LIBRARY_PIN = Pin(2064104, "9b0b7bcc0a5f19288d5ec3772594c6e64339becb56204276530d48e45c512604")
_SOURCE_MODEL_SHA256 = "6d7b43b4bd95c7a00c02c8babc7569d28558df894afe4874d96c202e6ab9a464"
_REVISION = "8e3b50beef7d775cedb7b876009e88bcf2e8d6af"
_MANIFEST = "pack.json"


def _relative(value: str) -> str:
    path = PurePosixPath(value)
    if (not value or path.is_absolute() or "\\" in value or ":" in value
            or any(part in ("", ".", "..") for part in value.split("/"))):
        raise PackError(f"Unsafe relative path: {value!r}")
    return value


def _checked_path(path: Path, kind: str) -> Path:
    path = path.absolute()
    if ".." in path.parts:
        raise PackError(f"Parent traversal is not accepted: {path}")
    for current in reversed((path, *path.parents)):
        mode = current.lstat().st_mode
        if stat.S_ISLNK(mode):
            raise PackError(f"Symlink is not accepted: {current}")
    mode = path.stat().st_mode
    if not (stat.S_ISREG(mode) if kind == "file" else stat.S_ISDIR(mode)):
        raise PackError(f"Expected a regular {kind}: {path}")
    return path


def _open_file(path: Path):
    _checked_path(path, "file")
    fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW)
    if not stat.S_ISREG(os.fstat(fd).st_mode):
        os.close(fd)
        raise PackError(f"Expected a regular file: {path}")
    return os.fdopen(fd, "rb")


def _digest(path: Path) -> Pin:
    digest = hashlib.sha256()
    size = 0
    with _open_file(path) as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
            size += len(chunk)
    return Pin(size, digest.hexdigest())


def _verify_file(path: Path, pin: Pin) -> None:
    if _digest(path) != pin:
        raise PackError(f"Size or SHA-256 mismatch: {path}")


def _object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise PackError(f"Duplicate JSON key: {key}")
        result[key] = value
    return result


def _json(data: bytes):
    return json.loads(data, object_pairs_hook=_object)


def _encode(value) -> bytes:
    return (json.dumps(value, indent=2, sort_keys=True, ensure_ascii=False) + "\n").encode()


def _policy() -> Policy:
    repository = Path(__file__).resolve().parents[3]
    directory = repository / "docs/validation/german-gector/2026-11-17-native"
    documents = {}
    for name, pin in _EVIDENCE_PINS.items():
        with _open_file(directory / name) as stream:
            data = stream.read()
        if Pin(len(data), hashlib.sha256(data).hexdigest()) != pin:
            raise PackError(f"Frozen evidence changed: {name}")
        documents[name] = _json(gzip.decompress(data) if name.endswith(".gz") else data)
    # Keep the production bundle pins and the archived reference in agreement.
    _verify_file(repository / "tools/proofing/german_model/artifacts.json", _EVIDENCE_PINS["artifacts.json"])
    conversion = documents["gector-de-mixed-q4_k.gguf.manifest.json"]
    qualification = documents["qualification-mixed-q4_k-policy-v2.json.gz"]
    build = documents["native-build-v2.json"]
    licenses = documents["native-build-and-licenses.json"]
    model = conversion["output"]
    library = build["library"]
    if (Pin(model["size_bytes"], model["sha256"]) != _MODEL_PIN
            or Pin(library["size_bytes"], library["sha256"]) != _LIBRARY_PIN
            or qualification["model"] != model
            or qualification["build"]["library"] != library
            or qualification["passed"] is not True
            or qualification["complete"] is not True
            or qualification["precision"] != "mixed-q4_k"
            or conversion["source"]["model_sha256"] != _SOURCE_MODEL_SHA256
            or conversion["source"]["revision"] != _REVISION):
        raise PackError("Frozen qualification identities are inconsistent.")
    model_directory = f"model/{model['sha256']}"
    library_path = f"native/{library['sha256']}/{library['file']}"
    entries = [Entry(f"{model_directory}/{model['file']}", _MODEL_PIN, "model", "")]
    sidecars = [row for row in documents["artifacts.json"] if row["file"] != "model.onnx"]
    if len(sidecars) != 12:
        raise PackError("The frozen bundle must contain twelve sidecars.")
    entries.extend(Entry(f"{model_directory}/{row['file']}", Pin(row["size"], row["sha256"]), "bundle", row["file"]) for row in sidecars)
    for row in licenses["installed_files"]:
        relative = library_path if row["path"] == f"lib/{library['file']}" else f"native/{row['path']}"
        entries.append(Entry(relative, Pin(row["bytes"], row["sha256"]), "native", row["path"]))
    entries.extend(Entry(f"evidence/{name}", pin, "evidence", name) for name, pin in _EVIDENCE_PINS.items())
    return Policy(tuple(entries), {
        "schema": "quds.gector.local-development-pack.v1",
        "scope": "local-development-only",
        "locale": "de-DE",
        "model": {**model, "directory": model_directory, "revision": _REVISION,
                  "source_model_sha256": _SOURCE_MODEL_SHA256, "precision": "mixed-q4_k",
                  "recipe": conversion["recipe"]},
        "native": {**library, "path": library_path, "platform": licenses["platform"],
                   "required_cpu_features": ["sse4_2", "avx", "avx2", "f16c", "fma", "bmi2"],
                   "environment_gate": "CRISPEMBED_GECTOR=1",
                   "abi": {"header": "native/include/gector.h", "batch_size": 1,
                           "maximum_tokens": 512, "vocabulary_size": 31102,
                           "label_width": 5000, "detection_width": 2,
                           "attention_mask": "all-ones-unpadded",
                           "provider_symbols": ["crispembed_gector_create", "crispembed_gector_forward", "crispembed_gector_free"]},
                   "system_dependencies": licenses["dynamic_dependencies"]},
        "qualification": {"report": "evidence/qualification-mixed-q4_k-policy-v2.json.gz",
                          "cases": 30, "saved_passes": 40, "long_tokens": [64, 128, 256],
                          "scope": "native numerical and frozen-case parity; not broad application quality"},
        "limits": ["No release, deployment, automatic download or native loading is performed.",
                   "System runtimes are not bundled; their recorded licenses are not shipping approval.",
                   "This exact Linux x86_64 binary requires the recorded ISA and compatible system ABI.",
                   "Keep model/library paths immutable for the entire process lifetime.",
                   "Read-only permissions prevent accidental writes, not owner-authorized modification."],
    }, directory)


def _entries(policy: Policy) -> tuple[Entry, ...]:
    entries = tuple(sorted(policy.entries, key=lambda entry: entry.path))
    paths = [_relative(entry.path) for entry in entries]
    if len(paths) != len(set(paths)) or _MANIFEST in paths:
        raise PackError("Duplicate pack destination.")
    for entry in entries:
        if entry.source_name:
            _relative(entry.source_name)
    return entries


def _manifest(policy: Policy) -> bytes:
    entries = _entries(policy)
    manifest = {**policy.metadata, "files": [
        {"path": entry.path, "bytes": entry.pin.bytes, "sha256": entry.pin.sha256,
         "role": entry.source_kind} for entry in entries],
        "sizes": {"payload_bytes": sum(entry.pin.bytes for entry in entries),
                  "manifest_bytes": 0, "total_bytes": 0, "file_count": len(entries) + 1}}
    # Account for pack.json itself without putting a self-referential hash in it.
    while True:
        encoded = _encode(manifest)
        if len(encoded) == manifest["sizes"]["manifest_bytes"]:
            return encoded
        manifest["sizes"]["manifest_bytes"] = len(encoded)
        manifest["sizes"]["total_bytes"] = manifest["sizes"]["payload_bytes"] + len(encoded)


def _verify_pack(root: Path, policy: Policy) -> dict:
    root = _checked_path(root, "directory")
    with _open_file(root / _MANIFEST) as stream:
        actual = stream.read()
    parsed = _json(actual)  # Reject duplicate keys, even if later values agree.
    if not isinstance(parsed, dict):
        raise PackError("Pack manifest must be a JSON object.")
    for row in parsed.get("files", []):
        _relative(row["path"])
    expected = _manifest(policy)
    if actual != expected:
        raise PackError("Pack manifest differs from the frozen development-pack contract.")
    expected_files = {_MANIFEST, *(entry.path for entry in _entries(policy))}
    expected_dirs = {"."}
    for relative in expected_files:
        expected_dirs.update(str(parent) for parent in PurePosixPath(relative).parents)
    actual_files = set()
    for current, directories, files in os.walk(root, followlinks=False):
        current = Path(current)
        for path in [current, *(current / name for name in directories)]:
            mode = path.lstat().st_mode
            if (not stat.S_ISDIR(mode) or mode & 0o222
                    or str(path.relative_to(root)) not in expected_dirs):
                raise PackError(f"Unexpected, writable or symlinked directory: {path}")
        for name in files:
            path = current / name
            mode = path.lstat().st_mode
            if not stat.S_ISREG(mode) or mode & 0o222:
                raise PackError(f"Non-regular or writable pack file: {path}")
            actual_files.add(path.relative_to(root).as_posix())
    if actual_files != expected_files:
        raise PackError("Pack contains missing or unexpected files.")
    for entry in _entries(policy):
        _verify_file(root / entry.path, entry.pin)
    return {"verified": True, "scope": "local-development-only", "pack": str(root),
            "manifest": str(root / _MANIFEST), "manifest_sha256": hashlib.sha256(actual).hexdigest(),
            "model_directory": str(root / policy.metadata["model"]["directory"]),
            "model": policy.metadata["model"],
            "library": str(root / policy.metadata["native"]["path"]),
            "library_sha256": policy.metadata["native"]["sha256"], "sizes": parsed["sizes"]}


def _publish_new(stage: Path, output: Path) -> None:
    # rename() may replace an existing empty directory on POSIX. Linux's
    # RENAME_NOREPLACE gives the required atomic fresh-publication guarantee.
    if not sys.platform.startswith("linux"):
        raise PackError("Atomic development-pack construction is supported on Linux only.")
    libc = ctypes.CDLL(None, use_errno=True)
    rename = getattr(libc, "renameat2", None)
    if rename is None:
        raise PackError("renameat2(RENAME_NOREPLACE) is required; no unsafe fallback.")
    rename.argtypes = [ctypes.c_int, ctypes.c_char_p, ctypes.c_int, ctypes.c_char_p, ctypes.c_uint]
    rename.restype = ctypes.c_int
    if rename(-100, os.fsencode(stage), -100, os.fsencode(output), 1) != 0:
        error = ctypes.get_errno()
        raise OSError(error, os.strerror(error), str(output))


def _build_pack(model: Path, bundle: Path, native_install: Path, output: Path, policy: Policy) -> dict:
    model = _checked_path(model, "file")
    bundle = _checked_path(bundle, "directory")
    native_install = _checked_path(native_install, "directory")
    output = output.absolute()
    _checked_path(output.parent, "directory")
    if ".." in output.parts or os.path.lexists(output):
        raise PackError("Output must be a new path without parent traversal.")
    roots = {"bundle": bundle, "native": native_install, "evidence": policy.evidence_directory}
    if any(output.is_relative_to(root) or root.is_relative_to(output) for root in roots.values()):
        raise PackError("Output must not overlap an input directory.")
    sources = [(entry, model if entry.source_kind == "model" else roots[entry.source_kind] / entry.source_name)
               for entry in _entries(policy)]
    for entry, source in sources:
        _verify_file(source, entry.pin)
    stage = Path(tempfile.mkdtemp(prefix=f".{output.name}.stage-", dir=output.parent))
    try:
        for entry, source in sources:
            target = stage / entry.path
            target.parent.mkdir(parents=True, exist_ok=True)
            with _open_file(source) as original, target.open("xb") as copied:
                shutil.copyfileobj(original, copied, 1024 * 1024)
                copied.flush()
                os.fsync(copied.fileno())
            _verify_file(target, entry.pin)
        with (stage / _MANIFEST).open("xb") as stream:
            stream.write(_manifest(policy))
            stream.flush()
            os.fsync(stream.fileno())
        for current, directories, files in os.walk(stage, topdown=False):
            for name in files:
                os.chmod(Path(current) / name, 0o444)
            os.chmod(current, 0o555)
            fd = os.open(current, os.O_RDONLY | os.O_DIRECTORY)
            try:
                os.fsync(fd)
            finally:
                os.close(fd)
        _verify_pack(stage, policy)
        _publish_new(stage, output)
        fd = os.open(output.parent, os.O_RDONLY | os.O_DIRECTORY)
        try:
            os.fsync(fd)
        finally:
            os.close(fd)
        return _verify_pack(output, policy)
    finally:
        if stage.exists():
            # Only this invocation's private staging tree is ever cleaned up.
            for current, directories, files in os.walk(stage):
                os.chmod(current, 0o700)
            shutil.rmtree(stage)


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    build = commands.add_parser("build", help="Build a fresh, read-only local development pack")
    build.add_argument("--model", type=Path, required=True)
    build.add_argument("--bundle", type=Path, required=True)
    build.add_argument("--native-install", type=Path, required=True)
    build.add_argument("--output", type=Path, required=True)
    verify = commands.add_parser("verify", help="Verify an existing pack against frozen trusted pins")
    verify.add_argument("--pack", type=Path, required=True)
    args = parser.parse_args(argv)
    try:
        policy = _policy()
        result = (_build_pack(args.model, args.bundle, args.native_install, args.output, policy)
                  if args.command == "build" else _verify_pack(args.pack, policy))
        print(json.dumps(result, indent=2, sort_keys=True))
        return 0
    except (OSError, ValueError, KeyError, TypeError) as error:
        print(f"GECToR development pack rejected: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())

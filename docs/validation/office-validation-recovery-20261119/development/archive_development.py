#!/usr/bin/env python3
"""Preserve explicitly labelled evidence sources and independently verify them.

Only --source inputs are read. Directory sources include all descendants,
including empty files/directories and symbolic links without following them.
No source is changed. Archives use sorted PAX headers, exact nanosecond mtimes,
original permission modes and normalized zero ownership. A second complete
build must reproduce the first archive byte for byte before publication.
"""

from __future__ import annotations

import argparse
from decimal import Decimal
import hashlib
import json
import lzma
import os
from pathlib import Path, PurePosixPath
import shutil
import stat
import sys
import tarfile
import tempfile


BLOCK = 1024 * 1024


def sha(path: Path) -> str:
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def write_json(path: Path, value: object) -> None:
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def safe_name(name: str) -> bool:
    path = PurePosixPath(name)
    return bool(path.parts) and not path.is_absolute() and ".." not in path.parts and str(path) == name


def parse_sources(arguments: list[str]) -> dict[str, Path]:
    sources: dict[str, Path] = {}
    for argument in arguments:
        label, separator, raw = argument.partition("=")
        if not separator or not safe_name(label) or label in sources or not raw:
            raise ValueError("Every source must have a unique safe LABEL=PATH: " + argument)
        path = Path(os.path.abspath(raw))
        path.lstat()
        sources[label] = path
    return dict(sorted(sources.items()))


def mtime_text(nanoseconds: int) -> str:
    seconds, fraction = divmod(nanoseconds, 1_000_000_000)
    return f"{seconds}.{fraction:09d}"


def inventory(sources: dict[str, Path]) -> list[dict]:
    members: dict[str, dict] = {}

    def visit(path: Path, name: str, source: str, relative: str) -> None:
        if name in members or not safe_name(name):
            raise ValueError("Colliding/unsafe archive member: " + name)
        before = path.lstat()
        row = {"name": name, "source": source, "source_relative": relative,
               "mode": stat.S_IMODE(before.st_mode), "mtime_ns": before.st_mtime_ns}
        if stat.S_ISREG(before.st_mode):
            row.update(type="file", bytes=before.st_size, sha256=sha(path))
        elif stat.S_ISDIR(before.st_mode):
            row.update(type="directory")
        elif stat.S_ISLNK(before.st_mode):
            row.update(type="symlink", link_target=os.readlink(path))
        else:
            raise ValueError("Unsupported special source member: " + str(path))
        after = path.lstat()
        if (before.st_mode, before.st_size, before.st_mtime_ns) != (
                after.st_mode, after.st_size, after.st_mtime_ns):
            raise RuntimeError("Source changed while inventoried: " + str(path))
        members[name] = row
        if row["type"] == "directory":
            for child in sorted(path.iterdir(), key=lambda child: child.name):
                child_relative = str(PurePosixPath(relative) / child.name) if relative else child.name
                visit(child, name + "/" + child.name, source, child_relative)

    for label, path in sources.items():
        visit(path, label, label, "")
    return [members[name] for name in sorted(members)]


def source_path(row: dict, sources: dict[str, Path]) -> Path:
    root = sources[row["source"]]
    return root / row["source_relative"] if row["source_relative"] else root


def build_archive(tar_path: Path, xz_path: Path, members: list[dict], sources: dict[str, Path]) -> None:
    with tarfile.open(tar_path, "w", format=tarfile.PAX_FORMAT) as archive:
        for row in members:
            info = tarfile.TarInfo(row["name"])
            info.mode = row["mode"]
            info.uid = info.gid = 0
            info.uname = info.gname = ""
            info.mtime = row["mtime_ns"] // 1_000_000_000
            info.pax_headers = {"mtime": mtime_text(row["mtime_ns"])}
            if row["type"] == "file":
                info.size = row["bytes"]
                with source_path(row, sources).open("rb") as stream:
                    archive.addfile(info, stream)
            else:
                info.type = tarfile.DIRTYPE if row["type"] == "directory" else tarfile.SYMTYPE
                if row["type"] == "symlink":
                    info.linkname = row["link_target"]
                archive.addfile(info)
    with tar_path.open("rb") as raw, lzma.open(
            xz_path, "wb", format=lzma.FORMAT_XZ, check=lzma.CHECK_SHA256, preset=6) as compressed:
        shutil.copyfileobj(raw, compressed, BLOCK)


def compare_files(first: Path, second: Path) -> bool:
    with first.open("rb") as left, second.open("rb") as right:
        while True:
            a, b = left.read(BLOCK), right.read(BLOCK)
            if a != b:
                return False
            if not a:
                return True


def verify_tar(tar_path: Path, members: list[dict], sources: dict[str, Path] | None) -> dict:
    expected = {row["name"]: row for row in members}
    if len(expected) != len(members):
        raise ValueError("Duplicate index members")
    seen: set[str] = set()
    regular = original_bytes = 0
    with tarfile.open(tar_path, "r:") as archive:
        for info in archive:
            if info.name in seen or info.name not in expected or not safe_name(info.name):
                raise ValueError("Unexpected/duplicate/unsafe tar member: " + info.name)
            seen.add(info.name)
            row = expected[info.name]
            kind = "file" if info.isfile() else "directory" if info.isdir() else "symlink" if info.issym() else "other"
            actual_mtime = Decimal(info.pax_headers.get("mtime", str(info.mtime)))
            if (kind != row["type"] or info.mode != row["mode"]
                    or actual_mtime != Decimal(row["mtime_ns"]) / Decimal(1_000_000_000)
                    or info.uid != 0 or info.gid != 0):
                raise ValueError("Tar metadata mismatch: " + info.name)
            if kind == "symlink" and info.linkname != row["link_target"]:
                raise ValueError("Tar link target mismatch: " + info.name)
            if kind != "file":
                continue
            if info.size != row["bytes"]:
                raise ValueError("Tar file size mismatch: " + info.name)
            digest = hashlib.sha256()
            count = 0
            stream = archive.extractfile(info)
            if stream is None:
                raise ValueError("Unreadable regular tar member: " + info.name)
            original = source_path(row, sources).open("rb") if sources is not None else None
            try:
                while data := stream.read(BLOCK):
                    count += len(data)
                    digest.update(data)
                    if original is not None and data != original.read(len(data)):
                        raise ValueError("Original-byte mismatch: " + info.name)
                if original is not None and original.read(1):
                    raise ValueError("Original has extra bytes: " + info.name)
            finally:
                stream.close()
                if original is not None:
                    original.close()
            if count != row["bytes"] or digest.hexdigest() != row["sha256"]:
                raise ValueError("Tar content hash mismatch: " + info.name)
            regular += 1
            original_bytes += count
    if seen != set(expected):
        raise ValueError("Tar omitted indexed members: " + repr(sorted(set(expected) - seen)))
    return {"members": len(seen), "regular_files": regular, "regular_bytes": original_bytes,
            "exact_member_set": True, "all_sizes_hashes_modes_mtimes_match": True,
            "all_original_file_bytes_match": sources is not None}


def verify(index_path: Path, sources: dict[str, Path] | None, reconstruct: Path | None = None) -> dict:
    index = json.loads(index_path.read_text(encoding="utf-8"))
    if sources is not None and set(sources) != set(index["sources"]):
        raise ValueError("Original-byte comparison requires every indexed --source label")
    with tempfile.TemporaryDirectory(prefix=".verify-", dir=index_path.parent) as temporary:
        work = Path(temporary)
        compressed = work / "reconstructed.tar.xz"
        expected_offset = 0
        with compressed.open("wb") as joined:
            for part in index["archive"]["parts"]:
                name = part["name"]
                if Path(name).name != name or part["offset"] != expected_offset:
                    raise ValueError("Unsafe or noncontiguous archive part")
                path = index_path.parent / name
                if path.stat().st_size != part["bytes"] or sha(path) != part["sha256"]:
                    raise ValueError("Archive part mismatch: " + name)
                with path.open("rb") as stream:
                    shutil.copyfileobj(stream, joined, BLOCK)
                expected_offset += part["bytes"]
        archive = index["archive"]
        if compressed.stat().st_size != archive["bytes"] or sha(compressed) != archive["sha256"]:
            raise ValueError("Reconstructed archive mismatch")
        raw = work / "reconstructed.tar"
        with lzma.open(compressed, "rb") as stream, raw.open("wb") as output:
            shutil.copyfileobj(stream, output, BLOCK)
        if raw.stat().st_size != archive["tar_bytes"] or sha(raw) != archive["tar_sha256"]:
            raise ValueError("Decompressed tar mismatch")
        result = verify_tar(raw, index["members"], sources)
        if sources is not None and inventory(sources) != index["members"]:
            raise ValueError("Original source inventory changed")
        if reconstruct is not None:
            with reconstruct.open("xb") as output, compressed.open("rb") as stream:
                shutil.copyfileobj(stream, output, BLOCK)
        result.update(index_sha256=sha(index_path), compressed_archive_sha256=archive["sha256"],
                      decompressed_tar_sha256=archive["tar_sha256"],
                      every_part_verified=True, byte_identical_reconstruction=True)
        return result


def pack(args: argparse.Namespace) -> dict:
    sources = parse_sources(args.source)
    destination = args.output.resolve()
    destination.mkdir(parents=True, exist_ok=True)
    if not safe_name(args.name) or Path(args.name).name != args.name or args.part_bytes < 1:
        raise ValueError("Use a plain archive name and positive part size")
    if any(destination.glob(args.name + ".*")):
        raise FileExistsError("Archive output already exists; preserve it and use another name")
    for path in sources.values():
        if path == destination or path in destination.parents:
            raise ValueError("Do not place archive output inside a source")
    members = inventory(sources)
    print(f"Inventoried {len(members)} exact members", flush=True)
    with tempfile.TemporaryDirectory(prefix=".pack-", dir=destination) as temporary:
        work = Path(temporary)
        raw, compressed = work / "first.tar", work / "first.tar.xz"
        build_archive(raw, compressed, members, sources)
        source_verification = verify_tar(raw, members, sources)
        print("Verified every original file byte and archived mode/mtime", flush=True)
        second_raw, second_xz = work / "second.tar", work / "second.tar.xz"
        build_archive(second_raw, second_xz, members, sources)
        if not compare_files(raw, second_raw) or not compare_files(compressed, second_xz):
            raise RuntimeError("Independent second build was not byte-identical")
        if inventory(sources) != members:
            raise RuntimeError("Source inventory changed during reproduction")
        print("Second complete archive build reproduced identical bytes", flush=True)
        size = compressed.stat().st_size
        parts = []
        with compressed.open("rb") as stream:
            number, offset = 1, 0
            while data := stream.read(args.part_bytes):
                name = args.name + ".tar.xz" + (f".part-{number:04d}" if size > args.part_bytes else "")
                path = destination / name
                with path.open("xb") as output:
                    output.write(data)
                parts.append({"name": name, "bytes": len(data), "offset": offset,
                              "sha256": hashlib.sha256(data).hexdigest()})
                number += 1
                offset += len(data)
        index = {"schema": 1, "purpose": "Unfrozen development and runtime-preparation preservation; not aggregate acceptance",
                 "producer": {"path": Path(__file__).name, "sha256": sha(Path(__file__)),
                              "python": sys.version},
                 "sources": {label: str(path) for label, path in sources.items()},
                 "archive": {"format": "POSIX PAX tar compressed with XZ", "xz_preset": 6,
                             "xz_check": "SHA256", "ownership": "normalized uid=gid=0; names empty",
                             "metadata": "original permission modes and nanosecond modification timestamps",
                             "reconstructed_name": args.name + ".tar.xz", "bytes": size,
                             "sha256": sha(compressed), "tar_bytes": raw.stat().st_size,
                             "tar_sha256": sha(raw), "maximum_part_bytes": args.part_bytes, "parts": parts},
                 "members": members, "packing_verification": source_verification,
                 "second_complete_build_byte_identical": True}
        index_path = destination / (args.name + ".index.json")
        write_json(index_path, index)
        result = verify(index_path, sources)
        result["second_complete_build_byte_identical"] = True
        write_json(destination / (args.name + ".verification.json"), result)
        return result


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    create = commands.add_parser("pack")
    create.add_argument("--source", action="append", required=True, metavar="LABEL=PATH")
    create.add_argument("--output", type=Path, required=True)
    create.add_argument("--name", default="development-evidence")
    create.add_argument("--part-bytes", type=int, default=BLOCK)
    check = commands.add_parser("verify")
    check.add_argument("--index", type=Path, required=True)
    check.add_argument("--source", action="append", metavar="LABEL=PATH")
    check.add_argument("--reconstruct", type=Path,
                       help="Write the verified concatenated .tar.xz to a new file")
    args = parser.parse_args()
    result = pack(args) if args.command == "pack" else verify(
        args.index.resolve(), parse_sources(args.source) if args.source else None, args.reconstruct)
    print(json.dumps(result, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

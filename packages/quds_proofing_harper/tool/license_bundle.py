#!/usr/bin/env python3
"""Audit actual active Cargo dependencies and preserve their original notices.

Invoke for every shipped target. The resulting directory must accompany the
binary/Wasm distribution. MPL source archives are included, with Cargo checksums.
"""
from __future__ import annotations

import argparse
import hashlib
import io
import json
import os
from pathlib import Path
import re
import subprocess
import tarfile
import tomllib
import urllib.request

PACKAGE = Path(__file__).resolve().parents[1]
MANIFEST = PACKAGE / "native" / "Cargo.toml"
ALLOWED = {
    "MIT", "Apache-2.0", "BSD-2-Clause", "BSD-3-Clause", "0BSD", "MPL-2.0",
    "Unicode-3.0", "ISC", "Zlib", "CC0-1.0",
}
ANCILLARY = {
    "Unicode-3.0": "Permissive Unicode data/code; preserve copyright and permission notices; no endorsement.",
    "ISC": "Permissive ancillary code; preserve copyright and permission notice.",
    "Zlib": "Permissive ancillary code; preserve notice and accurately identify unmodified source.",
    "CC0-1.0": "Public-domain dedication with permissive fallback; preserve the supplied legal text and provenance.",
}
FALLBACK_REVISIONS = {
    "harper-core": "ea9ab1b8f95be99a5d4040c53be92a6c2ad7f7f3",
    "harper-brill": "ea9ab1b8f95be99a5d4040c53be92a6c2ad7f7f3",
    "harper-pos-utils": "ea9ab1b8f95be99a5d4040c53be92a6c2ad7f7f3",
    "burn-ir": "a6da424feacf6d82d6a0e81db197310796267c2b",
    "burn-nn": "a6da424feacf6d82d6a0e81db197310796267c2b",
    "burn-optim": "a6da424feacf6d82d6a0e81db197310796267c2b",
    "cubecl-quant": "0e2ba072b1ebba595d65a90804e616e1b799ef16",
    "embassy-futures": "3e8d8fec15286eb25b8bba7d103c8fc279544551",
}


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def validate_fallback_revision(name: str, source: Path) -> None:
    """A lockfile update must not silently reuse a different revision's notice."""
    vcs = json.loads((source / ".cargo_vcs_info.json").read_text())
    if vcs.get("git", {}).get("sha1") != FALLBACK_REVISIONS[name]:
        raise ValueError(f"Review original notices for changed source revision: {name}")


def selection(expression: str) -> list[str]:
    """SPDX AND/OR/parentheses parser; never mistakes OR for an obligation to both."""
    if not expression:
        raise ValueError("Missing license expression")
    expression = expression.replace("/", " OR ")
    tokens = re.findall(r"\(|\)|[A-Za-z0-9.+-]+", expression)
    if "".join(tokens) != re.sub(r"\s", "", expression):
        raise ValueError(f"Unrecognized license expression: {expression}")
    index = 0

    def primary():
        nonlocal index
        if index >= len(tokens):
            raise ValueError("Incomplete license expression")
        token = tokens[index]
        index += 1
        if token == "(":
            value = either()
            if index >= len(tokens) or tokens[index] != ")":
                raise ValueError("Unbalanced license expression")
            index += 1
            return value
        if index < len(tokens) and tokens[index] == "WITH":
            index += 1
            if index >= len(tokens): raise ValueError("Missing license exception")
            token += " WITH " + tokens[index]
            index += 1
        return {token} if token in ALLOWED else None

    def both():
        nonlocal index
        value = primary()
        while index < len(tokens) and tokens[index] == "AND":
            index += 1
            next_value = primary()
            value = value | next_value if value is not None and next_value is not None else None
        return value

    def either():
        nonlocal index
        values = [both()]
        while index < len(tokens) and tokens[index] == "OR":
            index += 1
            values.append(both())
        accepted = [value for value in values if value is not None]
        return min(accepted, key=lambda v: ("MIT" not in v, "Apache-2.0" not in v, len(v), sorted(v))) if accepted else None

    selected = either()
    if index != len(tokens) or selected is None:
        raise ValueError(f"No allowed license branch in: {expression}")
    return sorted(selected)


def cargo(*args: str) -> str:
    return subprocess.check_output(["cargo", *args, "--manifest-path", str(MANIFEST), "--locked"], text=True)


def active_packages(target: str) -> tuple[dict, set[tuple[str, str]]]:
    metadata = json.loads(cargo("metadata", "--format-version=1", "--filter-platform", target))
    tree = cargo("tree", "--target", target, "--edges", "normal,build", "--prefix", "none", "--format", "{p}")
    identities = set()
    for line in tree.splitlines():
        match = re.match(r"^([\w-]+) v([\w.+-]+)", line)
        if not match:
            raise ValueError(f"Unexpected Cargo tree output: {line}")
        identities.add(match.groups())
    return metadata, identities


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--target", action="append", required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    packages = {}
    for target in args.target:
        metadata, active = active_packages(target)
        for package in metadata["packages"]:
            key = (package["name"], package["version"])
            if key in active:
                packages.setdefault(key, {"package": package, "targets": []})["targets"].append(target)
    lock_bytes = MANIFEST.with_name("Cargo.lock").read_bytes()
    lock = tomllib.loads(lock_bytes.decode())
    checksums = {(p["name"], p["version"]): p.get("checksum") for p in lock["package"]}
    records = []
    archive_files: dict[str, bytes] = {}
    missing_notices = []
    for key, entry in sorted(packages.items()):
        package = entry["package"]
        name, version = key
        selected = selection(package["license"])
        source = Path(package["manifest_path"]).parent
        notices = []
        # Actual files, including subdirectory notices, remain byte-for-byte.
        for path in sorted(source.rglob("*")):
            if path.is_file() and path.name.lower().startswith(("license", "licence", "copying", "copyright", "notice")):
                if "target" in path.relative_to(source).parts or "build" in path.relative_to(source).parts: continue
                content = path.read_bytes()
                relative = path.relative_to(source).as_posix()
                destination = f"notices/{name}-{version}/{relative}"
                archive_files[destination] = content
                notices.append({"file": destination, "sha256": sha256(content)})
        if not notices and name in FALLBACK_REVISIONS:
            validate_fallback_revision(name, source)
        if not notices and name in {"harper-core", "harper-brill", "harper-pos-utils"}:
            content = (PACKAGE / "licenses" / "upstream" / "HARPER-LICENSE").read_bytes()
            destination = f"notices/{name}-{version}/LICENSE"
            archive_files[destination] = content
            notices.append({"file": destination, "sha256": sha256(content),
                "source": "https://github.com/Automattic/harper/blob/ea9ab1b8f95be99a5d4040c53be92a6c2ad7f7f3/LICENSE"})
        if not notices and name in {"burn-ir", "burn-nn", "burn-optim", "cubecl-quant", "embassy-futures"}:
            prefix = "BURN" if name.startswith("burn-") else "CUBECL" if name == "cubecl-quant" else "EMBASSY"
            fallback_rows = json.loads((PACKAGE / "licenses" / "upstream" / "fallback-notices.json").read_text())
            for item in fallback_rows:
                if not item["file"].startswith(prefix + "-"): continue
                content = (PACKAGE / "licenses" / "upstream" / item["file"]).read_bytes()
                if sha256(content) != item["sha256"]: raise ValueError("Changed upstream notice")
                destination = f"notices/{name}-{version}/{item['file']}"
                archive_files[destination] = content
                notices.append({"file": destination, "sha256": sha256(content), "source": item["url"]})
        if not notices and name == "quds_proofing_harper":
            content = (PACKAGE / "LICENSE").read_bytes()
            destination = f"notices/{name}-{version}/LICENSE"
            archive_files[destination] = content
            notices.append({"file": destination, "sha256": sha256(content)})
        if not notices:
            missing_notices.append(f"{name}-{version}")
        record = {"name": name, "version": version, "declared_license": package["license"],
                  "selected_licenses": selected, "source": package["source"], "repository": package["repository"],
                  "crate_sha256": checksums.get(key), "targets": sorted(entry["targets"]), "notices": notices}
        if "MPL-2.0" in selected:
            url = f"https://static.crates.io/crates/{name}/{name}-{version}.crate"
            cache = Path(os.environ.get("CARGO_HOME", Path.home() / ".cargo")) / "registry" / "cache"
            matches = list(cache.glob(f"*/{name}-{version}.crate"))
            content = matches[0].read_bytes() if matches else urllib.request.urlopen(url, timeout=60).read()
            if sha256(content) != checksums[key]: raise ValueError(f"Changed MPL source archive: {name}")
            destination = f"sources/{name}-{version}.crate"
            archive_files[destination] = content
            record["mpl_source"] = {"file": destination, "sha256": sha256(content), "url": url,
                "modified": False}
        records.append(record)
    if missing_notices:
        raise SystemExit("Original notice files missing; review before redistribution: " + ", ".join(missing_notices))
    readme = (
        "Quds optional Harper distribution: original third-party notices and MPL source\n\n"
        "The manifest selects permissive licenses or MPL-2.0 from each SPDX expression.\n"
        "For MPL components, the exact unmodified source .crate archives are in sources/.\n"
        "These archives correspond to the checksummed Cargo.lock inputs used for the build.\n"
        "Keep this bundle and manifest with every redistributed native or Wasm binary.\n"
        "No GPL/AGPL/LGPL-only dependency is permitted by this audited selection.\n"
    ).encode()
    archive_files["README.txt"] = readme
    import gzip
    with (output / "notices-and-mpl-sources.tar.gz").open("wb") as destination:
        with gzip.GzipFile(fileobj=destination, mode="wb", mtime=0, filename="") as zipped:
            with tarfile.open(fileobj=zipped, mode="w") as archive:
                for filename, content in sorted(archive_files.items()):
                    info = tarfile.TarInfo(filename)
                    info.size = len(content)
                    info.mode = 0o644
                    archive.addfile(info, io.BytesIO(content))
    result = {"schema_version": 1, "policy": "permissive or MPL-2.0; no GPL/AGPL/LGPL-only components",
              "reviewed_ancillary_licenses": ANCILLARY, "targets": sorted(args.target),
              "cargo_lock_sha256": sha256(lock_bytes), "package_count": len(records),
              "notice_bundle_sha256": sha256((output / "notices-and-mpl-sources.tar.gz").read_bytes()),
              "packages": records}
    (output / "manifest.json").write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps({"packages": len(records), "output": str(output), "status": "passed"}))


if __name__ == "__main__":
    main()

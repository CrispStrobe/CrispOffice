#!/usr/bin/env python3
"""Recover only the exact previously measured German GECToR model bytes.

Use Python 3.12 (measured interpreter: 3.12.14). Install conversion packages into
an isolated path with --no-cache-dir:
  numpy==2.5.5 onnx==1.19.1 gguf==0.19.0
Let pip resolve their declared protobuf/ml_dtypes/typing_extensions/PyYAML/tqdm
closure; its historical versions were not archived. This script records the
installed versions and declared requirements rather than inventing old pins.
No ONNX Runtime, PyTorch, oracle replay or inference is used.

Run --output NEW_DIRECTORY --prepare-only while the native quantizer builds.
Use --bundle EXISTING_DIRECTORY to verify/reuse a downloaded bundle with no copy.
Then use --output SAME_DIRECTORY --resume --quantizer /absolute/quantizer.
A full run may instead supply --quantizer initially. It is checked only after
the bundle and F32 conversion are ready. --allow-candidate-quantizer explicitly
permits a different quantizer binary solely to regenerate the fixed model hash;
it never changes model pins or qualifies that binary. A different quantizer also
requires --candidate-quantizer-sha256, --candidate-build-receipt and
--candidate-source-dir. The standard sealed build receipt, every source hash and
the original source-inventory digest must match the pinned measured source.

All downloads are pinned. Sources are authenticated by immutable Git blob IDs.
Receipts append and logs have unique run IDs. Failed/partial files are retained.
"""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import importlib.metadata
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import traceback
import urllib.request

PROFILE = "quds.exact-gector-model-recovery.v1"
SOURCE_REVISION = "8e3b50beef7d775cedb7b876009e88bcf2e8d6af"
ONNX_SHA = "6d7b43b4bd95c7a00c02c8babc7569d28558df894afe4874d96c202e6ab9a464"
F32 = ("497657528f3a660b85b807a7da0db663abb5964ada81f819e26ed48b6e96b6c1", 453355328)
MIXED = ("549ee3a5272726d48608cebdb435aaea6a984f3f53508b20b3194a7175a5ef5b", 82756896)
QUANTIZER = ("8d38bcb36ed82e6ebae6c320ea07ff3a97343feafbc0f7c024b6c1d4c5373a46", 915904)
NATIVE_SOURCE_REVISION = "853a1ce6089e5d5486e37307f37051ad6a928745"
GGML_REVISION = "3a27b6c665b191cb230be367db5c52d81dd3e2ac"
SOURCE_INVENTORY_SHA = "923301782b6d91bc1c55eb3d124b784ac91045af715b1a92996462ddb0ccaddf"
PARENT_MANIFEST_SHA = "c17318bdb1ada8fc2b1c456948bab44c746b06c8287c445099826ad3573abde7"
PACKAGES = {"numpy": "2.5.5", "onnx": "1.19.1", "gguf": "0.19.0"}
SOURCES = {
    "artifacts.json": (
        "https://raw.githubusercontent.com/CrispStrobe/quds_office_suite/"
        "94efdd3ca7abade65fc3e9e6231e9a9a891c0fdc/tools/proofing/german_model/artifacts.json",
        "7e2750199183bcad22645ca1b59ee65b37a91db0", 3428),
    "convert-gector-onnx-to-gguf.py": (
        "https://raw.githubusercontent.com/CrispStrobe/CrispEmbed/"
        "853a1ce6089e5d5486e37307f37051ad6a928745/models/convert-gector-onnx-to-gguf.py",
        "1da106839d8a54eee03c724283d12ea7ba8ee3de", 31211),
}
OVERRIDES = [
    "*=f32", "enc.*.attn.*.weight=q4_k", "enc.*.ffn.*.weight=q4_k",
    "token_embd.weight=q8_0", "position_embd.weight=f16", "gector.*.weight=f16",
]


def sha256(path: Path) -> str:
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def git_blob(path: Path) -> str:
    data = path.read_bytes()
    return hashlib.sha1(b"blob " + str(len(data)).encode("ascii") + b"\0" + data).hexdigest()


def check(path: Path, expected_sha: str, expected_size: int) -> dict:
    if path.is_symlink() or not path.is_file():
        raise ValueError(f"Missing regular artifact: {path}")
    actual_size = path.stat().st_size
    actual_sha = sha256(path)
    if (actual_sha, actual_size) != (expected_sha, expected_size):
        raise ValueError(
            f"Artifact mismatch, preserved at {path}: size={actual_size}, sha256={actual_sha}"
        )
    return {"file": str(path), "size_bytes": actual_size, "sha256": actual_sha}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--quantizer", type=Path)
    parser.add_argument("--bundle", type=Path, help="Reuse an existing pinned bundle without downloads.")
    parser.add_argument("--candidate-quantizer-sha256")
    parser.add_argument("--candidate-build-receipt", type=Path)
    parser.add_argument("--candidate-source-dir", type=Path)
    parser.add_argument("--prepare-only", action="store_true")
    parser.add_argument("--resume", action="store_true")
    parser.add_argument("--allow-candidate-quantizer", action="store_true")
    args = parser.parse_args()
    if not args.prepare_only and args.quantizer is None:
        parser.error("--quantizer is required unless --prepare-only is selected")

    out = args.output.absolute()
    if out.is_symlink():
        raise ValueError("Output must not be a symlink.")
    events = out / "events.jsonl"
    first = None
    if args.resume:
        if not out.is_dir() or not events.is_file():
            raise ValueError("Resume requires an existing recovery directory and event ledger.")
        with events.open(encoding="utf-8") as stream:
            first = json.loads(stream.readline())
        if first.get("profile") != PROFILE or first.get("target_sha256") != MIXED[0]:
            raise ValueError("Existing output belongs to a different recovery profile.")
    else:
        out.mkdir(parents=False, exist_ok=False)
    for name in ("sources", "bundle", "models", "logs"):
        directory = out / name
        if directory.is_symlink():
            raise ValueError(f"Refusing symlinked output directory: {directory}")
        directory.mkdir(exist_ok=True)
    previous_bundle = first.get("bundle_directory") if first else None
    requested_bundle = args.bundle.absolute() if args.bundle else None
    if previous_bundle is not None:
        if requested_bundle is not None and str(requested_bundle) != previous_bundle:
            raise ValueError("Resume must retain the original bundle directory.")
        bundle = Path(previous_bundle)
        external_bundle = first.get("external_bundle", False)
    else:
        bundle = requested_bundle or out / "bundle"
        external_bundle = requested_bundle is not None
    if bundle.is_symlink() or not bundle.is_dir():
        raise ValueError("The reused bundle must be an existing regular directory.")
    run_id = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")
    ledger = events.open("a", encoding="utf-8")

    def emit(kind: str, **fields) -> None:
        record = {
            "profile": PROFILE, "target_sha256": MIXED[0], "run_id": run_id,
            "timestamp_utc": datetime.now(timezone.utc).isoformat(),
            "event": kind, **fields,
        }
        line = json.dumps(record, ensure_ascii=False, sort_keys=True)
        ledger.write(line + "\n")
        ledger.flush()
        os.fsync(ledger.fileno())
        print(line, flush=True)

    def fetch(url: str, path: Path, size: int, expected_sha: str | None = None,
              expected_blob: str | None = None) -> None:
        if not path.exists():
            partial = path.with_name(path.name + "." + run_id + ".partial")
            emit("download-start", url=url, output=str(path), partial=str(partial),
                 expected_size=size, expected_sha256=expected_sha,
                 expected_git_blob=expected_blob)
            count = 0
            with urllib.request.urlopen(url, timeout=120) as source, partial.open("xb") as dest:
                while chunk := source.read(1024 * 1024):
                    count += len(chunk)
                    if count > size:
                        raise ValueError(f"Download exceeded pinned size: {path.name}")
                    dest.write(chunk)
                dest.flush()
                os.fsync(dest.fileno())
            if partial.stat().st_size != size:
                raise ValueError(f"Download has wrong size; partial retained: {partial}")
            if expected_sha is not None and sha256(partial) != expected_sha:
                raise ValueError(f"Download hash failed; partial retained: {partial}")
            if expected_blob is not None and git_blob(partial) != expected_blob:
                raise ValueError(f"Source Git blob failed; partial retained: {partial}")
            os.link(partial, path)
            partial.unlink()
        if path.is_symlink() or not path.is_file() or path.stat().st_size != size:
            raise ValueError(f"Existing artifact is not the pinned regular file: {path}")
        actual_sha = sha256(path)
        if expected_sha is not None and actual_sha != expected_sha:
            raise ValueError(f"Existing artifact hash failed: {path}")
        actual_blob = git_blob(path) if expected_blob is not None else None
        if expected_blob is not None and actual_blob != expected_blob:
            raise ValueError(f"Existing source Git blob failed: {path}")
        emit("download-verified", file=str(path), size_bytes=size,
             sha256=actual_sha, git_blob=actual_blob)

    def execute(name: str, command: list[str], env: dict | None = None) -> None:
        log = out / "logs" / (run_id + "-" + name + ".log")
        emit(name + "-start", command=command, log=str(log))
        with log.open("x", encoding="utf-8") as stream:
            result = subprocess.run(command, stdout=stream, stderr=subprocess.STDOUT,
                                    env=env, timeout=1800, check=False)
            stream.flush()
            os.fsync(stream.fileno())
        emit(name + "-exit", returncode=result.returncode, log=str(log),
             log_sha256=sha256(log))
        if result.returncode:
            raise RuntimeError(f"{name} failed; complete output retained in {log}")

    def candidate_receipt(quantizer_sha: str, quantizer_bytes: int) -> dict:
        if (args.candidate_quantizer_sha256 is None
                or args.candidate_build_receipt is None or args.candidate_source_dir is None):
            raise ValueError("Candidate mode needs --candidate-quantizer-sha256, "
                             "--candidate-build-receipt and --candidate-source-dir.")
        if (not re.fullmatch(r"[0-9a-f]{64}", args.candidate_quantizer_sha256)
                or args.candidate_quantizer_sha256 != quantizer_sha):
            raise ValueError("Candidate quantizer differs from the explicit candidate SHA-256.")
        receipt_path = args.candidate_build_receipt.resolve(strict=True)
        source = args.candidate_source_dir.resolve(strict=True)
        record = json.loads(receipt_path.read_text(encoding="utf-8"))
        if (record.get("schema") != "quds.gector.native-build.v1"
                or record.get("portable") is not True
                or record.get("source_revision") != NATIVE_SOURCE_REVISION
                or record.get("ggml_revision") != GGML_REVISION):
            raise ValueError("Candidate build receipt does not identify the original pinned source.")
        native = record.get("quantizer", {})
        if (native.get("sha256"), native.get("size_bytes")) != (quantizer_sha, quantizer_bytes):
            raise ValueError("Candidate build receipt does not bind the supplied quantizer bytes.")
        flags = record.get("cmake_flags", {})
        if flags.get("GGML_NATIVE") != "OFF" or flags.get("CRISPEMBED_NATIVE") != "OFF":
            raise ValueError("Candidate build enables machine-native flags.")
        compiled = record.get("compiled_sources", [])
        if not any(row.get("file") == "tools/quantize.cpp" for row in compiled):
            raise ValueError("Candidate receipt omits the compiled quantizer source.")
        if any("march=native" in flag or "mcpu=native" in flag
               for row in compiled for flag in row.get("flags", [])):
            raise ValueError("Candidate compiler flags include machine-native selection.")
        inventory = record.get("source_sha256", {})
        inventory_sha = hashlib.sha256(json.dumps(inventory, sort_keys=True).encode()).hexdigest()
        if (inventory_sha != SOURCE_INVENTORY_SHA
                or record.get("source_inventory_sha256") != SOURCE_INVENTORY_SHA):
            raise ValueError("Candidate source inventory differs from the original recorded inventory.")
        for name, digest in inventory.items():
            path = source / name
            if (Path(name).is_absolute() or not path.resolve().is_relative_to(source)
                    or not path.is_file() or sha256(path) != digest):
                raise ValueError(f"Candidate source changed or escaped its root: {name}")
        return {
            "receipt": str(receipt_path), "receipt_sha256": sha256(receipt_path),
            "source_revision": NATIVE_SOURCE_REVISION, "ggml_revision": GGML_REVISION,
            "source_inventory_sha256": inventory_sha, "source_files_verified": len(inventory),
            "quantizer_sha256": quantizer_sha, "native_binary_qualified": False,
        }

    try:
        emit("start", resumed=args.resume, prepare_only=args.prepare_only,
             python=sys.version, script_sha256=sha256(Path(__file__)),
             bundle_directory=str(bundle), external_bundle=external_bundle)
        installed = {}
        for name, required in PACKAGES.items():
            actual = importlib.metadata.version(name)
            installed[name] = actual
            if actual != required:
                raise ValueError(f"Conversion package {name} must be {required}, found {actual}")
        closure = {}
        for name in ("protobuf", "ml_dtypes", "typing_extensions", "PyYAML", "tqdm", "packaging"):
            try:
                closure[name] = importlib.metadata.version(name)
            except importlib.metadata.PackageNotFoundError:
                closure[name] = None
        emit("dependencies-verified", packages=installed, resolved_closure=closure,
             declared_requirements={name: importlib.metadata.requires(name) for name in PACKAGES},
             historical_closure_versions_known=False, inference_dependencies_required=False)

        for name, (url, blob, size) in SOURCES.items():
            fetch(url, out / "sources" / name, size, expected_blob=blob)
        artifacts_path = out / "sources" / "artifacts.json"
        converter = out / "sources" / "convert-gector-onnx-to-gguf.py"
        artifacts = json.loads(artifacts_path.read_text(encoding="utf-8"))
        if len(artifacts) != 13 or len({item["file"] for item in artifacts}) != 13:
            raise ValueError("Pinned bundle must contain exactly 13 unique files.")
        prefix = "https://huggingface.co/proofbird/gector-bert-de/resolve/" + SOURCE_REVISION + "/"
        for item in artifacts:
            name = item["file"]
            if Path(name).name != name or item["url"] != prefix + name:
                raise ValueError("Artifact path or source revision is not pinned.")
            if not re.fullmatch(r"[0-9a-f]{64}", item["sha256"]) or type(item["size"]) is not int:
                raise ValueError("Artifact digest or size is invalid.")
            if external_bundle:
                verified = check(bundle / name, item["sha256"], item["size"])
                emit("existing-bundle-file-verified", artifact=verified)
            else:
                fetch(item["url"], bundle / name, item["size"],
                      expected_sha=item["sha256"])
        check(bundle / "model.onnx", ONNX_SHA, 452972247)
        emit("bundle-verified", files=13, total_bytes=sum(item["size"] for item in artifacts))

        f32 = out / "models" / "gector-de-f32.gguf"
        f32_manifest = f32.with_name(f32.name + ".manifest.json")
        if not f32.exists():
            if f32_manifest.exists():
                raise ValueError("Partial conversion manifest retained; use a fresh output directory.")
            execute("convert-f32", [
                sys.executable, str(converter), "--bundle", str(bundle),
                "--output", str(f32), "--dtype", "f32",
            ])
        f32_record = check(f32, *F32)
        if not f32_manifest.is_file() or f32_manifest.is_symlink():
            raise ValueError("The converter manifest is missing or not a regular file.")
        report = json.loads(f32_manifest.read_text(encoding="utf-8"))
        if (report.get("schema") != "crispembed.gector.conversion.v1"
                or report.get("precision") != "f32"
                or report.get("gguf_readback_verified") is not True
                or report.get("source", {}).get("model_sha256") != ONNX_SHA
                or report.get("source", {}).get("revision") != SOURCE_REVISION
                or report.get("converter_sha256") != sha256(converter)
                or report.get("output", {}).get("sha256") != F32[0]):
            raise ValueError("F32 conversion manifest does not bind the pinned source and output.")
        if git_blob(converter) != SOURCES[converter.name][1]:
            raise ValueError("Converter changed during execution.")
        emit("f32-verified", artifact=f32_record, manifest_sha256=sha256(f32_manifest),
             original_manifest_sha256=PARENT_MANIFEST_SHA,
             original_manifest_identical=sha256(f32_manifest) == PARENT_MANIFEST_SHA,
             converter_readback_verified=True)

        if args.prepare_only:
            emit("prepared", completed=True, exact_f32=True,
                 mixed_recovered=False, inference_executed=False,
                 next="Resume this directory with --resume --quantizer PATH.")
            return 0

        quantizer = args.quantizer.resolve(strict=True)
        if not quantizer.is_file() or not os.access(quantizer, os.X_OK):
            raise ValueError("Supplied quantizer is not an executable regular file.")
        quantizer_sha = sha256(quantizer)
        quantizer_bytes = quantizer.stat().st_size
        recorded_quantizer = (quantizer_sha, quantizer_bytes) == QUANTIZER
        emit("quantizer-identity", path=str(quantizer), sha256=quantizer_sha,
             size_bytes=quantizer_bytes, recorded_quantizer_identical=recorded_quantizer,
             recorded_quantizer_sha256=QUANTIZER[0],
             candidate_explicitly_allowed=args.allow_candidate_quantizer)
        candidate_seal = None
        if not recorded_quantizer:
            if not args.allow_candidate_quantizer:
                raise ValueError("Quantizer differs from the recorded binary; explicit "
                                 "--allow-candidate-quantizer is required for hash-gated recovery.")
            candidate_seal = candidate_receipt(quantizer_sha, quantizer_bytes)
            emit("candidate-source-build-verified", **candidate_seal)
        mixed = out / "models" / "gector-de-mixed-q4_k.gguf"
        if not mixed.exists():
            command = [str(quantizer), str(f32), str(mixed), "q4_k", "--standard-file-type"]
            for rule in OVERRIDES:
                command.extend(["--tensor-type", rule])
            command.extend(["--metadata-string", "gector.precision=mixed-q4_k"])
            removed = [name for name in os.environ if name.startswith(
                ("CRISPEMBED_QUANT", "CRISPEMBED_INPAINT", "CRISPEMBED_MIGAN"))]
            environment = {name: value for name, value in os.environ.items() if name not in removed}
            emit("quantizer-policy", overrides=OVERRIDES,
                 expected_tensor_types={"F16": 3, "F32": 125, "Q4_K": 72, "Q8_0": 1},
                 removed_policy_environment_names=sorted(removed),
                 imatrix_used=False, standard_file_type=True)
            execute("quantize", command, environment)
        recovered = check(mixed, *MIXED)
        check(f32, *F32)
        if sha256(quantizer) != quantizer_sha or quantizer.stat().st_size != quantizer_bytes:
            raise ValueError("Quantizer changed during execution.")
        if candidate_seal is not None:
            if candidate_receipt(quantizer_sha, quantizer_bytes) != candidate_seal:
                raise ValueError("Candidate receipt or source changed during quantization.")
        result = {
            "profile": PROFILE, "run_id": run_id,
            "recovered_exact_model": True, "model": recovered,
            "f32": f32_record, "quantizer_sha256": quantizer_sha,
            "recorded_quantizer_identical": recorded_quantizer,
            "candidate_source_build_seal": candidate_seal,
            "new_native_binary_qualified": False, "inference_executed": False,
            "full_reference_replayed": False, "timings_are_benchmarks": False,
            "acceptance": "Exact byte length and whole-file SHA-256 match the retained model pin.",
        }
        result_path = out / ("result-" + run_id + ".json")
        with result_path.open("x", encoding="utf-8") as stream:
            json.dump(result, stream, ensure_ascii=False, indent=2, sort_keys=True)
            stream.write("\n")
            stream.flush()
            os.fsync(stream.fileno())
        emit("complete", **result, result_file=str(result_path),
             result_sha256=sha256(result_path))
        return 0
    except BaseException as error:
        failure = out / "logs" / (run_id + "-failure.log")
        with failure.open("x", encoding="utf-8") as stream:
            traceback.print_exc(file=stream)
            stream.flush()
            os.fsync(stream.fileno())
        emit("failed", error_type=type(error).__name__, detail=str(error),
             failure_log=str(failure), failure_log_sha256=sha256(failure),
             partial_files_preserved=True, pins_changed=False)
        return 1
    finally:
        ledger.close()


if __name__ == "__main__":
    raise SystemExit(main())

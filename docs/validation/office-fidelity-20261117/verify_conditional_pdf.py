#!/usr/bin/env python3
"""Independently inspect the conditional-style PDF fixture with Poppler.

Checks a one-page nonempty raster, its dimensions against PDF page geometry,
exact expected conditional colors, absence of the overridden red fill, and an
independently extracted cell value. This is fixture evidence, not a comparison
against the editor or a claim of general rendering parity.
"""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import json
import math
from pathlib import Path
import re
import shutil
import subprocess
import sys

import PIL
from PIL import Image

DPI = 144
EXPECTED = {"123456": (0x12, 0x34, 0x56), "ABCDEF": (0xAB, 0xCD, 0xEF)}
OVERRIDDEN = (0xFF, 0, 0)


def digest(path: Path) -> str:
    result = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            result.update(block)
    return result.hexdigest()


def tool_identity(name: str) -> dict:
    found = shutil.which(name)
    if not found:
        raise RuntimeError(f"Required installed tool is missing: {name}")
    launcher = Path(found).resolve()
    actual = launcher
    # Resolve the installed runtime's transparent Poppler shell launcher.
    with launcher.open("rb") as stream:
        prefix = stream.read(2048)
    wrapped = f'${{SCRIPT_DIR}}/../../native/poppler/bin/{name}'.encode()
    if prefix.startswith(b"#!") and wrapped in prefix:
        actual = (launcher.parent / "../../native/poppler/bin" / name).resolve()
        if not actual.is_file():
            raise RuntimeError(f"Poppler launcher target is missing: {actual}")
    return {
        "launcher": str(launcher),
        "launcher_sha256": digest(launcher),
        "executable": str(actual),
        "executable_sha256": digest(actual),
    }


def run(command: list[str], label: str, directory: Path, receipt: dict,
        *, allow_stderr: bool = False) -> bytes:
    result = subprocess.run(command, capture_output=True, timeout=60)
    stdout_path = directory / f"{label}.stdout.log"
    stderr_path = directory / f"{label}.stderr.log"
    stdout_path.write_bytes(result.stdout)
    stderr_path.write_bytes(result.stderr)
    receipt["commands"].append({
        "argv": command,
        "exit_code": result.returncode,
        "stdout_file": stdout_path.name,
        "stderr_file": stderr_path.name,
        "stdout_sha256": digest(stdout_path),
        "stderr_sha256": digest(stderr_path),
    })
    if result.returncode != 0:
        raise RuntimeError(f"{label} exited with {result.returncode}")
    if result.stderr.strip() and not allow_stderr:
        raise RuntimeError(f"{label} emitted diagnostics: {result.stderr.decode(errors='replace')}")
    return result.stdout


def verify(directory: Path, receipt: dict) -> None:
    pdf = directory / "conditional-styles.pdf"
    before = digest(pdf)
    receipt["input_pdf_sha256"] = before
    for name in ("pdfinfo", "pdftoppm", "pdftotext"):
        identity = tool_identity(name)
        stdout = run([identity["launcher"], "-v"], name + "-version", directory,
                     receipt, allow_stderr=True)
        stderr = (directory / (name + "-version.stderr.log")).read_bytes()
        identity["version"] = (stdout + stderr).decode().strip()
        receipt["tools"][name] = identity
    info = run([receipt["tools"]["pdfinfo"]["launcher"], str(pdf)],
               "pdfinfo", directory, receipt).decode()
    pages = re.search(r"^Pages:\s+(\d+)\s*$", info, re.MULTILINE)
    size = re.search(r"^Page size:\s+([\d.]+) x ([\d.]+) pts", info, re.MULTILINE)
    rotation = re.search(r"^Page rot:\s+(-?\d+)\s*$", info, re.MULTILINE)
    if not pages or int(pages[1]) != 1:
        raise RuntimeError("Expected exactly one conditional-style PDF page")
    if not size or not rotation or int(rotation[1]) != 0:
        raise RuntimeError("Expected known unrotated PDF page geometry")
    points = [float(size[1]), float(size[2])]
    if not all(math.isfinite(x) and 0 < x <= 2000 for x in points):
        raise RuntimeError("Unexpected PDF page dimensions")
    expected_pixels = [math.ceil(x * DPI / 72) for x in points]
    stem = directory / "conditional-styles-poppler"
    run([receipt["tools"]["pdftoppm"]["launcher"], "-r", str(DPI),
         "-singlefile", "-png", str(pdf), str(stem)],
        "pdftoppm", directory, receipt)
    raster = stem.with_suffix(".png")
    with Image.open(raster) as original:
        original.load()
        image = original.convert("RGB")
    if list(image.size) != expected_pixels:
        raise RuntimeError(f"Raster dimensions {image.size} differ from PDF geometry {expected_pixels}")
    histogram = image.getcolors(maxcolors=image.width * image.height)
    if histogram is None:
        raise RuntimeError("Raster histogram exceeded its pixel-count bound")
    colors = {color: count for count, color in histogram}
    nonwhite = image.width * image.height - colors.get((255, 255, 255), 0)
    if nonwhite <= 0:
        raise RuntimeError("Conditional-style PDF raster is empty")
    counts = {hex_color: colors.get(rgb, 0) for hex_color, rgb in EXPECTED.items()}
    if not all(count > 0 for count in counts.values()):
        raise RuntimeError(f"Expected exact conditional colors are missing: {counts}")
    overridden = colors.get(OVERRIDDEN, 0)
    if overridden != 0:
        raise RuntimeError(f"Overridden red fill remains visible: {overridden} pixels")
    raw = run([receipt["tools"]["pdftotext"]["launcher"], "-raw", str(pdf), "-"],
              "pdftotext", directory, receipt)
    raw_path = directory / "conditional-styles-poppler-raw.txt"
    raw_path.write_bytes(raw)
    text = raw.decode("utf-8")
    if not re.search(r"(?<!\S)8(?!\S)", text):
        raise RuntimeError("The expected cell value 8 was not independently extracted")
    if digest(pdf) != before:
        raise RuntimeError("Conditional-style PDF changed during verification")
    receipt.update({
        "pages": 1,
        "page_points": points,
        "expected_raster_dimensions": expected_pixels,
        "actual_raster_dimensions": list(image.size),
        "nonwhite_pixels": nonwhite,
        "exact_color_pixels": counts,
        "overridden_red_pixels": overridden,
        "raw_extracted_text": text,
        "expected_cell_value": "8",
        "cell_value_present": True,
        "pdf_unchanged": True,
        "raster_file": raster.name,
        "raster_sha256": digest(raster),
        "raw_text_file": raw_path.name,
        "raw_text_sha256": digest(raw_path),
    })


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--directory", required=True, type=Path)
    args = parser.parse_args()
    directory = args.directory.resolve()
    receipt = {
        "started_at_utc": datetime.now(timezone.utc).isoformat(),
        "script_sha256": digest(Path(__file__)),
        "python": sys.version,
        "pillow_version": PIL.__version__,
        "dpi": DPI,
        "scope": "Known worksheet fixture: independently visible conditional fill and font colors",
        "not_claimed": "Editor/PDF rendering parity, complete conditional-format support or universal font fidelity",
        "github_actions_used": False,
        "tools": {},
        "commands": [],
        "status": "running",
    }
    fixture_test = Path(__file__).resolve().parents[3] / "packages/quds_office_engine/test/sheet_conditional_rendering_test.dart"
    if fixture_test.is_file():
        receipt["fixture_test_sha256"] = digest(fixture_test)
    try:
        verify(directory, receipt)
        receipt["status"] = "passed"
    except Exception as error:
        receipt["status"] = "failed"
        receipt["error"] = str(error)
    receipt["finished_at_utc"] = datetime.now(timezone.utc).isoformat()
    output = directory / "poppler-receipt.json"
    output.write_text(json.dumps(receipt, indent=2) + "\n")
    print(json.dumps({key: receipt[key] for key in (
        "status", "actual_raster_dimensions", "nonwhite_pixels", "exact_color_pixels", "error"
    ) if key in receipt}))
    return 0 if receipt["status"] == "passed" else 1


if __name__ == "__main__":
    raise SystemExit(main())

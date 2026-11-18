#!/usr/bin/env python3
"""Reapply preserved document assertions to the saved outputs without rendering.

Depends on audit_saved_office.py's verified extraction. It imports only the
preserved checker modules; the frame script's four pure assertion functions
are selected by AST to avoid its top-level compiler/converter orchestration.
"""
import argparse
import ast
from datetime import datetime, timezone
import hashlib
import importlib.util
import json
from pathlib import Path, PurePosixPath
import subprocess
import sys
import tarfile
import zipfile

from lxml import etree


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--repo", type=Path, required=True)
    ap.add_argument("--audit-root", type=Path, required=True)
    args = ap.parse_args()
    repo, out = args.repo.resolve(), args.audit_root.resolve()
    findings = []
    checks = 0
    started = datetime.now(timezone.utc).isoformat()

    def sha(data):
        return hashlib.sha256(data).hexdigest()

    def read(path):
        return json.loads(path.read_text())

    def equal(a, b):
        return json.dumps(a, sort_keys=True) == json.dumps(b, sort_keys=True)

    def check(value, name, detail=None):
        nonlocal checks
        checks += 1
        if not value:
            findings.append({"check": name, "detail": detail})
        return bool(value)

    saved = read(out / "saved-evidence-audit.json")
    check(saved["accepted"], "archive-source-event-audit-precondition")
    extracted = out / "extracted"
    harness = out / "replay-harness"
    harness.mkdir(exist_ok=True)
    archives = [
        repo / "docs/validation/office-reconciled-20261117/recovered/consumer-intermediate-1d8325d4.tar.xz",
        repo / "docs/validation/office-local-20261118/evidence/qualification-helpers.tar.xz",
    ]
    source_members = []
    for archive in archives:
        index = read(archive.with_name(archive.name.removesuffix(".xz") + ".index.json"))
        check(sha(archive.read_bytes()) == index["sha256"], "checker-archive-pin", archive.name)
        indexed = {x["path"]: x for x in index["members"]}
        with tarfile.open(archive) as tar:
            for member in tar:
                wanted = member.name.endswith(".py") or member.name.startswith("schemas/") or member.name == "tools/jing-20241231.jar"
                if not wanted:
                    continue
                pp = PurePosixPath(member.name)
                assert member.isfile() and not pp.is_absolute() and ".." not in pp.parts
                data = tar.extractfile(member).read()
                pin = indexed[member.name]
                check(sha(data) == pin["sha256"] and len(data) == pin["bytes"], "checker-member-pin", member.name)
                dest = harness / member.name
                dest.parent.mkdir(parents=True, exist_ok=True)
                dest.write_bytes(data)
                source_members.append({"path": member.name, "sha256": sha(data)})

    def module(name, path):
        spec = importlib.util.spec_from_file_location(name, path)
        mod = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(mod)
        return mod

    sys.path.insert(0, str(harness / "wave3-runner"))
    base = module("saved_retained_contract", harness / "wave3-runner/verify_consumers.py")
    current = module("saved_current_contract", harness / "check_current_consumers.py")
    boundary_path = repo / "docs/validation/office-reconciled-20261117/resume/consumer-new/verify_boundary_consumers.py"
    boundary = module("saved_boundary_contract", boundary_path)
    source_members.append({"path": str(boundary_path.relative_to(repo)), "sha256": sha(boundary_path.read_bytes())})
    frame_path = harness / "frame-harness/run_consumers.py"
    tree = ast.parse(frame_path.read_text())
    selected = []
    for node in tree.body:
        if isinstance(node, (ast.Import, ast.ImportFrom)):
            selected.append(node)
        elif isinstance(node, ast.FunctionDef) and node.name in {"require", "bookmark_text", "odf_text", "checks"}:
            selected.append(node)
        elif isinstance(node, ast.Assign) and all(isinstance(t, ast.Name) and t.id in {"NS", "W"} for t in node.targets):
            selected.append(node)
    check({x.name for x in selected if isinstance(x, ast.FunctionDef)} == {"require", "bookmark_text", "odf_text", "checks"}, "frame-only-pure-assertion-functions")
    frame = {"__name__": "saved_frame_contract"}
    exec(compile(ast.Module(body=selected, type_ignores=[]), str(frame_path), "exec"), frame)
    schema_path = harness / "schemas/OpenDocument-v1.3-schema.rng"
    manifest_path = harness / "schemas/OpenDocument-v1.3-manifest-schema.rng"
    schema = etree.RelaxNG(etree.parse(str(schema_path)))
    manifest = etree.RelaxNG(etree.parse(str(manifest_path)))
    jing = harness / "tools/jing-20241231.jar"
    check(sha(jing.read_bytes()) == "ea5e9026244d977e607d8b52212d6871498ece51939f9c49d0e7a77aad91133a", "jing-exact-pin")
    xmlroot = out / "replayed-xml"
    schema_counts = {}
    diagnostic_counts = {}

    def validate_odt(gate, name, package, use_jing):
        with zipfile.ZipFile(package) as z:
            for part in ["content.xml", "styles.xml", "meta.xml", "META-INF/manifest.xml"]:
                data = z.read(part)
                is_manifest = part.startswith("META-INF/")
                validator = manifest if is_manifest else schema
                lxml_ok = validator.validate(etree.fromstring(data))
                if use_jing:
                    xml = xmlroot / gate / name / part
                    xml.parent.mkdir(parents=True, exist_ok=True)
                    xml.write_bytes(data)
                    p = subprocess.run(["java", "-jar", str(jing), "-i", str(manifest_path if is_manifest else schema_path), str(xml)], capture_output=True, timeout=30)
                    passed = p.returncode == 0
                    check(passed, "official-jing-acceptance-replay", {"gate": gate, "fixture": name, "part": part, "stderr": p.stderr.decode(errors="replace") if not passed else ""})
                    diagnostic_counts[gate] = diagnostic_counts.get(gate, 0) + int(not lxml_ok)
                else:
                    passed = lxml_ok
                    check(passed, "schema-acceptance-replay", {"gate": gate, "fixture": name, "part": part, "errors": str(validator.error_log) if not passed else ""})
                schema_counts[gate] = schema_counts.get(gate, 0) + int(passed)

    rows = []
    folder = extracted / "retained33/result"
    spec_list = read(folder / "fixtures/fixtures.json")
    original = {r["name"]: r for r in read(folder / "receipt.json")["fixtures"]}
    for spec in spec_list:
        name = spec["name"]
        try:
            validate_odt("retained33", name, folder / "fixtures" / spec["file"], False)
            pages = base.page_words(folder / "converted" / (name + ".bbox.xhtml"))
            value = base.check_fixture(spec, folder)
            for func in [base.check_reopened, base.check_current, base.check_second_wave, base.check_inline_breaks]:
                value.update(func(spec, folder, pages))
            page = min(max(spec["word_pages"].values(), default=1), len(pages))
            if "red_picture" in spec:
                value["red_picture"] = base.check_red_picture(spec, folder / "rasters" / (name + ".png"), page)
            if "paragraph_decorations" in spec or "styled_footer" in spec:
                value["recovery_raster"] = base.check_raster(spec, folder / "rasters" / (name + ".png"), page, value)
            matched = equal(value, original[name]["semantics"])
            check(matched, "retained-reconstructed-semantics-exact", name)
            rows.append({"gate": "retained33", "fixture": name, "passed": True, "reconstructed_measurements_equal": matched})
        except Exception as e:
            check(False, "retained-replay-exception", {"fixture": name, "exception": repr(e)})
    folder = extracted / "current7/result"
    spec_list = read(folder / "fixtures/fixtures.json")
    original = {r["name"]: r for r in read(folder / "receipt.json")["fixtures"]}
    for spec in spec_list:
        name = spec["name"]
        try:
            validate_odt("current7", name, folder / "fixtures" / spec["file"], True)
            raw = current.check_raw(spec, folder / "fixtures" / spec["file"])
            pages = base.page_words(folder / "converted" / (name + ".bbox.xhtml"))
            native_path = folder / "converted" / (name + ".source.bbox.xhtml")
            native_pages = base.page_words(native_path) if native_path.is_file() else None
            value = current.check_consumer(spec, folder, pages, native_pages)
            matched = equal(raw, original[name]["raw_odf"]) and equal(value, original[name]["consumer"])
            check(matched, "current-reconstructed-semantics-exact", name)
            rows.append({"gate": "current7", "fixture": name, "passed": True, "reconstructed_measurements_equal": matched})
        except Exception as e:
            check(False, "current-replay-exception", {"fixture": name, "exception": repr(e)})
    folder = extracted / "boundary5/result"
    spec_list = read(folder / "fixtures/fixtures.json")
    original = {r["name"]: r for r in read(folder / "receipt.json")["fixtures"]}
    for spec in spec_list:
        name = spec["name"]
        try:
            variants = {}
            for variant in ["direct", "imported", "source"]:
                prefix = name + "." + variant
                pdf = boundary.check_pdf(folder / "pdf" / (prefix + ".bbox.xhtml"), spec)
                docx_path = folder / ("fixtures" if variant == "source" else "reopened") / (prefix + ".docx")
                result = {"pdf": pdf, "docx": boundary.check_docx(docx_path, spec)}
                if variant != "source":
                    result["odt"] = boundary.check_odt(folder / "fixtures" / (prefix + ".odt"), spec, [schema, manifest])
                    schema_counts["boundary5"] = schema_counts.get("boundary5", 0) + 4
                variants[variant] = result
            matched = equal(variants, original[name]["variants"])
            check(matched, "boundary-reconstructed-variants-exact", name)
            rows.append({"gate": "boundary5", "fixture": name, "passed": True, "reconstructed_measurements_equal": matched})
        except Exception as e:
            check(False, "boundary-replay-exception", {"fixture": name, "exception": repr(e)})
    folder = extracted / "frame5/result"
    spec_list = read(folder / "generated/fixtures.json")
    original = {r["name"]: r for r in read(folder / "fixture-results.json")}
    for spec in spec_list:
        name = spec["name"]
        try:
            package = folder / "generated" / (name + ".odt")
            validate_odt("frame5", name, package, True)
            source = {}
            with zipfile.ZipFile(package) as z:
                for part in ["content.xml", "styles.xml", "meta.xml", "META-INF/manifest.xml"]:
                    source[part] = etree.fromstring(z.read(part))
            docx = {}
            with zipfile.ZipFile(folder / "converted" / (name + ".docx")) as z:
                for part in z.namelist():
                    if part.endswith((".xml", ".rels")):
                        docx[part] = etree.fromstring(z.read(part))
            tree = etree.parse(str(folder / "converted" / (name + ".bbox.xhtml")))
            ns = frame["NS"]
            pages = [{"width": float(page.get("width")), "height": float(page.get("height")), "words": [dict(text=node.text or "", **{key: float(value) for key, value in node.attrib.items()}) for node in page.xpath(".//x:word", namespaces=ns)]} for page in tree.xpath("//x:page", namespaces=ns)]
            value = frame["checks"](spec, source, docx, pages, folder / "converted" / (name + ".pdf"))
            matched = equal(value, original[name]["checks"]) and equal(pages, original[name]["pages"])
            check(matched, "frame-reconstructed-semantics-exact", name)
            rows.append({"gate": "frame5", "fixture": name, "passed": True, "reconstructed_measurements_equal": matched})
        except Exception as e:
            check(False, "frame-replay-exception", {"fixture": name, "exception": repr(e)})
    check(len(rows) == 50 and all(r["passed"] and r["reconstructed_measurements_equal"] for r in rows), "all-fifty-fixtures-replayed")
    check(schema_counts == {"retained33": 132, "current7": 28, "boundary5": 40, "frame5": 20}, "all-220-schema-parts-replayed", schema_counts)
    check(diagnostic_counts == {"current7": 3, "frame5": 1}, "known-lxml-diagnostics-retained", diagnostic_counts)
    report = {
        "schema": "quds.office.saved_document_contract_replay.v1", "started_utc": started,
        "completed_utc": datetime.now(timezone.utc).isoformat(), "source_commit": saved["execution_source"],
        "evidence_commit": saved["evidence_commit"], "script_sha256": sha(Path(__file__).read_bytes()),
        "saved_archive_audit_sha256": sha((out / "saved-evidence-audit.json").read_bytes()),
        "checker_sources": source_members, "checks": checks, "findings": findings, "accepted": not findings,
        "fixtures": rows, "schema_parts": schema_counts, "known_lxml_false_negatives": diagnostic_counts,
        "compiler_or_document_converter_executed": False, "github_actions_endpoints_queried": 0,
        "scope": "Independent replay of unchanged retained assertions against verified archived PDF/XML/DOCX/raster outputs; official schema acceptance rechecked. This closes the saved consumer evidence review, not a new product run.",
        "limitations": ["Native library/model qualification remains separate.", "Boundary5 contains four strict layouts and one bounded page-precedence control.", "Fixture coverage is focused and overlapping; no arbitrary-document fidelity or Microsoft Word render claim."],
    }
    (out / "document-contract-replay.json").write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
    print(json.dumps({"accepted": not findings, "checks": checks, "fixtures": len(rows), "schema_parts": schema_counts, "findings": findings}))
    return 0 if not findings else 1


if __name__ == "__main__":
    raise SystemExit(main())

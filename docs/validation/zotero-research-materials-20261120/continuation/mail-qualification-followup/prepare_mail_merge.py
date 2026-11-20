#!/usr/bin/env python3
"""Build a bounded Mail merge proposal using an isolated Git index.

No current worktree, HEAD, ordinary index, ref, config or remote is modified.
Only local Git objects and files in this report directory are written.
The exact captured Mail head is reconciled; no newer branch is fetched.
"""
from __future__ import annotations
import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile

MAIL = "177f29d3f9450a58f41189b462b0814aad37e45c"
CORE = "214c4ed80bef0cb871f74e90c506d508679d3d6e"
BASE = "3e5f44ae14926b8054b2e5c0558ce71477891a33"
ZOTERO = "docs/validation/zotero-research-materials-20261120/"
MODEL = "packages/quds_office_engine/lib/src/slide/model/pml_presentation.dart"
SERIAL = "packages/quds_office_engine/lib/src/slide/serial/slide_serial.dart"
DRAWING = "packages/quds_office_engine/lib/src/slide/shapes/drawingml.dart"
IMPORT_TEST = "packages/quds_office_engine/test/slide_import_fidelity_test.dart"
PDF_TEST = "packages/quds_office_engine/test/office_pdf_export_test.dart"
PRODUCT_PATHS = [MODEL, SERIAL, DRAWING, IMPORT_TEST, PDF_TEST]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", type=Path, required=True)
    parser.add_argument("--ours", required=True)
    args = parser.parse_args()
    repo = args.repo.resolve()
    out = Path(__file__).resolve().parent
    env = os.environ.copy()
    env["GIT_NO_LAZY_FETCH"] = "1"

    def git(*a, data=None, run_env=env):
        return subprocess.check_output(["git", *a], cwd=repo, env=run_env, input=data)

    def show(ref, path):
        return git("show", f"{ref}:{path}").decode()

    def oid(ref, path):
        return git("rev-parse", f"{ref}:{path}").decode().strip()

    def tree(ref):
        result = {}
        for row in git("ls-tree", "-rz", "--full-tree", ref).split(b"\0"):
            if not row:
                continue
            meta, name = row.split(b"\t", 1)
            mode, kind, sha = meta.decode().split()
            if kind == "blob":
                result[os.fsdecode(name)] = (mode, sha)
        return result

    original_head = git("rev-parse", "HEAD").decode().strip()
    original_index_path = Path(git("rev-parse", "--git-path", "index").decode().strip())
    if not original_index_path.is_absolute():
        original_index_path = repo / original_index_path
    original_index_hash = hashlib.sha256(original_index_path.read_bytes()).hexdigest()
    ours = git("rev-parse", args.ours).decode().strip()
    assert git("merge-base", "--all", ours, MAIL).decode().splitlines() == [
        BASE, "f3f98987824e021ed22a4d909e38d6307495267b",
        "2c3479838721632167933eb99b78beaac285e862", "9d8a13733bde66f4a5cdb80e006a1637fc09bb77"]
    # Only documentation/web changes may have followed the qualified core on
    # these five product paths; refuse if a competing edit needs new review.
    for path in PRODUCT_PATHS:
        assert oid(CORE, path) == oid(ours, path), path
    command = ["git", "merge-tree", "--write-tree", f"--merge-base={BASE}", ours, MAIL]
    merged = subprocess.run(command, cwd=repo, env=env, capture_output=True)
    if merged.returncode not in (0, 1):
        raise RuntimeError(merged.stderr.decode())
    raw = merged.stdout.decode()
    initial_tree = raw.splitlines()[0]
    (out / "explicit-base-merge-tree.txt").write_text(raw)
    initial = tree(initial_tree)
    our_tree = tree(ours)
    resolutions = {}

    def put(path, data, reason):
        sha = git("hash-object", "-w", "--stdin", data=data.encode()).decode().strip()
        resolutions[path] = {"mode": "100644", "blob": sha, "reason": reason}

    def keep(path, ref, reason):
        mode, sha = tree_cache[ref][path]
        resolutions[path] = {"mode": mode, "blob": sha, "reason": reason}

    tree_cache = {ours: our_tree, MAIL: tree(MAIL)}
    model_ours, model_mail = show(ours, MODEL), show(MAIL, MODEL)
    enum_start = "enum PmlShapePreset {"
    enum_ours = model_ours[model_ours.index(enum_start):model_ours.index("\n}", model_ours.index(enum_start)) + 2]
    enum_mail = model_mail[model_mail.index(enum_start):model_mail.index("\n}", model_mail.index(enum_start)) + 2]
    model_union = model_mail.replace(enum_mail, enum_ours, 1)
    put(MODEL, model_union, "Mail authored-background ownership/copy fields with the exact current six geometry enum additions retained")
    keep(SERIAL, MAIL, "Take the completed Mail background inheritance/relationship/save implementation; its complete delta from current was reviewed")

    drawing_ours, drawing_mail = show(ours, DRAWING), show(MAIL, DRAWING)
    background_marker = "  final XmlElement? sourceBackground = slide.sourceBackground?.copy();"
    next_shape = "  /// writeStartElement API.\n  w.writeStartElement('spTree', prefix: 'p');"
    assert background_marker not in drawing_ours
    background_block = drawing_mail[drawing_mail.index(background_marker):drawing_mail.index(next_shape, drawing_mail.index(background_marker))]
    assert drawing_ours.count(next_shape) == 1
    drawing_union = drawing_ours.replace(next_shape, background_block + next_shape, 1)
    put(DRAWING, drawing_union, "Add only Mail background XML/media-id serialization; preserve every current geometry parser/writer line")

    test_ours, test_mail = show(ours, IMPORT_TEST), show(MAIL, IMPORT_TEST)
    geometry_start = "    test('common geometric presets survive import', () {"
    geometry_end = "    test('master background resolves theme lumMod', () {"
    geometry_test = test_ours[test_ours.index(geometry_start):test_ours.index(geometry_end, test_ours.index(geometry_start))]
    first_new_test = "    test(\n      'authored slide image replaces inherited images behind decorations',"
    assert geometry_start not in test_mail and test_mail.count(first_new_test) == 1
    import_union = test_mail.replace(first_new_test, geometry_test + first_new_test, 1)
    put(IMPORT_TEST, import_union, "Take Mail's background/copy/save regressions and retain the exact current geometric-presets test")
    keep(PDF_TEST, MAIL, "Add the two completed cropped/uncropped picture-border assertions; existing source implementation is already present")

    for path in [
        "packages/quds_office_editor/example/lib/suite_workspace.dart",
        "packages/quds_office_editor/lib/src/editor_slide/render_slide_stage.dart",
        "packages/quds_office_editor/lib/src/embed/office_controller.dart",
        "packages/quds_office_engine/lib/src/pdf/office_pdf_export.dart",
    ]:
        keep(path, ours, "Current bytes already contain Mail behavior and preserve newer Word/geometry/numeric-PDF code; incoming differences are obsolete omission or whitespace")
    for path in ["docs/roadmaps/mail/attachments.md", "docs/roadmaps/mail/status.md", "packages/quds_office_engine/CHANGELOG.md"]:
        keep(path, MAIL, "Use the completed captured Mail qualification/behavior documentation")
    keep("docs/zotero-validation.md", ours, "Preserve the current Zotero source/evidence notice exactly")
    for path in our_tree:
        if path.startswith(ZOTERO):
            keep(path, ours, "Preserve every current Zotero evidence/documentation byte, including newer continuation reports")
    remove_paths = [path for path in initial if path.startswith(ZOTERO) and path not in our_tree]
    with tempfile.TemporaryDirectory(prefix="mail-merge-index-", dir=repo.parent) as scratch:
        index_env = env.copy()
        index_env["GIT_INDEX_FILE"] = str(Path(scratch) / "index")
        git("read-tree", initial_tree, run_env=index_env)
        rows = []
        for path in remove_paths:
            rows.append(f"0 {'0' * 40}\t{path}\0".encode())
        for path, item in resolutions.items():
            rows.append(f"{item['mode']} {item['blob']}\t{path}\0".encode())
        git("update-index", "-z", "--index-info", data=b"".join(rows), run_env=index_env)
        proposed_tree = git("write-tree", run_env=index_env).decode().strip()
    final = tree(proposed_tree)
    changed = [p for p in sorted(set(our_tree) | set(final)) if our_tree.get(p) != final.get(p)]
    changed_dart = [p for p in changed if p.endswith(".dart") and p.startswith(("packages/", "third_party/"))]
    documentation_dart = [p for p in changed if p.endswith(".dart") and p.startswith("docs/")]
    assert changed_dart == sorted(PRODUCT_PATHS), changed_dart
    assert all(final[p] == item for p, item in our_tree.items() if p.startswith(ZOTERO))
    manifests = [p for p in our_tree if Path(p).name in ("pubspec.yaml", "pubspec.lock", "analysis_options.yaml", ".fvmrc")]
    assert all(final[p] == our_tree[p] for p in manifests)
    word_paths = [p for p in our_tree if ("/word/" in p or "/editor_word/" in p or "office_host_fonts" in p or "font_metrics" in p)]
    assert all(final[p] == our_tree[p] for p in word_paths)
    for path in changed:
        if path in PRODUCT_PATHS or path in resolutions and not path.startswith(ZOTERO):
            content = git("show", f"{proposed_tree}:{path}")
            assert not any(line.startswith((b"<<<<<<< ", b"=======", b">>>>>>> ")) for line in content.splitlines()), path
    assert git("rev-parse", "HEAD").decode().strip() == original_head
    assert hashlib.sha256(original_index_path.read_bytes()).hexdigest() == original_index_hash
    patch = git("diff", "--binary", ours, proposed_tree, "--", *PRODUCT_PATHS)
    (out / "resolved-product.patch").write_bytes(patch)
    (out / "resolved-files.json").write_text(json.dumps({p: resolutions[p] for p in PRODUCT_PATHS}, indent=2) + "\n")
    report = {
        "schema": 1, "generated_at_utc": datetime.now(timezone.utc).isoformat(),
        "ours_source": ours, "ours_tree": git("rev-parse", ours + "^{tree}").decode().strip(),
        "captured_mail_head": MAIL, "proposed_two_parents": [ours, MAIL],
        "qualified_core_source": CORE, "proposed_tree": proposed_tree,
        "method": "Explicit genuine common-base merge-tree followed by bounded resolutions in a separate temporary index; no worktree application",
        "common_bases": git("merge-base", "--all", ours, MAIL).decode().splitlines(),
        "selected_common_base": BASE, "initial_conflict_tree": initial_tree,
        "recursive_virtual_base_limitation": "The default recursive merge-tree at214c was independently observed to fail on missing virtual-base blob4c901da3a663c65d55a981324895442e92509ffe with lazy fetching disabled. It is absent from bothheads and allfour common-base trees. This proposal explicitly records its alternative genuine base and proves the bounded result; it does not claim the recursive merge succeeded.",
        "changed_path_count": len(changed), "changed_dart_paths": changed_dart,
        "changed_documentation_dart_paths": documentation_dart,
        "all_changed_paths": changed,
        "product_resolution": {p: {**resolutions[p], "ours_blob": our_tree[p][1], "mail_blob": tree_cache[MAIL][p][1]} for p in PRODUCT_PATHS},
        "nonproduct_or_keep_current_resolutions": {p: item for p, item in resolutions.items() if p not in PRODUCT_PATHS and not p.startswith(ZOTERO)},
        "current_zotero_subtree_exact": True, "current_zotero_paths_preserved": sum(p.startswith(ZOTERO) for p in our_tree),
        "current_word_font_paths_exact": True, "current_word_font_path_count": len(word_paths),
        "current_manifests_locks_analysis_exact": True, "manifest_path_count": len(manifests),
        "geometry_enum_exact": enum_ours in model_union,
        "geometry_import_regression_exact": geometry_test in import_union,
        "drawing_geometry_exact": drawing_union.replace(background_block, "", 1) == drawing_ours,
        "current_renderer_pdf_controller_workspace_exact": all(final[p] == our_tree[p] for p in [
            "packages/quds_office_editor/lib/src/editor_slide/render_slide_stage.dart",
            "packages/quds_office_engine/lib/src/pdf/office_pdf_export.dart",
            "packages/quds_office_editor/lib/src/embed/office_controller.dart",
            "packages/quds_office_editor/example/lib/suite_workspace.dart"]),
        "main_web_paths_exact": all(final[p] == our_tree[p] for p in our_tree if "/studio_web_data_store" in p or p.endswith(("studio_arabic_morph_host_web.dart", "studio_hunspell_host_web.dart", "studio_web_persistence_test.dart"))),
        "current_head_unchanged": original_head, "current_index_sha256_unchanged": original_index_hash,
        "product_patch_sha256": hashlib.sha256(patch).hexdigest(),
        "tests_run_by_proposal": False,
        "recommended_validation": [
            "Run the existing engine-rendering selection on the final merged source; it includes both modified assertion files and serialization/model regressions",
            "Run the existing editor-rendering selection because copied/resolved background-shape behavior is consumed by the unchanged renderer/controller",
            "Strict analysis/format checks for the five changed Dart paths and source-preservation proof for unchanged Word/Zotero/theme/web inputs",
            "Keep the known incoming pentagon silhouette limitation explicit; no newer unqualified VBA geometry/background work is included",
        ],
        "status": "reviewable local tree proposal; not applied, published or qualified by new test execution",
        "github_actions_queried": False, "branch_heads_fetched": False,
    }
    (out / "proposal.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps({"ours": ours, "mail": MAIL, "tree": proposed_tree,
                      "changed_paths": len(changed), "changed_dart_paths": changed_dart,
                      "head_and_index_unchanged": True}))


if __name__ == "__main__":
    main()

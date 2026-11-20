#!/usr/bin/env python3
"""Bind the final bounded slide/web delta without relabeling earlier runs.

Rehashes immutable Git inputs, replays the conservative VM import graph, and
uses Dart AST token identities to isolate the slide declaration changes.
This source review runs no application tests and changes no product source.
"""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import gzip
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import tempfile


HERE = Path(__file__).resolve().parent
CORE = "214c4ed80bef0cb871f74e90c506d508679d3d6e"
CORE_EVIDENCE = "d4dda1c8cca43d126285973c374c88e5f1e8e281"
WEB_SOURCE = "c86e4d100920d64b5db004c374c818f5710b890d"
MAIL = "177f29d3f9450a58f41189b462b0814aad37e45c"
MAIN = "43db439e1e605d6329a6eabe6817b04ca44ba1aa"
FIRST = "f3f98987824e021ed22a4d909e38d6307495267b"
PINNED_HELPER = "55418e615c35d0add37b14edc2370074a288a0be6b194c7ac11d63f8175924b5"
SLIDE = ["packages/quds_office_engine/lib/src/slide/" + name for name in
         ["model/pml_presentation.dart", "serial/slide_serial.dart", "shapes/drawingml.dart"]]
SLIDE_TESTS = ["packages/quds_office_engine/test/" + name for name in
               ["office_pdf_export_test.dart", "slide_import_fidelity_test.dart"]]
WEB = ["packages/quds_office_editor/example/lib/" + name for name in
       ["studio_hunspell_host_web.dart", "studio_arabic_morph_host_web.dart", "studio_web_data_store.dart",
        "studio_web_data_store_none.dart", "studio_web_data_store_cache.dart"]]
WEB_TEST = "packages/quds_office_editor/example/test/studio_web_persistence_test.dart"
MANIFEST = "packages/quds_office_editor/example/pubspec.yaml"
ARCHIVE_DART = ["docs/validation/mail-attachments-20261120/" + name for name in
                ["arabic-composer/capture_mail_arabic_test.dart", "attachment-core/attachment_mime_probe.dart"]]

AST_SOURCE = r'''
import 'dart:convert';
import 'dart:io';
import 'package:analyzer/dart/analysis/features.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:crypto/crypto.dart';
import 'package:pub_semver/pub_semver.dart';

String memberName(ClassMember node, int index) {
  if (node is ConstructorDeclaration) return 'constructor ${node.name?.lexeme ?? '<default>'}';
  if (node is MethodDeclaration) return '${node.isGetter ? 'get' : node.isSetter ? 'set' : 'method'} ${node.name.lexeme}';
  if (node is FieldDeclaration) return '${node.isStatic ? 'static' : 'instance'} fields ${node.fields.variables.map((v) => v.name.lexeme).join(',')}';
  return '${node.runtimeType}:$index';
}
Map<String, Object?> analyze(String source, String language) {
  final parsed = parseString(content: source,
      featureSet: FeatureSet.fromEnableFlags2(sdkLanguageVersion: Version.parse('$language.0'), flags: const []),
      throwIfDiagnostics: true);
  final lexical = <({int offset, String lexeme})>[];
  var token = parsed.unit.beginToken;
  while (!token.isEof) {
    lexical.add((offset: token.offset, lexeme: token.lexeme));
    token = token.next!;
  }
  String hash(AstNode node) => sha256.convert(utf8.encode(jsonEncode(
      lexical.where((token) => token.offset >= node.offset && token.offset < node.end)
          .map((token) => token.lexeme).toList()))).toString();
  final declarations = <String, Object?>{};
  final globals = <String, String>{};
  final statics = <String, String>{};
  var index = 0;
  for (final node in parsed.unit.declarations) {
    final String name;
    final members = <String, String>{};
    if (node is ClassDeclaration) {
      name = 'class ${node.namePart.toSource()}';
      var memberIndex = 0;
      for (final member in node.body.members) {
        final key = memberName(member, memberIndex++);
        if (members.containsKey(key)) throw StateError('Duplicate member $name/$key');
        members[key] = hash(member);
        if (member is FieldDeclaration && member.isStatic) statics['$name/$key'] = hash(member);
      }
    } else if (node is FunctionDeclaration) {
      name = 'function ${node.name.lexeme}';
    } else if (node is TopLevelVariableDeclaration) {
      name = 'globals ${node.variables.variables.map((v) => v.name.lexeme).join(',')}';
      globals[name] = hash(node);
    } else {
      name = '${node.runtimeType}:$index';
    }
    if (declarations.containsKey(name)) throw StateError('Duplicate declaration $name');
    declarations[name] = {'token_sha256': hash(node), 'members': members};
    index++;
  }
  return {'directives': parsed.unit.directives.map(hash).toList(), 'declarations': declarations,
          'top_level_variables': globals, 'static_fields': statics};
}
void main(List<String> args) {
  final input = jsonDecode(File(args[0]).readAsStringSync()) as Map<String, dynamic>;
  final result = <String, Object?>{};
  for (final entry in (input['files'] as Map).entries) {
    result[entry.key as String] = {
      'before': analyze(entry.value['before'] as String, input['language_version'] as String),
      'after': analyze(entry.value['after'] as String, input['language_version'] as String),
    };
  }
  File(args[1]).writeAsStringSync(jsonEncode(result));
}
'''


def load_helper():
    path = HERE.parent / "evidence-audit/recheck_saved_evidence.py"
    assert hashlib.sha256(path.read_bytes()).hexdigest() == PINNED_HELPER
    spec = importlib.util.spec_from_file_location("final_scope_helpers", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


h = load_helper()


def current(path: Path) -> dict:
    return h.record(path.read_bytes())


def entries(repo: Path, ref: str) -> dict:
    result = {}
    for row in h.git(repo, "ls-tree", "-rz", ref).split(b"\0"):
        if row:
            meta, path = row.split(b"\t", 1)
            mode, kind, oid = meta.decode().split()
            result[path.decode()] = {"mode": mode, "kind": kind, "oid": oid}
    return result


def write(path: Path, value: object) -> None:
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n")


def declarations(repo: Path, candidate: str, out: Path) -> dict:
    config = json.loads((repo / ".dart_tool/package_config.json").read_text())
    language = next(row["languageVersion"] for row in config["packages"] if row["name"] == "quds_office_engine")
    inputs = {"language_version": language, "files": {path: {
        "before": h.git(repo, "show", CORE + ":" + path).decode(),
        "after": h.git(repo, "show", candidate + ":" + path).decode(),
    } for path in SLIDE}}
    dart = Path(os.environ["FLUTTER_ROOT"]) / "bin/cache/dart-sdk/bin/dart"
    with tempfile.TemporaryDirectory(prefix="final-declaration-scope-") as work:
        tmp = Path(work)
        write(tmp / "inputs.json", inputs)
        (tmp / "declarations.dart").write_text(AST_SOURCE)
        command = [str(dart), "--packages=" + str(repo / ".dart_tool/package_config.json"),
                   str(tmp / "declarations.dart"), str(tmp / "inputs.json"), str(tmp / "output.json")]
        execution = subprocess.run(command, cwd=repo, capture_output=True, text=True)
        (out / "declaration-execution.log").write_text(execution.stdout + execution.stderr)
        assert execution.returncode == 0, execution.stderr
        data = h.read(tmp / "output.json")
    expected = {
        SLIDE[0]: {"class PmlSlide"},
        SLIDE[1]: {"class SlideDeserializer", "class SlideSerializer", "class _SlideTemplate", "class _SlideTemplates"},
        SLIDE[2]: {"function slideToXml"},
    }
    result = {}
    for path, pair in data.items():
        before, after = pair["before"], pair["after"]
        assert before["directives"] == after["directives"], (path, "changed imports")
        assert before["top_level_variables"] == after["top_level_variables"], (path, "changed global initializer")
        assert before["static_fields"] == after["static_fields"], (path, "changed static initializer")
        old, new = before["declarations"], after["declarations"]
        changed = {key for key in old.keys() | new.keys() if old.get(key) != new.get(key)}
        assert changed == expected[path], (path, changed)
        members = {}
        for name in sorted(changed):
            first, second = old.get(name, {}).get("members", {}), new.get(name, {}).get("members", {})
            members[name] = {key: {"before_token_sha256": first.get(key), "after_token_sha256": second.get(key)}
                             for key in sorted(first.keys() | second.keys()) if first.get(key) != second.get(key)}
        result[path] = {"changed_declarations": sorted(changed), "changed_members": members,
                        "unchanged_declaration_count": len(old.keys() & new.keys() - changed),
                        "directives_unchanged": True, "top_level_variables_unchanged": True,
                        "static_fields_unchanged": True}
    write(out / "declaration-identities.json", data)
    return {"files": result, "ast_source_sha256": hashlib.sha256(AST_SOURCE.encode()).hexdigest(),
            "package_language_version": language, "dart_binary_record": current(dart),
            "complete_identity_artifact": current(out / "declaration-identities.json"),
            "no_added_or_changed_top_level_variables_or_static_fields": True}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", type=Path, required=True)
    parser.add_argument("--candidate", required=True)
    parser.add_argument("--output", type=Path, default=HERE / "source-applicability.json")
    args = parser.parse_args()
    repo, out = args.repo.resolve(), args.output.resolve().parent
    candidate = h.git(repo, "rev-parse", "--verify", args.candidate).decode().strip()
    assert h.git(repo, "rev-parse", "HEAD").decode().strip() == candidate
    core_entries, final_entries = entries(repo, CORE), entries(repo, candidate)
    core_tree, final_tree, evidence_tree = h.tree(repo, CORE), h.tree(repo, candidate), h.tree(repo, CORE_EVIDENCE)
    changed = {path: {"before": core_entries.get(path), "after": final_entries.get(path)}
               for path in sorted(core_entries.keys() | final_entries.keys()) if core_entries.get(path) != final_entries.get(path)}
    product = sorted(path for path in changed if not path.startswith("docs/") and not path.endswith(".md"))
    assert set(product) == set(SLIDE + SLIDE_TESTS + WEB + [WEB_TEST, MANIFEST]), product
    libraries = sorted(path for path in product if "/lib/" in path)
    assert set(libraries) == set(SLIDE + WEB)
    changed_docs_dart = sorted(path for path in changed if path.startswith("docs/") and path.endswith(".dart"))
    assert changed_docs_dart == sorted(ARCHIVE_DART)
    assert h.git(repo, "show", "-s", "--format=%P", candidate).decode().split() == [WEB_SOURCE, MAIL]
    for ancestor in [CORE, CORE_EVIDENCE, WEB_SOURCE, MAIL, MAIN]:
        h.git(repo, "merge-base", "--is-ancestor", ancestor, candidate)
    patch = h.git(repo, "diff", "--full-index", CORE, candidate, "--", *product)
    (out / "production-delta.patch").write_bytes(patch)
    core_dir = HERE.parent / "host-main-followup"
    summary = h.read(core_dir / "summary.json")
    assert summary["fresh_distinct_passed_cases"] == 2386 and summary["fresh_distinct_test_files"] == 157
    inputs, selected, prior_receipts = {}, [], {}
    for row in summary["cohorts"]:
        folder = core_dir / ("accepted-" + row["name"])
        receipt = h.read(folder / "receipt.json")
        assert current(folder / "receipt.json")["sha256"] == row["receipt_sha256"]
        assert receipt["status"] == "passed" and all(receipt["guards"].values())
        assert receipt["source_head_at_start"] == receipt["source_head_at_finish"] == CORE
        for name, info in h.read(folder / "inputs.json.gz")["before"]["source"].items():
            assert core_tree[name] == info["git_blob_sha1"]
            if name in inputs:
                assert inputs[name] == info
            inputs[name] = info
        selected.extend(receipt["selected_repository_paths"])
        prior_receipts[row["name"]] = current(folder / "receipt.json")
    assert len(inputs) == 4012 and len(selected) == len(set(selected)) == 157
    input_changes = sorted(path for path in inputs if core_tree[path] != final_tree.get(path))
    expected_input_changes = SLIDE + SLIDE_TESTS + WEB[:2] + [MANIFEST]
    assert input_changes == sorted(expected_input_changes)
    selected_changes = sorted(path for path in selected if core_tree[path] != final_tree.get(path))
    assert selected_changes == sorted(SLIDE_TESTS)
    added_inputs = sorted(path for path in product if path not in core_tree)
    assert added_inputs == sorted(WEB[2:] + [WEB_TEST])
    preserved_core_prefix = str(core_dir.relative_to(repo)) + "/"
    preserved_core = [path for path in evidence_tree if path.startswith(preserved_core_prefix)]
    assert preserved_core and all(evidence_tree[path] == final_tree.get(path) for path in preserved_core)
    prior_prefix = str(HERE.parent.relative_to(repo)) + "/"
    preserved_first = [path for path in evidence_tree if path.startswith(prior_prefix) and
                       (path[len(prior_prefix):].startswith(("accepted-", "evidence-audit/", "unused-tool-import-graph/"))
                        or path[len(prior_prefix):] in {"summary.json", "proofing-accounting.json", "publication-audit.json",
                                                       "run_continuation.py", "run_spacy_with_qualified_bytes.py"})]
    assert preserved_first and all(evidence_tree[path] == final_tree.get(path) for path in preserved_first)
    graph_dir = out / "vm-import-scope"
    graph_receipt = h.read(graph_dir / "receipt.json")
    compressed = (graph_dir / "graph.json.gz").read_bytes()
    graph_bytes = gzip.decompress(compressed)
    graph = json.loads(graph_bytes)
    assert graph_receipt["status"] == "passed"
    assert graph_receipt["source_head"] == graph_receipt["source_head_after"] == candidate
    assert graph_receipt["compressed_graph"] == {key: value for key, value in h.record(compressed).items() if key != "git_blob_sha1"}
    assert graph_receipt["graph_sha256"] == hashlib.sha256(graph_bytes).hexdigest()
    assert graph_receipt["code_before"] == graph_receipt["code_after"] and graph_receipt["code_unchanged"]
    assert graph_receipt["code_before"]["checker"] == {key: value for key, value in current(out / "check_vm_import_scope.py").items() if key != "git_blob_sha1"}
    assert graph["errors"] == graph["source_changes_during_graph"] == []
    assert graph["package_config_unchanged"] and graph["package_config_sha256"] == current(repo / ".dart_tool/package_config.json")["sha256"]
    roots = h.read(graph_dir / "selection.json")["roots"]
    records = {row["path"]: row for row in graph["records"]}
    objects = h.source_records(repo, {final_tree[str(Path(path).relative_to(repo))] for path in records if Path(path).is_relative_to(repo)}
                              | {core_tree[path] for path in inputs} | {final_tree[path] for path in input_changes})
    for path, info in inputs.items():
        assert objects[core_tree[path]] == info
    workspace = {}
    for path, row in records.items():
        file = Path(path)
        if file.is_relative_to(repo):
            relative = str(file.relative_to(repo))
            expected = objects[final_tree[relative]]
            workspace[relative] = expected
        else:
            expected = current(file)
        assert row["bytes"] == expected["bytes"] and row["sha256"] == expected["sha256"], path
        assert all(edge in records for edge in row["edges"])
    assert len(records) == graph_receipt["graph_files"] and len(workspace) == graph_receipt["workspace_graph_files"]
    graph_scopes = {}
    for name, root_paths in roots.items():
        reached, queue = set(), list(root_paths)
        while queue:
            path = queue.pop()
            if path in reached:
                continue
            reached.add(path)
            queue.extend(records[path]["edges"])
        reached_changes = sorted(path for path in libraries if str(repo / path) in reached)
        assert reached_changes == sorted(str(Path(path).relative_to(repo)) for path in graph["cohorts"][name]["changed_libraries_reachable"])
        if name != "web-persistence-vm":
            assert set(reached_changes) == set(SLIDE)
            saved = h.read(core_dir / ("accepted-" + name) / "receipt.json")
            assert sorted(root_paths) == sorted(str(repo / path) for path in saved["selected_repository_paths"])
        graph_scopes[name] = {"root_count": len(root_paths), "reachable_files": len(reached),
                              "changed_libraries_reachable": reached_changes}
    assert all(path not in workspace for path in ARCHIVE_DART)
    factories = {}
    for family in ["hunspell", "arabic_morph"]:
        path = f"packages/quds_office_editor/example/lib/studio_{family}_host.dart"
        native = f"packages/quds_office_editor/example/lib/studio_{family}_host_native.dart"
        assert core_tree[path] == final_tree[path] and core_tree[native] == final_tree[native]
        choices = records[str(repo / path)]["conditional_choices"]
        expected_uri = f"studio_{family}_host_native.dart"
        matches = [row for row in choices if row["possible_uris"] == [expected_uri]]
        assert len(matches) == 1 and matches[0]["evaluated_conditions"][0]["name"] == "dart.library.io"
        factories[path] = {"factory_blob": final_tree[path], "native_blob": final_tree[native], "selection": matches[0]}
    unchanged_prefixes = [
        "packages/quds_office_engine/lib/src/word/", "packages/quds_office_engine/lib/src/zotero/",
        "packages/quds_office_engine/lib/src/proofing/", "packages/quds_office_engine/lib/src/automation/",
        "packages/quds_office_editor/lib/", "packages/quds_proofing_spacy/",
        "packages/quds_mail_transport/", "third_party/enough_mail/",
    ]
    unchanged = {}
    for prefix in unchanged_prefixes:
        paths = [path for path in core_tree.keys() | final_tree.keys() if path.startswith(prefix)]
        assert paths and all(core_entries.get(path) == final_entries.get(path) for path in paths), prefix
        unchanged[prefix] = len(paths)
    slide_declarations = declarations(repo, candidate, out)
    assert h.git(repo, "rev-parse", "HEAD").decode().strip() == candidate
    result = {
        "status": "verified_bounded_source_delta_and_applicability_scope",
        "audited_at_utc": datetime.now(timezone.utc).isoformat(),
        "core_test_source": CORE, "core_evidence_checkpoint": CORE_EVIDENCE,
        "first_continuation_test_source": FIRST, "publication_source": candidate,
        "publication_tree": h.git(repo, "rev-parse", candidate + "^{tree}").decode().strip(),
        "publication_parents": [WEB_SOURCE, MAIL], "preserved_main": MAIN,
        "complete_changed_paths": changed, "complete_changed_path_count": len(changed),
        "product_changed_paths": product, "product_dart_changed_path_count": sum(path.endswith(".dart") for path in product),
        "production_delta_patch": current(out / "production-delta.patch"),
        "core_recorded_source_paths": len(inputs), "unchanged_core_recorded_source_paths": len(inputs) - len(input_changes),
        "changed_core_recorded_source_paths": input_changes, "new_product_input_paths": added_inputs,
        "candidate_preserves_every_core_recorded_input": False,
        "core_selected_files": len(selected), "unchanged_core_selected_files": len(selected) - len(selected_changes),
        "changed_core_selected_files": selected_changes,
        "unchanged_implementation_prefixes": unchanged,
        "native_factory_boundaries": factories,
        "vm_import_scope": {"receipt": current(graph_dir / "receipt.json"), "graph_files": len(records),
                            "workspace_files": len(workspace), "cohorts": graph_scopes,
                            "changed_web_libraries_excluded_from_core_roots": True,
                            "slide_libraries_reachable_via_exports": True,
                            "historical_documentation_harnesses_reachable": False},
        "slide_declaration_scope": slide_declarations,
        "historical_documentation_dart_inputs": {path: {"blob": final_tree[path], "matches_captured_mail": final_tree[path] == h.tree(repo, MAIL)[path]}
                                                  for path in ARCHIVE_DART},
        "retained_evidence": {"core_paths_preserved": len(preserved_core), "first_continuation_paths_preserved": len(preserved_first),
                              "core_receipts": prior_receipts, "prior_receipts_or_reports_rewritten": False},
        "required_fresh_gates": ["engine-rendering14", "editor-rendering10", "web-vm3-files19-cases", "web-chrome1-file3-cases", "strict-active-Dart-static108"],
        "mail_readiness_supplement": {"captured_head": MAIL, "included_as_parent": True,
                                      "previous_host_review_retains_its_historical_observation": True,
                                      "new_behavior": "Only three slide/background libraries and two engine regression files change beyond the web/main checkpoint; existing Word, Zotero, Mail composition and Studio source stays preserved."},
        "callsite_review": [
            "Generic opening, macro opening and disk saving dispatch to the changed deserializer/serializer only for slide/PPTX data; Word and sheet branches retain their own unchanged implementations.",
            "EmbeddedObjectHost.asPresentation checks kind==slide before calling SlideDeserializer. This can expose repaired backgrounds in an embedded slide package, but does not route Word packages through slide deserialization.",
            "Controller presentation open/save/copy and PDF presentation export remain unchanged callers of the altered slide operations; the fresh rendering cohorts cover those model/import/export behaviors.",
        ],
        "limits": [
            "The earlier2386/157 and3201/129 results retain their original sources. This audit does not claim the entire earlier input inventory equals the final source or add historical counts together.",
            "Import reachability is broader than executed behavior: all old core cohorts reach the three slide files through shared exports. The bounded declaration review and fresh rendering gates cover their changes; this is not dynamic call-coverage proof.",
            "The full110-path static attempt remains rejected for two archived documentation harnesses. The separate108-path active-source gate must pass; original archive bytes and original rejection are retained.",
            "Native Word visual parity, installed macOS behavior, live accounts and real downloaded Wasm model activation are outside these local regression gates.",
        ],
        "auditor_record": current(Path(__file__)), "imported_helper_sha256": PINNED_HELPER,
        "github_actions_queried": False, "product_files_modified": False,
    }
    write(args.output.resolve(), result)
    print(json.dumps({key: result[key] for key in ["status", "complete_changed_path_count", "product_dart_changed_path_count",
                                                   "unchanged_core_recorded_source_paths", "changed_core_selected_files"]}, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

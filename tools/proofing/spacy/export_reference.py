#!/usr/bin/env python3
"""Export a frozen, developer-only spaCy oracle; never used by the application.

The verified wheel is read as model data, not imported as executable Python.
All numeric arrays are little-endian F32 in row-major order. No downloads,
pickle loading, implicit dependency installation, or native result substitution.
"""

from __future__ import annotations

import argparse
import hashlib
import importlib.metadata
import json
import os
from pathlib import Path, PurePosixPath
import platform
import re
import shutil
import sys
import tempfile
import zipfile

SCHEMA = "crispembed.spacy.reference.v1"
CASE_SCHEMA = "crispembed.spacy.fixture-inputs.v1"
WHEEL_NAME = "de_core_news_sm-3.8.0-py3-none-any.whl"
WHEEL_SIZE = 14639490
WHEEL_SHA256 = "fec69fec52b1780f2d269d5af7582a5e28028738bd3190532459aeb473bfa3e7"
WHEEL_URL = "https://github.com/explosion/spacy-models/releases/download/de_core_news_sm-3.8.0/" + WHEEL_NAME
MODEL_PREFIX = "de_core_news_sm/de_core_news_sm-3.8.0/"
PIPELINE = ["tok2vec", "tagger", "morphologizer", "parser", "lemmatizer", "attribute_ruler"]
FEATURES = ["NORM", "PREFIX", "SUFFIX", "SHAPE", "SPACY", "IS_SPACE"]
ROW_COUNTS = [5000, 1000, 2500, 2500, 50, 50]
RUNTIME = {"spacy": "3.8.18", "thinc": "8.3.14", "numpy": "2.4.6"}
SOURCE_PINS = {
    "spacy": {"tag": "release-v3.8.18", "commit": "43311999028032fd81bef77a75fdb4fa96803c98"},
    "thinc": {"tag": "v8.3.14", "commit": "e617de4ea2530c7091ea2110e011807c33c366f0"},
}
NUMERICAL_POLICY = {
    "dtype": "float32-le", "order": "C", "absolute_tolerance": 2e-4,
    "relative_tolerance": 2e-5,
    "criterion": "abs(candidate-reference) <= atol + rtol*abs(reference), every element",
    "discrete_outputs": "exact", "finite_values_required": True,
    "declared_before_native_comparison": True,
}
MAX_CASE_BYTES = 65536
MAX_CASES = 512


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def json_bytes(value) -> bytes:
    return (json.dumps(value, ensure_ascii=False, sort_keys=True, indent=2, allow_nan=False) + "\n").encode("utf-8")


def write_json(path: Path, value) -> None:
    path.write_bytes(json_bytes(value))


def load_cases(path: Path, split: str) -> tuple[dict, list[dict]]:
    """Reject ambiguous, empty, overlapping, and path-escaping fixture sets."""
    data = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(data, dict) or data.get("schema") != CASE_SCHEMA:
        raise ValueError("Unsupported fixture input schema")
    if split not in ("development", "acceptance"):
        raise ValueError("Choose development or acceptance explicitly")
    seen_ids: set[str] = set()
    seen_text: set[str] = set()
    for name in ("development", "acceptance"):
        cases = data.get(name)
        if not isinstance(cases, list) or not 1 <= len(cases) <= MAX_CASES:
            raise ValueError(f"{name} must contain 1..{MAX_CASES} cases")
        for case in cases:
            if not isinstance(case, dict) or set(case) != {"id", "locale", "family", "text"}:
                raise ValueError("Every case needs exactly id, locale, family, and text")
            ident = case["id"]
            if not isinstance(ident, str) or re.fullmatch(r"[a-z][a-z0-9-]{0,63}", ident) is None:
                raise ValueError("Unsafe or invalid fixture ID")
            if ident in seen_ids:
                raise ValueError(f"Duplicate case ID: {ident}")
            if case["locale"] != "de-DE" or not isinstance(case["family"], str) or not case["family"]:
                raise ValueError("This fixture contract requires de-DE and a named family")
            text = case["text"]
            if not isinstance(text, str):
                raise ValueError("Case text must be a string")
            if len(text.encode("utf-8", errors="strict")) > MAX_CASE_BYTES:
                raise ValueError(f"Case exceeds the {MAX_CASE_BYTES}-byte reference limit")
            if text in seen_text:
                raise ValueError("Repeated case text within or across development/acceptance")
            seen_ids.add(ident)
            seen_text.add(text)
        if not any(case["text"] for case in cases):
            raise ValueError(f"{name} cannot consist only of empty text")
    return data, data[split]


def coordinate_maps(text: str) -> tuple[list[int], list[int]]:
    """Map original Unicode scalar boundaries, without normalization/search."""
    byte_offsets = [0]
    utf16_offsets = [0]
    for scalar in text:
        byte_offsets.append(byte_offsets[-1] + len(scalar.encode("utf-8", errors="strict")))
        utf16_offsets.append(utf16_offsets[-1] + len(scalar.encode("utf-16-le", errors="strict")) // 2)
    return byte_offsets, utf16_offsets


def extract_verified_model(wheel: Path, target: Path) -> tuple[Path, list[dict]]:
    if not wheel.is_file():
        raise ValueError("Required model wheel is missing; supply --wheel with the pinned artifact")
    if wheel.stat().st_size != WHEEL_SIZE or sha256(wheel.read_bytes()) != WHEEL_SHA256:
        raise ValueError("Model wheel size or SHA-256 differs from the pinned de_core_news_sm 3.8.0 artifact")
    inventory = []
    with zipfile.ZipFile(wheel) as archive:
        names = archive.namelist()
        if len(names) != len(set(names)):
            raise ValueError("Duplicate wheel members")
        for name in sorted(names):
            if not name.startswith(MODEL_PREFIX) or name.endswith("/"):
                continue
            relative = PurePosixPath(name[len(MODEL_PREFIX):])
            if relative.is_absolute() or any(part in ("", ".", "..") for part in relative.parts):
                raise ValueError("Unsafe wheel member")
            content = archive.read(name)
            output = target.joinpath(*relative.parts)
            output.parent.mkdir(parents=True, exist_ok=True)
            output.write_bytes(content)
            inventory.append({"path": str(relative), "size_bytes": len(content), "sha256": sha256(content)})
    required = {"config.cfg", "meta.json", "LICENSE", "LICENSES_SOURCES", "tokenizer"}
    required.update(f"{component}/model" for component in PIPELINE[:-1])
    if not required.issubset({entry["path"] for entry in inventory}):
        raise ValueError("Pinned wheel lacks required pipeline data or notices")
    return target, inventory


def environment() -> dict:
    if platform.python_implementation() != "CPython" or platform.python_version() != "3.12.14":
        raise ValueError("Reference environment requires CPython 3.12.14; version changes need a separate oracle comparison")
    for name, version in RUNTIME.items():
        if importlib.metadata.version(name) != version:
            raise ValueError(f"Reference environment requires {name}=={version}")
    from packaging.requirements import Requirement
    from packaging.utils import canonicalize_name
    distributions = {}
    pending = list(RUNTIME)
    while pending:
        name = canonicalize_name(pending.pop())
        if name in distributions:
            continue
        distribution = importlib.metadata.distribution(name)
        distributions[name] = distribution.version
        for raw_requirement in distribution.requires or []:
            requirement = Requirement(raw_requirement)
            if requirement.marker is None or requirement.marker.evaluate({"extra": ""}):
                pending.append(requirement.name)
    return {
        "python": platform.python_version(), "implementation": platform.python_implementation(),
        "system": platform.system(), "machine": platform.machine(), "byteorder": sys.byteorder,
        "distribution_scope": "evaluated transitive runtime requirements of spaCy, Thinc, and NumPy; build tools excluded",
        "distributions": dict(sorted(distributions.items())),
        "runtime_pins": RUNTIME, "source_pins": SOURCE_PINS,
    }


class Traces:
    def __init__(self, path: Path):
        self.path = path
        self.entries: dict[str, dict] = {}
        self.arrays: dict[str, object] = {}
        self.stream = path.open("wb")

    def add(self, name: str, values) -> None:
        import numpy as np
        if name in self.entries:
            raise ValueError(f"Trace stage executed more than once: {name}")
        array = np.asarray(values)
        if array.dtype != np.float32 or not np.isfinite(array).all():
            raise ValueError(f"Trace {name} is not finite F32")
        array = np.array(array, dtype="<f4", order="C", copy=True)
        payload = array.tobytes(order="C")
        self.entries[name] = {
            "file": self.path.name, "offset_bytes": self.stream.tell(), "size_bytes": len(payload),
            "shape": list(array.shape), "dtype": "float32-le", "order": "C", "sha256": sha256(payload),
        }
        self.stream.write(payload)
        self.arrays[name] = array

    def close(self) -> None:
        self.stream.close()


class ModelHooks:
    """Observe actual inference calls; restore every original forward in finally."""

    def __init__(self, nlp, traces: Traces):
        self.traces = traces
        self.originals = []
        model = nlp.get_pipe("tok2vec").model
        nodes = list(model.walk())
        maxouts = [n for n in nodes if n.name == "maxout"]
        norms = [n for n in nodes if n.name == "layernorm"]
        windows = [n for n in nodes if n.name == "expand_window"]
        residuals = [n for n in nodes if n.name.startswith("residual(") and n.name.count("residual(") == 1]
        concat = [n for n in nodes if len(n.layers) == 6 and "|" in n.name]
        if [len(maxouts), len(norms), len(windows), len(residuals), len(concat)] != [5, 5, 4, 4, 1]:
            raise ValueError("Unsupported shared CNN graph topology")
        self.observe(concat[0], "tok2vec.embed.concat")
        self.observe(maxouts[0], "tok2vec.embed.maxout", affine="tok2vec.embed.affine")
        self.observe(norms[0], "tok2vec.embed.norm")
        for i in range(4):
            prefix = f"tok2vec.encoder.layer.{i}"
            self.observe(windows[i], prefix + ".window", input_name="tok2vec.encoder.input" if i == 0 else None)
            self.observe(maxouts[i + 1], prefix + ".maxout", affine=prefix + ".affine")
            self.observe(norms[i + 1], prefix + ".norm")
            self.observe(residuals[i], prefix + ".residual")
        for name in ("tagger", "morphologizer", "lemmatizer"):
            layers = [n for n in nlp.get_pipe(name).model.walk() if n.name == "softmax"]
            if len(layers) != 1 or layers[0].attrs["softmax_normalize"]:
                raise ValueError("Unsupported classifier topology")
            self.observe(layers[0], name + ".scores")
        parser = nlp.get_pipe("parser").model
        self.observe(parser.layers[0].layers[-1], "parser.reduce")
        self.observe(parser.layers[1], "parser.lower_cache")

    def observe(self, node, name, *, affine=None, input_name=None):
        original = node._func
        self.originals.append((node, original))
        traces = self.traces

        def wrapped(model, values, is_train):
            if is_train:
                raise ValueError("Training execution is forbidden in the reference exporter")
            if input_name:
                traces.add(input_name, values)
            if affine:
                width = model.get_dim("nO")
                pieces = model.get_dim("nP")
                weights = model.get_param("W").reshape(width * pieces, model.get_dim("nI"))
                projected = model.ops.gemm(values, weights, trans2=True)
                projected += model.get_param("b").reshape(-1)
                traces.add(affine, projected.reshape(len(values), width, pieces))
            result, backprop = original(model, values, is_train=False)
            traces.add(name, result)
            return result, backprop

        node._func = wrapped

    def close(self):
        for node, original in reversed(self.originals):
            node._func = original


def annotations(doc) -> dict:
    text = doc.text
    bytes_at, utf16_at = coordinate_maps(text)
    if "".join(token.text_with_ws for token in doc) != text:
        raise ValueError("Tokenizer failed exact original-text reconstruction")
    tokens = []
    previous = 0
    for token in doc:
        start, end = token.idx, token.idx + len(token.text)
        if start < previous or text[start:end] != token.text:
            raise ValueError("Invalid source token span")
        previous = end
        tokens.append({
            "i": token.i, "text": token.text, "whitespace": token.whitespace_,
            "start_byte": bytes_at[start], "end_byte": bytes_at[end],
            "start_codepoint": start, "end_codepoint": end,
            "start_utf16": utf16_at[start], "end_utf16": utf16_at[end],
            "orth_id": str(token.orth), "norm": token.norm_, "norm_id": str(token.norm),
            "prefix": token.prefix_, "suffix": token.suffix_, "shape": token.shape_,
            "is_space": token.is_space, "tag": token.tag_, "pos": token.pos_,
            "morph": str(token.morph), "lemma": token.lemma_,
            "head": token.head.i, "dep": token.dep_, "is_sent_start": token.is_sent_start,
        })
    sentences = []
    if doc.has_annotation("SENT_START"):
        for sentence in doc.sents:
            start, end = sentence.start_char, sentence.end_char
            sentences.append({
                "start_token": sentence.start, "end_token": sentence.end,
                "start_byte": bytes_at[start], "end_byte": bytes_at[end],
                "start_codepoint": start, "end_codepoint": end,
                "start_utf16": utf16_at[start], "end_utf16": utf16_at[end], "text": sentence.text,
            })
    return {"tokens": tokens, "sentences": sentences}


def parse_with_trace(parser, doc, traces: Traces) -> list[dict]:
    import numpy as np
    if parser.cfg["beam_width"] != 1:
        raise ValueError("Reference requires greedy parser beam_width=1")
    states = parser.moves.init_batch([doc])
    if not len(doc):
        parser.set_annotations([doc], states)
        return []
    step_model = parser.model.predict([doc])
    state = states[0]
    steps = []
    try:
        while not state.is_final():
            if len(steps) >= 8 * len(doc) + 32:
                raise ValueError("Parser exceeded bounded transition budget")
            index = len(steps)
            ids = step_model.get_token_ids(states)
            hidden = step_model.state2vec.predict(ids)
            scores = step_model.predict(states)
            valid = [bool(parser.moves.is_valid(state, i)) for i in range(len(parser.move_names))]
            allowed = [i for i, value in enumerate(valid) if value]
            if not allowed or scores.shape != (1, len(valid)):
                raise ValueError("Invalid parser state/action inventory")
            chosen = max(allowed, key=lambda i: float(scores[0, i]))
            summed = np.zeros((1, 64, 2), dtype="f")
            cache = traces.arrays["parser.lower_cache"]
            for feature, token_id in enumerate(ids[0]):
                summed[0] += cache[int(token_id) + 1, feature]
            summed += parser.model.layers[1].get_param("b")
            if not np.array_equal(summed.max(axis=2), hidden):
                raise ValueError("Reconstructed parser sum differs from the actual source hidden vector")
            prefix = f"parser.step.{index}"
            traces.add(prefix + ".sum", summed)
            traces.add(prefix + ".hidden", hidden)
            traces.add(prefix + ".scores", scores)
            steps.append({
                "step": index, "feature_token_ids": ids[0].tolist(), "valid_actions": valid,
                "chosen_action": chosen, "chosen_name": parser.move_names[chosen],
                "stack_before": list(state.stack), "queue_before": list(state.queue),
                "arcs_before": [{**arc, "label": str(arc["label"])} for arc in state.arcs],
            })
            parser.moves.transition(state, chosen)
        parser.set_annotations([doc], states)
    finally:
        step_model.clear_memory()
    return steps


def export_case(nlp, case: dict, target: Path) -> dict:
    import numpy as np
    target.mkdir()
    text = case["text"]
    ordinary_doc = nlp(text)
    ordinary = annotations(ordinary_doc)
    ordinary_tok2vec = ordinary_doc.tensor.copy()
    doc = nlp.make_doc(text)
    attributes = doc.to_array(FEATURES)
    if attributes.shape != (len(doc), 6):
        raise ValueError("Unexpected six-feature array shape")
    buckets = [nlp.get_pipe("tok2vec").model.ops.hash(np.ascontiguousarray(attributes[:, i]), 8 + i)
               % ROW_COUNTS[i] for i in range(6)]
    traces = Traces(target / "traces.f32")
    hooks = ModelHooks(nlp, traces)
    try:
        nlp.get_pipe("tok2vec")(doc)
        traces.add("tok2vec.output", doc.tensor)
        for name in ("tagger", "morphologizer"):
            nlp.get_pipe(name)(doc)
        parser_steps = parse_with_trace(nlp.get_pipe("parser"), doc, traces)
        lemmatizer = nlp.get_pipe("lemmatizer")
        lemmatizer(doc)
        lemma_decisions = []
        if len(doc):
            classes = traces.arrays["lemmatizer.scores"].argmax(axis=1)
            for token, class_id in zip(doc, classes):
                tree_id = int(lemmatizer.labels[int(class_id)])
                applied = lemmatizer.trees.apply(tree_id, token.text)
                lemma_decisions.append({"class": int(class_id), "tree": tree_id,
                                        "applicable": applied is not None, "applied": applied,
                                        "fallback": applied is None, "lemma": token.lemma_})
        before_ruler = annotations(doc)
        ruler = nlp.get_pipe("attribute_ruler")
        ruler_matches = [{"rule": doc.vocab.strings[match], "start_token": start, "end_token": end}
                         for match, start, end in ruler.matcher(doc)]
        ruler(doc)
        observed = annotations(doc)
        if observed != ordinary:
            raise ValueError(f"Instrumented pipeline differs from ordinary C greedy inference: {case['id']}")
        if not np.array_equal(doc.tensor, ordinary_tok2vec):
            raise ValueError("Instrumented tok2vec differs from ordinary inference")
        if len(doc):
            required = {"tok2vec.embed.concat", "tok2vec.embed.affine", "tok2vec.embed.maxout",
                        "tok2vec.embed.norm", "tok2vec.encoder.input", "tok2vec.output",
                        "tagger.scores", "morphologizer.scores", "lemmatizer.scores",
                        "parser.reduce", "parser.lower_cache"}
            required.update(f"tok2vec.encoder.layer.{i}.{stage}" for i in range(4)
                            for stage in ("window", "affine", "maxout", "norm", "residual"))
            if not required.issubset(traces.entries) or not parser_steps:
                raise ValueError("Incomplete required numerical reference traces")
        else:
            for name, width in (("tagger", 55), ("morphologizer", 671), ("lemmatizer", 1311)):
                traces.add(name + ".scores", np.zeros((0, width), dtype="f"))
        result = {
            "schema": SCHEMA, "case": case, "input_sha256": sha256(text.encode("utf-8")),
            "features": {"columns": FEATURES, "uint64_decimal": [[str(int(v)) for v in row] for row in attributes],
                         "hash_seeds": list(range(8, 14)), "rows": ROW_COUNTS,
                         "buckets": [[buckets[column][token].tolist() for column in range(6)] for token in range(len(doc))]},
            "annotations": observed, "before_attribute_ruler": before_ruler,
            "attribute_ruler_matches": ruler_matches, "lemma_decisions": lemma_decisions,
            "parser_steps": parser_steps, "traces": traces.entries,
            "ordinary_pipeline_annotations_exact": True,
            "ordinary_tok2vec_bit_exact": True,
            "empty_input_policy": "zero tokens and no executed CNN/parser stages" if not len(doc) else None,
        }
    finally:
        hooks.close()
        traces.close()
    write_json(target / "case.json", result)
    return {"id": case["id"], "tokens": len(doc), "parser_steps": len(parser_steps),
            "trace_stages": len(traces.entries), "input_sha256": result["input_sha256"],
            "files": [{"path": f"{case['id']}/{name}", "size_bytes": (target / name).stat().st_size,
                       "sha256": sha256((target / name).read_bytes())} for name in ("case.json", "traces.f32")]}


def run(wheel: Path, cases_path: Path, split: str, output: Path, environment_lock: Path) -> dict:
    _, cases = load_cases(cases_path, split)
    for key in ("OMP_NUM_THREADS", "OPENBLAS_NUM_THREADS", "BLIS_NUM_THREADS", "MKL_NUM_THREADS", "VECLIB_MAXIMUM_THREADS"):
        os.environ[key] = "1"
    runtime = environment()
    lock_bytes = environment_lock.read_bytes()
    lock_versions = dict(re.findall(r"^([A-Za-z0-9_.-]+)==([^\s;\\]+)", lock_bytes.decode("utf-8"), flags=re.MULTILINE))
    if not lock_versions or b"--hash=sha256:" not in lock_bytes:
        raise ValueError("Supply the hash-pinned reference environment lock")
    for name, version in runtime["distributions"].items():
        if lock_versions.get(name) != version:
            raise ValueError(f"Installed runtime dependency differs from the environment lock: {name}")
    runtime["threads"] = 1
    runtime["lock"] = {"path": "requirements-reference.txt", "size_bytes": len(lock_bytes), "sha256": sha256(lock_bytes)}
    if output.exists():
        raise ValueError("Output already exists; frozen references are never overwritten")
    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="spacy-oracle-data-") as temp:
        model_path, inventory = extract_verified_model(wheel, Path(temp))
        import spacy
        spacy.require_cpu()
        nlp = spacy.load(model_path, exclude=["ner"])
        if nlp.pipe_names != PIPELINE or nlp.disabled != ["senter"]:
            raise ValueError("Unexpected active/disabled model component order")
        if (nlp.meta["lang"], nlp.meta["name"], nlp.meta["version"]) != ("de", "core_news_sm", "3.8.0"):
            raise ValueError("Unexpected model identity")
        stage = Path(tempfile.mkdtemp(prefix=output.name + ".partial-", dir=output.parent))
        try:
            rows = [export_case(nlp, case, stage / case["id"]) for case in cases]
            if sum(row["tokens"] for row in rows) == 0:
                raise ValueError("A zero-token run cannot qualify inference")
            labels = {
                "tagger": list(nlp.get_pipe("tagger").labels),
                "morphologizer": list(nlp.get_pipe("morphologizer").labels),
                "lemmatizer": [int(v) for v in nlp.get_pipe("lemmatizer").labels],
                "parser": list(nlp.get_pipe("parser").move_names),
            }
            if [len(labels[name]) for name in ("tagger", "morphologizer", "lemmatizer", "parser")] != [55, 671, 1311, 137]:
                raise ValueError("Unexpected classifier/action label counts")
            manifest = {
                "schema": SCHEMA, "complete": True, "scope": "Python reference capture; no native inference qualification",
                "model": {"name": "de_core_news_sm", "version": "3.8.0", "wheel": WHEEL_NAME,
                          "url": WHEEL_URL, "size_bytes": WHEEL_SIZE, "sha256": WHEEL_SHA256,
                          "pipeline": PIPELINE, "excluded": ["ner"], "disabled": ["senter"], "source_files": inventory},
                "environment": runtime, "numerical_policy": NUMERICAL_POLICY,
                "exporter_sha256": sha256(Path(__file__).read_bytes()),
                "cases_file_sha256": sha256(cases_path.read_bytes()), "split": split,
                "cases": rows, "case_count": len(rows), "token_count": sum(row["tokens"] for row in rows),
                "trace_stage_count": sum(row["trace_stages"] for row in rows),
                "parser_step_count": sum(row["parser_steps"] for row in rows),
                "labels": labels, "attribute_ruler_patterns": nlp.get_pipe("attribute_ruler").patterns,
                "ordinary_pipeline_annotations_exact": True,
                "ordinary_tok2vec_bit_exact": True,
                "acceptance_outputs_used_for_tuning": False,
            }
            for name in ("LICENSE", "LICENSES_SOURCES"):
                shutil.copyfile(model_path / name, stage / name)
            (stage / "requirements-reference.txt").write_bytes(lock_bytes)
            manifest["notices"] = [{"path": name, "size_bytes": (stage / name).stat().st_size,
                                    "sha256": sha256((stage / name).read_bytes())}
                                   for name in ("LICENSE", "LICENSES_SOURCES")]
            write_json(stage / "manifest.json", manifest)
            os.rename(stage, output)
        except BaseException:
            shutil.rmtree(stage)
            raise
    return manifest


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--wheel", type=Path, required=True)
    parser.add_argument("--cases", type=Path, required=True)
    parser.add_argument("--split", choices=("development", "acceptance"), required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--environment-lock", type=Path, required=True,
                        help="Hash-pinned tools/spacy/requirements-reference.txt from CrispEmbed")
    args = parser.parse_args(argv)
    try:
        result = run(args.wheel, args.cases, args.split, args.output, args.environment_lock)
    except (ValueError, OSError, ImportError, zipfile.BadZipFile, json.JSONDecodeError) as error:
        print(f"Reference export FAILED: {error}", file=sys.stderr)
        return 2
    print(json.dumps({key: result[key] for key in ("case_count", "token_count", "trace_stage_count", "parser_step_count", "split")}))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

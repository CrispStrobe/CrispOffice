"""Proofbird GECToR grammar model (German): a complete, minimal way to run it (Python).

    pip install onnxruntime tokenizers huggingface_hub numpy
    python quickstart.py "Meine Schwester sind sehr mude."

This is the same algorithm the Proofbird app runs (C#), minus the guards in gector-guards.json (see the model card,
"What Proofbird adds"). Published by Patrick Andrew Hartnett - https://proofbird.app
"""
import argparse
import difflib
import json
import os
import re

import numpy as np
import onnxruntime as ort
from huggingface_hub import snapshot_download
from tokenizers import Tokenizer

MODEL = "proofbird/gector-bert-de"
WORD = re.compile(r"\w+(?:'\w+)?|[^\w\s]")          # a word (with one apostrophe inside), or one punctuation mark


class Gector:
    def __init__(self, model=MODEL, keep_confidence=0.0, min_error_prob=0.0):
        """keep_confidence: a bonus added to "$KEEP" before choosing (higher = fewer, safer edits).
        min_error_prob: ignore an edit, or a whole sentence, the model is less sure of than this.
        Both 0 by default, as in the Proofbird app."""
        self.keep_confidence, self.min_error_prob = keep_confidence, min_error_prob
        path = model if os.path.isdir(model) else snapshot_download(model)
        cfg = json.load(open(os.path.join(path, "config.json"), encoding="utf-8"))
        self.labels = [cfg["id2label"][str(i)] for i in range(len(cfg["id2label"]))]
        self.keep = self.labels.index(cfg.get("keep_label", "$KEEP"))
        self.incorrect = {v: int(k) for k, v in cfg["d_id2label"].items()}[cfg.get("incorrect_label", "$INCORRECT")]
        rules_path = os.path.join(path, "language-rules.json")
        rules = json.load(open(rules_path, encoding="utf-8")) if os.path.exists(rules_path) else {}
        # The final full stop comes off before the model and goes back on after (where the bundle says so).
        self.strip = rules.get("stripTerminators", ".!?") if rules.get("stripTrailingTerminator") else ""
        # Articles written glued to the next word with an apostrophe, which the model reads as two words (bundle data).
        self.glued = set((rules.get("elision") or {}).get("nonElidingArticles") or rules.get("nonElidingArticles") or [])
        self.verbs = {}                                    # "<word>_<from>_<to>" -> the verb form, for $TRANSFORM_VERB_*
        verb_path = os.path.join(path, "verb-form-vocab.txt")
        if os.path.exists(verb_path):
            for line in open(verb_path, encoding="utf-8"):
                if ":" in line:
                    words, tags = line.strip().split(":")
                    w1, w2 = words.split("_")
                    self.verbs[f"{w1}_{tags}"] = w2
        self.tokenizer = Tokenizer.from_file(os.path.join(path, "tokenizer.json"))
        self.session = ort.InferenceSession(os.path.join(path, "model.onnx"), providers=["CPUExecutionProvider"])

    # --- one pass: words in, one tag per word out -------------------------------------------------------------
    def tag(self, words):
        enc = self.tokenizer.encode(words, is_pretokenized=True)   # [CLS] w1 ... wn [SEP]; [CLS] stands for $START
        input_ids = np.array([enc.ids], dtype=np.int64)
        logits_labels, logits_d = self.session.run(
            ["logits_labels", "logits_d"],
            {"input_ids": input_ids, "attention_mask": np.ones_like(input_ids)})
        probs = softmax(logits_labels[0])                  # [tokens, 5000]
        probs[:, self.keep] += self.keep_confidence
        wrong = softmax(logits_d[0])[:, self.incorrect]    # [tokens]
        result, seen = [], set()
        for t, w in enumerate(enc.word_ids):               # one label per word, read at its first token
            word = 0 if t == 0 else (None if w is None else w + 1)
            if word is None or word in seen:
                continue
            seen.add(word)
            best = int(probs[t].argmax())
            label = self.labels[best] if probs[t, best] >= self.min_error_prob else "$KEEP"
            result.append((label, float(probs[t, best]), float(wrong[t])))
        if max(r[2] for r in result) < self.min_error_prob:   # no word is confidently wrong: keep the sentence
            result = [("$KEEP", p, e) for _, p, e in result]
        return input_ids, logits_labels.shape, result

    # --- apply one tag to one word ------------------------------------------------------------------------------
    def edit(self, word, label):
        if label.startswith("$APPEND_"):
            return word + " " + label[8:]
        if word == "$START" or label == "$KEEP":
            return word
        if label.startswith("$REPLACE_"):
            return label[9:]
        if label == "$DELETE":
            return ""
        if label.startswith("$TRANSFORM_SUF_"):          # change the ending: $TRANSFORM_SUF_<old>_<new>
            old, new = label[15:].split("_", 1)
            if not word.endswith(old):
                return word
            stem = word[: len(word) - len(old)]
            return stem + new
        if label.startswith("$TRANSFORM_VERB_"):         # verb form from verb-form-vocab.txt
            return self.verbs.get(f"{word}_{label[16:]}", word)
        if label == "$TRANSFORM_CASE_CAPITAL":
            return word[:1].upper() + word[1:].lower()
        if label == "$TRANSFORM_CASE_LOWER":
            return word.lower()
        if label == "$TRANSFORM_CASE_UPPER":
            return word.upper()
        if label == "$TRANSFORM_AGREEMENT_PLURAL":
            return word + "s"
        if label == "$TRANSFORM_AGREEMENT_SINGULAR":
            return word[:-1]
        if label == "$TRANSFORM_SPLIT_HYPHEN":
            return word.replace("-", " ")
        if label.startswith("$MERGE_"):
            return word + " " + label
        return word

    # --- the whole call: up to 5 passes, then the suggestions -------------------------------------------------
    def correct(self, text, max_passes=5, verbose=False):
        core, tail = text, ""
        if self.strip and text.rstrip()[-1:] and text.rstrip()[-1] in self.strip:
            core, tail = text.rstrip()[:-1], text[len(text.rstrip()) - 1:]
        plain = core.replace("’", "'")                # the models were trained on straight apostrophes
        words = self.words(plain)
        self.passes = []                                   # what each pass saw and did (for printing or a UI)
        for n in range(1, max_passes + 1):
            input_ids, shape, tags = self.tag(words)
            edited = [self.edit(w, label) for w, (label, _, _) in zip(["$START"] + words, tags)]
            tokens = (" ".join(e for e in edited if e).replace(" $MERGE_HYPHEN ", "-")
                      .replace(" $MERGE_SPACE ", "").split())
            new_words = [x for t in rejoin(t for t in tokens if t != "$START") for x in self.words(t)]
            self.passes.append({
                "pass": n, "input": join(" ".join(words)), "input_ids": input_ids[0].tolist(),
                "logits_labels_shape": list(shape),
                "words": [{"word": w, "tag": label, "probability": round(p, 6), "wrong": round(wrong, 6),
                           "edit": e if e != w else None}
                          for w, (label, p, wrong), e in zip(["$START"] + words, tags, edited)],
                "result": join(" ".join(new_words)), "changed": new_words != words})
            if verbose:
                print_pass(self.passes[-1])
            if new_words == words:
                break
            words = new_words
        found = self.suggestions(plain, words)             # same length as core, so positions match the real text
        corrected = core
        for f in reversed(found):                          # apply right to left, so positions stay valid
            f["original"] = core[f["start"]: f["start"] + f["length"]]
            corrected = corrected[: f["start"]] + f["replacement"] + corrected[f["start"] + f["length"]:]
        return corrected + tail, found

    def words(self, text):
        return [w for w, _, _ in self.spans(text)]

    def spans(self, text, surface=False):
        """The words of the text with their character positions. An article glued to the next word with an apostrophe
        (the bundle's list) is split into the two words the model was trained on."""
        out = []
        for m in WORD.finditer(text):
            article, sep, rest = m.group().partition("'")
            if sep and rest and article.lower() in self.glued:
                # the article keeps its apostrophe for comparing (so splitting it counts as a change), not for the model
                first = article + "'" if surface else article
                out += [(first, m.start(), m.start() + len(first)), (rest, m.end() - len(rest), m.end())]
            else:
                out.append((m.group(), m.start(), m.end()))
        return out

    def suggestions(self, original, corrected_words):
        """Compare the original words with the corrected ones: one suggestion per changed stretch, with its character
        position in the ORIGINAL text. Unchanged text keeps the writer's own spacing and characters."""
        spans = self.spans(original, surface=True)
        a = [w for w, _, _ in spans]
        out = []
        for op, i1, i2, j1, j2 in difflib.SequenceMatcher(a=a, b=corrected_words, autojunk=False).get_opcodes():
            if op == "equal":
                continue
            new = join(" ".join(corrected_words[j1:j2]))
            if i1 == i2:                                   # pure insertion
                if i1 < len(a):                            # before a word: "new "; before punctuation: " new"
                    start = end = spans[i1][1]
                    if new[-1:] in OPENING:
                        pass                               # an opening mark hugs the next word
                    elif i1 == 0 or a[i1][0].isalnum():
                        new = new + " "
                    else:
                        new = " " + new
                else:                                      # at the very end
                    start = end = spans[-1][2] if spans else 0
                    new = (" " if new[:1].isalnum() else "") + new
            else:
                start, end = spans[i1][1], spans[i2 - 1][2]
                if new and end < len(original) and original[end].isalnum() and new[-1].isalnum():
                    new += " "                             # a glued article split off: keep a space before the next word
                if not new:                                # pure deletion: take one neighbouring space with it
                    if end < len(original) and original[end] == " ":
                        end += 1
                    elif start > 0 and original[start - 1] == " ":
                        start -= 1
            out.append({"start": start, "length": end - start, "original": original[start:end], "replacement": new})
        return out


OPENING = "([{“«\""                       # marks that hug the word after them
CLOSING = ".,;:!?)]}%»”"                                  # marks that hug the word before them


def softmax(x):
    e = np.exp(x - x.max(axis=-1, keepdims=True))
    return e / e.sum(axis=-1, keepdims=True)


def print_pass(p):
    print(f"\n--- pass {p['pass']}: \"{p['input']}\"")
    print(f"request   input_ids {p['input_ids']}  attention_mask all 1")
    print(f"response  logits_labels {p['logits_labels_shape']}  logits_d {p['logits_labels_shape'][:2] + [2]}")
    for w in p["words"]:
        print(f"  {w['word']:<12} wrong {w['wrong']:6.1%}   {w['tag']} {w['probability']:.1%}")
    print(f"result    \"{p['result']}\"" + ("" if p["changed"] else "   (no change: stop)"))


def rejoin(tokens):
    """A word the model ends with an apostrophe hugs the next word."""
    out = []
    for t in tokens:
        if out and len(out[-1]) > 1 and out[-1].endswith("'") and t[:1].isalnum():
            out[-1] += t
        else:
            out.append(t)
    return out


def join(text):
    """Words back to normal text: no space before closing punctuation or after an opening mark."""
    text = re.sub(f" ([{re.escape(CLOSING)}])", r"\1", " ".join(text.split()))
    return re.sub(f"([{re.escape(OPENING.replace(chr(34), ''))}]) ", r"\1", text)


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("text")
    ap.add_argument("--model", default=MODEL, help="a Hugging Face repo id or a local folder")
    args = ap.parse_args()
    corrected, found = Gector(args.model).correct(args.text, verbose=True)
    print(f"\ncorrected: \"{corrected}\"")
    print("suggestions:", json.dumps(found, indent=2, ensure_ascii=False))

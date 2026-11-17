# Proofing continuation repairs

The newly captured main adds bounded noun-subject agreement and an offline
candidate-model evaluator. Review found two defects in that incoming work.

## Bounded predicate-tail scanning

The old noun-agreement gate used overlapping whitespace repetitions. A rejected
tail of 1,024 spaces followed by `?` took approximately 1.85 seconds in the
recorded Dart 3.13.7 probe, despite containing no valid predicate. Because this
gate runs synchronously, whitespace-heavy paragraphs could stall editing.

The replacement scans permitted horizontal whitespace and a finite token
vocabulary without overlapping backtracking. It retains the existing accepted
adverbs, optional preposition/noun suffix, final-period and trailing-newline
rules, including the old optional separator before a final preposition. It
does not add new grammar constructions or change finding offsets.

A bounded differential probe compared 228,692 old/new inputs with zero
differences. The new scan handled a 65,536-space rejected tail in approximately
149 microseconds in the recorded warmed probe. These measurements characterize
this specific gate on this runtime; they are not general editor latency or
German accuracy claims.

Nineteen added product controls cover accepted/rejected tails, Unicode spaces,
long spaces/tabs, source ranges, immutable request content, correction and
recheck. All 47 inherited noun-agreement cases remain.

## Execute the reviewed Python bytes

The candidate evaluator hashed `quickstart.py`, then used Python's source
loader. That loader could execute a timestamp-valid or unchecked-hash `.pyc`
instead of the verified source. Source changes during the intervening native
import could likewise change the code subsequently loaded.

Admission now retains the exact source bytes and digest, then compiles and
executes those bytes in the existing module namespace. Module name/file
metadata remains available, and the report records the admitted source hash.

Four new controls cover ordinary reviewed-source execution, timestamp-valid
foreign bytecode, unchecked-hash foreign bytecode, and source replacement
during the native import. Before repair the three adversarial controls fail;
after repair all nine admission controls pass. The tests use a local native
module double, with no model inference or network requirement.

Development logs, original source, commands and source hashes are retained in
the indexed archive under `development/`. Final source-bound application and
Python qualifications are reported separately.

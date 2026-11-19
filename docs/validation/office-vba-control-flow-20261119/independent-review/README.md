# Independent control-flow review

The compiler was reviewed independently for malformed nesting, inactive/unused
source checking, hidden recursion, type checks, call isolation, crossed loop
exits, bounded work, and object-context cleanup.

The initial recursive block evaluator passed the VM probe but overflowed the
JavaScript host stack in a fresh Node process at 32 procedure frames, 32 mixed
blocks, and 50 unary operators. A lower-depth warmup could mask that problem.
The pre-fix evidence is retained in `pre-fix-review.json` and the initial
`js-run.stderr.log`.

After the evaluator switched to explicit block continuations, both independent
probes passed on the VM and in fresh Node processes. Each performs 174 checks,
including malformed-source diagnostics and a combined depth scenario with 50
or 63 unary operators. These are standalone probe checks, not extra test-suite
cases. The 63-unary expression reaches the compiler's 64-node AST depth.

`fixed-review.json` records the final compiler/input hashes, commands, runtime
versions, exit codes, and log hashes. `control_flow_probe.dart` reproduces the
50-unary scenario; `control_flow_probe_63.dart` exercises the exact expression
depth boundary. No further defect was found in continuation ownership, For
counter increments, zero-iteration loops, crossed exits, or With cleanup.

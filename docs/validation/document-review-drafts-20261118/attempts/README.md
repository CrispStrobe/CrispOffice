# Development attempts — excluded from acceptance

These exact compressed logs preserve failed, interrupted and successful development checkpoints. **None contributes to final acceptance totals**, including the file whose historical name contains `accepted`. The early development logs below predate the acceptance candidate; the later rejected gate archive is bound to its own frozen source and described separately under `gates/`. Later retries overlap earlier cases, so their counts must not be added together.

`index.json` records the interpretation of each log. `manifest.json` records SHA-256 hashes for stored gzip files and their original uncompressed bytes. Failed assertions, compilation failures and interruptions remain visible; no failed log was replaced with a later successful one.

| Original log (under `logs/`) | Classification | Observed result | Explanation |
| --- | --- | --- | --- |
| `comment-keyboard-analysis.log.gz` | interrupted | No completed result | Analyzer emitted only its start marker. Operator confirmed manual Ctrl-C (exit 130) while coordinating resource pressure; no analysis conclusion was produced. |
| `comment-keyboard-development.log.gz` | failed | 8 passed / 1 failed | Covered-modal safety assertions passed; the final pumpAndSettle timed out because the caret ticker remained active. The harness was changed to a bounded 300 ms pump. |
| `draft-backend-development.log.gz` | passed-development | 17 passed / 0 failed | Early draft backend suite passed before the final source/dependency freeze. This is a development checkpoint only. |
| `draft-keyboard-review-attempt2.log.gz` | failed | 22 passed / 2 failed | Over-limit assertion expected the literal number 16384 although the descriptive limit message was present. The 650 px / 1.4 text-scale Arabic case exposed existing header/tab/ribbon overflows and used stale tap geometry after scrolling. Assertions, post-scroll pumping and responsive chrome were corrected. |
| `draft-proofing-attempt1.log.gz` | interrupted | No completed result | Stopped while parallel Flutter compilers and analyzers caused resource pressure. The log reaches +3 and begins the next case, but has no completion marker. These partial results are not accepted. |
| `draft-proofing-narrow-final.log.gz` | passed-development | 1 passed / 0 failed | Targeted retry of the unchanged 650×1000 Arabic case at 1.4 text scale passed after responsive chrome and geometry fixes. It remains a development retry, not the final frozen-source gate. |
| `draft-proofing-retry2.log.gz` | failed | 1 passed / 1 failed | Over-limit case passed. Actual narrow draft correction also worked, but three remaining 4 px command/paste-column overflows failed the narrow case. The later fix measured labels using the actual Material bodyMedium style. |
| `review-backend-analysis-development.log.gz` | interrupted | No completed result | Analyzer emitted only its start marker and was stopped while serializing runtime use after resource pressure. No analysis conclusion was produced. |
| `review-backend-development-accepted.log.gz` | passed-development | 26 passed / 0 failed | Targeted draft and priority backend retries passed. Despite accepted in this historical filename, this mutable-source development log is explicitly excluded from final acceptance. |
| `review-backend-development.log.gz` | failed | 43 passed / 2 failed | Two test suites failed to load during compilation; the priority fixture omitted required named argument endnote. Other suites reported 43 passing tests. The fixture argument was corrected; this run is not accepted. |
| `review-priority-development.log.gz` | failed | 6 passed / 1 failed | Case-sensitive fixture assertion expected comment while the displayed label was Comment 8. The assertion was corrected; six other priority cases passed during this attempt. |

The two analyzer logs contain start messages without conclusions. Runtime operations were subsequently serialized because concurrent compilers/analyzers caused resource pressure. The interrupted draft log reaches a visible `+3` progress marker without completing the next case; it supplies no accepted suite result.

The narrow Arabic test retained 650×1000 geometry and 1.4 text scale through the fixes. The successful development retry confirms that the original stress case was preserved. Final accepted tests and visual captures are stored separately.

The bundle contains only these explicitly selected logs, with no environment dump or credential configuration. A scan of uncompressed content found no common credential/token/private-key patterns and required no redaction. No GitHub Actions status was queried or awaited.

## Complete rejected gate and initial preflight

`gates/` adds the full failed bfa88aab gate (879 passed / two failed), its immutable source/environment manifests, and the initial offline preflight failure. See `gates/README.md` and its per-file receipts. These source-bound failures also remain excluded from acceptance. The earlier staging index, README and manifest are preserved in `history/before-first-gate/`.

The corrected development preflight is also preserved in `gates/preflight-fixes-corrected.tar.gz`, with exact verification and per-file receipts. Offline lock enforcement, formatting, strict 39-file analysis and both targeted body keyboard cases passed without changing dependency/runtime hashes. These development results remain excluded from acceptance. Earlier staging documents are preserved in `history/before-corrected-preflight/`.

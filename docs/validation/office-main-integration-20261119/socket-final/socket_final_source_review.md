# Final Socket source selection review

Reviewed Git source: `ac1e4c8c788ea608402c2260488235c0189efcba`. Read-only comparison against incoming `022a974a96db23e22bc161f7d465e4b972e8c2a9` and the preserved `4624218f9468eeeac07f1f100ac0e4bb6b050a17` checkpoint. No tests were executed and no tracked or runtime inputs were modified.

**No source or test selection discrepancy found.**

- The Socket facade is byte-identical to incoming `022a`. `client_base.dart` and the real-TLS round-trip test exactly match the reviewed cleanup/assertion patch.
- TCP ownership, close ordering, per-generation abort settlement, late-result disposal and producer cancellation remain present. The rejected-upgrade catch aborts only the current generation and rethrows; the existing trust tests verify disconnected/logged-out state before finally cleanup.
- The model equality fixture retains the exact previously qualified blob, including distinct instances, equal hashes and Set.add. The migration fixture and preserved application scopes remain identical to `4624`.
- All remaining incoming TLS, native-provider and raw-FETCH implementation/test files match `022a` exactly. The focused plan retains the same 35 suite paths, 26 analysis/format paths and seven byte-identical TLS fixture inputs. These are selection counts, not fresh execution results.
- The new socket-final merge review accurately limits immediate physical pending-handshake cancellation to the default owned raw transport. The manual SDK Socket path retains its narrower abort/late-disposal scope.

## Publication follow-up

The integration directory's top-level README still explicitly reports the `4624` checkpoint and its old manual-socket rejection behavior. Preserve it as that historical report and replace or clearly label the current entry point when publishing ac1 results. The new socket-final review already describes the selected behavior accurately.

# Independent Hunspell native lifecycle review

Review date: 19 November 2026.

**Result: no remaining blocking defect identified in the reviewed lifecycle
repair after the finalizer reachability finding below was addressed.** This is
an independent static review of the implementation, its deterministic C ABI
fixture, and the eight test scenarios. It is not an independent execution of
those tests or the final combined source qualification.

## Reviewed inputs

The repair follows incoming integration checkpoint
`94b4f2bdc541cbd3821b3dfaeb40a6a1466f4eb2`. The reviewed working-tree files matched
the author's development receipt, and their SHA-256 values were independently
checked during review:

| File | SHA-256 |
| --- | --- |
| [Native transport](../../../../packages/quds_proofing_hunspell/lib/src/hunspell_transport_native.dart) | `3e59a79f64743ae987df7858b23e77e34b17d66bb828a729ca0b1726cfbad1a5` |
| [Lifecycle tests](../../../../packages/quds_proofing_hunspell/test/native_lifecycle_test.dart) | `6b9dd16c4f52e324b7de029eff4c0f9a39740889b486e7f7a6781beeabc8b041` |
| [C ABI fixture](../../../../packages/quds_proofing_hunspell/test/fixtures/lifecycle_hunspell.cpp) | `7bb9f7851904b2d5370bbd9072a413ccaed858ad628bcc961b20e3e6181100b7` |

The baseline native source had SHA-256
`d16e4af1258787657118c3e062427c4caa2428c0083e5cfd8e70346ca35b91d0`.

## Defects and ownership repair

The previous disposal path killed the isolate without explicitly closing its
native Hunspell handle. Reopening also closed the previous pointer before
assigning the new pointer; an exception during allocation for the replacement
could therefore leave the freed pointer in the worker's state. The author
reports deterministic failures against that earlier source for both ordinary
disposal and allocation-failed reopening. Those failures are consistent with
the reviewed control flow.

The repaired transport immediately rejects pending Dart requests when disposal
begins, then asks the worker to close its handle and waits for a close
acknowledgement. A cached disposal future means concurrent and repeated
disposers share that completion. The worker processes the close after an
already-running native call, avoiding a concurrent native free. The owned
handle clears its pointer and detaches its finalizer before invoking native
close. Reopening also clears the worker's owner before attempting the
replacement, so a failed replacement leaves no handle available for reuse.

The startup path checks disposal before admitting work and kills a late-created
isolate. Startup failure performs synchronous failure cleanup, avoiding a
dispose/startup future dependency cycle. These paths were reviewed together
with request rejection and the worker's acknowledgement and exit handling.

## Review finding: finalizer reachability

The first repair stored its `NativeFinalizer` only on the `_Bindings` instance.
That instance shared the owner graph whose disappearance the finalizer was
intended to cover. The pinned Dart SDK's `lib/ffi/native_finalizer.dart`
documentation explicitly requires keeping the finalizer itself reachable so it
is not disposed before its callback can run; its example uses a static root.

The author addressed this finding with `_Bindings._finalizers`, a static cache
keyed by the native close callback address. Owners obtain the corresponding
finalizer from that cache, independently of their own reachability. Explicit
close still detaches the owner before releasing the handle. The owner implements
`Finalizable`, and native operations are performed through its instance methods
to preserve ownership while those operations execute.

This resolves the reviewed finalizer-lifetime issue. It does not establish a
deadline for garbage collection, finalizer execution, or termination of an
active native call.

## Development evidence and its limits

The author's `hunspell-lifecycle-development/receipt.json` identifies the final
focused run as `green-final-native-lifecycle.jsonl`, SHA-256
`da07e199798c445acf6a7771c5cb4097543d4316edb7f2cc27593f446ae7ac2b`.
It records **eight passing executions, zero failures, and zero skips** after
the static finalizer cache change. The author also reports strict analysis and
formatting success. These are author-run development results inspected through
the receipt; this reviewer did not rerun the suite.

The eight reviewed scenarios cover ordinary disposal, concurrent and repeated
disposal, successful reopening, allocation-failed reopening, pending native
work released during disposal, disposal during startup, unused disposal, and
native open rejection. The fixture counts open/live/closed handles and invalid
use or double-close attempts. Its blocked-call scenario verifies that disposal
rejects the pending Dart request immediately, does not free the still-active
native handle, and completes only after release and explicit native closure.

**Graceful cleanup is the tested guarantee.** These deterministic Linux fixture
executions establish the explicit close/acknowledgement behavior, including
exactly-once cleanup in the covered races. After a two-second acknowledgement
timeout or worker failure, the transport forces termination and retains a
native-finalizer fallback. The eight scenarios do not qualify prompt finalizer
execution after that forced path, an indefinitely stuck native call, process
crashes, or other operating systems. No immediate native-destruction guarantee
is inferred for those cases.

Final combined qualification must use the exact integrated source and provide
`QUDS_HUNSPELL_LIFECYCLE_LIBRARY` for the compiled fixture. The standalone test
file skips when that variable is absent, so a zero-skip gate must verify that
all eight lifecycle scenarios actually execute. The development receipt alone
does not qualify later source changes or the complete merged repository.

No production, test, fixture, or runtime files were changed by this reviewer,
and no GitHub Actions status was queried or awaited for this review.

# Incoming Zotero editor reconciliation checks

The incoming editor integration passed focused local validation on Linux with
Flutter 3.47.8 / Dart 3.13.7. GitHub Actions were not used or waited for.

| Check | Result |
| --- | --- |
| Fatal-info analysis of `word_zotero_dialog.dart`, `word_zotero_format.dart` and the three new tests | Exit 0; no issues |
| `word_zotero_backoff_session_test.dart` | 5 passed |
| `word_zotero_dialog_scaling_test.dart` | 2 passed |
| `word_zotero_source_identity_test.dart` | 2 passed |
| Recorded source/package/lock inputs | Unchanged during validation |

The three files ran together with `flutter test --no-pub --concurrency=1
--reporter expanded`, for **9 passing tests**. [receipt.json](receipt.json)
records exact commands, exit codes, timings, source hashes and log hashes.
The hash scope includes the incoming editor files, directly changed engine
Zotero dependencies and package/lock inputs. The full application dependency
closure belongs to the final integration receipt.

## Review findings

No concrete defect was found in the incoming editor changes. All five online
client construction paths reuse the same session backoff state; the desktop
client retains independent state. The tests cover reconnection, dialog closure
and reopening, key/library changes, disconnect, successful responses carrying
Backoff, and desktop access while online requests are paused.

Document action availability reuses the already parsed field list. Its
nonempty-citation-item predicate preserves the previous action semantics while
avoiding repeated whole-document scans. The 1,000-citation case observes one
scan when opening the dialog; it is a regression check, not a latency benchmark.
Bibliography-only documents keep source-dependent actions disabled.

The basic bibliography now uses the shared engine alias resolver. Tests cover
late and transitive aliases, alias-only records without CSL data, preservation
of the first available snapshot, separation of unrelated group sources, and
unchanged input citation JSON. Sorting applies to the returned list and does
not rewrite the embedded maps.

No shared source was modified during this review. Network transports are test
doubles; these checks make no claim of a live Zotero service or desktop session.

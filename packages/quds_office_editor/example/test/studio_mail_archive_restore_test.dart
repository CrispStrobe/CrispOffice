import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_store/quds_mail_store.dart';
import 'package:quds_office_studio/studio_mail_archive_native.dart';
import 'package:quds_office_studio/studio_mail_archive_restore_strings.dart';
import 'package:quds_office_studio/studio_mail_archive_strings.dart';
import 'package:quds_office_studio/studio_strings.dart';

MailArchiveRestorePlan _plan({bool longLabels = false, int completed = 0}) {
  final plan = MailArchiveRestorePlan.fromManifest(
    directoryPath: '/selected/exported-mail',
    manifest: encodeMailArchiveExportManifest(
      MailArchiveExportPlan(
        profile: MailProfileId(
          longLabels ? 'archive-' * 100 : 'source-archive',
          hostId: longLabels ? 'host-' * 100 : 'different-host',
        ),
        createdAt: DateTime.utc(2026, 11, 19, 12),
        items: [
          for (final id in ['a', 'b'])
            MailArchiveExportItem(
              id: id * 64,
              byteLength: 25,
              origins: [
                MailArchiveOrigin(
                  source: 'Original account',
                  folder: '/Inbox',
                  sourceMessageId: id,
                ),
              ],
            ),
        ],
      ),
      const MailArchiveExportLimits(),
    ),
  );
  return completed == 0
      ? plan
      : plan.withCheckpoint(
          MailArchiveRestoreCheckpoint(
            manifestSha256: plan.manifestSha256,
            planned: plan.messageCount,
            totalBytes: plan.totalBytes,
            completedMessages: completed,
            completedBytes: completed * 25,
          ),
        );
}

MailArchiveRestoreReport _report({
  MailArchiveRestoreStatus status = MailArchiveRestoreStatus.completed,
  int saved = 1,
  int duplicates = 1,
  int failed = 0,
  int resumed = 0,
  int resumedIndexWarnings = 0,
  MailProblemCode? problem,
}) => MailArchiveRestoreReport(
  status: status,
  planned: 2,
  saved: saved,
  duplicates: duplicates,
  failed: failed,
  originsAdded: saved + duplicates,
  bytes: 25 * (saved + duplicates),
  indexWarnings: 0,
  resumed: resumed,
  resumedBytes: resumed * 25,
  resumedIndexWarnings: resumedIndexWarnings,
  elapsedMicroseconds: 10,
  observerErrors: 0,
  failures: [
    if (failed > 0)
      const MailArchiveRestoreFailure(
        ordinal: 2,
        code: MailProblemCode.unavailable,
      ),
  ],
  droppedFailures: 0,
  problem: problem == null ? null : MailProblem(problem),
);

final class _Store extends Fake implements StudioMailArchiveStore {
  _Store({MailArchiveRestorePlan? plan}) : plan = plan ?? _plan();

  final MailArchiveRestorePlan plan;
  int inspections = 0;
  int restores = 0;
  int searches = 0;
  int closes = 0;
  bool? indexAttachments;
  bool? resume;
  final forgotten = <String>[];
  int checkpointLists = 0;
  MailCancellationToken? token;
  MailArchiveRestoreProgressSink? progress;
  Future<MailResult<MailArchiveRestorePlan>> Function()? onInspect;
  Future<MailArchiveRestoreReport> Function()? onRestore;
  Future<MailResult<List<MailArchiveRestoreCheckpoint>>> Function()? onList;
  Future<MailResult<MailUnit>> Function()? onForget;

  @override
  set diagnostics(MailArchiveDiagnostics? value) {}

  @override
  Future<MailResult<MailArchiveSearchPage>> search(
    MailArchiveSearchRequest request,
  ) async {
    searches++;
    return MailSuccess(MailArchiveSearchPage(hits: [], total: 0, offset: 0));
  }

  @override
  Future<MailResult<MailArchiveStats>> statistics() async => const MailSuccess(
    MailArchiveStats(messages: 0, rawBytes: 0, indexedMessages: 0, origins: 0),
  );

  @override
  Future<MailResult<List<MailArchiveSavedSearch>>> listSearches() async =>
      const MailSuccess([]);

  @override
  Future<MailResult<MailArchiveRestorePlan>> inspectRestore(
    String directoryPath, {
    MailCancellationToken? cancellation,
  }) async {
    inspections++;
    expect(directoryPath, plan.directoryPath);
    token = cancellation;
    return onInspect == null ? MailSuccess(plan) : onInspect!();
  }

  @override
  Future<MailArchiveRestoreReport> restoreExport(
    MailArchiveRestorePlan selected, {
    bool indexAttachmentText = false,
    bool resume = false,
    MailCancellationToken? cancellation,
    MailArchiveRestoreProgressSink? onProgress,
  }) async {
    restores++;
    expect(identical(selected, plan), isTrue);
    indexAttachments = indexAttachmentText;
    this.resume = resume;
    token = cancellation;
    progress = onProgress;
    return onRestore == null ? _report() : onRestore!();
  }

  @override
  Future<MailResult<List<MailArchiveRestoreCheckpoint>>>
  listRestoreCheckpoints() async {
    checkpointLists++;
    if (onList != null) return onList!();
    return MailSuccess([?plan.checkpoint]);
  }

  @override
  Future<MailResult<MailUnit>> forgetRestoreCheckpoint(
    String manifestSha256, {
    MailCancellationToken? cancellation,
  }) async {
    forgotten.add(manifestSha256);
    token = cancellation;
    if (onForget != null) return onForget!();
    return const MailSuccess(MailUnit.value);
  }

  @override
  Future<void> close() async => closes++;
}

final class _Files extends Fake implements StudioMailArchiveFiles {
  String? directory = '/selected/exported-mail';
  int picks = 0;

  @override
  Future<String?> pickDirectory() async {
    picks++;
    return directory;
  }
}

Finder _key(String name) => find.byKey(ValueKey(name));

Future<void> _pump(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump();
}

Future<void> _tap(WidgetTester tester, String name) async {
  await tester.ensureVisible(_key(name));
  await tester.pump();
  await tester.tap(_key(name));
  await _pump(tester);
}

Future<void> _show(
  WidgetTester tester,
  _Store store, {
  _Files? files,
  StudioLanguage language = StudioLanguage.en,
  Size size = const Size(1200, 1000),
  double textScale = 1,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: StudioMailArchiveDialog(
        strings: StudioStrings(language),
        store: store,
        files: files ?? _Files(),
      ),
    ),
  );
  await _pump(tester);
}

void main() {
  testWidgets('preview requires confirmation and preserves the selection', (
    tester,
  ) async {
    final store = _Store();
    await _show(tester, store);
    await _tap(tester, 'archive-restore-export');
    expect(store.inspections, 1);
    expect(store.restores, 0);
    expect(
      find.textContaining('2 original messages (50 bytes)'),
      findsOneWidget,
    );
    expect(
      find.textContaining('different-host / source-archive'),
      findsOneWidget,
    );
    expect(find.textContaining('unsigned export'), findsOneWidget);
    expect(_key('archive-restore-directory'), findsOneWidget);
    await _tap(tester, 'archive-restore-attachments');
    await _tap(tester, 'archive-restore-confirm');
    expect(store.restores, 1);
    expect(store.indexAttachments, isTrue);
    expect(store.resume, isFalse);
    expect(find.textContaining('1 saved · 1 already archived'), findsOneWidget);
    expect(find.textContaining('2 source entries added'), findsOneWidget);
    expect(store.searches, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'recorded progress defaults to resume and keeps the exact selection',
    (tester) async {
      final store = _Store(plan: _plan(completed: 1))
        ..onRestore = () async => _report(duplicates: 0, resumed: 1);
      await _show(tester, store);
      await _tap(tester, 'archive-restore-export');
      expect(
        find.textContaining('1 of 2 messages recorded as committed'),
        findsOneWidget,
      );
      expect(
        tester.widget<CheckboxListTile>(_key('archive-restore-resume')).value,
        isTrue,
      );
      expect(find.text('Resume restore'), findsOneWidget);
      expect(
        find.textContaining('Their export files are not read again'),
        findsOneWidget,
      );
      await _tap(tester, 'archive-restore-confirm');
      expect(store.resume, isTrue);
      expect(store.restores, 1);
      expect(
        find.textContaining('1 saved · 0 already archived'),
        findsOneWidget,
      );
      expect(
        find.textContaining(
          '1 previously committed · 25 archive bytes rechecked',
        ),
        findsOneWidget,
      );
      expect(store.forgotten, isEmpty);
    },
  );

  testWidgets(
    'turning resume off requests full source verification without forgetting progress',
    (tester) async {
      final store = _Store(plan: _plan(completed: 2));
      await _show(tester, store);
      await _tap(tester, 'archive-restore-export');
      await _tap(tester, 'archive-restore-resume');
      expect(find.text('Restore messages'), findsOneWidget);
      await _tap(tester, 'archive-restore-confirm');
      expect(store.resume, isFalse);
      expect(store.forgotten, isEmpty);
    },
  );

  testWidgets(
    'resumed progress and previous indexing warnings remain separate from this run',
    (tester) async {
      final done = Completer<MailArchiveRestoreReport>();
      final store = _Store(plan: _plan(completed: 1))
        ..onRestore = () => done.future;
      await _show(tester, store);
      await _tap(tester, 'archive-restore-export');
      await _tap(tester, 'archive-restore-confirm');
      store.progress!(
        const MailArchiveRestoreProgress(
          phase: MailArchiveRestorePhase.message,
          planned: 2,
          saved: 0,
          duplicates: 0,
          failed: 0,
          originsAdded: 0,
          bytes: 0,
          indexWarnings: 0,
          resumed: 1,
          resumedBytes: 25,
          resumedIndexWarnings: 1,
          elapsedMicroseconds: 1,
          observerErrors: 0,
        ),
      );
      await _pump(tester);
      expect(
        find.textContaining('0 source bytes verified · 0 indexing warnings'),
        findsOneWidget,
      );
      expect(
        find.textContaining(
          '1 previously committed · 25 archive bytes rechecked · 1 earlier indexing warnings',
        ),
        findsOneWidget,
      );
      await _tap(tester, 'archive-cancel');
      expect(store.token!.isCancelled, isTrue);
      done.complete(
        _report(
          status: MailArchiveRestoreStatus.cancelled,
          saved: 0,
          duplicates: 0,
          resumed: 1,
          resumedIndexWarnings: 1,
        ),
      );
      await _pump(tester);
      expect(find.textContaining('Cancelled. 0 saved'), findsOneWidget);
      expect(find.textContaining('1 previously committed'), findsOneWidget);
    },
  );

  testWidgets(
    'restore progress management confirms forgetting and keeps messages untouched',
    (tester) async {
      final store = _Store(plan: _plan(completed: 1));
      await _show(tester, store);
      expect(store.checkpointLists, 0);
      await _tap(tester, 'archive-restore-progress');
      expect(store.checkpointLists, 1);
      expect(
        find.textContaining('1 of 2 messages recorded as committed'),
        findsOneWidget,
      );
      await _tap(tester, 'archive-restore-forget-0');
      expect(
        find.textContaining('Archived messages and source files are kept'),
        findsOneWidget,
      );
      expect(store.forgotten, isEmpty);
      await _tap(tester, 'archive-restore-forget-dismiss');
      expect(store.forgotten, isEmpty);
      await _tap(tester, 'archive-restore-forget-0');
      await _tap(tester, 'archive-restore-forget-confirm');
      expect(store.forgotten, [store.plan.manifestSha256]);
      expect(_key('archive-restore-progress-empty'), findsOneWidget);
      expect(store.restores, 0);
      expect(store.inspections, 0);
      await _tap(tester, 'archive-restore-progress-close');
      expect(
        tester.widget<OutlinedButton>(_key('archive-restore-export')).onPressed,
        isNotNull,
      );
    },
  );

  testWidgets('forget failure is sanitized and retains the listed progress', (
    tester,
  ) async {
    final store = _Store(plan: _plan(completed: 1))
      ..onForget = () async => throw StateError('private archive path');
    await _show(tester, store);
    await _tap(tester, 'archive-restore-progress');
    await _tap(tester, 'archive-restore-forget-0');
    await _tap(tester, 'archive-restore-forget-confirm');
    expect(_key('archive-restore-progress-error'), findsOneWidget);
    expect(_key('archive-restore-forget-0'), findsOneWidget);
    expect(find.textContaining('private archive path'), findsNothing);
  });

  testWidgets('disposing during progress listing drops a late dialog', (
    tester,
  ) async {
    final done = Completer<MailResult<List<MailArchiveRestoreCheckpoint>>>();
    final store = _Store(plan: _plan(completed: 1))..onList = () => done.future;
    await _show(tester, store);
    await _tap(tester, 'archive-restore-progress');
    await tester.pumpWidget(const SizedBox.shrink());
    done.complete(MailSuccess([store.plan.checkpoint!]));
    await _pump(tester);
    expect(_key('archive-restore-progress-dialog'), findsNothing);
    expect(store.forgotten, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'disposing during forgetting cancels its token and ignores the result',
    (tester) async {
      final done = Completer<MailResult<MailUnit>>();
      final store = _Store(plan: _plan(completed: 1))
        ..onForget = () => done.future;
      await _show(tester, store);
      await _tap(tester, 'archive-restore-progress');
      await _tap(tester, 'archive-restore-forget-0');
      await _tap(tester, 'archive-restore-forget-confirm');
      expect(
        tester
            .widget<TextButton>(_key('archive-restore-progress-close'))
            .onPressed,
        isNull,
      );
      expect(
        tester.widget<TextButton>(_key('archive-restore-forget-0')).onPressed,
        isNull,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      expect(store.token!.isCancelled, isTrue);
      done.complete(const MailSuccess(MailUnit.value));
      await _pump(tester);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('dismissing preview performs no restore', (tester) async {
    final store = _Store();
    await _show(tester, store);
    await _tap(tester, 'archive-restore-export');
    await _tap(tester, 'archive-restore-dismiss');
    expect(store.restores, 0);
    expect(_key('archive-restore-confirm'), findsNothing);
  });

  testWidgets('cancelling the folder picker performs no inspection', (
    tester,
  ) async {
    final store = _Store();
    final files = _Files()..directory = null;
    await _show(tester, store, files: files);
    await _tap(tester, 'archive-restore-export');
    expect(files.picks, 1);
    expect(store.inspections, 0);
    expect(store.restores, 0);
  });

  testWidgets('invalid export is reported before showing the preview', (
    tester,
  ) async {
    final store = _Store()
      ..onInspect = () async =>
          const MailFailure(MailProblem(MailProblemCode.invalidInput));
    await _show(tester, store);
    await _tap(tester, 'archive-restore-export');
    expect(_key('archive-error'), findsOneWidget);
    expect(_key('archive-restore-confirm'), findsNothing);
    expect(store.restores, 0);
  });

  testWidgets('unexpected inspection exceptions are sanitized', (tester) async {
    final store = _Store()
      ..onInspect = () async =>
          throw StateError('private source and credential');
    await _show(tester, store);
    await _tap(tester, 'archive-restore-export');
    expect(_key('archive-error'), findsOneWidget);
    expect(find.textContaining('private source'), findsNothing);
    expect(store.restores, 0);
  });

  testWidgets('cancellation awaits confirmed counts and keeps earlier saves', (
    tester,
  ) async {
    final done = Completer<MailArchiveRestoreReport>();
    final store = _Store()..onRestore = () => done.future;
    await _show(tester, store);
    await _tap(tester, 'archive-restore-export');
    await _tap(tester, 'archive-restore-confirm');
    store.progress!(
      const MailArchiveRestoreProgress(
        phase: MailArchiveRestorePhase.message,
        planned: 2,
        saved: 1,
        duplicates: 0,
        failed: 0,
        originsAdded: 1,
        bytes: 25,
        indexWarnings: 0,
        elapsedMicroseconds: 1,
        observerErrors: 0,
      ),
    );
    await _pump(tester);
    expect(find.textContaining('1 saved · 0 already archived'), findsOneWidget);
    await _tap(tester, 'archive-cancel');
    expect(store.token!.isCancelled, isTrue);
    expect(
      tester.widget<OutlinedButton>(_key('archive-restore-export')).onPressed,
      isNull,
    );
    done.complete(
      _report(status: MailArchiveRestoreStatus.cancelled, duplicates: 0),
    );
    await _pump(tester);
    expect(find.textContaining('Cancelled. 1 saved'), findsOneWidget);
    expect(
      tester.widget<OutlinedButton>(_key('archive-restore-export')).onPressed,
      isNotNull,
    );
  });

  testWidgets('partial restore exposes bounded item failures', (tester) async {
    final store = _Store()
      ..onRestore = () async => _report(
        status: MailArchiveRestoreStatus.partial,
        duplicates: 0,
        failed: 1,
      );
    await _show(tester, store);
    await _tap(tester, 'archive-restore-export');
    await _tap(tester, 'archive-restore-confirm');
    expect(find.textContaining('Partly completed. 1 saved'), findsOneWidget);
    await _tap(tester, 'archive-restore-failures');
    expect(find.text('Export item 2'), findsOneWidget);
    expect(
      find.text(
        const StudioStrings(
          StudioLanguage.en,
        ).archiveProblem(MailProblemCode.unavailable),
      ),
      findsOneWidget,
    );
  });

  testWidgets('disposing during inspection cancels and drops late preview', (
    tester,
  ) async {
    final inspected = Completer<MailResult<MailArchiveRestorePlan>>();
    final store = _Store()..onInspect = () => inspected.future;
    await _show(tester, store);
    await _tap(tester, 'archive-restore-export');
    await tester.pumpWidget(const SizedBox.shrink());
    expect(store.token!.isCancelled, isTrue);
    inspected.complete(MailSuccess(store.plan));
    await _pump(tester);
    expect(store.restores, 0);
    expect(store.closes, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('disposing during restore ignores late progress and result', (
    tester,
  ) async {
    final done = Completer<MailArchiveRestoreReport>();
    final store = _Store()..onRestore = () => done.future;
    await _show(tester, store);
    await _tap(tester, 'archive-restore-export');
    await _tap(tester, 'archive-restore-confirm');
    await tester.pumpWidget(const SizedBox.shrink());
    expect(store.token!.isCancelled, isTrue);
    done.complete(_report());
    await _pump(tester);
    expect(tester.takeException(), isNull);
    expect(store.closes, 1);
  });

  for (final language in StudioLanguage.values) {
    testWidgets('narrow $language resume and progress controls remain usable', (
      tester,
    ) async {
      final store = _Store(plan: _plan(longLabels: true, completed: 1));
      await _show(
        tester,
        store,
        language: language,
        size: const Size(360, 800),
        textScale: 1.6,
      );
      final strings = StudioStrings(language);
      await _tap(tester, 'archive-restore-export');
      expect(find.text(strings.archiveRestoreResumeStart), findsOneWidget);
      expect(_key('archive-restore-recorded'), findsOneWidget);
      await _tap(tester, 'archive-restore-resume');
      expect(find.text(strings.archiveRestoreStart), findsOneWidget);
      await _tap(tester, 'archive-restore-dismiss');
      await _tap(tester, 'archive-restore-progress');
      expect(
        Directionality.of(
          tester.element(_key('archive-restore-progress-close')),
        ),
        language == StudioLanguage.ar ? TextDirection.rtl : TextDirection.ltr,
      );
      await _tap(tester, 'archive-restore-forget-0');
      expect(
        Directionality.of(
          tester.element(_key('archive-restore-forget-confirm')),
        ),
        language == StudioLanguage.ar ? TextDirection.rtl : TextDirection.ltr,
      );
      await _tap(tester, 'archive-restore-forget-dismiss');
      await _tap(tester, 'archive-restore-progress-close');
      expect(tester.takeException(), isNull);
      expect(store.forgotten, isEmpty);
    });

    testWidgets('narrow $language preview supports long profile labels', (
      tester,
    ) async {
      final store = _Store(plan: _plan(longLabels: true));
      await _show(
        tester,
        store,
        language: language,
        size: const Size(360, 800),
      );
      await _tap(tester, 'archive-restore-export');
      final strings = StudioStrings(language);
      expect(find.text(strings.archiveRestoreStart), findsOneWidget);
      expect(find.text(strings.archiveRestoreTrust), findsOneWidget);
      expect(
        Directionality.of(tester.element(_key('archive-restore-confirm'))),
        language == StudioLanguage.ar ? TextDirection.rtl : TextDirection.ltr,
      );
      await _tap(tester, 'archive-restore-dismiss');
      expect(store.restores, 0);
      expect(tester.takeException(), isNull);
    });
  }
}

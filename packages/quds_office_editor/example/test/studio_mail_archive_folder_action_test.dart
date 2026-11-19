import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_store/quds_mail_archive_native.dart';
import 'package:quds_office_studio/studio_mail_archive_folder_action.dart';
import 'package:quds_office_studio/studio_mail_archive_strings.dart';
import 'package:quds_office_studio/studio_strings.dart';

const _strings = StudioStrings(StudioLanguage.en);
const _profile = MailArchiveProfile(
  id: 'stable-folder-profile',
  name: 'Inbox',
  source: 'Account fixture',
  folder: '/Inbox',
  kind: MailArchiveProfileKind.mailbox,
  includeSubfolders: false,
);

MailArchiveRunReport _report({
  MailArchiveRunStatus status = MailArchiveRunStatus.completed,
  int saved = 2,
  int duplicates = 1,
  int failed = 0,
  MailProblem? problem,
  List<MailArchiveRunFailure> failures = const [],
  int droppedFailures = 0,
}) => MailArchiveRunReport(
  status: status,
  pages: 2,
  processed: saved + duplicates + failed,
  saved: saved,
  duplicates: duplicates,
  failed: failed,
  bytes: saved * 10,
  elapsedMicroseconds: 1000,
  observerErrors: 0,
  failures: failures,
  droppedFailures: droppedFailures,
  problem: problem,
);

MailArchiveRunProgress _progress({
  int saved = 2,
  int duplicates = 1,
  int failed = 0,
}) => MailArchiveRunProgress(
  operationId: 1,
  phase: MailArchiveRunPhase.message,
  pages: 2,
  processed: saved + duplicates + failed,
  saved: saved,
  duplicates: duplicates,
  failed: failed,
  bytes: saved * 10,
  elapsedMicroseconds: 900,
  observerErrors: 0,
);

Future<void> _pump(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump();
}

Finder _key(String key) => find.byKey(ValueKey(key));

Future<void> _tap(WidgetTester tester, String key) async {
  await tester.ensureVisible(_key(key));
  await tester.tap(_key(key));
  await _pump(tester);
}

Future<void> _show(
  WidgetTester tester, {
  required StudioMailArchiveFolderWriter writer,
  ValueNotifier<Object>? session,
  StudioStrings strings = _strings,
  Size size = const Size(1000, 950),
  bool enabled = true,
  String folder = '/Inbox',
  ValueChanged<bool>? onDialogChanged,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final identity = session ?? ValueNotifier(Object());
  if (session == null) addTearDown(identity.dispose);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ValueListenableBuilder<Object>(
          valueListenable: identity,
          builder: (context, value, _) => StudioArchiveFolderButton(
            strings: strings,
            source: 'private-source@example.test',
            folder: folder,
            profileId: _profile.id,
            sessionKey: value,
            enabled: enabled,
            writer: writer,
            onDialogChanged: onDialogChanged,
            runner: (_, _, {cancellation, onProgress}) =>
                throw StateError('Injected writer must own the run.'),
          ),
        ),
      ),
    ),
  );
  await _pump(tester);
  if (enabled) await _tap(tester, 'archive-selected-folder');
}

void main() {
  test(
    'folder profile and overlong provenance fingerprints are stable and bounded',
    () {
      final first = studioArchiveFolderProfileId(
        'ews:https://example.test',
        'team@example.test',
        'box',
      );
      expect(
        first,
        studioArchiveFolderProfileId(
          'ews:https://example.test',
          'team@example.test',
          'box',
        ),
      );
      expect(
        first,
        isNot(
          studioArchiveFolderProfileId(
            'ews:https://other.test',
            'team@example.test',
            'box',
          ),
        ),
      );
      expect(first.length, lessThan(1024));
      expect(studioArchiveSourceMessageId('one'), 'one');
      final long = 'opaque-value' * 200;
      final hashed = studioArchiveSourceMessageId(long);
      expect(hashed, startsWith('sha256:'));
      expect(hashed.length, 71);
      expect(hashed, studioArchiveSourceMessageId(long));
      expect(hashed, isNot(studioArchiveSourceMessageId('${long}x')));
      expect(studioArchiveSourceMessageId('a\u0000b'), startsWith('sha256:'));
    },
  );

  testWidgets('disabled folder action cannot start or open an archive', (
    tester,
  ) async {
    var calls = 0;
    await _show(
      tester,
      enabled: false,
      writer:
          (
            profile, {
            required cancellation,
            onProgress,
            required verboseDiagnostics,
          }) async {
            calls++;
            return _report();
          },
    );
    expect(
      tester.widget<IconButton>(_key('archive-selected-folder')).onPressed,
      isNull,
    );
    expect(find.byType(AlertDialog), findsNothing);
    expect(calls, 0);
  });

  testWidgets(
    'selected folder waits for Start and passes explicit extraction settings',
    (tester) async {
      final dialogs = <bool>[];
      MailArchiveProfile? received;
      bool? verbose;
      await _show(
        tester,
        onDialogChanged: dialogs.add,
        writer:
            (
              profile, {
              required cancellation,
              onProgress,
              required verboseDiagnostics,
            }) async {
              received = profile;
              verbose = verboseDiagnostics;
              return _report();
            },
      );
      expect(received, isNull);
      expect(find.text('Source: private-source@example.test'), findsOneWidget);
      expect(find.text('Folder: /Inbox'), findsOneWidget);
      await _tap(tester, 'archive-folder-attachment-text');
      await _tap(tester, 'archive-folder-verbose');
      await _tap(tester, 'archive-folder-start');
      expect(received!.id, _profile.id);
      expect(received!.source, 'private-source@example.test');
      expect(received!.folder, '/Inbox');
      expect(received!.kind, MailArchiveProfileKind.mailbox);
      expect(received!.includeSubfolders, isFalse);
      expect(received!.indexAttachmentText, isTrue);
      expect(verbose, isTrue);
      expect(
        find.text(_strings.archiveFolderCounts(2, 1, 0, 2, 20)),
        findsOneWidget,
      );
      expect(
        find.text(_strings.archiveFolderStatus(MailArchiveRunStatus.completed)),
        findsOneWidget,
      );
      await _tap(tester, 'archive-folder-close');
      expect(dialogs, [true, false]);
    },
  );

  testWidgets(
    'long Unicode mailbox paths keep their provenance with a bounded display name',
    (tester) async {
      final folder = '/${'nested😀/' * 100}';
      MailArchiveProfile? received;
      await _show(
        tester,
        folder: folder,
        writer:
            (
              profile, {
              required cancellation,
              onProgress,
              required verboseDiagnostics,
            }) async {
              received = profile;
              return _report();
            },
      );
      await _tap(tester, 'archive-folder-start');
      expect(received!.folder, folder);
      expect(received!.source, 'private-source@example.test');
      expect(received!.id, _profile.id);
      expect(received!.name.length, lessThanOrEqualTo(256));
      expect(received!.name, String.fromCharCodes(folder.runes.take(128)));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('a run with only failed attempts reports failed, not partial', (
    tester,
  ) async {
    await _show(
      tester,
      writer:
          (
            profile, {
            required cancellation,
            onProgress,
            required verboseDiagnostics,
          }) async {
            onProgress!(_progress(saved: 0, duplicates: 0, failed: 3));
            throw StateError('private failure');
          },
    );
    await _tap(tester, 'archive-folder-start');
    expect(
      find.text(_strings.archiveFolderStatus(MailArchiveRunStatus.failed)),
      findsOneWidget,
    );
    expect(
      find.text(_strings.archiveFolderCounts(0, 0, 3, 2, 0)),
      findsOneWidget,
    );
    expect(
      find.text(_strings.archiveFolderStatus(MailArchiveRunStatus.partial)),
      findsNothing,
    );
  });

  testWidgets(
    'cancel prevents dismissal until final committed counts are known',
    (tester) async {
      final complete = Completer<MailArchiveRunReport>();
      MailCancellationToken? token;
      await _show(
        tester,
        writer:
            (
              profile, {
              required cancellation,
              onProgress,
              required verboseDiagnostics,
            }) {
              token = cancellation;
              onProgress!(_progress(saved: 3, duplicates: 2));
              return complete.future;
            },
      );
      await _tap(tester, 'archive-folder-start');
      expect(_key('archive-folder-close'), findsNothing);
      await tester.binding.handlePopRoute();
      await _pump(tester);
      expect(find.byType(AlertDialog), findsOneWidget);
      await _tap(tester, 'archive-folder-cancel');
      expect(token!.isCancelled, isTrue);
      expect(find.text(_strings.archiveFolderCancelling), findsOneWidget);
      expect(
        tester.widget<TextButton>(_key('archive-folder-cancel')).onPressed,
        isNull,
      );
      complete.complete(
        _report(
          status: MailArchiveRunStatus.cancelled,
          saved: 4,
          duplicates: 2,
        ),
      );
      await _pump(tester);
      expect(
        find.text(_strings.archiveFolderCounts(4, 2, 0, 2, 40)),
        findsOneWidget,
      );
      expect(
        find.text(_strings.archiveFolderStatus(MailArchiveRunStatus.cancelled)),
        findsOneWidget,
      );
      expect(_key('archive-folder-close'), findsOneWidget);
    },
  );

  testWidgets(
    'throwing writer reports a fixed failure and retains prior saved counts',
    (tester) async {
      await _show(
        tester,
        writer:
            (
              profile, {
              required cancellation,
              onProgress,
              required verboseDiagnostics,
            }) async {
              onProgress!(_progress(saved: 5, duplicates: 1, failed: 2));
              throw StateError('private-token raw-server-body SELECT secret');
            },
      );
      await _tap(tester, 'archive-folder-start');
      expect(
        find.text(_strings.archiveFolderCounts(5, 1, 2, 2, 50)),
        findsOneWidget,
      );
      expect(
        find.text(_strings.archiveFolderStatus(MailArchiveRunStatus.partial)),
        findsOneWidget,
      );
      expect(
        find.text(_strings.archiveProblem(MailProblemCode.providerFailure)),
        findsOneWidget,
      );
      expect(find.textContaining('private-token'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'run limits are described as incomplete without discarding committed messages',
    (tester) async {
      await _show(
        tester,
        writer:
            (
              profile, {
              required cancellation,
              onProgress,
              required verboseDiagnostics,
            }) async => _report(
              status: MailArchiveRunStatus.limited,
              saved: 100,
              duplicates: 20,
              failed: 3,
              problem: const MailProblem(MailProblemCode.quotaExceeded),
            ),
      );
      await _tap(tester, 'archive-folder-start');
      expect(
        find.text(_strings.archiveFolderStatus(MailArchiveRunStatus.limited)),
        findsOneWidget,
      );
      expect(
        find.text(_strings.archiveFolderCounts(100, 20, 3, 2, 1000)),
        findsOneWidget,
      );
      expect(
        find.text(_strings.archiveFolderStatus(MailArchiveRunStatus.completed)),
        findsNothing,
      );
    },
  );

  testWidgets('partial results expose bounded fixed per-item reasons', (
    tester,
  ) async {
    await _show(
      tester,
      writer:
          (
            profile, {
            required cancellation,
            onProgress,
            required verboseDiagnostics,
          }) async => _report(
            status: MailArchiveRunStatus.partial,
            failed: 2,
            failures: const [
              MailArchiveRunFailure(
                ordinal: 3,
                stage: MailArchiveRunStage.fetch,
                code: MailProblemCode.permissionDenied,
              ),
            ],
            droppedFailures: 1,
          ),
    );
    await _tap(tester, 'archive-folder-start');
    await _tap(tester, 'archive-folder-failures');
    expect(find.text(_strings.archiveFolderItemFailures(1, 1)), findsOneWidget);
    expect(
      find.text(_strings.archiveFolderFailure(3, MailArchiveRunStage.fetch)),
      findsOneWidget,
    );
    expect(
      find.text(_strings.archiveProblem(MailProblemCode.permissionDenied)),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('session replacement cancels the frozen run', (tester) async {
    final session = ValueNotifier<Object>(Object());
    addTearDown(session.dispose);
    final complete = Completer<MailArchiveRunReport>();
    MailCancellationToken? token;
    await _show(
      tester,
      session: session,
      writer:
          (
            profile, {
            required cancellation,
            onProgress,
            required verboseDiagnostics,
          }) {
            token = cancellation;
            return complete.future;
          },
    );
    await _tap(tester, 'archive-folder-start');
    session.value = Object();
    await _pump(tester);
    expect(token!.reason, MailCancellationReason.accountChanged);
    complete.complete(_report(status: MailArchiveRunStatus.cancelled));
    await _pump(tester);
    expect(
      find.text(_strings.archiveFolderStatus(MailArchiveRunStatus.cancelled)),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('session replacement before Start never invokes the writer', (
    tester,
  ) async {
    final session = ValueNotifier<Object>(Object());
    addTearDown(session.dispose);
    var calls = 0;
    await _show(
      tester,
      session: session,
      writer:
          (
            profile, {
            required cancellation,
            onProgress,
            required verboseDiagnostics,
          }) async {
            calls++;
            return _report();
          },
    );
    session.value = Object();
    await _pump(tester);
    await _tap(tester, 'archive-folder-start');
    expect(calls, 0);
    expect(
      find.text(_strings.archiveFolderStatus(MailArchiveRunStatus.cancelled)),
      findsOneWidget,
    );
  });

  testWidgets('disposal cancels and ignores a late writer completion', (
    tester,
  ) async {
    final complete = Completer<MailArchiveRunReport>();
    MailCancellationToken? token;
    await _show(
      tester,
      writer:
          (
            profile, {
            required cancellation,
            onProgress,
            required verboseDiagnostics,
          }) {
            token = cancellation;
            return complete.future;
          },
    );
    await _tap(tester, 'archive-folder-start');
    await tester.pumpWidget(const SizedBox.shrink());
    expect(token!.reason, MailCancellationReason.disposed);
    complete.complete(_report());
    await _pump(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'verbose progress is bounded and contains only fixed fields and counters',
    (tester) async {
      await _show(
        tester,
        writer:
            (
              profile, {
              required cancellation,
              onProgress,
              required verboseDiagnostics,
            }) async {
              for (var count = 1; count <= 80; count++) {
                onProgress!(_progress(saved: count));
              }
              return _report(saved: 80);
            },
      );
      await _tap(tester, 'archive-folder-verbose');
      await _tap(tester, 'archive-folder-start');
      await _tap(tester, 'archive-folder-log-panel');
      final log = tester
          .widget<SelectableText>(_key('archive-folder-log'))
          .data!;
      expect(log.split('\n'), hasLength(60));
      expect(log, contains('"saved":80'));
      expect(log, isNot(contains('private-source')));
      expect(log, isNot(contains('/Inbox')));
    },
  );

  for (final language in StudioLanguage.values) {
    testWidgets(
      'folder controls and result remain scrollable at 320px in ${language.name}',
      (tester) async {
        final strings = StudioStrings(language);
        await _show(
          tester,
          strings: strings,
          size: const Size(320, 650),
          writer:
              (
                profile, {
                required cancellation,
                onProgress,
                required verboseDiagnostics,
              }) async => _report(),
        );
        await _tap(tester, 'archive-folder-start');
        await tester.ensureVisible(_key('archive-folder-status'));
        await _pump(tester);
        expect(
          find.text(
            strings.archiveFolderStatus(MailArchiveRunStatus.completed),
          ),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        await _tap(tester, 'archive-folder-close');
        expect(find.byType(AlertDialog), findsNothing);
      },
    );
  }

  test('opening failures are typed and never start a provider run', () async {
    var runs = 0;
    for (final throws in [false, true]) {
      final report = await archiveStudioMailFolder(
        runner: (_, _, {cancellation, onProgress}) async {
          runs++;
          return _report();
        },
        profile: _profile,
        cancellation: MailCancellationSource().token,
        openArchive: ({diagnostics}) async {
          if (throws) throw StateError('private database path and SQL');
          return const MailFailure(
            MailProblem(MailProblemCode.permissionDenied),
          );
        },
      );
      expect(report.status, MailArchiveRunStatus.failed);
      expect(
        report.problem!.code,
        throws
            ? MailProblemCode.storageFailure
            : MailProblemCode.permissionDenied,
      );
      expect(report.saved, 0);
    }
    expect(runs, 0);
  });

  test('unsupported folder profiles cannot open or save an archive', () async {
    var opened = 0;
    for (final profile in const [
      MailArchiveProfile(
        id: 'wrong-kind',
        name: 'Files',
        source: 'Fixture',
        includeSubfolders: false,
      ),
      MailArchiveProfile(
        id: 'recursive',
        name: 'Mailbox',
        source: 'Fixture',
        kind: MailArchiveProfileKind.mailbox,
      ),
    ]) {
      final report = await archiveStudioMailFolder(
        profile: profile,
        cancellation: MailCancellationSource().token,
        runner: (_, _, {cancellation, onProgress}) async => _report(),
        openArchive: ({diagnostics}) async {
          opened++;
          return const MailFailure(MailProblem(MailProblemCode.storageFailure));
        },
      );
      expect(report.status, MailArchiveRunStatus.failed);
      expect(report.problem!.code, MailProblemCode.unsupported);
    }
    expect(opened, 0);
  });

  test('pre-cancelled helper does not open any archive', () async {
    final cancel = MailCancellationSource()..cancel();
    var opened = false;
    final report = await archiveStudioMailFolder(
      runner: (_, _, {cancellation, onProgress}) async => _report(),
      profile: _profile,
      cancellation: cancel.token,
      openArchive: ({diagnostics}) async {
        opened = true;
        return const MailFailure(MailProblem(MailProblemCode.storageFailure));
      },
    );
    expect(opened, isFalse);
    expect(report.status, MailArchiveRunStatus.cancelled);
  });

  test(
    'owned folder archive preserves committed originals and profile after runner failure',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'studio-folder-test-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final owner = MailProfileId('folder-tests', hostId: 'studio');
      final raw = MailBytes(Uint8List.fromList([1, 2, 3, 4]));
      final report = await archiveStudioMailFolder(
        profile: _profile,
        cancellation: MailCancellationSource().token,
        openArchive: ({diagnostics}) => openNativeMailArchive(
          appDirectory: directory,
          profile: owner,
          diagnostics: diagnostics,
        ),
        runner: (archive, profile, {cancellation, onProgress}) async {
          final stored = await archive.archiveMessage(
            MailMessage(
              raw: raw,
              envelope: MailEnvelope(subject: 'Original'),
            ),
            origin: MailArchiveOrigin(
              source: profile.source,
              folder: profile.folder,
            ),
          );
          expect(stored, isA<MailSuccess<MailArchiveImportResult>>());
          onProgress!(_progress(saved: 1, duplicates: 0));
          throw StateError('private provider failure');
        },
      );
      expect(report.status, MailArchiveRunStatus.partial);
      expect(report.saved, 1);
      expect(report.problem!.code, MailProblemCode.providerFailure);
      final reopened = await openNativeMailArchive(
        appDirectory: directory,
        profile: owner,
      );
      expect(reopened, isA<MailSuccess<SqliteMailArchive>>());
      final archive = (reopened as MailSuccess<SqliteMailArchive>).value;
      try {
        expect(
          (await archive.listProfiles()
                  as MailSuccess<List<MailArchiveProfile>>)
              .value
              .single
              .id,
          _profile.id,
        );
        expect(
          (await archive.loadOriginal(raw.sha256) as MailSuccess<MailBytes?>)
              .value!
              .bytes,
          orderedEquals(raw.bytes),
        );
      } finally {
        await archive.close();
      }
    },
  );

  test(
    'cancellation during open closes the owned store without saving settings or reading mail',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'studio-folder-open-test-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final owner = MailProfileId('folder-open-tests', hostId: 'studio');
      final gate = Completer<MailResult<SqliteMailArchive>>();
      final cancel = MailCancellationSource();
      var reads = 0;
      final run = archiveStudioMailFolder(
        profile: _profile,
        cancellation: cancel.token,
        openArchive: ({diagnostics}) => gate.future,
        runner: (_, _, {cancellation, onProgress}) async {
          reads++;
          return _report();
        },
      );
      final opened = await openNativeMailArchive(
        appDirectory: directory,
        profile: owner,
      );
      cancel.cancel();
      gate.complete(opened);
      expect((await run).status, MailArchiveRunStatus.cancelled);
      expect(reads, 0);
      final reopened =
          (await openNativeMailArchive(appDirectory: directory, profile: owner)
                  as MailSuccess<SqliteMailArchive>)
              .value;
      try {
        expect(
          (await reopened.listProfiles()
                  as MailSuccess<List<MailArchiveProfile>>)
              .value,
          isEmpty,
        );
      } finally {
        await reopened.close();
      }
    },
  );
}

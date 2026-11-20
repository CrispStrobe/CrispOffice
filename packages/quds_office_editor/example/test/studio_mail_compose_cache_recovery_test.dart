import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_store/quds_mail_store.dart';
import 'package:quds_office_editor/quds_office_editor.dart';
import 'package:quds_office_studio/studio_mail_cached_strings.dart';
import 'package:quds_office_studio/studio_mail_compose.dart';
import 'package:quds_office_studio/studio_mail_draft_store.dart';
import 'package:quds_office_studio/studio_mail_draft_store_native.dart';
import 'package:quds_office_studio/studio_mail_mailbox_store.dart';
import 'package:quds_office_studio/studio_mail_strings.dart';
import 'package:quds_office_studio/studio_strings.dart';

import 'support/mail_outbox_store.dart';

const _strings = StudioStrings(StudioLanguage.en);
const _cleared = MailCacheCleanupReport(
  removedViews: 1,
  evictedBodies: 1,
  removedHeaders: 2,
  retainedBodies: 0,
  hasMore: false,
);
const _more = MailCacheCleanupReport(
  removedViews: 1,
  evictedBodies: 2,
  removedHeaders: 3,
  retainedBodies: 4,
  hasMore: true,
);

Finder _field(String label) => find.byWidgetPredicate(
  (widget) => widget is TextField && widget.decoration?.labelText == label,
);
Finder get _clear =>
    find.byKey(const ValueKey('studio-mail-compose-clear-cache'));
Finder get _confirm =>
    find.byKey(const ValueKey('studio-mail-compose-clear-cache-confirm'));
WordEditorController _body(WidgetTester tester) =>
    tester.widget<QudsWordEditor>(find.byType(QudsWordEditor)).controller;

Future<void> _pump(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
  await tester.pump();
}

Future<void> _tap(WidgetTester tester, Finder target) async {
  await tester.ensureVisible(target);
  await tester.pump();
  await tester.tap(target);
  await _pump(tester);
}

Future<void> _until(WidgetTester tester, bool Function() done) async {
  for (var i = 0; i < 1000 && !done(); i++) {
    await tester.pump(const Duration(milliseconds: 1));
    if (!done()) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 1)),
      );
    }
  }
  expect(done(), isTrue, reason: 'Local storage operation must finish.');
}

Future<void> _open(
  WidgetTester tester, {
  Future<void> Function(StudioMailDraft)? save,
  Future<MailCacheCleanupReport> Function()? clear,
  Future<void> Function(StudioMailDraft)? queue,
  ValueChanged<StudioMailDraft?>? result,
  StudioMailDraft? initial,
  StudioStrings strings = _strings,
  Size size = const Size(1100, 850),
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await _pump(tester);
  });
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async {
              final draft = await showDialog<StudioMailDraft>(
                context: context,
                barrierDismissible: false,
                builder: (_) => Directionality(
                  textDirection: strings.language == StudioLanguage.ar
                      ? TextDirection.rtl
                      : TextDirection.ltr,
                  child: StudioMailComposeDialog(
                    strings: strings,
                    from: 'writer@example.test',
                    initialDraft: initial,
                    onSaveDraft: save,
                    onQueueDraft: queue,
                    onClearMailCache: clear,
                  ),
                ),
              );
              result?.call(draft);
            },
            child: const Text('Open recovery composer'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open recovery composer'));
  await _pump(tester);
}

Future<void> _editAndFail(
  WidgetTester tester, {
  String body = 'Live edits',
}) async {
  await tester.enterText(_field(_strings.to), 'reader@example.test');
  await tester.enterText(_field(_strings.subject), 'Unfinished subject');
  _body(tester).insertText(body);
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pump();
  expect(find.text(_strings.mailDraftSaveFailed), findsOneWidget);
}

void main() {
  testWidgets('cleanup is offered only with a failed save and callback', (
    tester,
  ) async {
    await _open(tester, save: (_) async => throw StateError('disk full'));
    await _editAndFail(tester);
    expect(_clear, findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await _open(tester, clear: () async => _cleared);
    await tester.enterText(_field(_strings.subject), 'No local saver');
    await tester.pump(const Duration(seconds: 1));
    expect(_clear, findsNothing);
  });

  for (final intent in ['send', 'queue', 'close']) {
    testWidgets(
      'cleanup after failed $intent saves in place without finishing',
      (tester) async {
        var released = false;
        var clears = 0;
        var queues = 0;
        var returned = false;
        final attempts = <StudioMailDraft>[];
        await _open(
          tester,
          save: (draft) async {
            attempts.add(draft);
            if (!released) throw StateError('quota');
          },
          clear: () async {
            clears++;
            released = true;
            return _cleared;
          },
          queue: (_) async => queues++,
          result: (_) => returned = true,
        );
        await tester.enterText(_field(_strings.to), 'reader@example.test');
        await tester.enterText(_field(_strings.subject), 'Retain these edits');
        final body = _body(tester)
          ..insertText('Keep the live Word controller.');
        final finish = switch (intent) {
          'send' => find.widgetWithText(FilledButton, _strings.send),
          'queue' => find.byKey(const ValueKey('studio-mail-queue')),
          _ => find.text(_strings.mailDraftSaveClose),
        };
        await _tap(tester, finish);
        expect(attempts, hasLength(1));
        expect(find.text(_strings.mailDraftSaveFailed), findsOneWidget);
        await _tap(tester, _clear);
        expect(clears, 0);
        expect(find.text(_strings.mailCacheDraftClearHelp), findsOneWidget);
        await _tap(tester, _confirm);
        expect(clears, 1);
        expect(attempts, hasLength(2));
        expect(attempts.last.subject, 'Retain these edits');
        expect(attempts.last.body, 'Keep the live Word controller.');
        expect(find.text(_strings.mailDraftSaved), findsOneWidget);
        expect(_body(tester), same(body));
        expect(body.isDisposed, isFalse);
        expect(returned, isFalse);
        expect(queues, 0);
        expect(_clear, findsNothing);
        expect(find.text(_strings.mailCacheCleared(1, 1, 2)), findsOneWidget);
        body.undo();
        expect(body.document.paragraphs.single.text, isEmpty);
        body.redo();
        expect(body.document.paragraphs.single.text, attempts.last.body);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('canceling cleanup preserves live edits without another save', (
    tester,
  ) async {
    var saves = 0;
    var clears = 0;
    await _open(
      tester,
      save: (_) async {
        saves++;
        throw StateError('quota');
      },
      clear: () async {
        clears++;
        return _cleared;
      },
    );
    await _editAndFail(tester);
    final body = _body(tester);
    await _tap(tester, _clear);
    await _tap(tester, find.widgetWithText(TextButton, _strings.cancel));
    await tester.pump(const Duration(seconds: 1));
    expect(clears, 0);
    expect(saves, 1);
    expect(_body(tester), same(body));
    expect(body.document.paragraphs.single.text, 'Live edits');
    expect(find.text(_strings.mailDraftSaveFailed), findsOneWidget);
  });

  for (final synchronous in [false, true]) {
    testWidgets('redacts ${synchronous ? 'sync' : 'async'} cleanup failure', (
      tester,
    ) async {
      var saves = 0;
      await _open(
        tester,
        save: (_) async {
          saves++;
          throw StateError('quota');
        },
        clear: () {
          if (synchronous) throw StateError('private-cleanup-path');
          return Future<MailCacheCleanupReport>.error(
            StateError('private-cleanup-path'),
          );
        },
      );
      await _editAndFail(tester);
      final body = _body(tester);
      await _tap(tester, _clear);
      await _tap(tester, _confirm);
      expect(find.text(_strings.mailCacheDraftClearFailed), findsOneWidget);
      expect(find.textContaining('private-cleanup-path'), findsNothing);
      expect(saves, 1);
      expect(_body(tester), same(body));
      expect(body.document.paragraphs.single.text, 'Live edits');
      expect(tester.widget<TextButton>(_clear).onPressed, isNotNull);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'cleanup waits for pending save and blocks stale finish actions',
    (tester) async {
      final writing = Completer<void>();
      final clearing = Completer<MailCacheCleanupReport>();
      final order = <String>[];
      final attempts = <StudioMailDraft>[];
      var returned = false;
      var queued = 0;
      await _open(
        tester,
        save: (draft) async {
          attempts.add(draft);
          order.add('save${attempts.length}');
          if (attempts.length == 1) throw StateError('quota');
          if (attempts.length == 2) await writing.future;
        },
        clear: () {
          order.add('clear');
          return clearing.future;
        },
        queue: (_) async => queued++,
        result: (_) => returned = true,
      );
      await _editAndFail(tester);
      final finish = tester
          .widget<TextButton>(
            find.widgetWithText(TextButton, _strings.mailDraftSaveClose),
          )
          .onPressed!;
      final send = tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, _strings.send),
          )
          .onPressed!;
      final queue = tester
          .widget<TextButton>(find.byKey(const ValueKey('studio-mail-queue')))
          .onPressed!;
      final abandon = tester
          .widget<TextButton>(
            find.widgetWithText(TextButton, _strings.mailDraftCloseUnsaved),
          )
          .onPressed!;
      final retry = tester
          .widget<TextButton>(
            find.widgetWithText(TextButton, _strings.mailDraftRetrySave),
          )
          .onPressed!;
      final clear = tester.widget<TextButton>(_clear).onPressed!;
      await _tap(tester, find.text(_strings.mailDraftRetrySave));
      expect(attempts, hasLength(2));
      await _tap(tester, _clear);
      await _tap(tester, _confirm);
      expect(order, ['save1', 'save2']);
      final body = _body(tester)..insertText(' and late IME text');
      finish();
      send();
      queue();
      abandon();
      retry();
      clear();
      await tester.binding.handlePopRoute();
      await tester.pump(const Duration(seconds: 1));
      expect(returned, isFalse);
      expect(queued, 0);
      expect(order, ['save1', 'save2']);
      writing.completeError(StateError('quota still full'));
      await _pump(tester);
      expect(order, ['save1', 'save2', 'clear']);
      expect(find.text(_strings.mailCacheClearing), findsOneWidget);
      finish();
      await tester.binding.handlePopRoute();
      await _pump(tester);
      expect(returned, isFalse);
      clearing.complete(_cleared);
      await _pump(tester);
      expect(order, ['save1', 'save2', 'clear', 'save3']);
      expect(attempts.last.body, 'Live edits and late IME text');
      expect(_body(tester), same(body));
      expect(find.text(_strings.mailDraftSaved), findsOneWidget);
      expect(queued, 0);
      expect(returned, isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('successful pending retry makes confirmed cleanup unnecessary', (
    tester,
  ) async {
    final gate = Completer<void>();
    var saves = 0;
    var clears = 0;
    await _open(
      tester,
      save: (_) async {
        saves++;
        if (saves == 1) throw StateError('temporary failure');
        await gate.future;
      },
      clear: () async {
        clears++;
        return _cleared;
      },
    );
    await _editAndFail(tester);
    await _tap(tester, find.text(_strings.mailDraftRetrySave));
    await _tap(tester, _clear);
    await _tap(tester, _confirm);
    gate.complete();
    await _pump(tester);
    expect(clears, 0);
    expect(saves, 2);
    expect(find.text(_strings.mailDraftSaved), findsOneWidget);
  });

  testWidgets('late cleanup completion after disposal does not retry saving', (
    tester,
  ) async {
    final gate = Completer<MailCacheCleanupReport>();
    var saves = 0;
    await _open(
      tester,
      save: (_) async {
        saves++;
        throw StateError('quota');
      },
      clear: () => gate.future,
    );
    await _editAndFail(tester);
    final body = _body(tester);
    await _tap(tester, _clear);
    await _tap(tester, _confirm);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(body.isDisposed, isTrue);
    gate.complete(_cleared);
    await _pump(tester);
    expect(saves, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'disposal while waiting for save prevents cleanup and later writes',
    (tester) async {
      final gate = Completer<void>();
      var saves = 0;
      var clears = 0;
      await _open(
        tester,
        save: (_) async {
          saves++;
          if (saves == 1) throw StateError('quota');
          await gate.future;
        },
        clear: () async {
          clears++;
          return _cleared;
        },
      );
      await _editAndFail(tester);
      await _tap(tester, find.text(_strings.mailDraftRetrySave));
      await _tap(tester, _clear);
      await _tap(tester, _confirm);
      _body(tester).insertText(' late');
      await tester.pumpWidget(const SizedBox.shrink());
      gate.complete();
      await _pump(tester);
      expect(saves, 2);
      expect(clears, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('reports partial cleanup and pinned content without repeating', (
    tester,
  ) async {
    var saves = 0;
    var clears = 0;
    await _open(
      tester,
      save: (_) async {
        saves++;
        throw StateError('still no room');
      },
      clear: () async {
        clears++;
        return _more;
      },
    );
    await _editAndFail(tester);
    await _tap(tester, _clear);
    await _tap(tester, _confirm);
    expect(saves, 2);
    expect(clears, 1);
    expect(find.text(_strings.mailCacheCleared(1, 2, 3)), findsOneWidget);
    expect(find.text(_strings.mailCacheDraftClearMore), findsOneWidget);
    expect(find.text(_strings.mailCacheProtected(4)), findsOneWidget);
    expect(find.text(_strings.mailDraftSaveFailed), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    expect(saves, 2);
    expect(clears, 1);
  });

  for (final language in StudioLanguage.values) {
    testWidgets(
      'narrow ${language.name} recovery preserves confirmation direction',
      (tester) async {
        final strings = StudioStrings(language);
        var clears = 0;
        await _open(
          tester,
          strings: strings,
          size: const Size(420, 700),
          save: (_) async => throw StateError('quota'),
          clear: () async {
            clears++;
            if (clears == 1) throw StateError('private-cache-path');
            return _more;
          },
        );
        await tester.enterText(_field(strings.subject), 'Unsaved');
        _body(tester).insertText('Keep this مرحبًا');
        await tester.pump(const Duration(milliseconds: 500));
        await tester.pump();
        await _tap(tester, _clear);
        expect(
          Directionality.of(tester.element(find.byType(AlertDialog))),
          language == StudioLanguage.ar ? TextDirection.rtl : TextDirection.ltr,
        );
        expect(tester.takeException(), isNull);
        await _tap(tester, _confirm);
        expect(find.text(strings.mailCacheDraftClearFailed), findsOneWidget);
        expect(tester.takeException(), isNull);
        await _tap(tester, _clear);
        await _tap(tester, _confirm);
        expect(find.text(strings.mailCacheDraftClearFailed), findsNothing);
        expect(find.text(strings.mailCacheDraftClearMore), findsOneWidget);
        expect(find.text(strings.mailCacheProtected(4)), findsOneWidget);
        await tester.ensureVisible(find.text(strings.mailDraftSaveClose));
        await tester.pump();
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('native quota recovery saves exact live draft without leaving', (
    tester,
  ) async {
    final identity = StudioMailDraftAccount(
      provider: 'imap',
      endpoint: 'imaps://mail.example.test:993',
      login: 'writer@example.test',
      sender: 'writer@example.test',
    );
    final directory = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('compose-cache-recovery-'),
    ))!;
    final owners = <StudioMailDraftStore>[];
    Future<StudioMailDraftStore> openStore() async {
      final owner = await openStudioMailDraftStore(
        identity,
        appDirectory: directory,
        limits: const MailStoreLimits(maxAccountBytes: 16384),
      );
      owners.add(owner);
      return owner;
    }

    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await awaitOutboxOperation(tester, () async {
        for (final owner in owners) {
          await owner.close();
        }
        await directory.delete(recursive: true);
      }());
    });
    final owner = await awaitOutboxOperation(tester, openStore());
    final mailbox = (owner as StudioMailMailboxStoreOwner).mailboxStore;
    await awaitOutboxOperation(tester, () async {
      final folder = MailMailbox(
        id: MailMailboxId('Inbox', account: identity.account),
        displayName: 'Inbox',
      );
      final header = MailHeaderRecord(
        id: MailMessageId('cached'),
        remote: MailImapIdentity(mailbox: folder.id, uidValidity: 1, uid: 1),
        envelope: MailEnvelope(subject: 'Cached mail'),
      );
      final lease = MailAccountSession(identity.account).begin();
      await mailbox.saveView(folder, [header], hasMore: false, lease: lease);
      await mailbox.cacheMessage(
        header,
        MailMessage(
          raw: MailBytes(Uint8List.fromList(List<int>.filled(8000, 65))),
          envelope: header.envelope,
          body: MailBody(plainText: 'b' * 1000),
          localId: header.id,
          remoteIdentity: header.remote,
        ),
        lease: lease,
      );
      await owner.load();
    }());
    final failures = <MailProblemCode>[];
    var saves = 0;
    var clears = 0;
    var queued = 0;
    var returned = false;
    await _open(
      tester,
      save: (draft) async {
        saves++;
        try {
          await owner.save(draft, submissionUncertain: false);
        } on StudioMailDraftStoreException catch (error) {
          failures.add(error.code);
          rethrow;
        }
      },
      clear: () {
        clears++;
        return mailbox.clearCache();
      },
      queue: (_) async => queued++,
      result: (_) => returned = true,
    );
    await tester.enterText(_field(_strings.to), 'still typing@');
    await tester.enterText(_field(_strings.subject), 'Retain exact work');
    final text = 'x' * 5000;
    final body = _body(tester)..insertText(text);
    await tester.pump(const Duration(milliseconds: 500));
    await _until(
      tester,
      () => find.text(_strings.mailDraftSaveFailed).evaluate().isNotEmpty,
    );
    expect(failures, [MailProblemCode.quotaExceeded]);
    expect(body.document.paragraphs.single.text, text);
    await _tap(tester, _clear);
    await _tap(tester, _confirm);
    await _until(
      tester,
      () => find.text(_strings.mailDraftSaved).evaluate().isNotEmpty,
    );
    expect(clears, 1);
    expect(saves, 2);
    expect(returned, isFalse);
    expect(queued, 0);
    expect(_body(tester), same(body));
    final persisted = await awaitOutboxOperation(tester, owner.load());
    expect(persisted!.draft.body, text);
    expect(persisted.draft.to, 'still typing@');
    expect(persisted.draft.subject, 'Retain exact work');
    expect(persisted.draft.problem, StudioMailDraftProblem.recipient);
    await _tap(tester, find.text(_strings.mailDraftSaveClose));
    expect(returned, isTrue);
    expect(body.isDisposed, isTrue);
    await awaitOutboxOperation(tester, owner.close());
    final reopened = await awaitOutboxOperation(tester, openStore());
    final restored = await awaitOutboxOperation(tester, reopened.load());
    expect(restored!.draft.body, text);
    expect(restored.draft.subject, 'Retain exact work');
    expect(tester.takeException(), isNull);
  });
}

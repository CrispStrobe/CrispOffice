import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';
import 'package:quds_office_studio/studio_mail_compose.dart';
import 'package:quds_office_studio/studio_mail_strings.dart';
import 'package:quds_office_studio/studio_strings.dart';

const _strings = StudioStrings(StudioLanguage.en);

void main() {
  testWidgets(
    'debounced autosave preserves incomplete recipients and Word edits',
    (tester) async {
      final saved = <StudioMailDraft>[];
      await _open(tester, save: (draft) async => saved.add(draft));
      await tester.enterText(_field(_strings.to), 'Alice <unfinished');
      await tester.tap(find.text(_strings.mailCopyRecipients));
      await tester.pump();
      await tester.enterText(_field(_strings.mailCc), 'team@');
      await tester.enterText(_field(_strings.mailBcc), 'private@');
      await tester.enterText(_field(_strings.subject), 'Unfinished subject');
      _body(tester).insertText('Work in progress مرحبا');

      await tester.pump(const Duration(milliseconds: 499));
      expect(saved, isEmpty);
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump();
      expect(saved, hasLength(1));
      expect(saved.single.to, 'Alice <unfinished');
      expect(saved.single.cc, 'team@');
      expect(saved.single.bcc, 'private@');
      expect(saved.single.subject, 'Unfinished subject');
      expect(saved.single.body, 'Work in progress مرحبا');
      expect(saved.single.problem, StudioMailDraftProblem.recipient);
      expect(find.text(_strings.mailDraftSaved), findsOneWidget);
      await _close(tester);
      expect(saved, hasLength(1));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'save and close flushes latest text before allowing the route to pop',
    (tester) async {
      final gate = Completer<void>();
      final saved = <StudioMailDraft>[];
      var returned = false;
      StudioMailDraft? result;
      await _open(
        tester,
        save: (draft) {
          saved.add(draft);
          return gate.future;
        },
        result: (draft) {
          returned = true;
          result = draft;
        },
      );
      await tester.enterText(_field(_strings.to), 'incomplete@');
      _body(tester).insertText('last instant edit');
      await _tap(tester, find.text(_strings.mailDraftSaveClose));
      expect(saved, hasLength(1));
      expect(saved.single.body, 'last instant edit');
      expect(returned, isFalse);
      expect(find.byType(StudioMailComposeDialog), findsOneWidget);
      gate.complete();
      await _routePump(tester);
      expect(returned, isTrue);
      expect(result, isNull);
      expect(find.byType(StudioMailComposeDialog), findsNothing);
      await tester.pump(const Duration(seconds: 1));
      expect(saved, hasLength(1));
      expect(tester.takeException(), isNull);
    },
  );

  for (final synchronous in [false, true]) {
    testWidgets(
      '${synchronous ? 'synchronous' : 'asynchronous'} save failure remains retryable and prevents send',
      (tester) async {
        var fail = true;
        var attempts = 0;
        var returned = false;
        StudioMailDraft? result;
        await _open(
          tester,
          save: (draft) {
            attempts++;
            if (fail) {
              if (synchronous) throw StateError('private-disk-marker');
              return Future<void>.error(StateError('private-disk-marker'));
            }
            return Future<void>.value();
          },
          result: (draft) {
            returned = true;
            result = draft;
          },
        );
        await tester.enterText(_field(_strings.to), 'recipient@example.test');
        _body(tester).insertText('Preserve this work');
        await tester.pump(const Duration(milliseconds: 500));
        await tester.pump();
        expect(attempts, 1);
        expect(find.text(_strings.mailDraftSaveFailed), findsOneWidget);
        expect(find.textContaining('private-disk-marker'), findsNothing);

        await _tap(tester, find.widgetWithText(FilledButton, _strings.send));
        expect(returned, isFalse);
        expect(find.byType(StudioMailComposeDialog), findsOneWidget);
        expect(attempts, 2);
        fail = false;
        await _tap(tester, find.text(_strings.mailDraftRetrySave));
        expect(attempts, 3);
        expect(find.text(_strings.mailDraftSaved), findsOneWidget);
        await _tap(tester, find.widgetWithText(FilledButton, _strings.send));
        await _routePump(tester);
        expect(returned, isTrue);
        expect(result!.body, 'Preserve this work');
        expect(attempts, 3);
        await tester.pump(const Duration(seconds: 1));
        expect(attempts, 3);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'unsaved close needs confirmation and never sends or saves after exit',
    (tester) async {
      var attempts = 0;
      var returned = false;
      StudioMailDraft? result;
      await _open(
        tester,
        save: (_) {
          attempts++;
          return Future<void>.error(StateError('unavailable-draft-store'));
        },
        result: (draft) {
          returned = true;
          result = draft;
        },
      );
      expect(find.text(_strings.mailDraftCloseUnsaved), findsNothing);
      await tester.enterText(_field(_strings.to), 'recipient@example.test');
      final body = _body(tester);
      body.insertText('Unsaved work');

      await _tap(tester, find.text(_strings.mailDraftSaveClose));
      expect(attempts, 1);
      expect(returned, isFalse);
      expect(find.byType(StudioMailComposeDialog), findsOneWidget);
      expect(find.text(_strings.mailDraftSaveFailed), findsOneWidget);

      final abandon = find.widgetWithText(
        TextButton,
        _strings.mailDraftCloseUnsaved,
      );
      await _tap(tester, abandon);
      await _routePump(tester);
      expect(
        find.text(_strings.mailDraftCloseUnsavedExplanation),
        findsOneWidget,
      );
      await _tap(tester, find.widgetWithText(TextButton, _strings.cancel));
      await _routePump(tester);
      expect(returned, isFalse);
      expect(find.byType(StudioMailComposeDialog), findsOneWidget);
      expect(body.document.paragraphs.single.text, 'Unsaved work');
      expect(attempts, 1);

      await _tap(tester, abandon);
      await _routePump(tester);
      // A late editor notification while confirmation is open must not leave
      // a scheduled write that survives the user's explicit unsaved exit.
      body.insertText(' and late edit');
      await tester.pump();
      await _tap(
        tester,
        find.widgetWithText(FilledButton, _strings.mailDraftCloseUnsaved),
      );
      await _routePump(tester);
      expect(returned, isTrue);
      expect(result, isNull);
      expect(body.isDisposed, isTrue);
      expect(find.byType(StudioMailComposeDialog), findsNothing);
      await tester.pump(const Duration(seconds: 1));
      expect(attempts, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('editing during a delayed write saves newest snapshot serially', (
    tester,
  ) async {
    final first = Completer<void>();
    final saved = <StudioMailDraft>[];
    var active = 0;
    var maxActive = 0;
    await _open(
      tester,
      save: (draft) async {
        saved.add(draft);
        active++;
        if (active > maxActive) maxActive = active;
        if (saved.length == 1) await first.future;
        active--;
      },
    );
    await tester.enterText(_field(_strings.to), 'reader@example.test');
    _body(tester).insertText('first');
    await tester.pump(const Duration(milliseconds: 500));
    expect(saved, hasLength(1));
    expect(saved.single.body, 'first');

    await tester.enterText(_field(_strings.subject), 'newest subject');
    _body(tester).insertText(' and newest');
    await tester.pump(const Duration(milliseconds: 500));
    expect(saved, hasLength(1));
    first.complete();
    await tester.pump();
    await tester.pump();
    expect(saved, hasLength(2));
    expect(saved.first.body, 'first');
    expect(saved.last.body, 'first and newest');
    expect(saved.last.subject, 'newest subject');
    expect(maxActive, 1);
    expect(find.text(_strings.mailDraftSaved), findsOneWidget);
    await _close(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Send waits for durable latest revision and cancels late autosave',
    (tester) async {
      final gate = Completer<void>();
      final saved = <StudioMailDraft>[];
      StudioMailDraft? sent;
      await _open(
        tester,
        save: (draft) {
          saved.add(draft);
          return saved.length == 1 ? gate.future : Future<void>.value();
        },
        result: (draft) => sent = draft,
      );
      await tester.enterText(_field(_strings.to), 'recipient@example.test');
      final body = _body(tester);
      body.insertText('Before send');
      await _tap(tester, find.widgetWithText(FilledButton, _strings.send));
      expect(sent, isNull);
      expect(saved, hasLength(1));
      // A delayed editor notification is still tracked while pointer input is
      // blocked. The returned send snapshot must match the final persisted body.
      body.insertText(' and final edit');
      await tester.pump();
      gate.complete();
      await _routePump(tester);
      expect(saved, hasLength(2));
      expect(saved.last.body, 'Before send and final edit');
      expect(sent!.body, saved.last.body);
      expect(body.isDisposed, isTrue);
      await tester.pump(const Duration(seconds: 1));
      expect(saved, hasLength(2));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'late invalid recipient is saved but revalidation prevents Send',
    (tester) async {
      final gate = Completer<void>();
      final saved = <StudioMailDraft>[];
      var returned = false;
      await _open(
        tester,
        save: (draft) {
          saved.add(draft);
          return saved.length == 1 ? gate.future : Future<void>.value();
        },
        result: (_) => returned = true,
      );
      await tester.enterText(_field(_strings.to), 'recipient@example.test');
      _body(tester).insertText('Keep this draft');
      await _tap(tester, find.widgetWithText(FilledButton, _strings.send));
      tester.widget<TextField>(_field(_strings.to)).controller!.text =
          'unfinished@';
      await tester.pump();
      gate.complete();
      await _routePump(tester);
      expect(returned, isFalse);
      expect(saved.last.to, 'unfinished@');
      expect(find.text(_strings.mailInvalidRecipient), findsOneWidget);
      expect(find.byType(StudioMailComposeDialog), findsOneWidget);
      await _close(tester);
      expect(returned, isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'back navigation flushes unfinished work without returning a send',
    (tester) async {
      final gate = Completer<void>();
      final saved = <StudioMailDraft>[];
      var returned = false;
      StudioMailDraft? result;
      await _open(
        tester,
        save: (draft) {
          saved.add(draft);
          return gate.future;
        },
        result: (draft) {
          returned = true;
          result = draft;
        },
      );
      await tester.enterText(_field(_strings.to), 'unfinished');
      _body(tester).insertText('saved by back');
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(returned, isFalse);
      expect(saved.single.to, 'unfinished');
      expect(saved.single.body, 'saved by back');
      gate.complete();
      await _routePump(tester);
      expect(returned, isTrue);
      expect(result, isNull);
      expect(find.byType(StudioMailComposeDialog), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'attachment snapshots survive autosave and later removal independently',
    (tester) async {
      final bytes = Uint8List.fromList([0, 128, 255]);
      final initial = StudioMailDraft(
        to: 'reader@example.test',
        subject: 'Attachment',
        body: '',
        attachments: StudioMailAttachments.from([
          StudioMailAttachment(name: 'saved.pdf', bytes: bytes),
        ]),
      );
      final saved = <StudioMailDraft>[];
      await _open(
        tester,
        initial: initial,
        save: (draft) async => saved.add(draft),
      );
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump();
      expect(saved, hasLength(1));
      bytes.fillRange(0, bytes.length, 42);
      await _tap(
        tester,
        find.byKey(const ValueKey('studio-mail-remove-attachment-0')),
      );
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump();
      expect(saved, hasLength(2));
      expect(saved.first.attachments.items.single.content.bytes, [0, 128, 255]);
      expect(saved.last.attachments.isEmpty, isTrue);
      expect(initial.attachments.items, hasLength(1));
      await _close(tester);
      expect(tester.takeException(), isNull);
    },
  );
}

Finder _field(String label) => find.byWidgetPredicate(
  (widget) => widget is TextField && widget.decoration?.labelText == label,
);

WordEditorController _body(WidgetTester tester) =>
    tester.widget<QudsWordEditor>(find.byType(QudsWordEditor)).controller;

Future<void> _open(
  WidgetTester tester, {
  required Future<void> Function(StudioMailDraft) save,
  ValueChanged<StudioMailDraft?>? result,
  StudioMailDraft? initial,
}) async {
  await tester.binding.setSurfaceSize(const Size(1100, 850));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async {
              final draft = await showDialog<StudioMailDraft>(
                context: context,
                barrierDismissible: false,
                builder: (_) => StudioMailComposeDialog(
                  strings: _strings,
                  from: 'writer@example.test',
                  initialDraft: initial,
                  onSaveDraft: save,
                ),
              );
              result?.call(draft);
            },
            child: const Text('Open autosave composer'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open autosave composer'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
  await tester.pump();
}

Future<void> _tap(WidgetTester tester, Finder target) async {
  await tester.ensureVisible(target);
  await tester.tap(target);
  await tester.pump();
  await tester.pump();
}

Future<void> _routePump(WidgetTester tester) async {
  await tester.pump();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
  await tester.pump();
}

Future<void> _close(WidgetTester tester) async {
  await _tap(tester, find.text(_strings.mailDraftSaveClose));
  await _routePump(tester);
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_office_studio/studio_mail_compose_tools_dialog.dart';
import 'package:quds_office_studio/studio_mail_compose_tools_strings.dart';
import 'package:quds_office_studio/studio_strings.dart';

const _strings = StudioStrings(StudioLanguage.en);

Finder _key(String suffix) => find.byKey(ValueKey('studio-mail-$suffix'));

MailAccountId _account([String name = 'writer']) => MailAccountId(
  name,
  profile: MailProfileId('local-profile', hostId: 'studio'),
);

MailComposeSettings _settings({
  String signature = '',
  List<MailQuickText> quickTexts = const [],
}) => MailComposeSettings(
  account: _account(),
  revision: 4,
  signature: signature,
  quickTexts: quickTexts,
);

final class _Host {
  _Host(this.initial);

  final MailComposeSettings initial;
  final writes = <MailComposeSettings>[];
  bool current = true;
  int closes = 0;
  MailComposeSettings? result;
  Future<MailComposeSettings> Function(MailComposeSettings)? save;

  Future<MailComposeSettings> persist(MailComposeSettings settings) async {
    writes.add(settings);
    final handler = save;
    if (handler != null) return handler(settings);
    return settings.copyWith(revision: settings.revision + 1);
  }
}

Future<void> _press(WidgetTester tester, String suffix) async {
  final finder = _key(suffix);
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
}

Future<void> _enter(
  WidgetTester tester,
  String suffix,
  String text,
) async {
  final finder = _key(suffix);
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.enterText(finder, text);
  await tester.pump();
}

Future<void> _show(
  WidgetTester tester,
  _Host host, {
  StudioStrings strings = _strings,
  Size size = const Size(1000, 850),
  double scale = 1,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            key: const ValueKey('studio-mail-open-tools'),
            onPressed: () async {
              host.result = await showDialog<MailComposeSettings>(
                context: context,
                builder: (_) => Directionality(
                  textDirection: strings.language == StudioLanguage.ar
                      ? TextDirection.rtl
                      : TextDirection.ltr,
                  child: StudioMailComposeToolsDialog(
                    strings: strings,
                    initialSettings: host.initial,
                    onSave: host.persist,
                    isCurrent: () => host.current,
                  ),
                ),
              );
              host.closes++;
            },
            child: const Text('Open tools'),
          ),
        ),
      ),
    ),
  );
  await _press(tester, 'open-tools');
}

Future<void> _add(
  WidgetTester tester, {
  String name = 'Greeting',
  String text = 'Hello from Quick Text.',
}) async {
  await _press(tester, 'quick-text-add');
  await _enter(tester, 'quick-text-name', name);
  await _enter(tester, 'quick-text-body', text);
  await _press(tester, 'quick-text-apply');
}

void main() {
  testWidgets('local signature and Quick Text CRUD save one account revision', (
    tester,
  ) async {
    final host = _Host(
      _settings(
        signature: 'Old signature',
        quickTexts: const [
          MailQuickText(id: 'keep', name: 'Old text', text: 'Old body'),
          MailQuickText(id: 'remove', name: 'Remove me', text: 'Remove body'),
        ],
      ),
    );
    await _show(tester, host);
    await _enter(tester, 'compose-signature', 'Regards, Writer');
    await _press(tester, 'compose-signature-new');
    await _press(tester, 'compose-signature-replies');
    await _press(tester, 'quick-text-edit-keep');
    await _enter(tester, 'quick-text-name', '  Updated text  ');
    await _enter(tester, 'quick-text-body', 'Updated body');
    await _press(tester, 'quick-text-apply');
    await _press(tester, 'quick-text-remove-remove');
    await _add(tester);

    expect(host.writes, isEmpty);
    expect(host.initial.signature, 'Old signature');
    expect(host.initial.quickTexts, hasLength(2));
    expect(host.initial.quickTexts.first.name, 'Old text');

    await _press(tester, 'compose-tools-save');
    expect(host.writes, hasLength(1));
    final submitted = host.writes.single;
    expect(submitted.account, host.initial.account);
    expect(submitted.revision, host.initial.revision);
    expect(submitted.signature, 'Regards, Writer');
    expect(submitted.signatureForNewMessages, isTrue);
    expect(submitted.signatureForReplies, isTrue);
    expect(submitted.quickTexts, hasLength(2));
    expect(submitted.quickTexts.first.id, 'keep');
    expect(submitted.quickTexts.first.name, 'Updated text');
    expect(submitted.quickTexts.first.text, 'Updated body');
    expect(submitted.quickTexts.last.id, hasLength(32));
    expect(submitted.quickTexts.last.name, 'Greeting');
    expect(submitted.quickTexts.last.text, 'Hello from Quick Text.');
    expect(host.result!.revision, host.initial.revision + 1);
    expect(host.result!.isValid, isTrue);
    expect(host.closes, 1);
    expect(find.byType(StudioMailComposeToolsDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('closing discards local edits without calling the store', (
    tester,
  ) async {
    final host = _Host(_settings(signature: 'Original'));
    await _show(tester, host);
    await _enter(tester, 'compose-signature', 'Not saved');
    await _add(tester);
    await _press(tester, 'compose-tools-close');
    expect(host.writes, isEmpty);
    expect(host.initial.signature, 'Original');
    expect(host.initial.quickTexts, isEmpty);
    expect(host.closes, 1);
    expect(host.result, isNull);
  });

  testWidgets('Quick Text validates names and blocks saving unfinished edits', (
    tester,
  ) async {
    final host = _Host(
      _settings(
        quickTexts: const [
          MailQuickText(id: 'hello', name: 'Greeting', text: 'Hello'),
        ],
      ),
    );
    await _show(tester, host);
    await _press(tester, 'quick-text-add');
    expect(
      tester.widget<FilledButton>(_key('compose-tools-save')).onPressed,
      isNull,
    );
    await _press(tester, 'quick-text-apply');
    expect(find.text(_strings.mailComposeQuickTextInvalid), findsOneWidget);
    await _enter(tester, 'quick-text-name', '  GREETING  ');
    await _enter(tester, 'quick-text-body', 'Another greeting');
    await _press(tester, 'quick-text-apply');
    expect(find.text(_strings.mailComposeQuickTextDuplicate), findsOneWidget);
    expect(host.writes, isEmpty);
    await _press(tester, 'quick-text-cancel');
    await _press(tester, 'compose-tools-save');
    expect(host.result!.quickTexts, hasLength(1));
    expect(host.result!.quickTexts.single.text, 'Hello');
  });

  testWidgets('oversized UTF-16 edits preserve prior signature and name', (
    tester,
  ) async {
    final host = _Host(_settings(signature: 'Original'));
    await _show(tester, host);
    await _enter(
      tester,
      'compose-signature',
      List.filled(8193, '😀').join(),
    );
    expect(
      tester.widget<TextField>(_key('compose-signature')).controller!.text,
      'Original',
    );
    await _press(tester, 'quick-text-add');
    await _enter(tester, 'quick-text-name', 'Kept name');
    await _enter(tester, 'quick-text-name', List.filled(41, '😀').join());
    expect(
      tester.widget<TextField>(_key('quick-text-name')).controller!.text,
      'Kept name',
    );
    await _enter(tester, 'quick-text-body', 'Kept body');
    await _press(tester, 'quick-text-apply');
    await _press(tester, 'compose-tools-save');
    expect(host.result!.signature, 'Original');
    expect(host.result!.quickTexts.single.name, 'Kept name');
    expect(tester.takeException(), isNull);
  });

  testWidgets('the entry cap allows removal before adding another snippet', (
    tester,
  ) async {
    final host = _Host(
      _settings(
        quickTexts: [
          for (var i = 0; i < MailComposeSettings.maxQuickTexts; i++)
            MailQuickText(id: 'text-$i', name: 'Text $i', text: 'Body $i'),
        ],
      ),
    );
    await _show(tester, host);
    expect(
      tester.widget<TextButton>(_key('quick-text-add')).onPressed,
      isNull,
    );
    await _press(tester, 'quick-text-remove-text-0');
    expect(
      tester.widget<TextButton>(_key('quick-text-add')).onPressed,
      isNotNull,
    );
    expect(host.initial.quickTexts, hasLength(32));
    expect(host.writes, isEmpty);
  });

  testWidgets('combined text limits are checked before adding a snippet', (
    tester,
  ) async {
    final body = List.filled(16000, 'x').join();
    final host = _Host(
      _settings(
        signature: body,
        quickTexts: [
          for (var i = 0; i < 7; i++)
            MailQuickText(id: 'text-$i', name: 'Text $i', text: body),
        ],
      ),
    );
    expect(host.initial.isValid, isTrue);
    await _show(tester, host);
    await _add(tester, text: List.filled(4000, 'y').join());
    expect(find.text(_strings.mailComposeToolsInvalid), findsOneWidget);
    expect(_key('quick-text-body'), findsOneWidget);
    expect(host.writes, isEmpty);
  });

  testWidgets('a pending save freezes edits and blocks close and system back', (
    tester,
  ) async {
    final host = _Host(_settings(signature: 'Signature'));
    final gate = Completer<MailComposeSettings>();
    host.save = (_) => gate.future;
    await _show(tester, host);
    await _press(tester, 'compose-tools-save');
    expect(host.writes, hasLength(1));
    expect(
      tester.widget<TextField>(_key('compose-signature')).readOnly,
      isTrue,
    );
    expect(
      tester.widget<SwitchListTile>(_key('compose-signature-new')).onChanged,
      isNull,
    );
    expect(
      tester.widget<TextButton>(_key('compose-tools-close')).onPressed,
      isNull,
    );
    expect(
      tester.widget<FilledButton>(_key('compose-tools-save')).onPressed,
      isNull,
    );
    await tester.binding.handlePopRoute();
    await tester.pump();
    await tester.tapAt(const Offset(1, 1));
    await tester.pump();
    expect(find.byType(StudioMailComposeToolsDialog), findsOneWidget);
    expect(host.closes, 0);
    gate.complete(host.writes.single.copyWith(revision: 5));
    await tester.pumpAndSettle();
    expect(host.closes, 1);
    expect(host.result!.signature, 'Signature');
    expect(tester.takeException(), isNull);
  });

  testWidgets('an unconfirmed save retains edits and requires reload', (
    tester,
  ) async {
    final host = _Host(_settings(signature: 'Original'));
    host.save = (_) async => throw StateError('Acknowledgement lost');
    await _show(tester, host);
    await _enter(tester, 'compose-signature', 'Keep these edits');
    await _add(tester, text: 'Keep this whole snippet');
    await _press(tester, 'compose-tools-save');
    expect(find.text(_strings.mailComposeToolsSaveUnconfirmed), findsOneWidget);
    expect(
      tester.widget<TextField>(_key('compose-signature')).controller!.text,
      'Keep these edits',
    );
    expect(find.text('Keep this whole snippet'), findsOneWidget);
    expect(
      tester.widget<FilledButton>(_key('compose-tools-save')).onPressed,
      isNull,
    );
    expect(host.writes, hasLength(1));
    expect(host.writes.single.quickTexts.single.text, 'Keep this whole snippet');
    expect(host.result, isNull);
    expect(host.closes, 0);
    await _press(tester, 'compose-tools-close');
    expect(host.closes, 1);
    expect(host.writes, hasLength(1));
    expect(tester.takeException(), isNull);
  });

  for (final wrongAccount in [false, true]) {
    testWidgets(
      'an invalid save acknowledgement is not returned: wrongAccount=$wrongAccount',
      (tester) async {
        final host = _Host(_settings(signature: 'Signature'));
        host.save = (settings) async => wrongAccount
            ? MailComposeSettings(
                account: _account('other'),
                revision: settings.revision + 1,
                signature: settings.signature,
              )
            : settings;
        await _show(tester, host);
        await _press(tester, 'compose-tools-save');
        expect(
          find.text(_strings.mailComposeToolsSaveUnconfirmed),
          findsOneWidget,
        );
        expect(host.result, isNull);
        expect(host.closes, 0);
        expect(
          tester.widget<FilledButton>(_key('compose-tools-save')).onPressed,
          isNull,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('a stale account cannot save even without a prior rebuild', (
    tester,
  ) async {
    final host = _Host(_settings(signature: 'Signature'));
    await _show(tester, host);
    host.current = false;
    await _press(tester, 'compose-tools-save');
    expect(host.writes, isEmpty);
    expect(find.text(_strings.mailComposeToolsStale), findsOneWidget);
    await _press(tester, 'compose-tools-close');
    expect(host.closes, 1);
    expect(host.result, isNull);
  });

  testWidgets('account changes while saving fence the returned settings', (
    tester,
  ) async {
    final host = _Host(_settings(signature: 'Signature'));
    final gate = Completer<MailComposeSettings>();
    host.save = (_) => gate.future;
    await _show(tester, host);
    await _press(tester, 'compose-tools-save');
    host.current = false;
    gate.complete(host.writes.single.copyWith(revision: 5));
    await tester.pumpAndSettle();
    expect(find.text(_strings.mailComposeToolsStale), findsOneWidget);
    expect(host.closes, 0);
    expect(host.result, isNull);
    expect(
      tester.widget<FilledButton>(_key('compose-tools-save')).onPressed,
      isNull,
    );
    await _press(tester, 'compose-tools-close');
    expect(host.closes, 1);
    expect(host.result, isNull);
  });

  for (final language in StudioLanguage.values) {
    testWidgets(
      'compact enlarged ${language.name} tools retain keyboard access',
      (tester) async {
        final host = _Host(_settings());
        final strings = StudioStrings(language);
        await _show(
          tester,
          host,
          strings: strings,
          size: const Size(440, 850),
          scale: 1.5,
        );
        expect(find.text(strings.mailComposeTools), findsOneWidget);
        expect(find.text(strings.mailComposeSignatureForReplies), findsOneWidget);
        await _press(tester, 'quick-text-add');
        expect(
          tester.widget<TextField>(_key('quick-text-name')).focusNode!.hasFocus,
          isTrue,
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        expect(
          tester.widget<TextField>(_key('quick-text-body')).focusNode!.hasFocus,
          isTrue,
        );
        await _enter(
          tester,
          'quick-text-name',
          language == StudioLanguage.ar ? 'تحية' : 'Greeting',
        );
        await _enter(tester, 'quick-text-body', 'Reusable body');
        await _press(tester, 'quick-text-apply');
        await _press(tester, 'compose-tools-save');
        expect(host.result!.quickTexts.single.text, 'Reusable body');
        expect(host.closes, 1);
        expect(tester.takeException(), isNull);
      },
    );
  }
}

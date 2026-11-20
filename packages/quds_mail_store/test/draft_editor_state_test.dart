import 'dart:convert';

import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_store/src/codec.dart';
import 'package:test/test.dart';

void main() {
  test('old draft payloads still decode without synthetic editor state', () {
    final payload = MailStoreCodec.encodeDraft(_draft());
    expect(_object(payload.data)['version'], 1);
    final restored = _decode(payload.data);
    expect(restored.editorState, isNull);
    expect(restored.envelope.to.single.address, 'recipient@example.test');
    expect(restored.body.plainText, 'body');
  });

  test(
    'typed editor payload preserves arbitrary unfinished recipient input',
    () {
      final editor = MailDraftEditorState(
        to: 'Alice <unfinished',
        cc: 'name;\nsecond@',
        bcc: 'مرحبا\u0000',
        submissionUncertain: true,
      );
      final payload = MailStoreCodec.encodeDraft(_draft(editor));
      expect(_object(payload.data)['version'], 2);
      final restored = _decode(payload.data);
      expect(restored.editorState!.to, editor.to);
      expect(restored.editorState!.cc, editor.cc);
      expect(restored.editorState!.bcc, editor.bcc);
      expect(restored.editorState!.submissionUncertain, isTrue);
      expect(restored.editorState!.isCleared, isFalse);
      expect(MailStoreCodec.decodeDraftBody(payload.data).plainText, 'body');
      expect(MailStoreCodec.encodeDraft(restored).data, payload.data);
    },
  );

  test('editor fields are validated even for a body-only projection', () {
    final payload = MailStoreCodec.encodeDraft(_draft(MailDraftEditorState()));
    for (final mutate in <void Function(Map<String, Object?>)>[
      (state) => state['submissionUncertain'] = 'false',
      (state) => state['to'] = ['hidden@example.test'],
      (state) => state.remove('isCleared'),
      (state) => state['untrustedExtra'] = 'private-marker',
      (state) {
        state['isCleared'] = true;
        state['submissionUncertain'] = true;
      },
    ]) {
      final value = _object(payload.data);
      final editor = value['editorState']! as Map<String, Object?>;
      mutate(editor);
      final corrupt = jsonEncode(value);
      expect(() => _decode(corrupt), throwsFormatException);
      expect(
        () => MailStoreCodec.decodeDraftBody(corrupt),
        throwsFormatException,
      );
    }
  });

  test('unknown draft version and cross-version field mixing fail closed', () {
    final old = _object(MailStoreCodec.encodeDraft(_draft()).data);
    old['version'] = 2;
    expect(() => _decode(jsonEncode(old)), throwsFormatException);
    final current = _object(
      MailStoreCodec.encodeDraft(_draft(MailDraftEditorState())).data,
    );
    current['version'] = 1;
    expect(() => _decode(jsonEncode(current)), throwsFormatException);
    current['version'] = 3;
    expect(() => _decode(jsonEncode(current)), throwsFormatException);
  });

  test(
    'cleared input cannot conceal raw recipients or uncertain submission',
    () {
      expect(
        () => MailDraftEditorState(to: 'private-marker', isCleared: true),
        throwsArgumentError,
      );
      expect(
        () => MailDraftEditorState(submissionUncertain: true, isCleared: true),
        throwsArgumentError,
      );
    },
  );
}

final _account = MailAccountId(
  'account',
  profile: MailProfileId('profile', hostId: 'host'),
);

MailDraft _draft([MailDraftEditorState? editor]) => MailDraft(
  id: 'draft',
  account: _account,
  revision: 1,
  envelope: MailEnvelope(to: [const MailAddress('recipient@example.test')]),
  body: const MailBody(plainText: 'body'),
  editorState: editor,
);

MailDraft _decode(String data) => MailStoreCodec.decodeDraft(
  data,
  account: _account,
  id: 'draft',
  revision: 1,
  blobs: const {},
);

Map<String, Object?> _object(String data) {
  final Object? value = jsonDecode(data);
  return value! as Map<String, Object?>;
}

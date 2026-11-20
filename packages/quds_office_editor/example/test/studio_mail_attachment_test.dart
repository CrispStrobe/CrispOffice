import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_mime/quds_mail_mime.dart';
import 'package:quds_office_studio/studio_mail_draft.dart';
import 'package:quds_office_studio/studio_mail_submission.dart';
import 'package:quds_office_studio/studio_mail_threading.dart';

const _sender = 'writer@example.invalid';

Matcher _problem(StudioMailAttachmentProblem problem) => throwsA(
  isA<StudioMailAttachmentException>().having(
    (error) => error.problem,
    'problem',
    problem,
  ),
);

StudioMailAttachment _attachment(String name, [List<int> bytes = const [1]]) =>
    StudioMailAttachment(name: name, bytes: Uint8List.fromList(bytes));

StudioMailDraft _draft(
  Iterable<StudioMailAttachment> attachments, {
  String body = 'Hello مرحبًا <reader> & "quoted" = ✓',
  StudioMailThread thread = const StudioMailThread.empty(),
}) => StudioMailDraft(
  to: 'reader@example.invalid',
  cc: 'copy@example.invalid',
  bcc: 'hidden@example.invalid',
  subject: 'Anlage مرفق',
  body: body,
  thread: thread,
  attachments: StudioMailAttachments.from(attachments),
);

void main() {
  test('ordinary const drafts retain an immutable empty attachment bundle', () {
    const draft = StudioMailDraft(to: _sender, subject: '', body: '');
    expect(draft.attachments.isEmpty, isTrue);
    expect(draft.attachments.isNotEmpty, isFalse);
    expect(draft.attachments.totalBytes, 0);
    expect(draft.attachments.items, isEmpty);
    expect(
      () => draft.attachments.items.add(_attachment('new.txt')),
      throwsUnsupportedError,
    );
  });

  test('attachments own input bytes and expose no writable view', () {
    final source = Uint8List.fromList([0, 1, 127, 128, 255]);
    final attachment = StudioMailAttachment(name: 'bytes.bin', bytes: source);
    source.fillRange(0, source.length, 42);
    expect(attachment.content.bytes, [0, 1, 127, 128, 255]);
    expect(attachment.length, 5);
    expect(() => attachment.content.bytes[0] = 42, throwsUnsupportedError);
    expect(
      () => attachment.content.bytes.buffer.asUint8List()[0] = 42,
      throwsUnsupportedError,
    );
    final exported = attachment.content.copyBytes();
    exported[0] = 42;
    expect(attachment.content.bytes[0], 0);
  });

  test(
    'selection owns its list and preserves order and duplicate filenames',
    () {
      final first = _attachment('same.docx', [1, 2]);
      final second = _attachment('same.docx', [3]);
      final input = [first, second];
      final attachments = StudioMailAttachments.from(input);
      input.clear();
      expect(attachments.items, [same(first), same(second)]);
      expect(attachments.totalBytes, 3);
      expect(attachments.isNotEmpty, isTrue);
      expect(() => attachments.items.clear(), throwsUnsupportedError);
      expect(() => attachments.items[0] = second, throwsUnsupportedError);
    },
  );

  test('allows zero-byte files and exactly ten attachments', () {
    final empty = _attachment('empty.bin', []);
    final attachments = StudioMailAttachments.from(List.filled(10, empty));
    expect(attachments.items, hasLength(10));
    expect(attachments.totalBytes, 0);
    expect(
      () => StudioMailAttachments.from(List.filled(11, empty)),
      _problem(StudioMailAttachmentProblem.tooMany),
    );
  });

  test(
    'bounds iterator consumption before retaining an eleventh attachment',
    () {
      var consumed = 0;
      final attachment = _attachment('bounded.bin');
      Iterable<StudioMailAttachment> source() sync* {
        while (true) {
          consumed++;
          yield attachment;
        }
      }

      expect(
        () => StudioMailAttachments.from(source()),
        _problem(StudioMailAttachmentProblem.tooMany),
      );
      expect(consumed, 11);
    },
  );

  test('enforces ten MiB cumulatively and on individual snapshots', () {
    final maximum = StudioMailAttachment(
      name: 'maximum.bin',
      bytes: Uint8List(StudioMailAttachments.maxTotalBytes),
    );
    final accepted = StudioMailAttachments.from([maximum]);
    expect(accepted.totalBytes, StudioMailAttachments.maxTotalBytes);
    expect(
      () => StudioMailAttachments.from([maximum, _attachment('extra.bin')]),
      _problem(StudioMailAttachmentProblem.tooLarge),
    );
    expect(accepted.items.single, same(maximum));
    expect(
      () => StudioMailAttachment(
        name: 'oversized.bin',
        bytes: Uint8List(StudioMailAttachments.maxTotalBytes + 1),
      ),
      _problem(StudioMailAttachmentProblem.tooLarge),
    );
  });

  for (final name in <String>[
    '',
    ' ',
    '.',
    '..',
    '../private.txt',
    r'C:\private.txt',
    '/private.txt',
    'private.txt\r\nBcc: secret@example.invalid',
    'null\u0000.txt',
    'tab\t.txt',
    'delete\u007f.txt',
    'next\u0085line.txt',
    'separator\u2028.txt',
    'paragraph\u2029.txt',
    'hidden\u202eexe.txt',
    'isolate\u2066.txt',
    'mark\u200f.txt',
    ' leading.txt',
    'trailing.txt ',
    'broken\ud800.txt',
    'a' * 256,
    'é' * 128,
  ]) {
    test('rejects unsafe filename ${jsonEncode(name)} before snapshotting', () {
      expect(StudioMailAttachment.isSupportedName(name), isFalse);
      expect(
        () => StudioMailAttachment.validateName(name),
        _problem(StudioMailAttachmentProblem.invalidName),
      );
      expect(
        () => _attachment(name),
        _problem(StudioMailAttachmentProblem.invalidName),
      );
    });
  }

  test('filename bound counts UTF-8 bytes and preserves supported Unicode', () {
    final boundary = '${'é' * 125}.txt';
    expect(utf8.encode(boundary), hasLength(254));
    expect(_attachment(boundary).name, boundary);
    expect(_attachment('a' * 255).name, hasLength(255));
    for (final name in [
      '研究😀.pdf',
      'سجل "alpha"; 100%.pdf',
      "John's notes.txt",
    ]) {
      expect(_attachment(name).name, name);
    }
  });

  test('fixed Office and generic type hints never inspect or rewrite bytes', () {
    final expected = <String, String>{
      'Report.DOCX':
          'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      'Budget.xlsx':
          'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      'Deck.pptx':
          'application/vnd.openxmlformats-officedocument.presentationml.presentation',
      'Macro.xlsm': 'application/vnd.ms-excel.sheet.macroenabled.12',
      'Document.pdf': 'application/pdf',
      'Data.csv': 'text/csv',
      'Image.png': 'image/png',
      'Archive.zip': 'application/zip',
      'Original.eml': 'application/octet-stream',
      'unknown.custom': 'application/octet-stream',
      '.pdf': 'application/octet-stream',
    };
    for (final entry in expected.entries) {
      final attachment = _attachment(entry.key, [255, 0, 128]);
      expect(attachment.mediaType, entry.value);
      expect(attachment.content.bytes, [255, 0, 128]);
    }
    expect(
      StudioMailAttachment(
        name: 'data.custom',
        bytes: Uint8List(0),
        mediaType: 'APPLICATION/PDF',
      ).mediaType,
      'application/pdf',
    );
  });

  for (final type in <String>[
    '',
    'text',
    'text/plain; charset=utf-8',
    'text/plain\r\nX-Injected: yes',
    'text/plain\n',
    ' text/plain',
    'text/plain ',
    'application/a b',
    'image/صورة',
    'multipart/mixed',
    'message/rfc822',
    'application/${'a' * 120}',
  ]) {
    test('rejects unsafe or container media type ${jsonEncode(type)}', () {
      expect(
        () => StudioMailAttachment(
          name: 'valid.bin',
          bytes: Uint8List(0),
          mediaType: type,
        ),
        _problem(StudioMailAttachmentProblem.invalidMediaType),
      );
    });
  }

  test('typed failures never expose a filename or header fragment', () {
    try {
      _attachment('private\r\nX-Secret: value');
      fail('Expected filename refusal');
    } on StudioMailAttachmentException catch (error) {
      expect(error.toString(), 'StudioMailAttachmentException(invalidName)');
      expect(error.toString(), isNot(contains('private')));
      expect(error.toString(), isNot(contains('Secret')));
    }
  });

  test(
    'mixed MIME retains alternative body and exact binary attachment bytes',
    () {
      final binary = List<int>.generate(4097, (index) => index % 256);
      final draft = _draft([
        _attachment('Budget.xlsx', binary),
        _attachment('Empty.bin', []),
        _attachment('Legacy.txt', [0xff, 0x80, 0, 0x0a]),
      ]);
      final mime = buildStudioMailMessage(draft, _sender);
      final wire = mime.renderMessage();
      expect(wire.codeUnits.every((unit) => unit < 128), isTrue);
      expect(mime.mediaType.text, 'multipart/mixed');
      expect(mime.parts, hasLength(4));
      expect(mime.parts!.first.mediaType.text, 'multipart/alternative');
      expect(mime.parts!.first.parts, hasLength(2));
      for (final part in mime.parts!.skip(1)) {
        expect(part.getHeaderValue('content-transfer-encoding'), 'base64');
        expect(
          part.getHeaderContentDisposition()!.dispositionText,
          'attachment',
        );
        expect(part.getHeaderContentType()!.charset, isNull);
      }
      final parsed = const QudsMimeCodec().parse(ascii.encode(wire));
      expect(
        parsed.status,
        MailParseStatus.complete,
        reason: '${parsed.diagnostics}',
      );
      expect(parsed.message!.body.plainText, draft.body);
      expect(
        parsed.message!.body.html,
        contains('&lt;reader&gt; &amp; &quot;quoted&quot;'),
      );
      expect(parsed.message!.attachments, hasLength(3));
      for (var index = 0; index < draft.attachments.items.length; index++) {
        final source = draft.attachments.items[index];
        final decoded = parsed.message!.attachments[index];
        expect(decoded.displayName, source.name);
        expect(decoded.content.bytes, source.content.bytes);
        expect(decoded.content.sha256, source.content.sha256);
        expect(decoded.declaredSize, source.length);
        expect(decoded.mediaType, source.mediaType);
        expect(decoded.inline, isFalse);
      }
      expect(parsed.message!.envelope.bcc, isEmpty);
      expect(wire, isNot(contains('hidden@example.invalid')));
      expect(draft.recipients.envelope, [
        'reader@example.invalid',
        'copy@example.invalid',
        'hidden@example.invalid',
      ]);
    },
  );

  test('Unicode and quoted filenames use ASCII-safe RFC 2231 parameters', () {
    const name = 'سجل "alpha"; 100%😀.pdf';
    final mime = buildStudioMailMessage(_draft([_attachment(name)]), _sender);
    final wire = mime.renderMessage();
    expect(wire.codeUnits.every((unit) => unit < 128), isTrue);
    expect(wire, contains("filename*=utf-8''"));
    expect(wire, contains("name*=utf-8''"));
    expect(wire, isNot(contains(name)));
    expect(mime.parts!.last.decodeFileName(), name);
    final parsed = const QudsMimeCodec().parse(ascii.encode(wire));
    expect(parsed.status, MailParseStatus.complete);
    expect(parsed.message!.attachments.single.displayName, name);
    expect(parsed.message!.attachments.single.content.bytes, [1]);
  });

  test('255-byte filename produces bounded MIME header lines', () {
    final mime = buildStudioMailMessage(
      _draft([_attachment('${'é' * 125}a.pdf')]),
      _sender,
    );
    final wire = mime.renderMessage();
    expect(wire.split('\r\n').every((line) => line.length <= 998), isTrue);
    expect(mime.parts!.last.decodeFileName(), '${'é' * 125}a.pdf');
  });

  test('attachments preserve reply threading and never add Bcc to headers', () {
    final thread = StudioMailThread.replyTo(
      MailEnvelope(
        messageId: '<parent@example.invalid>',
        references: const ['<root@example.invalid>'],
      ),
    );
    final draft = _draft([_attachment('reply.docx')], thread: thread);
    final mime = buildStudioMailMessage(draft, _sender);
    expect(mime.getHeaderValue('in-reply-to'), '<parent@example.invalid>');
    expect(
      mime.getHeaderValue('references'),
      '<root@example.invalid> <parent@example.invalid>',
    );
    expect(mime.getHeaderValue('bcc'), isNull);
    expect(mime.cc!.single.email, 'copy@example.invalid');
    expect(mime.to!.single.email, 'reader@example.invalid');
  });

  test(
    'editing another draft field can share immutable attachment snapshots',
    () {
      final first = _draft([
        _attachment('unchanged.docx', [1, 2, 3]),
      ]);
      final edited = StudioMailDraft(
        to: first.to,
        subject: 'Edited subject',
        body: 'Edited body',
        attachments: first.attachments,
      );
      expect(edited.attachments, same(first.attachments));
      final wire = buildStudioMailMessage(edited, _sender).renderMessage();
      final parsed = const QudsMimeCodec().parse(ascii.encode(wire));
      expect(parsed.message!.attachments.single.content.bytes, [1, 2, 3]);
      expect(first.subject, 'Anlage مرفق');
    },
  );

  test('plain drafts keep alternative MIME and wrap long ASCII body lines', () {
    final body = 'x' * 4096;
    final mime = buildStudioMailMessage(_draft([], body: body), _sender);
    expect(mime.mediaType.text, 'multipart/alternative');
    expect(mime.parts, hasLength(2));
    for (final part in mime.parts!) {
      expect(
        part.getHeaderValue('content-transfer-encoding'),
        'quoted-printable',
      );
    }
    final wire = mime.renderMessage();
    expect(wire.split('\r\n').every((line) => line.length <= 998), isTrue);
    final parsed = const QudsMimeCodec().parse(ascii.encode(wire));
    expect(parsed.status, MailParseStatus.complete);
    expect(parsed.message!.body.plainText, body);
    expect(parsed.message!.attachments, isEmpty);
  });
}

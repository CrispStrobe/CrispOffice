import 'package:enough_mail/enough_mail.dart' as mail;
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_studio/studio_mail_draft.dart';
import 'package:quds_office_studio/studio_mail_recipients.dart';
import 'package:quds_office_studio/studio_mail_submission.dart';

void main() {
  test('parses all recipient groups with commas, semicolons and spaces', () {
    final recipients = StudioMailRecipients.tryParse(
      to: ' one@example.test, two@example.test ; three@example.test ',
      cc: ' copy@example.test ',
      bcc: 'hidden@example.test; hidden-two@example.test',
    )!;
    expect(recipients.to, [
      'one@example.test',
      'two@example.test',
      'three@example.test',
    ]);
    expect(recipients.cc, ['copy@example.test']);
    expect(recipients.bcc, ['hidden@example.test', 'hidden-two@example.test']);
    expect(recipients.envelope, [
      ...recipients.to,
      ...recipients.cc,
      ...recipients.bcc,
    ]);
  });

  test(
    'deduplicates across groups with visible precedence and exact locals',
    () {
      final recipients = StudioMailRecipients.tryParse(
        to: 'Reader@EXAMPLE.test, Reader@example.test',
        cc: 'Reader@example.TEST; reader@example.test; Copy@example.test',
        bcc: 'Copy@EXAMPLE.test; Hidden@example.test; Reader@example.test',
      )!;
      expect(recipients.to, ['Reader@EXAMPLE.test']);
      expect(recipients.cc, ['reader@example.test', 'Copy@example.test']);
      expect(recipients.bcc, ['Hidden@example.test']);
      expect(recipients.envelope, hasLength(4));
    },
  );

  test('Cc-only and Bcc-only drafts need no fabricated visible recipient', () {
    for (final hidden in [false, true]) {
      final draft = StudioMailDraft(
        to: '',
        cc: hidden ? '' : 'copy@example.test',
        bcc: hidden ? 'hidden@example.test' : '',
        subject: 'Only one group',
        body: 'Body',
      );
      expect(draft.problem, isNull);
      final mime = buildStudioMailMessage(draft, 'sender@example.test');
      expect(mime.to, isEmpty);
      expect(mime.getHeaderValue('bcc'), isNull);
      expect(mime.bcc, isEmpty);
      expect(mime.renderMessage(), isNot(contains('hidden@example.test')));
      expect(draft.recipients.envelope, [
        hidden ? 'hidden@example.test' : 'copy@example.test',
      ]);
    }
  });

  test('all exposed recipient groups are immutable snapshots', () {
    final recipients = StudioMailRecipients.tryParse(
      to: 'one@example.test',
      cc: 'copy@example.test',
      bcc: 'hidden@example.test',
    )!;
    for (final group in [
      recipients.to,
      recipients.cc,
      recipients.bcc,
      recipients.envelope,
    ]) {
      expect(() => group.clear(), throwsUnsupportedError);
      expect(() => group.add('another@example.test'), throwsUnsupportedError);
    }
  });

  test('admits exactly 100 entries across groups and rejects a 101st', () {
    final to = [
      for (var index = 0; index < 98; index++) 'r$index@example.test',
    ];
    final accepted = StudioMailRecipients.tryParse(
      to: to.join(', '),
      cc: 'copy@example.test',
      bcc: 'hidden@example.test',
    );
    expect(accepted?.envelope, hasLength(100));
    expect(
      StudioMailRecipients.tryParse(
        to: to.join(', '),
        cc: 'copy@example.test',
        bcc: 'hidden@example.test; extra@example.test',
      ),
      isNull,
    );
  });

  test('duplicate entries still count toward the manual input bound', () {
    expect(
      StudioMailRecipients.tryParse(
        to: List.filled(100, 'one@example.test').join(','),
      )?.envelope,
      ['one@example.test'],
    );
    expect(
      StudioMailRecipients.tryParse(
        to: List.filled(101, 'one@example.test').join(','),
      ),
      isNull,
    );
  });

  test('input character bound includes all groups before splitting', () {
    const address = 'one@example.test';
    final padded =
        '${' ' * (StudioMailRecipients.maxInputLength - address.length)}$address';
    expect(StudioMailRecipients.tryParse(to: padded)?.to, [address]);
    expect(StudioMailRecipients.tryParse(to: padded, cc: ' '), isNull);
  });

  test('empty optional groups are allowed but an empty envelope is not', () {
    expect(StudioMailRecipients.tryParse(to: ' ', cc: '', bcc: ' '), isNull);
    expect(
      StudioMailRecipients.tryParse(to: 'one@example.test', cc: ' ', bcc: ''),
      isNotNull,
    );
  });

  for (final invalid in <String>[
    ',',
    'one@example.test,',
    ',one@example.test',
    'one@example.test;;two@example.test',
    'Name <one@example.test>',
    'Team:one@example.test;',
    'one@example.test (comment)',
    '"quoted"@example.test',
    'one@example.test two@example.test',
    'one@example.test\t',
    'one@example.test\n',
    'one@example.test\r\nBcc: hidden@example.test',
    'one@example.test\u0000',
    'one@example.test\u007f',
    'one@example.test\u00a0',
    'مستخدم@example.test',
    'one@[127.0.0.1]',
    'one@-example.test',
    'one@example..test',
    'one..two@example.test',
  ]) {
    test(
      'rejects unsupported input in every recipient group: ${invalid.codeUnits}',
      () {
        expect(StudioMailRecipients.tryParse(to: invalid), isNull);
        expect(
          StudioMailRecipients.tryParse(to: 'valid@example.test', cc: invalid),
          isNull,
        );
        final draft = StudioMailDraft(
          to: 'valid@example.test',
          bcc: invalid,
          subject: 'Subject',
          body: 'Body',
        );
        expect(draft.problem, StudioMailDraftProblem.recipient);
        expect(
          () => buildStudioMailMessage(draft, 'sender@example.test'),
          throwsFormatException,
        );
      },
    );
  }

  test('mailbox limits preserve the complete 254-character address', () {
    final domain = '${'a' * 63}.${'b' * 63}.${'c' * 61}';
    final address = '${'l' * 64}@$domain';
    expect(address, hasLength(254));
    expect(StudioMailRecipients.isSupportedAddress(address), isTrue);
    expect(StudioMailRecipients.isSupportedAddress('${address}c'), isFalse);
    expect(
      StudioMailRecipients.isSupportedAddress('${'l' * 65}@example.test'),
      isFalse,
    );
    expect(
      StudioMailRecipients.isSupportedAddress('one@${'a' * 64}.test'),
      isFalse,
    );
  });

  test(
    'canonical MIME contains visible groups and excludes hidden addresses',
    () {
      const draft = StudioMailDraft(
        to: 'one@example.test; two@example.test',
        cc: 'copy@example.test, one@EXAMPLE.test',
        bcc: 'hidden@example.test; copy@EXAMPLE.test',
        subject: 'Subject',
        body: 'Body',
      );
      final mime = buildStudioMailMessage(draft, 'sender@example.test');
      expect(mime.to!.map((address) => address.email), [
        'one@example.test',
        'two@example.test',
      ]);
      expect(mime.cc!.map((address) => address.email), ['copy@example.test']);
      expect(mime.getHeaderValue('bcc'), isNull);
      expect(mime.renderMessage(), isNot(contains('hidden@example.test')));
      expect(draft.recipients.envelope, [
        'one@example.test',
        'two@example.test',
        'copy@example.test',
        'hidden@example.test',
      ]);
      expect(
        mime.renderMessage().codeUnits.every((unit) => unit < 128),
        isTrue,
      );
    },
  );

  test('100 maximum-length recipients survive folded MIME round trips', () {
    final domain = '${'a' * 63}.${'b' * 63}.${'c' * 61}';
    final addresses = [
      for (var index = 0; index < 100; index++)
        '${'r$index'.padRight(64, 'a')}@$domain',
    ];
    expect(addresses.every((address) => address.length == 254), isTrue);
    final draft = StudioMailDraft(
      to: addresses.join(', '),
      subject: 'Maximum supported recipient list',
      body: 'Body',
    );
    expect(draft.problem, isNull);
    final wire = buildStudioMailMessage(
      draft,
      'sender@example.test',
    ).renderMessage();
    expect(wire.codeUnits.every((unit) => unit < 128), isTrue);
    expect(wire.split('\r\n').every((line) => line.length <= 998), isTrue);
    final decoded = mail.MimeMessage.parseFromText(wire);
    expect(decoded.to!.map((address) => address.email), addresses);
    expect(decoded.bcc, isEmpty);
  });
}

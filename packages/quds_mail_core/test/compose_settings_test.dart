import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:test/test.dart';

final _account = MailAccountId(
  'personal',
  profile: MailProfileId('mail', hostId: 'office'),
);

MailQuickText _text({
  String id = 'thanks',
  String name = 'Thanks',
  String text = 'Thank you!\nشكراً 📨',
}) => MailQuickText(id: id, name: name, text: text);

void main() {
  test(
    'owns snapshots and retains account identity through independent edits',
    () {
      final texts = [_text()];
      final original = MailComposeSettings(
        account: _account,
        quickTexts: texts,
      );
      texts.clear();
      expect(original.quickTexts.single.text, 'Thank you!\nشكراً 📨');
      expect(() => original.quickTexts.clear(), throwsUnsupportedError);
      final edited = original.copyWith(
        revision: 7,
        signature: 'Best wishes',
        signatureForNewMessages: true,
        quickTexts: [original.quickTexts.single.copyWith(text: 'Changed')],
      );
      expect(identical(edited.account, original.account), isTrue);
      expect(edited.revision, 7);
      expect(edited.signatureForNewMessages, isTrue);
      expect(edited.signatureForReplies, isFalse);
      expect(edited.quickTexts.single.id, 'thanks');
      expect(original.revision, 0);
      expect(original.signature, isEmpty);
      expect(original.quickTexts.single.text, 'Thank you!\nشكراً 📨');
    },
  );

  test(
    'defaults are valid and leave automatic signature insertion disabled',
    () {
      final settings = MailComposeSettings(account: _account);
      expect(settings.isValid, isTrue);
      expect(settings.signature, isEmpty);
      expect(settings.quickTexts, isEmpty);
      expect(settings.signatureForNewMessages, isFalse);
      expect(settings.signatureForReplies, isFalse);
      expect(settings.toString(), 'MailComposeSettings(redacted)');
      expect(_text().toString(), 'MailQuickText(redacted)');
    },
  );

  test(
    'retains literal markup and international text without substitution',
    () {
      final settings = MailComposeSettings(
        account: _account,
        signature:
            'مرحبا 📨\t& <b>literal</b>\r\n'
            r'$name',
        quickTexts: [_text(id: 'سريع-📨', name: 'ÄRGER 📨')],
      );
      expect(settings.isValid, isTrue);
      expect(settings.quickTexts.single.nameKey, 'ärger 📨');
      expect(settings.signature, contains(r'$name'));
    },
  );

  test('requires unique IDs and case-insensitive trimmed names', () {
    for (final texts in [
      [_text(), _text(name: 'Another')],
      [_text(), _text(id: 'second', name: 'THANKS')],
    ]) {
      expect(
        MailComposeSettings(account: _account, quickTexts: texts).isValid,
        isFalse,
      );
    }
    expect(_text(name: ' Thanks ').isValid, isFalse);
    expect(_text(id: ' id ').isValid, isFalse);
  });

  for (final (label, text) in [
    ('empty ID', _text(id: '')),
    ('large ID', _text(id: 'x' * 1025)),
    ('empty name', _text(name: '')),
    ('whitespace name', _text(name: ' \t ')),
    ('large name', _text(name: 'x' * 81)),
    ('large Unicode name', _text(name: '📨' * 41)),
    ('large body', _text(text: 'x' * 16385)),
    ('name newline', _text(name: 'one\ntwo')),
    ('identity tab', _text(id: 'one\ttwo')),
  ]) {
    test('rejects $label', () => expect(text.isValid, isFalse));
  }

  test('accepts exact individual bounds and all 32 snippets', () {
    final settings = MailComposeSettings(
      account: _account,
      revision: MailComposeSettings.maxRevision,
      signature: '📨' * 8192,
      quickTexts: [
        _text(id: 'i' * 1024, name: '📨' * 40, text: 'x' * 16384),
        for (var i = 1; i < 32; i++) _text(id: '$i', name: 'Item $i', text: ''),
      ],
    );
    expect(settings.isValid, isTrue);
    expect(
      settings.copyWith(quickTexts: [...settings.quickTexts, _text()]).isValid,
      isFalse,
    );
    expect(
      settings.copyWith(signature: '${settings.signature}x').isValid,
      isFalse,
    );
  });

  test('total budget covers ownership, IDs, names, keys and authored text', () {
    final items = [
      for (var i = 0; i < 8; i++)
        _text(id: '$i', name: '$i', text: 'x' * 16000),
    ];
    final base = MailComposeSettings(account: _account, quickTexts: items);
    final remaining =
        MailComposeSettings.maxMetadataCodeUnits - base.metadataCodeUnits;
    final exact = base.copyWith(signature: 's' * remaining);
    expect(exact.metadataCodeUnits, MailComposeSettings.maxMetadataCodeUnits);
    expect(exact.isValid, isTrue);
    expect(exact.copyWith(signature: '${exact.signature}x').isValid, isFalse);
  });

  for (final revision in [-1, MailComposeSettings.maxRevision + 1]) {
    test('rejects invalid revision $revision', () {
      expect(
        MailComposeSettings(account: _account, revision: revision).isValid,
        isFalse,
      );
    });
  }

  for (final control in [
    '\u0000',
    '\u0001',
    '\u000b',
    '\u007f',
    '\u0085',
    '\u009f',
  ]) {
    final code = control.codeUnitAt(0).toRadixString(16);
    test('rejects non-compose control U+$code', () {
      expect(_text(id: 'a${control}b').isValid, isFalse);
      expect(_text(name: 'a${control}b').isValid, isFalse);
      expect(_text(text: 'a${control}b').isValid, isFalse);
      expect(
        MailComposeSettings(account: _account, signature: control).isValid,
        isFalse,
      );
    });
  }

  for (final (label, malformed) in [
    ('high', '\uD800'),
    ('low', '\uDC00'),
    ('unpaired', '\uD800a'),
    ('reversed', '\uDC00\uD800'),
  ]) {
    test('rejects $label UTF-16 in text and every ownership component', () {
      expect(_text(id: malformed).isValid, isFalse);
      expect(_text(name: malformed).isValid, isFalse);
      expect(_text(text: malformed).isValid, isFalse);
      expect(
        MailComposeSettings(account: _account, signature: malformed).isValid,
        isFalse,
      );
      for (final account in [
        MailAccountId(malformed, profile: _account.profile),
        MailAccountId('a', profile: MailProfileId(malformed, hostId: 'office')),
        MailAccountId('a', profile: MailProfileId('mail', hostId: malformed)),
      ]) {
        expect(MailComposeSettings(account: account).isValid, isFalse);
      }
    });
  }

  group('sender identities and message templates', () {
    const sender = MailSenderIdentity(
      id: 'work',
      name: 'Work',
      address: 'sender@example.test',
      displayName: 'مرحبا 📨',
      replyTo: 'reply@example.test',
    );
    const template = MailMessageTemplate(
      id: 'follow-up',
      name: 'Follow-up',
      to: 'recipient@example.test',
      cc: 'copy@example.test',
      bcc: 'private@example.test',
      subject: 'Meeting 📨',
      body: '<b>literal</b>\n\$name\r\nمرحبا',
      senderIdentityId: 'work',
    );

    MailComposeSettings settings() => MailComposeSettings(
      account: _account,
      senderIdentities: [sender],
      defaultSenderIdentityId: sender.id,
      templates: [template],
    );

    test(
      'owns immutable lists, preserves literal fields and copies references',
      () {
        final senders = [sender];
        final templates = [template];
        final original = MailComposeSettings(
          account: _account,
          senderIdentities: senders,
          templates: templates,
          defaultSenderIdentityId: sender.id,
        );
        senders.clear();
        templates.clear();
        expect(original.isValid, isTrue);
        expect(original.senderIdentities.single.displayName, 'مرحبا 📨');
        expect(original.templates.single.bcc, 'private@example.test');
        expect(original.templates.single.body, contains(r'$name'));
        expect(() => original.senderIdentities.clear(), throwsUnsupportedError);
        expect(() => original.templates.clear(), throwsUnsupportedError);
        final copy = original.copyWith(signature: 'Independent');
        expect(copy.defaultSenderIdentityId, 'work');
        expect(copy.templates.single.senderIdentityId, 'work');
        expect(copy.senderIdentities.single.address, 'sender@example.test');
        expect(sender.copyWith(address: 'alias@example.test').id, sender.id);
        expect(template.copyWith(subject: 'Changed').id, template.id);
        expect(sender.toString(), 'MailSenderIdentity(redacted)');
        expect(template.toString(), 'MailMessageTemplate(redacted)');
      },
    );

    test(
      'default and template references must resolve in the same snapshot',
      () {
        final original = settings();
        expect(
          original.copyWith(defaultSenderIdentityId: 'missing').isValid,
          isFalse,
        );
        expect(original.copyWith(senderIdentities: []).isValid, isFalse);
        expect(
          original
              .copyWith(
                templates: [template.copyWith(senderIdentityId: 'missing')],
              )
              .isValid,
          isFalse,
        );
        final cleared = original.copyWith(
          senderIdentities: [],
          clearDefaultSenderIdentity: true,
          templates: [template.copyWith(clearSenderIdentity: true)],
        );
        expect(cleared.isValid, isTrue);
        expect(cleared.defaultSenderIdentityId, isNull);
        expect(cleared.templates.single.senderIdentityId, isNull);
        expect(original.defaultSenderIdentityId, 'work');
      },
    );

    test(
      'names and IDs are unique within each independently named collection',
      () {
        for (final senders in [
          [sender, sender.copyWith(name: 'Another')],
          [
            sender,
            const MailSenderIdentity(
              id: 'other',
              name: 'WORK',
              address: 'other@example.test',
            ),
          ],
        ]) {
          expect(
            settings().copyWith(senderIdentities: senders).isValid,
            isFalse,
          );
        }
        for (final templates in [
          [template, template.copyWith(name: 'Another')],
          [template, const MailMessageTemplate(id: 'other', name: 'FOLLOW-UP')],
        ]) {
          expect(settings().copyWith(templates: templates).isValid, isFalse);
        }
        expect(
          settings()
              .copyWith(
                quickTexts: [_text(id: 'work', name: 'Work')],
              )
              .isValid,
          isTrue,
        );
      },
    );

    test(
      'template recipient text can remain incomplete without becoming a send',
      () {
        final authored = template.copyWith(
          to: 'unfinished@',
          cc: '',
          bcc: '',
          body: '',
        );
        expect(authored.isValid, isTrue);
        expect(
          const MailMessageTemplate(id: 'blank', name: 'Blank').isValid,
          isTrue,
        );
        expect(settings().copyWith(templates: [authored]).isValid, isTrue);
      },
    );

    test('sender mailbox fields reject unsafe or unsupported syntax', () {
      for (final address in [
        '',
        'Name <sender@example.test>',
        'a@example.test\r\nBcc: x@y.test',
        'sender@example.test,second@example.test',
        '.a@example.test',
        'a..b@example.test',
        'a@-example.test',
        'a@example..test',
        'a@[127.0.0.1]',
        'ü@example.test',
        '${'a' * 65}@example.test',
      ]) {
        expect(
          sender.copyWith(address: address).isValid,
          isFalse,
          reason: address,
        );
        expect(
          sender.copyWith(replyTo: address).isValid,
          address.isEmpty,
          reason: address,
        );
      }
      expect(
        sender.copyWith(address: 'first+tag@EXAMPLE.test', replyTo: '').isValid,
        isTrue,
      );
    });

    test('bounds each new field, collection and complete settings budget', () {
      expect(sender.copyWith(displayName: '📨' * 128).isValid, isTrue);
      expect(sender.copyWith(displayName: '📨' * 129).isValid, isFalse);
      expect(sender.copyWith(name: 'x' * 81).isValid, isFalse);
      expect(
        template.copyWith(subject: 'x' * 512, body: 'x' * 16384).isValid,
        isTrue,
      );
      expect(template.copyWith(subject: 'x' * 513).isValid, isFalse);
      expect(template.copyWith(body: 'x' * 16385).isValid, isFalse);
      expect(
        template.copyWith(to: 'x' * 25600, cc: '', bcc: '').isValid,
        isTrue,
      );
      expect(
        template.copyWith(to: 'x' * 25600, cc: 'x', bcc: '').isValid,
        isFalse,
      );
      final all = MailComposeSettings(
        account: _account,
        senderIdentities: [
          for (var i = 0; i < 16; i++)
            MailSenderIdentity(
              id: '$i',
              name: '$i',
              address: 'a$i@example.test',
            ),
        ],
        templates: [
          for (var i = 0; i < 32; i++)
            MailMessageTemplate(id: '$i', name: '$i'),
        ],
      );
      expect(all.isValid, isTrue);
      expect(
        all
            .copyWith(senderIdentities: [...all.senderIdentities, sender])
            .isValid,
        isFalse,
      );
      expect(
        all.copyWith(templates: [...all.templates, template]).isValid,
        isFalse,
      );
      final full = settings().copyWith(
        templates: [
          for (var i = 0; i < 9; i++)
            MailMessageTemplate(id: '$i', name: '$i', body: 'x' * 16000),
        ],
      );
      expect(
        full.metadataCodeUnits,
        greaterThan(MailComposeSettings.maxMetadataCodeUnits),
      );
      expect(full.isValid, isFalse);
      final counted = settings();
      final expected =
          _account.value.length +
          _account.profile.value.length +
          _account.profile.hostId.length +
          sender.id.length +
          sender.name.length +
          sender.nameKey.length +
          sender.address.length +
          sender.displayName.length +
          sender.replyTo.length +
          sender.id.length +
          template.id.length +
          template.name.length +
          template.nameKey.length +
          template.to.length +
          template.cc.length +
          template.bcc.length +
          template.subject.length +
          template.body.length +
          sender.id.length;
      expect(counted.metadataCodeUnits, expected);
    });

    test(
      'rejects header controls and malformed Unicode before persistence',
      () {
        for (final invalid in [
          '\r',
          '\n',
          '\t',
          '\u0000',
          '\u0085',
          '\uD800',
          '\uDC00',
        ]) {
          expect(sender.copyWith(name: 'a${invalid}b').isValid, isFalse);
          expect(sender.copyWith(displayName: 'a${invalid}b').isValid, isFalse);
          expect(template.copyWith(to: 'a${invalid}b').isValid, isFalse);
          expect(template.copyWith(cc: 'a${invalid}b').isValid, isFalse);
          expect(template.copyWith(bcc: 'a${invalid}b').isValid, isFalse);
          expect(template.copyWith(subject: 'a${invalid}b').isValid, isFalse);
        }
        for (final invalid in ['\u0000', '\u0085', '\uD800', '\uDC00']) {
          expect(template.copyWith(body: 'a${invalid}b').isValid, isFalse);
        }
        expect(template.copyWith(body: 'one\r\n\ttwo').isValid, isTrue);
      },
    );
  });

  group('rich message templates', () {
    MailComposeBody rich(String text) => MailComposeBody(
      paragraphs: [
        MailComposeParagraph(
          runs: [MailComposeRun(text: text, bold: true)],
          rightToLeft: true,
        ),
      ],
    );

    MailMessageTemplate template(MailComposeBody body) => MailMessageTemplate(
      id: 'rich',
      name: 'Formatted',
      body: body.plainText,
      richBody: body,
    );

    test('owns rich content across copies until it is explicitly cleared', () {
      final body = rich('مرحبا 📨');
      final original = template(body);
      expect(original.isValid, isTrue);
      final renamed = original.copyWith(name: 'Renamed');
      expect(identical(renamed.richBody, body), isTrue);
      expect(renamed.richBody!.paragraphs.single.runs.single.bold, isTrue);
      expect(renamed.body, body.plainText);
      expect(original.copyWith(body: 'Changed').isValid, isFalse);
      final plain = original.copyWith(body: 'Changed', clearRichBody: true);
      expect(plain.isValid, isTrue);
      expect(plain.richBody, isNull);
      expect(original.richBody, body);
      expect(original.toString(), 'MailMessageTemplate(redacted)');
    });

    test('normalizes only line endings when matching plain and rich text', () {
      final body = rich('one\ntwo\nمرحبا');
      final item = template(body);
      expect(item.copyWith(body: 'one\r\ntwo\rمرحبا').isValid, isTrue);
      for (final different in [
        ' one\ntwo\nمرحبا',
        'one\ntwo\nمرحبا ',
        'one\ntwo\n',
        'one\ntwo\nother',
      ]) {
        expect(item.copyWith(body: different).isValid, isFalse);
      }
    });

    test('legacy literal markup never acquires an inferred rich alternative', () {
      const item = MailMessageTemplate(
        id: 'plain',
        name: 'Plain',
        body: '<b>literal</b>\r\n\$name',
      );
      expect(item.isValid, isTrue);
      expect(item.richBody, isNull);
      expect(item.copyWith(name: 'Renamed').body, item.body);
      expect(item.copyWith(name: 'Renamed').richBody, isNull);
    });

    test('empty paragraph typing marks remain authored template content', () {
      final item = template(rich(''));
      expect(item.isValid, isTrue);
      expect(item.body, isEmpty);
      expect(item.richBody!.hasFormatting, isTrue);
      expect(item.richBody!.paragraphs.single.rightToLeft, isTrue);
      expect(item.richBody!.paragraphs.single.runs.single.bold, isTrue);
    });

    test('rich bodies keep the existing plain UTF-16 budget', () {
      expect(template(rich('📨' * 8192)).isValid, isTrue);
      expect(template(rich('📨' * 8193)).isValid, isFalse);
      expect(template(rich('x' * 16385)).isValid, isFalse);
    });

    test('canonical HTML has an exact independent UTF-16 budget', () {
      final overhead = rich('').html.length - '<br />'.length;
      final plainUnits =
          (MailMessageTemplate.maxRichBodyCodeUnits - overhead) ~/ 4;
      final prefix = '<' * plainUnits;
      final remaining =
          MailMessageTemplate.maxRichBodyCodeUnits - rich(prefix).html.length;
      final exact = rich('$prefix${'x' * remaining}');
      expect(
        exact.plainText.length,
        lessThan(MailMessageTemplate.maxBodyCodeUnits),
      );
      expect(exact.html.length, MailMessageTemplate.maxRichBodyCodeUnits);
      expect(template(exact).isValid, isTrue);
      final tooLarge = rich('${exact.plainText}x');
      expect(tooLarge.html.length, MailMessageTemplate.maxRichBodyCodeUnits + 1);
      expect(template(tooLarge).isValid, isFalse);
    });

    test('both alternatives count toward the shared settings budget', () {
      final item = template(rich('x' * 3000));
      final plain = MailComposeSettings(
        account: _account,
        templates: [item.copyWith(clearRichBody: true)],
        quickTexts: [
          for (var index = 0; index < 7; index++)
            _text(id: '$index', name: '$index', text: 'x' * 16000),
        ],
      );
      final formatted = plain.copyWith(templates: [item]);
      expect(
        formatted.metadataCodeUnits,
        plain.metadataCodeUnits + item.richBody!.html.length,
      );
      final remaining =
          MailComposeSettings.maxMetadataCodeUnits - formatted.metadataCodeUnits;
      expect(
        remaining,
        inInclusiveRange(1, MailComposeSettings.maxSignatureCodeUnits),
      );
      final exact = formatted.copyWith(signature: 'x' * remaining);
      expect(exact.isValid, isTrue);
      expect(exact.copyWith(signature: '${exact.signature}x').isValid, isFalse);
    });
  });
}

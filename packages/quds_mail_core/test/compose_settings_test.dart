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
  test('owns snapshots and retains account identity through independent edits', () {
    final texts = [_text()];
    final original = MailComposeSettings(account: _account, quickTexts: texts);
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
  });

  test('defaults are valid and leave automatic signature insertion disabled', () {
    final settings = MailComposeSettings(account: _account);
    expect(settings.isValid, isTrue);
    expect(settings.signature, isEmpty);
    expect(settings.quickTexts, isEmpty);
    expect(settings.signatureForNewMessages, isFalse);
    expect(settings.signatureForReplies, isFalse);
    expect(settings.toString(), 'MailComposeSettings(redacted)');
    expect(_text().toString(), 'MailQuickText(redacted)');
  });

  test('retains literal markup and international text without substitution', () {
    final settings = MailComposeSettings(
      account: _account,
      signature: 'مرحبا 📨\t& <b>literal</b>\r\n' r'$name',
      quickTexts: [_text(id: 'سريع-📨', name: 'ÄRGER 📨')],
    );
    expect(settings.isValid, isTrue);
    expect(settings.quickTexts.single.nameKey, 'ärger 📨');
    expect(settings.signature, contains(r'$name'));
  });

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
      settings.copyWith(signature: settings.signature + 'x').isValid,
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
    expect(
      exact.copyWith(signature: exact.signature + 'x').isValid,
      isFalse,
    );
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
    '\u0000', '\u0001', '\u000b', '\u007f', '\u0085', '\u009f',
  ]) {
    final code = control.codeUnitAt(0).toRadixString(16);
    test('rejects non-compose control U+$code', () {
      expect(_text(id: 'a' + control + 'b').isValid, isFalse);
      expect(_text(name: 'a' + control + 'b').isValid, isFalse);
      expect(_text(text: 'a' + control + 'b').isValid, isFalse);
      expect(
        MailComposeSettings(account: _account, signature: control).isValid,
        isFalse,
      );
    });
  }

  for (final (label, malformed) in [
    ('high', '\uD800'), ('low', '\uDC00'),
    ('unpaired', '\uD800a'), ('reversed', '\uDC00\uD800'),
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
}

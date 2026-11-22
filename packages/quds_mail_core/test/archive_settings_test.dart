import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:test/test.dart';

final _profile = MailProfileId('profile', hostId: 'office');
final _account = MailAccountId('account', profile: _profile);

void main() {
  test(
    'defaults do not choose a folder and diagnostics redact the account',
    () {
      final settings = MailArchiveDestinationSettings(account: _account);
      expect(settings.isValid, isTrue);
      expect(settings.revision, 0);
      expect(settings.destination, isNull);
      expect(settings.toString(), 'MailArchiveDestinationSettings(redacted)');
    },
  );

  test('retains exact case, significant whitespace and Unicode paths', () {
    for (final value in [' Archive/Ärger/أرشيف 📨 ', 'archive', 'Archive']) {
      final folder = MailMailboxId(value, account: _account);
      final settings = MailArchiveDestinationSettings(
        account: _account,
        destination: folder,
      );
      expect(settings.isValid, isTrue);
      expect(settings.destination?.value, value);
      expect(settings.copyWith(revision: 7).destination, same(folder));
      expect(settings.revision, 0);
    }
  });

  test('explicit reset preserves owner and revision independently', () {
    final original = MailArchiveDestinationSettings(
      account: _account,
      revision: 4,
      destination: MailMailboxId('Archive', account: _account),
    );
    final reset = original.copyWith(clearDestination: true);
    expect(reset.destination, isNull);
    expect(reset.account, same(_account));
    expect(reset.revision, 4);
    expect(original.destination?.value, 'Archive');
    expect(
      original.copyWith(destination: null).destination,
      original.destination,
    );
  });

  test(
    'rejects foreign accounts and profiles even with equal mailbox values',
    () {
      for (final foreign in [
        MailAccountId('other', profile: _profile),
        MailAccountId(
          'account',
          profile: MailProfileId('other', hostId: 'office'),
        ),
        MailAccountId(
          'account',
          profile: MailProfileId('profile', hostId: 'other'),
        ),
      ]) {
        expect(
          MailArchiveDestinationSettings(
            account: _account,
            destination: MailMailboxId('Archive', account: foreign),
          ).isValid,
          isFalse,
        );
      }
    },
  );

  test(
    'admits exact UTF-16 bounds and rejects oversized astral identities',
    () {
      expect(
        MailArchiveDestinationSettings(
          account: _account,
          revision: MailArchiveDestinationSettings.maxRevision,
          destination: MailMailboxId('📨' * 512, account: _account),
        ).isValid,
        isTrue,
      );
      expect(
        MailArchiveDestinationSettings(
          account: _account,
          destination: MailMailboxId('📨' * 513, account: _account),
        ).isValid,
        isFalse,
      );
    },
  );

  for (final (label, value) in [
    ('unpaired high surrogate', '\uD800'),
    ('unpaired low surrogate', '\uDC00'),
    ('broken surrogate pair', '\uD800x'),
    ('C1 control', 'folder\u0085name'),
    ('oversized folder', 'x' * 1025),
  ]) {
    test('rejects $label before encoding a stored destination', () {
      expect(
        MailArchiveDestinationSettings(
          account: _account,
          destination: MailMailboxId(value, account: _account),
        ).isValid,
        isFalse,
      );
    });
  }

  test(
    'validates all owner identifiers and exactly representable revisions',
    () {
      for (final account in [
        MailAccountId(' account ', profile: _profile),
        MailAccountId('\uD800', profile: _profile),
        MailAccountId('x' * 1025, profile: _profile),
        MailAccountId(
          'account',
          profile: MailProfileId('\uDC00', hostId: 'office'),
        ),
        MailAccountId(
          'account',
          profile: MailProfileId('profile', hostId: ' bad '),
        ),
      ]) {
        expect(
          MailArchiveDestinationSettings(account: account).isValid,
          isFalse,
        );
      }
      for (final revision in [
        -1,
        MailArchiveDestinationSettings.maxRevision + 1,
      ]) {
        expect(
          MailArchiveDestinationSettings(
            account: _account,
            revision: revision,
          ).isValid,
          isFalse,
        );
      }
    },
  );
}

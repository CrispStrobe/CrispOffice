import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:test/test.dart';

const _first = MailSavedHeaderSearchFolder(
  accountId: 'a',
  mailboxId: 'inbox',
  displayName: 'Inbox',
);
const _second = MailSavedHeaderSearchFolder(
  accountId: 'b',
  mailboxId: 'inbox',
  displayName: 'Inbox',
);

MailSavedHeaderSearch _search({
  List<String> accounts = const ['a', 'b'],
  List<MailSavedHeaderSearchFolder>? folders,
}) => MailSavedHeaderSearch(
  id: 'view',
  name: 'Inbox view',
  query: 'is:unread',
  accountIds: accounts,
  folders: folders,
);

void main() {
  test(
    'published folderScopes aliases share one immutable canonical selection',
    () {
      final input = [_first, _second];
      final saved = MailSavedHeaderSearch(
        id: 'published',
        name: 'Published',
        query: '',
        accountIds: ['a', 'b'],
        folderScopes: input,
      );
      input.clear();
      expect(saved.folders, [_first, _second]);
      expect(identical(saved.folderScopes, saved.folders), isTrue);
      expect(MailSavedHeaderSearch.maxFolderScopes, 200);
      expect(
        MailSavedHeaderSearch.maxFolders,
        MailSavedHeaderSearch.maxFolderScopes,
      );
      expect(saved.copyWith(folderScopes: [_second, _first]).folders, [
        _second,
        _first,
      ]);
      expect(saved.copyWith(allFolders: true).folderScopes, isNull);
    },
  );

  test(
    'simultaneous legacy and typed selections cannot hide an ambiguous scope',
    () {
      expect(
        () => MailSavedHeaderSearch(
          id: 'ambiguous',
          name: 'Ambiguous',
          query: '',
          accountIds: ['a', 'b'],
          folders: [_first, _second],
          folderScopes: [_second, _first],
        ),
        throwsArgumentError,
      );
      expect(
        () => _search().copyWith(
          folders: [_first, _second],
          folderScopes: [_first, _second],
        ),
        throwsArgumentError,
      );
      expect(
        () => _search().copyWith(
          allFolders: true,
          folderScopes: [_first, _second],
        ),
        throwsArgumentError,
      );
    },
  );

  test(
    'legacy scope remains all folders, explicit scope owns its snapshot',
    () {
      expect(_search().folders, isNull);
      final source = [_first, _second];
      final saved = _search(folders: source);
      source.clear();
      expect(saved.folders, [_first, _second]);
      expect(saved.isValid, isTrue);
      expect(() => saved.folders!.clear(), throwsUnsupportedError);
    },
  );

  test('folder identity uses exact account and folder, never display name', () {
    expect(_first, isNot(_second));
    const renamed = MailSavedHeaderSearchFolder(
      accountId: 'a',
      mailboxId: 'inbox',
      displayName: 'Posteingang',
    );
    expect(_first, renamed);
    expect(_first.hashCode, renamed.hashCode);
    expect(_search(folders: [_first, renamed, _second]).isValid, isFalse);
    expect(_first.toString(), 'MailSavedHeaderSearchFolder(redacted)');
  });

  test('every account is explicitly represented and foreign accounts fail', () {
    for (final folders in <List<MailSavedHeaderSearchFolder>>[
      [],
      [_first],
      [_second],
      [
        _first,
        _second,
        const MailSavedHeaderSearchFolder(accountId: 'c', mailboxId: 'inbox'),
      ],
    ]) {
      expect(_search(folders: folders).isValid, isFalse);
    }
    expect(_search(accounts: ['a'], folders: [_first]).isValid, isTrue);
  });

  test('copy preserves folders unless reset to all is explicit', () {
    final saved = _search(folders: [_first, _second]);
    expect(saved.copyWith(query: '').folders, [_first, _second]);
    expect(saved.copyWith(folders: null).folders, [_first, _second]);
    expect(saved.copyWith(allFolders: true).folders, isNull);
    expect(
      saved.copyWith(accountIds: ['a'], folders: [_first]).isValid,
      isTrue,
    );
    expect(
      () => saved.copyWith(allFolders: true, folders: [_first, _second]),
      throwsArgumentError,
    );
  });

  test(
    'significant folder whitespace and valid supplementary text survive',
    () {
      const folder = MailSavedHeaderSearchFolder(
        accountId: 'a',
        mailboxId: ' صندوق 📨 ',
        displayName: 'رسائل 📨',
      );
      expect(folder.isValid, isTrue);
      expect(folder.mailboxId, ' صندوق \uD83D\uDCE8 ');
      expect(_search(accounts: ['a'], folders: [folder]).isValid, isTrue);
      expect(
        folder,
        isNot(
          const MailSavedHeaderSearchFolder(
            accountId: 'a',
            mailboxId: 'صندوق 📨',
          ),
        ),
      );
    },
  );

  test('folder count, ID length and display length have exact ceilings', () {
    final folders = List.generate(
      MailSavedHeaderSearch.maxFolders,
      (index) =>
          MailSavedHeaderSearchFolder(accountId: 'a', mailboxId: '$index'),
    );
    expect(_search(accounts: ['a'], folders: folders).isValid, isTrue);
    expect(
      _search(accounts: ['a'], folders: [...folders, _first]).isValid,
      isFalse,
    );
    final maximum = MailSavedHeaderSearchFolder(
      accountId: 'a',
      mailboxId: 'm' * 1024,
      displayName: '📨' * 2048,
    );
    expect(maximum.isValid, isTrue);
  });

  for (final (field, invalid) in <(String, String)>[
    ('account', ''),
    ('account', ' a'),
    ('account', 'a\u0000b'),
    ('account', 'a\uD800'),
    ('mailbox', ''),
    ('mailbox', 'm' * 1025),
    ('mailbox', 'a\nb'),
    ('mailbox', 'a\uDC00'),
    ('display', 'x' * 4097),
    ('display', 'a\u0000b'),
    ('display', 'a\uD800'),
  ]) {
    test('rejects malformed $field with length ${invalid.length}', () {
      final folder = MailSavedHeaderSearchFolder(
        accountId: field == 'account' ? invalid : 'a',
        mailboxId: field == 'mailbox' ? invalid : 'inbox',
        displayName: field == 'display' ? invalid : 'Inbox',
      );
      expect(folder.isValid, isFalse);
      expect(_search(accounts: ['a'], folders: [folder]).isValid, isFalse);
    });
  }
}

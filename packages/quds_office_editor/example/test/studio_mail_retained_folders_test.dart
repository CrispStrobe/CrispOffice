import 'package:flutter_test/flutter_test.dart';
import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_store/quds_mail_store.dart';
import 'package:quds_office_studio/studio_mail_mailbox_store.dart';
import 'package:quds_office_studio/studio_mail_retained_folders.dart';

final _account = MailAccountId(
  'reader',
  profile: MailProfileId('profile', hostId: 'retained-folders-test'),
);
final _otherAccount = MailAccountId('other', profile: _account.profile);
final _otherProfile = MailAccountId(
  _account.value,
  profile: MailProfileId('other-profile', hostId: _account.profile.hostId),
);
final _time = DateTime.utc(2026, 11, 22);

MailMailbox _mailbox(
  String id, {
  MailAccountId? account,
  String? name,
  bool isLabel = false,
}) => MailMailbox(
  id: MailMailboxId(id, account: account ?? _account),
  displayName: name ?? id,
  isLabel: isLabel,
);

MailCachedMailboxSummary _browse(
  String id, {
  MailAccountId? account,
  String? name,
  bool isLabel = false,
  int revision = 1,
  DateTime? time,
  int count = 2,
  bool hasMore = true,
}) => MailCachedMailboxSummary(
  mailbox: _mailbox(id, account: account, name: name, isLabel: isLabel),
  revision: revision,
  capturedAt: time ?? _time,
  headerCount: count,
  hasMore: hasMore,
);

MailMailboxSyncSummary _sync(
  String id, {
  MailAccountId? account,
  String? name,
  bool isLabel = false,
  int revision = 1,
  DateTime? time,
  int count = 2000,
  bool hasMore = false,
}) => MailMailboxSyncSummary(
  mailbox: _mailbox(id, account: account, name: name, isLabel: isLabel),
  revision: revision,
  updatedAt: time ?? _time,
  headerCount: count,
  hasMore: hasMore,
);

List<StudioMailRetainedFolder> _merge({
  List<MailCachedMailboxSummary> browsing = const [],
  List<MailMailboxSyncSummary> synchronized = const [],
}) => studioMailRetainedFolders(
  account: _account,
  browsing: browsing,
  synchronized: synchronized,
);

Matcher _problem(MailProblemCode code) => throwsA(
  isA<StudioMailMailboxStoreException>().having(
    (error) => error.code,
    'code',
    code,
  ),
);

void main() {
  test('empty catalogs remain empty without inventing folders', () {
    expect(_merge(), isEmpty);
  });

  test('browse-only and sync-only folders retain their distinct coverage', () {
    final browsing = _browse('recent', count: 50, hasMore: true);
    final synchronized = _sync('downloaded', count: 2400, hasMore: false);
    final result = _merge(browsing: [browsing], synchronized: [synchronized]);
    expect(result.map((folder) => folder.id.value), ['downloaded', 'recent']);
    expect(result.first.synchronized, same(synchronized));
    expect(result.first.browse, isNull);
    expect(result.first.synchronized!.headerCount, 2400);
    expect(result.first.synchronized!.hasMore, isFalse);
    expect(result.last.browse, same(browsing));
    expect(result.last.synchronized, isNull);
    expect(result.last.browse!.headerCount, 50);
    expect(result.last.browse!.hasMore, isTrue);
  });

  test(
    'overlapping folder keeps both observations and sync display metadata',
    () {
      final browsing = _browse('inbox', name: 'Old name', revision: 8);
      final synchronized = _sync('inbox', name: 'Renamed inbox', revision: 3);
      final result = _merge(browsing: [browsing], synchronized: [synchronized]);
      expect(result, hasLength(1));
      expect(result.single.id, browsing.mailbox.id);
      expect(result.single.mailbox, same(synchronized.mailbox));
      expect(result.single.mailbox.displayName, 'Renamed inbox');
      expect(result.single.browse, same(browsing));
      expect(result.single.synchronized, same(synchronized));
      expect(result.single.browse!.revision, 8);
      expect(result.single.synchronized!.revision, 3);
    },
  );

  test(
    'activity ordering uses newer browse or sync time with stable ID ties',
    () {
      final older = _time.subtract(const Duration(days: 2));
      final newest = _time.add(const Duration(days: 1));
      final result = _merge(
        browsing: [
          _browse('z-last', time: older),
          _browse('b-tied'),
          _browse('browse-newest', time: newest),
          _browse('a-tied'),
          _browse('sync-newest', time: older),
        ],
        synchronized: [
          _sync('sync-newest', time: newest),
          _sync('browse-newest', time: older),
        ],
      );
      expect(result.map((folder) => folder.id.value), [
        'browse-newest',
        'sync-newest',
        'a-tied',
        'b-tied',
        'z-last',
      ]);
    },
  );

  test('result is immutable and independent of later source list edits', () {
    final browsing = [_browse('browse')];
    final synchronized = [_sync('sync')];
    final result = _merge(browsing: browsing, synchronized: synchronized);
    browsing.clear();
    synchronized
      ..clear()
      ..add(_sync('replacement'));
    expect(result.map((folder) => folder.id.value), ['browse', 'sync']);
    expect(() => result.clear(), throwsUnsupportedError);
    expect(() => result.add(result.first), throwsUnsupportedError);
  });

  test(
    'duplicate browse identities fail instead of choosing an observation',
    () {
      expect(
        () => _merge(browsing: [_browse('same'), _browse('same', revision: 2)]),
        _problem(MailProblemCode.conflict),
      );
    },
  );

  test(
    'duplicate sync identities fail even when they also overlap browsing',
    () {
      expect(
        () => _merge(
          browsing: [_browse('same')],
          synchronized: [_sync('same'), _sync('same', revision: 2)],
        ),
        _problem(MailProblemCode.conflict),
      );
    },
  );

  for (final (name, account) in [
    ('account', _otherAccount),
    ('profile', _otherProfile),
  ]) {
    test('foreign $name cannot merge through matching folder text', () {
      expect(
        () => _merge(
          browsing: [_browse('same')],
          synchronized: [_sync('same', account: account)],
        ),
        _problem(MailProblemCode.conflict),
      );
      expect(
        () => _merge(browsing: [_browse('same', account: account)]),
        _problem(MailProblemCode.conflict),
      );
    });
  }

  test(
    'overlap may rename a folder but cannot change folder/label semantics',
    () {
      expect(
        () => _merge(
          browsing: [_browse('same', isLabel: true)],
          synchronized: [_sync('same', isLabel: false)],
        ),
        _problem(MailProblemCode.conflict),
      );
      final label = _merge(
        browsing: [_browse('same', isLabel: true)],
        synchronized: [_sync('same', isLabel: true)],
      ).single;
      expect(label.mailbox.isLabel, isTrue);
    },
  );

  test('exactly 1000 distinct folders are retained without truncation', () {
    final result = _merge(
      browsing: [for (var i = 0; i < 1000; i++) _browse('folder-$i')],
      synchronized: [for (var i = 0; i < 1000; i++) _sync('folder-$i')],
    );
    expect(result, hasLength(1000));
    expect(result.every((folder) => folder.browse != null), isTrue);
    expect(result.every((folder) => folder.synchronized != null), isTrue);
  });

  test(
    'individually bounded catalogs cannot silently overflow merged limit',
    () {
      expect(
        () => _merge(
          browsing: [for (var i = 0; i < 1000; i++) _browse('folder-$i')],
          synchronized: [_sync('extra')],
        ),
        _problem(MailProblemCode.quotaExceeded),
      );
    },
  );

  test('each input catalog is bounded before merging', () {
    expect(
      () => _merge(
        browsing: [for (var i = 0; i <= 1000; i++) _browse('folder-$i')],
      ),
      _problem(MailProblemCode.quotaExceeded),
    );
    expect(
      () => _merge(
        synchronized: [for (var i = 0; i <= 1000; i++) _sync('folder-$i')],
      ),
      _problem(MailProblemCode.quotaExceeded),
    );
  });

  for (final revision in [-1, 0, 9007199254740992]) {
    test('invalid revision $revision is rejected in both sources', () {
      expect(
        () => _merge(browsing: [_browse('folder', revision: revision)]),
        _problem(MailProblemCode.conflict),
      );
      expect(
        () => _merge(synchronized: [_sync('folder', revision: revision)]),
        _problem(MailProblemCode.conflict),
      );
    });
  }

  test('safe maximum revisions and epoch observations remain valid', () {
    final epoch = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    final result = _merge(
      browsing: [
        _browse('empty', revision: 9007199254740991, time: epoch, count: 0),
      ],
      synchronized: [
        _sync('empty', revision: 9007199254740991, time: epoch, count: 0),
      ],
    );
    expect(result.single.browse!.headerCount, 0);
    expect(result.single.synchronized!.headerCount, 0);
  });

  test(
    'pre-epoch observations fail instead of sorting as valid retained mail',
    () {
      final beforeEpoch = DateTime.fromMillisecondsSinceEpoch(-1, isUtc: true);
      expect(
        () => _merge(browsing: [_browse('folder', time: beforeEpoch)]),
        _problem(MailProblemCode.conflict),
      );
      expect(
        () => _merge(synchronized: [_sync('folder', time: beforeEpoch)]),
        _problem(MailProblemCode.conflict),
      );
    },
  );

  test('browse counts stay bounded separately from synchronized totals', () {
    for (final count in [-1, 1001]) {
      expect(
        () => _merge(browsing: [_browse('folder', count: count)]),
        _problem(MailProblemCode.conflict),
      );
    }
    for (final count in [-1, 9007199254740992]) {
      expect(
        () => _merge(synchronized: [_sync('folder', count: count)]),
        _problem(MailProblemCode.conflict),
      );
    }
    final result = _merge(
      browsing: [_browse('folder', count: 1000)],
      synchronized: [_sync('folder', count: 9007199254740991)],
    );
    expect(result.single.browse!.headerCount, 1000);
    expect(result.single.synchronized!.headerCount, 9007199254740991);
  });

  test('oversized folder identifiers and display metadata fail explicitly', () {
    final longId = 'i' * 1025;
    final longName = 'n' * 4097;
    expect(
      () => _merge(browsing: [_browse(longId)]),
      _problem(MailProblemCode.conflict),
    );
    expect(
      () => _merge(synchronized: [_sync(longId)]),
      _problem(MailProblemCode.conflict),
    );
    expect(
      () => _merge(browsing: [_browse('folder', name: longName)]),
      _problem(MailProblemCode.conflict),
    );
    expect(
      () => _merge(synchronized: [_sync('folder', name: longName)]),
      _problem(MailProblemCode.conflict),
    );
  });

  test(
    'aggregate metadata is bounded even when individual names are valid',
    () {
      final name = 'n' * 4096;
      expect(
        () => _merge(
          browsing: [
            for (var i = 0; i < 300; i++) _browse('folder-$i', name: name),
          ],
          synchronized: [
            for (var i = 0; i < 300; i++) _sync('folder-$i', name: name),
          ],
        ),
        _problem(MailProblemCode.quotaExceeded),
      );
    },
  );

  test('valid Unicode names and maximum-sized individual metadata survive', () {
    final id = 'i' * 1024;
    final name = 'صندوق' * 819;
    final result = _merge(
      browsing: [_browse(id, name: name)],
      synchronized: [_sync(id, name: 'Posteingang — البريد')],
    );
    expect(result.single.id.value, id);
    expect(result.single.browse!.mailbox.displayName, name);
    expect(result.single.mailbox.displayName, 'Posteingang — البريد');
  });
}

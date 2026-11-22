import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_office_studio/studio_mail_archive_destination.dart';
import 'package:quds_office_studio/studio_mail_archive_settings_store.dart';

final _profile = MailProfileId('archive-owner', hostId: 'studio');
final _owner = MailAccountId('stable-local-owner', profile: _profile);
final _provider = MailAccountId(
  'ephemeral-provider-session',
  profile: MailProfileId('connection', hostId: 'transport'),
);
final _foreign = MailAccountId('other-account', profile: _profile);

MailArchiveDestinationSettings _settings({
  MailAccountId? owner,
  String? destination = ' Archive ',
  int revision = 7,
}) {
  final account = owner ?? _owner;
  return MailArchiveDestinationSettings(
    account: account,
    revision: revision,
    destination: destination == null
        ? null
        : MailMailboxId(destination, account: account),
  );
}

MailMailbox _folder(
  String id, {
  MailAccountId? account,
  String name = 'Archive',
  bool label = false,
}) => MailMailbox(
  id: MailMailboxId(id, account: account ?? _provider),
  displayName: name,
  isLabel: label,
);

Matcher _failure(StudioMailArchiveDestinationFailure failure) =>
    isA<StudioMailArchiveDestinationException>().having(
      (error) => error.failure,
      'failure',
      failure,
    );

final class _Store implements StudioMailArchiveSettingsStore {
  _Store(this.settings);

  MailArchiveDestinationSettings settings;
  MailAccountId owner = _owner;
  int loads = 0;
  Future<MailArchiveDestinationSettings> Function()? read;

  @override
  MailAccountId get account => owner;

  @override
  Future<MailArchiveDestinationSettings> loadArchiveSettings() async {
    loads++;
    return read == null ? settings : await read!();
  }

  @override
  Future<MailArchiveDestinationSettings> saveArchiveSettings(
    MailArchiveDestinationSettings settings, {
    required int expectedRevision,
  }) => throw StateError('Resolution must never write preferences.');
}

void main() {
  test('reads only the current stable account owner', () async {
    final expected = _settings();
    final store = _Store(expected);
    final loaded = await readStudioMailArchiveSettings(
      store,
      isCurrent: () => true,
    );
    expect(loaded.account, _owner);
    expect(loaded.destination!.account, _owner);
    expect(loaded.destination!.value, ' Archive ');
    expect(loaded.revision, 7);
    expect(store.loads, 1);
  });

  test('already stale reader never enters storage', () async {
    final store = _Store(_settings());
    await expectLater(
      readStudioMailArchiveSettings(store, isCurrent: () => false),
      throwsA(_failure(StudioMailArchiveDestinationFailure.stale)),
    );
    expect(store.loads, 0);
  });

  for (final changeOwner in [false, true]) {
    test(
      'rejects a late settings read after ${changeOwner ? 'owner' : 'session'} change',
      () async {
        final pending = Completer<MailArchiveDestinationSettings>();
        final store = _Store(_settings())..read = () => pending.future;
        var current = true;
        final result = readStudioMailArchiveSettings(
          store,
          isCurrent: () => current,
        );
        final assertion = expectLater(
          result,
          throwsA(_failure(StudioMailArchiveDestinationFailure.stale)),
        );
        if (changeOwner) {
          store.owner = _foreign;
        } else {
          current = false;
        }
        pending.complete(_settings());
        await assertion;
        expect(store.loads, 1);
      },
    );
  }

  for (final invalid in <String, MailArchiveDestinationSettings>{
    'foreign owner': _settings(owner: _foreign),
    'provider-scoped destination': MailArchiveDestinationSettings(
      account: _owner,
      destination: MailMailboxId('Archive', account: _provider),
    ),
    'negative revision': _settings(revision: -1),
    'malformed destination': _settings(destination: 'bad\u0085route'),
  }.entries) {
    test('refuses ${invalid.key} returned by storage', () async {
      await expectLater(
        readStudioMailArchiveSettings(
          _Store(invalid.value),
          isCurrent: () => true,
        ),
        throwsA(_failure(StudioMailArchiveDestinationFailure.unavailable)),
      );
    });
  }

  test(
    'saved local route resolves to the exact live provider identity',
    () async {
      final exact = _folder(' Archive ', name: 'Renamed destination');
      final result = await resolveStudioMailSavedArchiveDestination(
        settings: _settings(),
        providerAccount: _provider,
        loadFolders: () async => [
          _folder('Archive'),
          _folder(' archive '),
          exact,
        ],
        isCurrent: () => true,
      );
      expect(result, same(exact));
      expect(result!.id.account, _provider);
      expect(result.id.account, isNot(_owner));
      expect(result.displayName, 'Renamed destination');
    },
  );

  test(
    'an unset preference leaves provider default resolution to the host',
    () async {
      var catalogReads = 0;
      final result = await resolveStudioMailSavedArchiveDestination(
        settings: _settings(destination: null),
        providerAccount: _provider,
        loadFolders: () async {
          catalogReads++;
          return [_folder('Archive')];
        },
        isCurrent: () => true,
      );
      expect(result, isNull);
      expect(catalogReads, 0);
    },
  );

  for (final nearMatch in ['Archive', ' archive ', ' Archive', 'Archive ']) {
    test('missing exact route never falls back to $nearMatch', () async {
      await expectLater(
        resolveStudioMailSavedArchiveDestination(
          settings: _settings(),
          providerAccount: _provider,
          loadFolders: () async => [_folder(nearMatch, name: ' Archive ')],
          isCurrent: () => true,
        ),
        throwsA(_failure(StudioMailArchiveDestinationFailure.missing)),
      );
    });
  }

  test(
    'a saved label is unavailable as an ordinary Archive destination',
    () async {
      await expectLater(
        resolveStudioMailSavedArchiveDestination(
          settings: _settings(),
          providerAccount: _provider,
          loadFolders: () async => [_folder(' Archive ', label: true)],
          isCurrent: () => true,
        ),
        throwsA(_failure(StudioMailArchiveDestinationFailure.missing)),
      );
    },
  );

  test(
    'catalog excludes labels but preserves all ordinary exact identities',
    () {
      final normal = _folder('Archive');
      final whitespace = _folder(' Archive ');
      final listed = studioMailArchiveDestinations([
        _folder('important', label: true),
        normal,
        whitespace,
      ], _provider);
      expect(listed, [normal, whitespace]);
      expect(() => listed.add(_folder('extra')), throwsUnsupportedError);
    },
  );

  for (final malformed in <String, List<MailMailbox>>{
    'duplicate route': [
      _folder(' Archive '),
      _folder(' Archive ', name: 'Other'),
    ],
    'duplicate label route': [
      _folder(' Archive '),
      _folder(' Archive ', label: true),
    ],
    'foreign folder after exact match': [
      _folder(' Archive '),
      _folder('foreign', account: _foreign),
    ],
    'foreign label': [
      _folder(' Archive '),
      _folder('label', account: _foreign, label: true),
    ],
    'C1 control': [_folder(' Archive '), _folder('bad\u0085route')],
    'unpaired surrogate': [_folder(' Archive '), _folder('bad\ud800')],
    'oversized ID': [_folder(' Archive '), _folder('x' * 1025)],
  }.entries) {
    test('refuses complete malformed catalog: ${malformed.key}', () async {
      expect(
        () => studioMailArchiveDestinations(malformed.value, _provider),
        throwsA(_failure(StudioMailArchiveDestinationFailure.unavailable)),
      );
      await expectLater(
        resolveStudioMailSavedArchiveDestination(
          settings: _settings(),
          providerAccount: _provider,
          loadFolders: () async => malformed.value,
          isCurrent: () => true,
        ),
        throwsA(_failure(StudioMailArchiveDestinationFailure.unavailable)),
      );
    });
  }

  test('catalog bound accepts 10000 identities and rejects 10001', () {
    final folders = [
      for (var index = 0; index < 10000; index++) _folder('$index'),
    ];
    expect(studioMailArchiveDestinations(folders, _provider), hasLength(10000));
    expect(
      () => studioMailArchiveDestinations([
        ...folders,
        _folder('extra'),
      ], _provider),
      throwsA(_failure(StudioMailArchiveDestinationFailure.unavailable)),
    );
  });

  test('stale resolution does not request a provider catalog', () async {
    var loads = 0;
    await expectLater(
      resolveStudioMailSavedArchiveDestination(
        settings: _settings(),
        providerAccount: _provider,
        loadFolders: () async {
          loads++;
          return [_folder(' Archive ')];
        },
        isCurrent: () => false,
      ),
      throwsA(_failure(StudioMailArchiveDestinationFailure.stale)),
    );
    expect(loads, 0);
  });

  test('late folder catalog cannot authorize a retired session', () async {
    final pending = Completer<List<MailMailbox>>();
    var current = true;
    final result = resolveStudioMailSavedArchiveDestination(
      settings: _settings(),
      providerAccount: _provider,
      loadFolders: () => pending.future,
      isCurrent: () => current,
    );
    final assertion = expectLater(
      result,
      throwsA(_failure(StudioMailArchiveDestinationFailure.stale)),
    );
    current = false;
    pending.complete([_folder(' Archive ')]);
    await assertion;
  });

  test(
    'unchanged revision and destination pass the pre-dispatch recheck',
    () async {
      final store = _Store(_settings());
      await verifyStudioMailArchiveSettings(
        store,
        _settings(),
        isCurrent: () => true,
      );
      expect(store.loads, 1);
    },
  );

  for (final change in <String, MailArchiveDestinationSettings>{
    'same route but newer revision': _settings(revision: 8),
    'different route at same revision': _settings(destination: 'Other'),
    'clear at same revision': _settings(destination: null),
    'clear with newer revision': _settings(destination: null, revision: 8),
  }.entries) {
    test('pre-dispatch recheck refuses ${change.key}', () async {
      await expectLater(
        verifyStudioMailArchiveSettings(
          _Store(change.value),
          _settings(),
          isCurrent: () => true,
        ),
        throwsA(_failure(StudioMailArchiveDestinationFailure.changed)),
      );
    });
  }

  test(
    'pre-dispatch recheck rejects a session lost while storage is reading',
    () async {
      final pending = Completer<MailArchiveDestinationSettings>();
      final store = _Store(_settings())..read = () => pending.future;
      var current = true;
      final result = verifyStudioMailArchiveSettings(
        store,
        _settings(),
        isCurrent: () => current,
      );
      final assertion = expectLater(
        result,
        throwsA(_failure(StudioMailArchiveDestinationFailure.stale)),
      );
      current = false;
      pending.complete(_settings());
      await assertion;
    },
  );

  test('diagnostic text contains no route or account identity', () {
    for (final reason in StudioMailArchiveDestinationFailure.values) {
      final text = StudioMailArchiveDestinationException(reason).toString();
      expect(text, 'Archive destination is unavailable.');
      expect(text, isNot(contains(_owner.value)));
      expect(text, isNot(contains(' Archive ')));
    }
  });
}

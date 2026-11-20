import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_store/quds_mail_store.dart';
import 'package:test/test.dart';

T _value<T>(MailResult<T> result) {
  expect(result, isA<MailSuccess<T>>());
  return (result as MailSuccess<T>).value;
}

void _problem<T>(MailResult<T> result, MailProblemCode code) {
  expect(result, isA<MailFailure<T>>());
  expect((result as MailFailure<T>).problem.code, code);
}

final _profile = MailProfileId('catalog', hostId: 'mail-test');
final _account = MailAccountId('account', profile: _profile);

MailDraft _draft(
  String id, {
  int revision = 0,
  MailAccountId? account,
  bool cleared = false,
  bool legacy = false,
  bool attachment = false,
}) => MailDraft(
  id: id,
  account: account ?? _account,
  revision: revision,
  envelope: cleared ? MailEnvelope() : MailEnvelope(subject: 'Subject $id'),
  body: cleared ? const MailBody() : const MailBody(plainText: 'private body'),
  editorState: legacy
      ? null
      : cleared
      ? MailDraftEditorState(isCleared: true)
      : MailDraftEditorState(
          to: 'unfinished <',
          cc: 'visible@example.test',
          bcc: 'hidden@example.test',
          submissionUncertain: true,
        ),
  attachments: attachment
      ? [
          MailAttachment(
            partPath: 'file',
            mediaType: 'application/octet-stream',
            displayName: 'file.bin',
            content: MailBytes(Uint8List.fromList([0, 1, 128, 255])),
          ),
        ]
      : const [],
);

void main() {
  late NativeDatabase executor;
  late SqliteMailRepository store;

  setUp(() async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    executor = NativeDatabase.memory();
    store = _value(
      await SqliteMailRepository.open(executor: executor, profile: _profile),
    );
    _value(
      await store.createAccount(
        MailStoreAccount(
          id: _account,
          provider: MailProviderKind.imap,
          displayName: 'Account',
        ),
      ),
    );
  });

  tearDown(() => store.close());

  test('bounded pages preserve order and expose every continuation', () async {
    for (final id in ['c', 'a', 'b']) {
      _value(await store.saveDraft(_draft(id), expectedRevision: null));
    }
    final first = _value(await store.listDrafts(_account, limit: 2));
    expect(first.drafts.map((item) => item.id), ['a', 'b']);
    expect(first.nextAfterId, 'b');
    expect(first.drafts.first.envelope.subject, 'Subject a');
    expect(first.drafts.first.editorState!.to, 'unfinished <');
    expect(first.drafts.first.editorState!.submissionUncertain, isTrue);
    final second = _value(
      await store.listDrafts(_account, limit: 2, afterId: first.nextAfterId),
    );
    expect(second.drafts.map((item) => item.id), ['c']);
    expect(second.nextAfterId, isNull);
    expect(() => first.drafts.clear(), throwsUnsupportedError);
  });

  test('tombstone history does not consume live catalog page slots', () async {
    for (var index = 0; index < 20; index++) {
      _value(
        await store.saveDraft(
          _draft('old-${index.toString().padLeft(2, '0')}', cleared: true),
          expectedRevision: null,
        ),
      );
    }
    _value(await store.saveDraft(_draft('z-live'), expectedRevision: null));
    final page = _value(await store.listDrafts(_account, limit: 1));
    expect(page.drafts.single.id, 'z-live');
    expect(page.nextAfterId, isNull);
  });

  test(
    'summary works without reading corrupt attachment payload bytes',
    () async {
      _value(
        await store.saveDraft(
          _draft('file', attachment: true),
          expectedRevision: null,
        ),
      );
      await executor.runCustom('UPDATE blobs SET data=?', [
        Uint8List.fromList([42, 42, 42, 42]),
      ]);
      final summary = _value(await store.listDrafts(_account)).drafts.single;
      expect(summary.attachmentCount, 1);
      expect(summary.id, 'file');
      _problem(
        await store.loadDraft(_account, 'file'),
        MailProblemCode.storageFailure,
      );
    },
  );

  test(
    'old drafts without editor state remain visible at shared-store boundary',
    () async {
      _value(
        await store.saveDraft(
          _draft('legacy', legacy: true),
          expectedRevision: null,
        ),
      );
      final summary = _value(await store.listDrafts(_account)).drafts.single;
      expect(summary.editorState, isNull);
      expect(summary.envelope.subject, 'Subject legacy');
    },
  );

  test(
    'catalog rejects malformed metadata with a content-free failure',
    () async {
      _value(await store.saveDraft(_draft('corrupt'), expectedRevision: null));
      await executor.runCustom('UPDATE drafts SET data=? WHERE id=?', [
        '{"version":99,"private":"sensitive-content"}',
        'corrupt',
      ]);
      final result = await store.listDrafts(_account);
      _problem(result, MailProblemCode.storageFailure);
      expect(
        (result as MailFailure<MailDraftPage>).problem.toString(),
        isNot(contains('sensitive-content')),
      );
    },
  );

  test(
    'unknown and nonempty cleared rows are not hidden as tombstones',
    () async {
      _value(
        await store.saveDraft(
          _draft('corrupt', cleared: true),
          expectedRevision: null,
        ),
      );
      final rows = await executor.runSelect(
        'SELECT data FROM drafts WHERE id=?',
        ['corrupt'],
      );
      final Object? decoded = jsonDecode(rows.single['data']! as String);
      final data = decoded! as Map<String, Object?>;
      final body = data['body']! as Map<String, Object?>;
      body['plainText'] = 'retained content';
      await executor.runCustom('UPDATE drafts SET data=? WHERE id=?', [
        jsonEncode(data),
        'corrupt',
      ]);
      _problem(
        await store.listDrafts(_account),
        MailProblemCode.storageFailure,
      );
      body['plainText'] = null;
      data['version'] = 3;
      await executor.runCustom('UPDATE drafts SET data=? WHERE id=?', [
        jsonEncode(data),
        'corrupt',
      ]);
      _problem(
        await store.listDrafts(_account),
        MailProblemCode.storageFailure,
      );
    },
  );

  test('noncanonical empty metadata retains a usable continuation', () async {
    _value(
      await store.saveDraft(_draft('a', cleared: true), expectedRevision: null),
    );
    _value(await store.saveDraft(_draft('b'), expectedRevision: null));
    await executor.runCustom("UPDATE drafts SET data=' ' || data WHERE id=?", [
      'a',
    ]);
    final first = _value(await store.listDrafts(_account, limit: 1));
    expect(first.drafts, isEmpty);
    expect(first.nextAfterId, 'a');
    final second = _value(
      await store.listDrafts(_account, afterId: first.nextAfterId, limit: 1),
    );
    expect(second.drafts.single.id, 'b');
  });

  test('account and profile scoping apply before returning metadata', () async {
    final other = MailAccountId('other', profile: _profile);
    _value(
      await store.createAccount(
        MailStoreAccount(
          id: other,
          provider: MailProviderKind.imap,
          displayName: 'Other',
        ),
      ),
    );
    _value(await store.saveDraft(_draft('same'), expectedRevision: null));
    _value(
      await store.saveDraft(
        _draft('same', account: other),
        expectedRevision: null,
      ),
    );
    expect(
      _value(await store.listDrafts(_account)).drafts.single.account,
      _account,
    );
    expect(_value(await store.listDrafts(other)).drafts.single.account, other);
    final foreign = MailAccountId(
      'account',
      profile: MailProfileId('foreign', hostId: 'mail-test'),
    );
    _problem(await store.listDrafts(foreign), MailProblemCode.permissionDenied);
    _value(await store.removeAccount(other));
    _problem(await store.listDrafts(other), MailProblemCode.unavailable);
  });

  test('invalid page bounds and cursors fail explicitly', () async {
    for (final limit in [-1, 0, 101]) {
      _problem(
        await store.listDrafts(_account, limit: limit),
        MailProblemCode.invalidInput,
      );
    }
    for (final cursor in ['', 'bad\nidentity']) {
      _problem(
        await store.listDrafts(_account, afterId: cursor),
        MailProblemCode.invalidInput,
      );
    }
    _problem(
      await store.saveDraft(
        _draft('invalid'),
        expectedRevision: null,
        maxActiveDrafts: 0,
      ),
      MailProblemCode.invalidInput,
    );
  });

  test(
    'capacity is atomic, allows edits, and reopens after a tombstone',
    () async {
      final writes = await Future.wait([
        store.saveDraft(
          _draft('a'),
          expectedRevision: null,
          maxActiveDrafts: 1,
        ),
        store.saveDraft(
          _draft('b'),
          expectedRevision: null,
          maxActiveDrafts: 1,
        ),
      ]);
      expect(writes.whereType<MailSuccess<MailUnit>>(), hasLength(1));
      expect(
        writes.whereType<MailFailure<MailUnit>>().single.problem.code,
        MailProblemCode.quotaExceeded,
      );
      final id = _value(await store.listDrafts(_account)).drafts.single.id;
      _value(
        await store.saveDraft(
          _draft(id, revision: 1),
          expectedRevision: 0,
          maxActiveDrafts: 1,
        ),
      );
      _value(
        await store.saveDraft(
          _draft(id, revision: 2, cleared: true),
          expectedRevision: 1,
          maxActiveDrafts: 1,
        ),
      );
      _value(
        await store.saveDraft(
          _draft('new'),
          expectedRevision: null,
          maxActiveDrafts: 1,
        ),
      );
      _problem(
        await store.saveDraft(
          _draft(id, revision: 3),
          expectedRevision: 2,
          maxActiveDrafts: 1,
        ),
        MailProblemCode.quotaExceeded,
      );
      expect(_value(await store.listDrafts(_account)).drafts.single.id, 'new');
    },
  );

  test('existing over-limit catalogs remain pageable and editable', () async {
    for (var index = 0; index < 103; index++) {
      _value(
        await store.saveDraft(
          _draft('draft-${index.toString().padLeft(3, '0')}'),
          expectedRevision: null,
        ),
      );
    }
    final first = _value(await store.listDrafts(_account));
    expect(first.drafts, hasLength(100));
    expect(first.nextAfterId, isNotNull);
    final rest = _value(
      await store.listDrafts(_account, afterId: first.nextAfterId),
    );
    expect(rest.drafts, hasLength(3));
    expect(rest.nextAfterId, isNull);
    _value(
      await store.saveDraft(
        _draft('draft-000', revision: 1),
        expectedRevision: 0,
        maxActiveDrafts: 100,
      ),
    );
    _problem(
      await store.saveDraft(
        _draft('extra'),
        expectedRevision: null,
        maxActiveDrafts: 100,
      ),
      MailProblemCode.quotaExceeded,
    );
  });
}

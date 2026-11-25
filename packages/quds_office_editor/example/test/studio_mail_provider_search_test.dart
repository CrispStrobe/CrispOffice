import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_office_studio/studio_mail_provider_search.dart';
import 'package:quds_office_studio/studio_mail_server_search.dart';

final _profile = MailProfileId('search-profile', hostId: 'studio');
final _account = MailAccountId('account', profile: _profile);
final _mailbox = MailMailboxId('inbox', account: _account);

final class _Search implements MailProviderSearch {
  int calls = 0;
  Future<MailResult<MailProviderSearchResult>> Function(
    MailProviderSearchRequest,
    MailOperationLease,
  )?
  handler;

  @override
  Set<MailProviderSearchField> get searchFields => const {
    MailProviderSearchField.subject,
    MailProviderSearchField.from,
  };

  @override
  Future<MailResult<MailProviderSearchResult>> search(
    MailProviderSearchRequest request, {
    required MailOperationLease lease,
  }) async {
    calls++;
    return handler?.call(request, lease) ??
        MailSuccess(
          MailProviderSearchResult(
            mailbox: request.mailbox,
            messages: const [],
            hasMore: false,
          ),
        );
  }
}

MailProviderSearchRequest _request({
  MailMailboxId? mailbox,
  MailProviderSearchField field = MailProviderSearchField.subject,
}) => studioMailProviderSearchRequest(
  mailbox: mailbox ?? _mailbox,
  field: field,
  range: StudioMailServerSearchRange.anyTime,
  query: 'invoice',
);

Matcher _failure(MailProblemCode code) => isA<StudioMailProviderSearchFailure>()
    .having((error) => error.code, 'code', code);

void main() {
  test('range uses one exact folder and a portable UTC day boundary', () {
    final request = studioMailProviderSearchRequest(
      mailbox: _mailbox,
      field: MailProviderSearchField.from,
      range: StudioMailServerSearchRange.last7Days,
      query: '  sender@example.test  ',
      now: DateTime.parse('2026-11-25T01:30:45.123456+02:00'),
    );
    expect(request.isValid, isTrue);
    expect(request.mailbox, _mailbox);
    expect(request.field, MailProviderSearchField.from);
    expect(request.query, 'sender@example.test');
    expect(request.receivedAfter, DateTime.utc(2026, 11, 17));
    expect(request.receivedBefore, isNull);
    expect(request.maxResults, 50);
    expect(_request().receivedAfter, isNull);
  });

  test(
    'unsupported fields and foreign accounts fail before provider IO',
    () async {
      final search = _Search();
      final session = MailAccountSession(_account);
      addTearDown(session.dispose);
      await expectLater(
        runStudioMailProviderSearch(
          provider: search,
          request: _request(field: MailProviderSearchField.body),
          lease: session.begin(),
        ),
        throwsA(_failure(MailProblemCode.unsupported)),
      );
      final foreign = MailMailboxId(
        'inbox',
        account: MailAccountId('other', profile: _profile),
      );
      await expectLater(
        runStudioMailProviderSearch(
          provider: search,
          request: _request(mailbox: foreign),
          lease: session.begin(),
        ),
        throwsA(_failure(MailProblemCode.invalidInput)),
      );
      expect(search.calls, 0);
    },
  );

  test('cancelled lease does not call provider', () async {
    final search = _Search();
    final session = MailAccountSession(_account);
    addTearDown(session.dispose);
    final source = MailCancellationSource();
    final lease = session.begin(cancellation: source.token);
    source.cancel();
    await expectLater(
      runStudioMailProviderSearch(
        provider: search,
        request: _request(),
        lease: lease,
      ),
      throwsA(isA<MailCancelled>()),
    );
    expect(search.calls, 0);
  });

  test('account invalidation discards an in-flight search snapshot', () async {
    final search = _Search();
    final session = MailAccountSession(_account);
    addTearDown(session.dispose);
    final pending = Completer<MailResult<MailProviderSearchResult>>();
    search.handler = (_, _) => pending.future;
    final result = runStudioMailProviderSearch(
      provider: search,
      request: _request(),
      lease: session.begin(),
    );
    final rejected = expectLater(result, throwsA(isA<MailCancelled>()));
    session.invalidate();
    pending.complete(
      MailSuccess(
        MailProviderSearchResult(
          mailbox: _mailbox,
          messages: const [],
          hasMore: false,
        ),
      ),
    );
    await rejected;
  });

  test('different folder and over-budget snapshots are rejected', () async {
    final search = _Search();
    final session = MailAccountSession(_account);
    addTearDown(session.dispose);
    search.handler = (_, _) async => MailSuccess(
      MailProviderSearchResult(
        mailbox: MailMailboxId('another-folder', account: _account),
        messages: const [],
        hasMore: false,
      ),
    );
    await expectLater(
      runStudioMailProviderSearch(
        provider: search,
        request: _request(),
        lease: session.begin(),
      ),
      throwsA(_failure(MailProblemCode.conflict)),
    );
    search.handler = (_, _) async => MailSuccess(
      MailProviderSearchResult(
        mailbox: _mailbox,
        messages: [
          for (var index = 0; index < 51; index++)
            MailHeaderRecord(
              id: MailMessageId('message-$index'),
              remote: MailOpaqueIdentity(
                account: _account,
                provider: MailProviderKind.graph,
                value: 'message-$index',
              ),
              envelope: MailEnvelope(subject: 'Invoice'),
            ),
        ],
        hasMore: true,
      ),
    );
    await expectLater(
      runStudioMailProviderSearch(
        provider: search,
        request: _request(),
        lease: session.begin(),
      ),
      throwsA(_failure(MailProblemCode.conflict)),
    );
  });

  test('provider failures preserve redacted typed feedback', () async {
    final search = _Search()
      ..handler = (_, _) async => const MailFailure(
        MailProblem(MailProblemCode.authenticationRequired),
      );
    final session = MailAccountSession(_account);
    addTearDown(session.dispose);
    await expectLater(
      runStudioMailProviderSearch(
        provider: search,
        request: _request(),
        lease: session.begin(),
      ),
      throwsA(_failure(MailProblemCode.authenticationRequired)),
    );
  });
}

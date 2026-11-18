@TestOn('node')
library;

import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_store/src/browser_problem.dart';
import 'package:quds_mail_store/src/errors.dart';
import 'package:sqlite3/common.dart';
import 'package:test/test.dart';
import 'package:web/web.dart' as web;

void main() {
  test('DOM storage quota maps by name without copying private error text', () {
    final problem = mailBrowserStoreProblem(
      web.DOMException(
        'private message and filesystem details',
        'QuotaExceededError',
      ),
    );
    expect(problem.code, MailProblemCode.quotaExceeded);
    expect(problem.toString(), isNot(contains('private message')));
  });

  test('blocked and aborted browser storage have typed results', () {
    for (final name in ['SecurityError', 'NotAllowedError']) {
      expect(
        mailBrowserStoreProblem(web.DOMException('sensitive', name)).code,
        MailProblemCode.permissionDenied,
      );
    }
    expect(
      mailBrowserStoreProblem(web.DOMException('sensitive', 'AbortError')).code,
      MailProblemCode.cancelled,
    );
    expect(
      mailBrowserStoreProblem(
        web.DOMException('sensitive', 'UnknownError'),
      ).code,
      MailProblemCode.unavailable,
    );
  });

  test('typed SQLite and domain failures retain their classification', () {
    expect(
      mailBrowserStoreProblem(
        SqliteException(
          extendedResultCode: 13,
          message: 'sensitive',
          causingStatement: 'private SQL',
          parametersToStatement: ['private content'],
        ),
      ).code,
      MailProblemCode.quotaExceeded,
    );
    expect(
      mailBrowserStoreProblem(
        const MailStoreStorageException(MailProblemCode.conflict),
      ).code,
      MailProblemCode.conflict,
    );
    expect(
      mailBrowserStoreProblem(StateError('private')).code,
      MailProblemCode.unavailable,
    );
  });
}

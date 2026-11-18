import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:test/test.dart';

void main() {
  late MailAccountSession session;
  setUp(() {
    session = MailAccountSession(
      MailAccountId('a', profile: MailProfileId('p', hostId: 'office')),
    );
  });

  test('invalidate rejects old callbacks but allows a new generation', () {
    final old = session.begin();
    old.checkCurrent();
    session.invalidate();
    expect(old.isCurrent, isFalse);
    expect(
      old.checkCurrent,
      throwsA(
        isA<MailCancelled>().having(
          (error) => error.reason,
          'reason',
          MailCancellationReason.accountChanged,
        ),
      ),
    );
    expect(session.begin().isCurrent, isTrue);
  });

  test('dispose invalidates all callbacks and cannot reopen a session', () {
    final first = session.begin();
    final second = session.begin();
    session.dispose();
    session.dispose();
    expect(first.isCurrent, isFalse);
    expect(second.isCurrent, isFalse);
    expect(session.begin, throwsA(isA<MailCancelled>()));
    expect(
      first.checkCurrent,
      throwsA(
        isA<MailCancelled>().having(
          (error) => error.reason,
          'reason',
          MailCancellationReason.disposed,
        ),
      ),
    );
  });

  test('explicit cancellation is typed and keeps the first reason', () {
    final source = MailCancellationSource();
    final lease = session.begin(cancellation: source.token);
    source.cancel(MailCancellationReason.budgetExpired);
    source.cancel(MailCancellationReason.user);
    expect(source.token.isCancelled, isTrue);
    expect(source.token.reason, MailCancellationReason.budgetExpired);
    expect(lease.isCurrent, isFalse);
    expect(source.token.throwIfCancelled, throwsA(isA<MailCancelled>()));
    expect(lease.checkCurrent, throwsA(isA<MailCancelled>()));
  });
}

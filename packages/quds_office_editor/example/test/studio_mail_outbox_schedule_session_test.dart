import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_office_studio/studio_mail_outbox_schedule_session.dart';

final _account = MailAccountId(
  'one',
  profile: MailProfileId('profile', hostId: 'schedule-session-test'),
);
final _start = DateTime.utc(2026, 11, 21, 10);

MailOutboxEntry _queued(String id, {MailAccountId? account}) =>
    MailOutboxEntry.queued(
      id: id,
      now: _start,
      prepared: MailPreparedMessage(
        account: account ?? _account,
        draftId: 'draft-$id',
        draftRevision: 1,
        wire: MailBytes(Uint8List.fromList([1, 2, 3])),
        envelope: MailTransportEnvelope(
          sender: 'sender@example.test',
          recipients: ['reader@example.test'],
        ),
      ),
    );

MailOutboxEntry _scheduled(
  String id, {
  Duration delay = const Duration(seconds: 10),
}) => _queued(id).schedule(sendNotBefore: _start.add(delay), now: _start);

void main() {
  late DateTime now;
  late Duration elapsed;
  late StudioMailOutboxScheduleSession session;

  setUp(() {
    now = _start;
    elapsed = Duration.zero;
    session = StudioMailOutboxScheduleSession(
      clock: () => now,
      elapsed: () => elapsed,
    );
  });

  test('reading overdue entries does not grant foreground permission', () {
    final entry = _scheduled('one');
    now = _start.add(const Duration(days: 1));
    session.reconcile([entry]);
    expect(session.takeDue([entry]), isNull);
    expect(session.isEmpty, isTrue);
    session.arm(entry);
    expect(session.takeDue([entry]), same(entry));
    expect(session.takeDue([entry]), isNull);
  });

  test('the full undo window survives a forward wall-clock jump', () {
    final entry = _scheduled('one');
    session.arm(entry, minimumWait: const Duration(seconds: 10));
    now = _start.add(const Duration(days: 1));
    elapsed = const Duration(seconds: 9);
    expect(session.remaining(entry), const Duration(seconds: 1));
    expect(session.takeDue([entry]), isNull);
    elapsed = const Duration(seconds: 10);
    expect(session.takeDue([entry]), same(entry));
  });

  test('a backward wall-clock jump postpones an elapsed undo window', () {
    final entry = _scheduled('one');
    session.arm(entry, minimumWait: const Duration(seconds: 10));
    elapsed = const Duration(minutes: 1);
    now = _start.subtract(const Duration(hours: 1));
    expect(session.takeDue([entry]), isNull);
    now = entry.sendNotBefore!;
    expect(session.takeDue([entry]), same(entry));
  });

  test('clock equality is due and a due entry is consumed only once', () {
    final entry = _scheduled('one');
    session.arm(entry);
    now = entry.sendNotBefore!.subtract(const Duration(microseconds: 1));
    expect(session.takeDue([entry]), isNull);
    now = entry.sendNotBefore!;
    expect(session.takeDue([entry]), same(entry));
    expect(session.takeDue([entry]), isNull);
  });

  test('changing a schedule away and back requires explicit rearming', () {
    final entry = _scheduled('one');
    session.arm(entry);
    final other = entry.schedule(
      sendNotBefore: _start.add(const Duration(hours: 2)),
      now: _start,
    );
    final restored = other.schedule(
      sendNotBefore: entry.sendNotBefore,
      now: _start,
    );
    now = entry.sendNotBefore!;
    expect(session.takeDue([restored]), isNull);
    expect(session.isEmpty, isTrue);
    session.arm(restored);
    expect(session.takeDue([restored]), same(restored));
  });

  test('account collisions cannot inherit another account permission', () {
    final entry = _scheduled('one');
    session.arm(entry);
    final other = _queued(
      'one',
      account: MailAccountId('two', profile: _account.profile),
    ).schedule(sendNotBefore: entry.sendNotBefore, now: _start);
    now = entry.sendNotBefore!;
    expect(session.takeDue([other]), isNull);
    expect(session.isEmpty, isTrue);
  });

  test('pause, deletion and cancellation revoke pending permission', () {
    final entry = _scheduled('one');
    session.arm(entry);
    session.pause(entry);
    expect(session.isEmpty, isTrue);
    session.arm(entry);
    session.reconcile([]);
    expect(session.isEmpty, isTrue);
    session.arm(entry);
    session.reconcile([entry.cancel(now: _start)]);
    expect(session.isEmpty, isTrue);
    session.arm(entry);
    session.pauseAll();
    expect(session.isEmpty, isTrue);
  });

  test('two due entries are taken in deadline then stable identity order', () {
    final later = _scheduled('a', delay: const Duration(minutes: 2));
    final first = _scheduled('b');
    final second = _scheduled('c');
    final entries = [later, second, first];
    for (final entry in entries) {
      session.arm(entry);
    }
    now = _start.add(const Duration(hours: 1));
    expect(session.takeDue(entries), same(first));
    expect(session.takeDue(entries), same(second));
    expect(session.takeDue(entries), same(later));
    expect(session.takeDue(entries), isNull);
  });

  test(
    'ordinary queues and retryable or uncertain attempts cannot be armed',
    () {
      final entry = _scheduled('one');
      final attempt = entry.beginAttempt(
        attemptId: 'attempt',
        now: entry.sendNotBefore!,
      );
      for (final outcome in [
        MailSubmissionOutcome.retryableFailure,
        MailSubmissionOutcome.uncertain,
      ]) {
        final completed = attempt.complete(
          MailSubmissionResult(attemptId: 'attempt', outcome: outcome),
          now: entry.sendNotBefore!,
        );
        expect(() => session.arm(completed), throwsStateError);
      }
      expect(() => session.arm(_queued('one')), throwsStateError);
      expect(
        () => session.arm(entry, minimumWait: const Duration(seconds: -1)),
        throwsStateError,
      );
    },
  );
}

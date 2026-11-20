import 'package:drift/native.dart';
import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_store/quds_mail_store.dart';

/// Synchronous native SQLite for another package's widget tests. The production
/// repository and transactions are unchanged; the native background-isolate
/// opener is qualified separately under a real clock by storage tests.
Future<SqliteMailRepository> openOutboxWidgetDatabase({
  required MailProfileId profile,
  MailStoreFaultInjector? faultInjector,
}) async => switch (await SqliteMailRepository.open(
  executor: NativeDatabase.memory(),
  profile: profile,
  faultInjector: faultInjector,
)) {
  MailSuccess<SqliteMailRepository>(:final value) => value,
  MailFailure<SqliteMailRepository>(:final problem) => throw StateError(
    'Widget repository failed: ${problem.code.name}',
  ),
};

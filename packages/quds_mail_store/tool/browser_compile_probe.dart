import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_store/quds_mail_store_web.dart';

/// Compile-only probe. A successful compile is not browser persistence evidence.
Future<void> main() async {
  final result = await openBrowserMailStore(
    profile: MailProfileId('compile-probe', hostId: 'office'),
    storageNamespace: 'mail-qualification',
    sqlite3Uri: Uri.parse('/assets/sqlite3.wasm'),
    driftWorkerUri: Uri.parse('/assets/mail_store_worker.js'),
  );
  if (result case MailSuccess(:final value)) await value.close();
}

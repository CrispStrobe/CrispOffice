import 'dart:js_interop';

// Public exception API is stable; Drift marks its versioned protocol experimental.
// Both worker and client use the exact pinned Drift dependency.
// ignore: experimental_member_use
import 'package:drift/remote.dart';
import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:sqlite3/common.dart';
import 'package:web/web.dart' as web;

import 'errors.dart';

/// Inspect only typed exception identities and standard DOM error names.
/// Browser error messages may contain private database paths or content.
MailProblem mailBrowserStoreProblem(Object error) {
  if (error is MailStoreStorageException ||
      error is SqliteException ||
      error is DriftRemoteException) {
    return mailStoreProblem(error);
  }
  if (error.isA<web.DOMException>()) {
    final name = (error as web.DOMException).name;
    return MailProblem(switch (name) {
      'QuotaExceededError' => MailProblemCode.quotaExceeded,
      'NotAllowedError' || 'SecurityError' => MailProblemCode.permissionDenied,
      'AbortError' => MailProblemCode.cancelled,
      _ => MailProblemCode.unavailable,
    });
  }
  return const MailProblem(MailProblemCode.unavailable);
}

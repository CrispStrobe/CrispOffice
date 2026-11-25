import 'dart:io';

import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_mime/quds_mail_mime.dart';

import '../configuration.dart';
import '../oauth.dart';
import '../provider.dart';
import 'authorization.dart';
import 'http.dart';

MailCloudProvider createMailCloudProvider({
  required MailCloudConfiguration configuration,
  required MailCloudTokenSource tokenSource,
  MailCodec codec = const QudsMimeCodec(),
  MailCloudLimits limits = const MailCloudLimits(),
  MailCloudLogSink? log,
}) => ApiMailCloudProvider(
  configuration: configuration,
  tokenSource: tokenSource,
  transport: NativeMailCloudHttpTransport(),
  codec: codec,
  limits: limits,
  log: log,
);

Future<MailResult<MailCloudTokenSource>> authorizeMailCloud({
  required MailOAuthConfiguration configuration,
  required MailAccountId account,
  required Future<bool> Function(Uri) openBrowser,
  required MailOperationLease lease,
  MailCloudLogSink? log,
  Duration timeout = const Duration(minutes: 5),
}) {
  if (!Platform.isLinux && !Platform.isMacOS && !Platform.isWindows) {
    return Future.value(
      const MailFailure(MailProblem(MailProblemCode.unsupported)),
    );
  }
  return authorizeNativeMailCloud(
    configuration: configuration,
    account: account,
    openBrowser: openBrowser,
    lease: lease,
    log: log,
    timeout: timeout,
  );
}

Future<MailResult<MailCloudTokenSource>> authorizeTasksCloud({
  required MailOAuthConfiguration configuration,
  required MailAccountId account,
  required Future<bool> Function(Uri) openBrowser,
  required MailOperationLease lease,
  required Future<void> Function(String) saveRefreshToken,
}) {
  if (!configuration.tasksOnly ||
      (!Platform.isLinux && !Platform.isMacOS && !Platform.isWindows)) {
    return Future.value(
      const MailFailure(MailProblem(MailProblemCode.unsupported)),
    );
  }
  return authorizeNativeMailCloud(
    configuration: configuration,
    account: account,
    openBrowser: openBrowser,
    lease: lease,
    saveRefreshToken: saveRefreshToken,
  );
}

MailCloudTokenSource restoreTasksCloud({
  required MailOAuthConfiguration configuration,
  required MailAccountId account,
  required String refreshToken,
  required Future<void> Function(String) saveRefreshToken,
}) => MailOAuthTokenSession.restoreTasks(
  configuration: configuration,
  account: account,
  transport: NativeMailCloudHttpTransport(),
  refreshToken: refreshToken,
  saveRefreshToken: saveRefreshToken,
);

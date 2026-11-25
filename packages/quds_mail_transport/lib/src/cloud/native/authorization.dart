import 'dart:async';
import 'dart:io';

import 'package:quds_mail_core/quds_mail_core.dart';

import '../configuration.dart';
import '../http.dart';
import '../oauth.dart';
import 'http.dart';

/// System-browser PKCE authorization with an ephemeral IPv4 loopback listener.
/// The injectable IO seams are internal and are never exported from the package.
Future<MailResult<MailCloudTokenSource>> authorizeNativeMailCloud({
  required MailOAuthConfiguration configuration,
  required MailAccountId account,
  required Future<bool> Function(Uri) openBrowser,
  required MailOperationLease lease,
  MailCloudLogSink? log,
  Duration timeout = const Duration(minutes: 5),
  Future<HttpServer> Function()? bindServer,
  MailCloudHttpTransport Function()? transportFactory,
  Future<void> Function(String)? saveRefreshToken,
}) async {
  if (lease.account != account ||
      timeout <= Duration.zero ||
      timeout > const Duration(minutes: 15)) {
    return const MailFailure(MailProblem(MailProblemCode.invalidInput));
  }
  final watch = Stopwatch()..start();
  void event(MailCloudLogStage stage, {MailProblemCode? problem}) {
    emitMailCloudLog(
      log,
      MailCloudLogEvent(
        service: configuration.service,
        operation: MailCloudOperation.authorize,
        stage: stage,
        elapsedMilliseconds: watch.elapsedMilliseconds,
        problemCode: problem,
      ),
    );
  }

  event(MailCloudLogStage.started);
  HttpServer? server;
  StreamSubscription<HttpRequest>? subscription;
  Timer? deadline;
  Timer? poll;
  MailCloudHttpTransport? transport;
  var adopted = false;
  var retired = false;
  final callback = Completer<MailResult<String>>();
  void finish(MailResult<String> result) {
    if (!callback.isCompleted) callback.complete(result);
  }

  try {
    lease.checkCurrent();
    deadline = Timer(
      timeout,
      () => finish(const MailFailure(MailProblem(MailProblemCode.cancelled))),
    );
    poll = Timer.periodic(const Duration(milliseconds: 25), (_) {
      if (!lease.isCurrent) {
        finish(
          MailFailure(
            MailProblem(
              lease.cancellation?.isCancelled == true
                  ? MailProblemCode.cancelled
                  : MailProblemCode.staleOperation,
            ),
          ),
        );
      }
    });
    final binding =
        (bindServer?.call() ??
                HttpServer.bind(InternetAddress.loopbackIPv4, 0, shared: false))
            .then((bound) async {
              if (retired || callback.isCompleted) {
                try {
                  await bound.close(force: true);
                } on Object {
                  // A late listener is still retired even if its close fails.
                }
                throw const MailCloudException(
                  MailProblem(MailProblemCode.cancelled),
                );
              }
              return bound;
            });
    server = await Future.any<HttpServer>([
      binding,
      callback.future.then((result) {
        throw MailCloudException(
          result is MailFailure<String>
              ? result.problem
              : const MailProblem(MailProblemCode.cancelled),
        );
      }),
    ]);
    lease.checkCurrent();
    if (!server.address.isLoopback || server.port < 1) {
      throw const MailCloudException(MailProblem(MailProblemCode.invalidInput));
    }
    server.idleTimeout = const Duration(seconds: 15);
    final redirect = Uri(
      scheme: 'http',
      // Google's Desktop registration accepts the literal loopback address.
      // Entra's Mobile/Desktop http://localhost registration ignores the port.
      host: configuration.service == MailCloudService.gmail
          ? '127.0.0.1'
          : 'localhost',
      port: server.port,
      path: configuration.service == MailCloudService.gmail
          ? '/oauth2/callback'
          : '/',
    );
    final challenge = MailOAuthChallenge.generate();
    var invalidRequests = 0;

    Future<void> respond(HttpRequest request) async {
      try {
        request.response.headers
          ..contentType = ContentType.text
          ..set('cache-control', 'no-store')
          ..set('pragma', 'no-cache')
          ..set('referrer-policy', 'no-referrer')
          ..set('x-content-type-options', 'nosniff');
        if (retired || callback.isCompleted || !lease.isCurrent) {
          request.response.statusCode = HttpStatus.gone;
          request.response.write('This sign-in attempt is no longer active.');
          return;
        }
        if (request.method != 'GET' ||
            request.headers.value(HttpHeaders.hostHeader) !=
                '${redirect.host}:${redirect.port}' ||
            request.uri.path != redirect.path ||
            request.uri.scheme.isNotEmpty ||
            request.uri.hasFragment ||
            request.uri.hasAuthority ||
            request.uri.toString().length > 16 * 1024) {
          request.response.statusCode = HttpStatus.badRequest;
          request.response.write('Invalid sign-in callback.');
          if (++invalidRequests >= 16) {
            finish(
              const MailFailure(MailProblem(MailProblemCode.invalidInput)),
            );
          }
          return;
        }
        final result = challenge.validateCallback(
          redirect.replace(query: request.uri.query),
          redirect,
        );
        if (result case MailFailure<String>(
          :final problem,
        ) when problem.code == MailProblemCode.invalidInput) {
          request.response.statusCode = HttpStatus.badRequest;
          request.response.write('Invalid sign-in callback.');
          if (++invalidRequests >= 16) finish(result);
          return;
        }
        finish(result);
        request.response.statusCode = HttpStatus.ok;
        request.response.write(
          'Sign-in response received. Return to CrispOffice.',
        );
      } on Object {
        finish(const MailFailure(MailProblem(MailProblemCode.providerFailure)));
      } finally {
        try {
          await request.response.close();
        } on Object {
          // The callback has already been validated; a closed browser tab must
          // not trigger code replay or leak the response through an exception.
        }
      }
    }

    subscription = server.listen(
      (request) => unawaited(respond(request)),
      onError: (Object _) =>
          finish(const MailFailure(MailProblem(MailProblemCode.unavailable))),
      onDone: () =>
          finish(const MailFailure(MailProblem(MailProblemCode.cancelled))),
    );
    // Launch may stall inside an OS plugin. The bounded callback future can
    // still cancel/expire the attempt while that plugin remains unresolved.
    final launch = Future<void>(() async {
      try {
        if (retired || callback.isCompleted || !lease.isCurrent) return;
        final opened = await openBrowser(
          challenge.authorizationUri(configuration, redirect),
        );
        if (!opened) {
          finish(const MailFailure(MailProblem(MailProblemCode.unavailable)));
        }
      } on Object {
        finish(const MailFailure(MailProblem(MailProblemCode.unavailable)));
      }
    });
    unawaited(launch);
    final result = await callback.future;
    lease.checkCurrent();
    retired = true;
    if (result case MailFailure<String>(:final problem)) {
      event(MailCloudLogStage.failed, problem: problem.code);
      return MailFailure(problem);
    }
    final code = (result as MailSuccess<String>).value;
    final remaining = timeout - watch.elapsed;
    if (remaining <= Duration.zero) {
      throw const MailCloudException(MailProblem(MailProblemCode.cancelled));
    }
    transport = transportFactory?.call() ?? NativeMailCloudHttpTransport();
    final exchanged = await MailOAuthTokenSession.exchange(
      configuration: configuration,
      account: account,
      transport: transport,
      challenge: challenge,
      code: code,
      redirect: redirect,
      lease: lease,
      log: log,
      timeout: remaining < const Duration(seconds: 30)
          ? remaining
          : const Duration(seconds: 30),
      saveRefreshToken: saveRefreshToken,
    );
    if (exchanged is MailSuccess<MailCloudTokenSource>) {
      if (!lease.isCurrent) {
        exchanged.value.dispose();
        lease.checkCurrent();
      }
      adopted = true;
      event(MailCloudLogStage.completed);
    } else {
      event(
        MailCloudLogStage.failed,
        problem: (exchanged as MailFailure<MailCloudTokenSource>).problem.code,
      );
    }
    return exchanged;
  } on Object catch (error) {
    final problem = error is MailCloudException
        ? error.problem
        : MailProblem(
            !lease.isCurrent
                ? (lease.cancellation?.isCancelled == true
                      ? MailProblemCode.cancelled
                      : MailProblemCode.staleOperation)
                : MailProblemCode.unavailable,
          );
    event(MailCloudLogStage.failed, problem: problem.code);
    return MailFailure(problem);
  } finally {
    retired = true;
    deadline?.cancel();
    poll?.cancel();
    try {
      await subscription?.cancel();
    } on Object {
      // Continue closing the listener and unadopted token transport.
    }
    try {
      await server?.close(force: true);
    } on Object {
      // Preserve the typed authorization outcome.
    }
    if (!adopted) {
      try {
        transport?.close();
      } on Object {
        // Cleanup is best-effort and must not turn into an uncaught callback.
      }
    }
  }
}

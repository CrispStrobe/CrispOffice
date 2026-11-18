import '../model/identity.dart';

enum MailCancellationReason { user, accountChanged, disposed, budgetExpired }

final class MailCancelled implements Exception {
  const MailCancelled(this.reason);
  final MailCancellationReason reason;
  @override
  String toString() => 'Mail operation cancelled (${reason.name}).';
}

/// Cooperative cancellation, usable in native and browser work without IO.
final class MailCancellationToken {
  MailCancellationToken._(this._source);
  final MailCancellationSource _source;
  bool get isCancelled => _source._reason != null;
  MailCancellationReason? get reason => _source._reason;
  void throwIfCancelled() {
    final cancelledReason = reason;
    if (cancelledReason != null) throw MailCancelled(cancelledReason);
  }
}

final class MailCancellationSource {
  MailCancellationReason? _reason;
  late final MailCancellationToken token = MailCancellationToken._(this);
  void cancel([MailCancellationReason reason = MailCancellationReason.user]) {
    _reason ??= reason;
  }
}

/// Account callbacks must retain a lease and validate it after every await.
/// Invalidating a session makes all previous generations stale immediately.
final class MailAccountSession {
  MailAccountSession(this.account);
  final MailAccountId account;
  int _generation = 0;
  bool _disposed = false;
  bool get isDisposed => _disposed;

  MailOperationLease begin({MailCancellationToken? cancellation}) {
    if (_disposed) throw const MailCancelled(MailCancellationReason.disposed);
    cancellation?.throwIfCancelled();
    return MailOperationLease._(this, _generation, cancellation);
  }

  void invalidate() {
    if (!_disposed) _generation++;
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _generation++;
  }
}

final class MailOperationLease {
  const MailOperationLease._(
    this._session,
    this._generation,
    this.cancellation,
  );
  final MailAccountSession _session;
  final int _generation;
  final MailCancellationToken? cancellation;
  MailAccountId get account => _session.account;
  bool get isCurrent =>
      !_session._disposed &&
      _session._generation == _generation &&
      !(cancellation?.isCancelled ?? false);

  void checkCurrent() {
    cancellation?.throwIfCancelled();
    if (_session._disposed) {
      throw const MailCancelled(MailCancellationReason.disposed);
    }
    if (_generation != _session._generation) {
      throw const MailCancelled(MailCancellationReason.accountChanged);
    }
  }
}

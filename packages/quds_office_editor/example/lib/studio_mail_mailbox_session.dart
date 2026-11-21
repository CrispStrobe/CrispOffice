import 'dart:async';

import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_store/quds_mail_store.dart';

import 'studio_mail_mailbox_store.dart';

enum StudioMailMailboxPhase { idle, loading, ready, missing, failed, closed }

/// A bounded durable folder view. Counts describe saved headers only; they are
/// never presented as authoritative server totals.
final class StudioMailMailboxSnapshot {
  const StudioMailMailboxSnapshot({
    required this.phase,
    this.mailbox,
    this.view,
    this.problem,
  });

  final StudioMailMailboxPhase phase;
  final MailMailboxId? mailbox;
  final MailCachedMailboxView? view;
  final MailProblem? problem;

  int get unreadCount =>
      view?.headers.where((header) => header.flags?.isRead == false).length ??
      0;
  int get unknownReadCount =>
      view?.headers.where((header) => header.flags == null).length ?? 0;
}

/// One account's selected folder, independent of providers and Flutter. Every
/// selection retires its predecessor before attaching another repository
/// stream. Late callbacks cannot repopulate a switched or closed workspace.
final class StudioMailMailboxSession {
  StudioMailMailboxSession({required this.store, required this.provider});

  final StudioMailMailboxStore store;
  final MailProviderKind provider;
  final _changes = StreamController<StudioMailMailboxSnapshot>.broadcast();
  StreamSubscription<MailResult<MailCachedMailboxView?>>? _subscription;
  Future<void> _transition = Future<void>.value();
  Future<void>? _closing;
  Completer<void>? _first;
  int _generation = 0;
  int _highestRevision = 0;
  bool _closed = false;
  StudioMailMailboxSnapshot _snapshot = const StudioMailMailboxSnapshot(
    phase: StudioMailMailboxPhase.idle,
  );

  StudioMailMailboxSnapshot get snapshot => _snapshot;
  // Delivery is asynchronous so a listener can safely switch or close. A
  // queued event also needs a delivery-time check: it may have been superseded
  // since the repository callback accepted it.
  Stream<StudioMailMailboxSnapshot> get changes =>
      _changes.stream.where((value) => identical(value, _snapshot));

  void _publish(StudioMailMailboxSnapshot value) {
    _snapshot = value;
    if (!_changes.isClosed) _changes.add(value);
  }

  void _finishFirst() {
    final first = _first;
    _first = null;
    if (first != null && !first.isCompleted) first.complete();
  }

  bool _current(int generation) => !_closed && generation == _generation;

  void _fail(int generation, MailMailboxId mailbox, MailProblem problem) {
    if (!_current(generation)) return;
    _publish(
      StudioMailMailboxSnapshot(
        phase: StudioMailMailboxPhase.failed,
        mailbox: mailbox,
        view: _snapshot.view,
        problem: problem,
      ),
    );
    if (_current(generation)) _finishFirst();
  }

  void _accept(
    int generation,
    MailMailboxId mailbox,
    MailResult<MailCachedMailboxView?> result,
  ) {
    if (!_current(generation)) return;
    if (result case MailFailure<MailCachedMailboxView?>(:final problem)) {
      _fail(generation, mailbox, problem);
      return;
    }
    final view = (result as MailSuccess<MailCachedMailboxView?>).value;
    if (view != null) {
      final ids = <MailMessageId>{};
      final remotes = <MailRemoteIdentity>{};
      int? uidValidity;
      var valid =
          view.mailbox.id == mailbox &&
          view.revision > 0 &&
          view.revision <= 9007199254740991 &&
          view.headers.length <= 1000 &&
          view.revision >= _highestRevision;
      for (final header in view.headers) {
        valid =
            valid &&
            header.remote.account == store.account &&
            header.remote.provider == provider &&
            ids.add(header.id) &&
            remotes.add(header.remote);
        if (header.remote case MailImapIdentity(
          :final mailbox,
          uidValidity: final validity,
        )) {
          valid =
              valid &&
              mailbox == view.mailbox.id &&
              (uidValidity == null || uidValidity == validity);
          uidValidity = validity;
        }
      }
      if (!valid) {
        _fail(generation, mailbox, const MailProblem(MailProblemCode.conflict));
        return;
      }
      _highestRevision = view.revision;
    }
    _publish(
      StudioMailMailboxSnapshot(
        phase: view == null
            ? StudioMailMailboxPhase.missing
            : StudioMailMailboxPhase.ready,
        mailbox: mailbox,
        view: view,
      ),
    );
    if (_current(generation)) _finishFirst();
  }

  /// Completes on the first result, or when another selection/close supersedes
  /// this one. A missing saved folder is distinct from a saved empty folder.
  Future<void> select(MailMailboxId mailbox) {
    if (_closed) return Future<void>.value();
    final generation = ++_generation;
    _highestRevision = 0;
    _finishFirst();
    final first = Completer<void>();
    _first = first;
    _publish(
      StudioMailMailboxSnapshot(
        phase: StudioMailMailboxPhase.loading,
        mailbox: mailbox,
      ),
    );
    _transition = _transition
        .then((_) async {
          if (!_current(generation)) return;
          final old = _subscription;
          _subscription = null;
          await old?.cancel();
          if (!_current(generation)) return;
          if (mailbox.account != store.account) {
            _fail(
              generation,
              mailbox,
              const MailProblem(MailProblemCode.permissionDenied),
            );
            return;
          }
          final source = store;
          final stream = source is StudioMailMailboxWatchStore
              ? (source as StudioMailMailboxWatchStore).watchView(mailbox)
              : Stream<MailResult<MailCachedMailboxView?>>.fromFuture(
                  source.loadView(mailbox).then(MailSuccess.new),
                );
          _subscription = stream.listen(
            (result) => _accept(generation, mailbox, result),
            onError: (Object _) => _fail(
              generation,
              mailbox,
              const MailProblem(MailProblemCode.storageFailure),
            ),
            onDone: () {
              // A one-shot adapter remains valid for hosts without live storage.
              // An unexpectedly closed live store must not look synchronized.
              if (source is StudioMailMailboxWatchStore ||
                  _snapshot.phase == StudioMailMailboxPhase.loading) {
                _fail(
                  generation,
                  mailbox,
                  const MailProblem(MailProblemCode.unavailable),
                );
              }
            },
          );
        })
        .catchError((Object _) {
          _fail(
            generation,
            mailbox,
            const MailProblem(MailProblemCode.storageFailure),
          );
        });
    return first.future;
  }

  /// Immediately clears selection and invalidates late work; cancellation is
  /// awaited before the storage owner may close or be acquired elsewhere.
  Future<void> close() {
    if (_closing case final closing?) return closing;
    _closed = true;
    _generation++;
    _finishFirst();
    _publish(
      const StudioMailMailboxSnapshot(phase: StudioMailMailboxPhase.closed),
    );
    return _closing = _transition.then((_) async {
      final subscription = _subscription;
      _subscription = null;
      await subscription?.cancel();
      await _changes.close();
    });
  }
}

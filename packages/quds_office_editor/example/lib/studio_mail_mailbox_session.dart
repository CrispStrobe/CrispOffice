import 'dart:async';

import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_store/quds_mail_store.dart';

import 'studio_mail_mailbox_store.dart';

enum StudioMailMailboxPhase { idle, loading, ready, missing, failed, closed }

/// Browsing windows and synchronized memberships have different coverage.
/// Selecting one never silently substitutes data from the other.
enum StudioMailMailboxSource { browse, synchronized }

/// A bounded durable folder view. Counts describe saved headers only; they are
/// never presented as authoritative server totals.
final class StudioMailMailboxSnapshot {
  const StudioMailMailboxSnapshot({
    required this.phase,
    this.mailbox,
    this.source = StudioMailMailboxSource.browse,
    this.view,
    this.synchronizedView,
    this.requestedOffset = 0,
    this.pageSize = 100,
    this.problem,
  });

  final StudioMailMailboxPhase phase;
  final MailMailboxId? mailbox;
  final StudioMailMailboxSource source;
  final MailCachedMailboxView? view;
  final MailMailboxSyncSnapshot? synchronizedView;
  final int requestedOffset;
  final int pageSize;
  final MailProblem? problem;

  List<MailHeaderRecord> get headers =>
      synchronizedView?.headers ?? view?.headers ?? const [];
  MailMailbox? get mailboxDetails => synchronizedView?.mailbox ?? view?.mailbox;
  int get headerCount => synchronizedView?.headerCount ?? headers.length;
  int get offset => synchronizedView?.offset ?? requestedOffset;
  int? get nextOffset =>
      synchronizedView?.hasMoreHeaders == true ? offset + headers.length : null;
  DateTime? get capturedAt => synchronizedView?.updatedAt ?? view?.capturedAt;
  int? get revision => synchronizedView?.revision ?? view?.revision;

  /// Provider scan continuation for synchronized data; unvisited server rows
  /// for a saved browsing window. Local paging is separately [nextOffset].
  bool get hasMore => synchronizedView?.hasMore ?? view?.hasMore ?? false;

  int get unreadCount =>
      headers.where((header) => header.flags?.isRead == false).length;
  int get unknownReadCount =>
      headers.where((header) => header.flags == null).length;
}

/// One account's selected folder, independent of providers and Flutter. Every
/// selection retires its predecessor before attaching another repository
/// stream. Late callbacks cannot repopulate a switched or closed workspace.
final class StudioMailMailboxSession {
  StudioMailMailboxSession({required this.store, required this.provider});

  final StudioMailMailboxStore store;
  final MailProviderKind provider;
  final _changes = StreamController<StudioMailMailboxSnapshot>.broadcast();
  StreamSubscription<Object?>? _subscription;
  Future<void>? _pendingRead;
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
        source: _snapshot.source,
        view: _snapshot.view,
        synchronizedView: _snapshot.synchronizedView,
        requestedOffset: _snapshot.requestedOffset,
        pageSize: _snapshot.pageSize,
        problem: problem,
      ),
    );
    if (_current(generation)) _finishFirst();
  }

  bool _validHeaders(MailMailboxId mailbox, List<MailHeaderRecord> headers) {
    final ids = <MailMessageId>{};
    final remotes = <MailRemoteIdentity>{};
    int? uidValidity;
    for (final header in headers) {
      if (header.remote.account != store.account ||
          header.remote.provider != provider ||
          !ids.add(header.id) ||
          !remotes.add(header.remote)) {
        return false;
      }
      if (header.remote case MailImapIdentity(
        mailbox: final remoteMailbox,
        uidValidity: final validity,
      )) {
        if (remoteMailbox != mailbox ||
            (uidValidity != null && uidValidity != validity)) {
          return false;
        }
        uidValidity = validity;
      }
    }
    return true;
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
      final valid =
          view.mailbox.id == mailbox &&
          view.revision > 0 &&
          view.revision <= 9007199254740991 &&
          view.headers.length <= 1000 &&
          view.revision >= _highestRevision &&
          _validHeaders(mailbox, view.headers);
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

  void _acceptSynchronized(
    int generation,
    MailMailboxId mailbox,
    int limit,
    int offset,
    MailResult<MailMailboxSyncSnapshot?> result,
  ) {
    if (!_current(generation)) return;
    if (result case MailFailure<MailMailboxSyncSnapshot?>(:final problem)) {
      _fail(generation, mailbox, problem);
      return;
    }
    final view = (result as MailSuccess<MailMailboxSyncSnapshot?>).value;
    if (view != null) {
      final remaining = view.headerCount - offset;
      final expectedCount = remaining <= 0
          ? 0
          : remaining < limit
          ? remaining
          : limit;
      if (view.mailbox.id != mailbox ||
          view.revision < 1 ||
          view.revision > 9007199254740991 ||
          view.revision < _highestRevision ||
          view.headerCount < 0 ||
          view.headerCount > 9007199254740991 ||
          view.offset != offset ||
          view.headers.length != expectedCount ||
          view.hasMoreHeaders != (remaining > view.headers.length) ||
          !_validHeaders(mailbox, view.headers)) {
        _fail(generation, mailbox, const MailProblem(MailProblemCode.conflict));
        return;
      }
      _highestRevision = view.revision;
      if (offset > 0 && offset >= view.headerCount) {
        // A later committed membership change can remove the current last
        // page. Retire that observer before reading the new last page. Keep
        // the first-result waiter and revision fence across this repair.
        final repairedOffset = view.headerCount == 0
            ? 0
            : ((view.headerCount - 1) ~/ limit) * limit;
        unawaited(
          _selectMailbox(
            mailbox,
            source: StudioMailMailboxSource.synchronized,
            limit: limit,
            offset: repairedOffset,
            carriedFirst: _first,
            minimumRevision: _highestRevision,
          ),
        );
        return;
      }
    }
    _publish(
      StudioMailMailboxSnapshot(
        phase: view == null
            ? StudioMailMailboxPhase.missing
            : StudioMailMailboxPhase.ready,
        mailbox: mailbox,
        source: StudioMailMailboxSource.synchronized,
        synchronizedView: view,
        requestedOffset: offset,
        pageSize: limit,
      ),
    );
    if (_current(generation)) _finishFirst();
  }

  Future<void> _cancelObservation() async {
    final old = _subscription;
    final read = _pendingRead;
    _subscription = null;
    _pendingRead = null;
    await old?.cancel();
    // A canceled Stream.fromFuture does not cancel the underlying local read.
    // Its owner must remain open until that read has settled too.
    await read;
  }

  /// Completes on the first result, or when another selection/close supersedes
  /// this one. A missing saved folder is distinct from a saved empty folder.
  Future<void> select(MailMailboxId mailbox) =>
      _selectMailbox(mailbox, source: StudioMailMailboxSource.browse);

  /// Reads only locally retained synchronized headers. Missing checkpoints,
  /// unsupported storage and saved empty folders remain distinct outcomes.
  Future<void> selectSynchronized(
    MailMailboxId mailbox, {
    int limit = 100,
    int offset = 0,
  }) => _selectMailbox(
    mailbox,
    source: StudioMailMailboxSource.synchronized,
    limit: limit,
    offset: offset,
  );

  Future<void> _selectMailbox(
    MailMailboxId mailbox, {
    required StudioMailMailboxSource source,
    int limit = 100,
    int offset = 0,
    Completer<void>? carriedFirst,
    int minimumRevision = 0,
  }) {
    if (_closed) return Future<void>.value();
    final generation = ++_generation;
    _highestRevision = minimumRevision;
    if (!identical(_first, carriedFirst)) _finishFirst();
    final first = carriedFirst ?? Completer<void>();
    _first = first;
    _publish(
      StudioMailMailboxSnapshot(
        phase: StudioMailMailboxPhase.loading,
        mailbox: mailbox,
        source: source,
        requestedOffset: offset,
        pageSize: limit,
      ),
    );
    _transition = _transition
        .then((_) async {
          if (!_current(generation)) return;
          await _cancelObservation();
          if (!_current(generation)) return;
          if (mailbox.account != store.account) {
            _fail(
              generation,
              mailbox,
              const MailProblem(MailProblemCode.permissionDenied),
            );
            return;
          }
          final storage = store;
          if (source == StudioMailMailboxSource.synchronized) {
            if (limit < 1 ||
                limit > 1000 ||
                offset < 0 ||
                offset > 9007199254740991) {
              _fail(
                generation,
                mailbox,
                const MailProblem(MailProblemCode.invalidInput),
              );
              return;
            }
            if (storage is! StudioMailSyncStore) {
              _fail(
                generation,
                mailbox,
                const MailProblem(MailProblemCode.unsupported),
              );
              return;
            }
            _subscription = (storage as StudioMailSyncStore)
                .watchSyncMailbox(mailbox, limit: limit, offset: offset)
                .listen(
                  (result) => _acceptSynchronized(
                    generation,
                    mailbox,
                    limit,
                    offset,
                    result,
                  ),
                  onError: (Object _) => _fail(
                    generation,
                    mailbox,
                    const MailProblem(MailProblemCode.storageFailure),
                  ),
                  onDone: () => _fail(
                    generation,
                    mailbox,
                    const MailProblem(MailProblemCode.unavailable),
                  ),
                );
            return;
          }
          final Stream<MailResult<MailCachedMailboxView?>> stream;
          if (storage is StudioMailMailboxWatchStore) {
            stream = (storage as StudioMailMailboxWatchStore).watchView(
              mailbox,
            );
          } else {
            final read = storage.loadView(mailbox).then(MailSuccess.new);
            _pendingRead = read.then<void>(
              (_) {},
              onError: (Object _, StackTrace _) {},
            );
            stream = Stream<MailResult<MailCachedMailboxView?>>.fromFuture(
              read,
            );
          }
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
              if (storage is StudioMailMailboxWatchStore ||
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

  /// Retires the selection immediately and drains its read/observer. The
  /// session stays reusable; a later selection cannot receive old callbacks.
  Future<void> clear() {
    if (_closed) return _closing ?? Future<void>.value();
    final generation = ++_generation;
    _highestRevision = 0;
    _finishFirst();
    _publish(
      const StudioMailMailboxSnapshot(phase: StudioMailMailboxPhase.idle),
    );
    return _transition = _transition.then((_) async {
      if (_current(generation)) await _cancelObservation();
    });
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
      await _cancelObservation();
      await _changes.close();
    });
  }
}

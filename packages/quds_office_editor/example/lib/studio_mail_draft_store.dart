import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_store/quds_mail_store.dart';

import 'studio_mail_draft.dart';
import 'studio_mail_outbox.dart';
import 'studio_mail_submission.dart';
import 'studio_mail_threading.dart';

/// Stable non-secret identity for the local draft belonging to one connection.
/// Hosts provide the configured endpoint, login and actual sending identity.
/// Passwords, access tokens and refresh tokens never enter this value.
final class StudioMailDraftAccount {
  factory StudioMailDraftAccount({
    required String provider,
    required String endpoint,
    required String login,
    required String sender,
  }) {
    final kind = MailProviderKind.values.where(
      (value) => value.name == provider.trim().toLowerCase(),
    );
    if (kind.length != 1 || kind.single == MailProviderKind.local) {
      throw const StudioMailDraftStoreException(MailProblemCode.invalidInput);
    }
    final parts = [endpoint.trim(), login.trim(), sender.trim()];
    if (parts.any(
      (value) =>
          value.isEmpty ||
          value.length > 4096 ||
          value.contains(RegExp(r'[\x00-\x1f\x7f]')),
    )) {
      throw const StudioMailDraftStoreException(MailProblemCode.invalidInput);
    }
    final uri = Uri.tryParse(parts[0]);
    if (uri == null ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment) {
      throw const StudioMailDraftStoreException(MailProblemCode.invalidInput);
    }
    // Structured encoding prevents delimiter collisions. Case-sensitive login
    // and mailbox local parts remain distinct; endpoint URI host casing is
    // canonicalized by Uri without altering a case-sensitive path.
    final fingerprint = sha256
        .convert(
          utf8.encode(
            jsonEncode([
              'studio-draft-account-v1',
              'quds-office-studio',
              kind.single.name,
              uri.toString(),
              parts[1],
              parts[2],
            ]),
          ),
        )
        .toString();
    final profile = MailProfileId(
      'drafts-$fingerprint',
      hostId: 'quds-office-studio',
    );
    return StudioMailDraftAccount._(
      kind.single,
      MailAccountId(fingerprint, profile: profile),
    );
  }

  const StudioMailDraftAccount._(this.provider, this.account);

  final MailProviderKind provider;
  final MailAccountId account;
  MailProfileId get profile => account.profile;
}

final class StudioMailStoredDraft {
  const StudioMailStoredDraft({
    required this.draft,
    required this.submissionUncertain,
  });

  final StudioMailDraft draft;
  final bool submissionUncertain;
}

/// Content-redacted storage failure. Hosts supply localized user feedback.
final class StudioMailDraftStoreException implements Exception {
  const StudioMailDraftStoreException(this.code);

  final MailProblemCode code;

  @override
  String toString() => 'StudioMailDraftStoreException(${code.name})';
}

typedef StudioMailDraftStoreFactory =
    Future<StudioMailDraftStore> Function(StudioMailDraftAccount account);

/// Exactly one foreground draft per scoped account, never an automatic sender.
///
/// Await [load] before editing, and await a save with submissionUncertain=true
/// before invoking a transport. Once set, uncertainty remains sticky across
/// ordinary autosaves. A verified rejected attempt may restore its prior
/// uncertainty through [saveRejectedDraft]; exceptions and ambiguous responses
/// never use that path. Await [clear] after confirmed acceptance or a confirmed
/// discard. Closing never clears content.
abstract interface class StudioMailDraftStore {
  Future<StudioMailStoredDraft?> load();
  Future<void> save(StudioMailDraft draft, {required bool submissionUncertain});

  /// Atomically retains a definitely unsubmitted draft and the uncertainty
  /// observed before that attempt's marker. The host must verify a matching
  /// attempt ID and rejected/retryableFailure outcome before calling this.
  /// An earlier uncertain attempt remains guarded even if this retry failed.
  /// This is never an autosave or a general-purpose uncertainty reset.
  Future<void> saveRejectedDraft(
    StudioMailDraft draft, {
    required bool wasPreviouslyUncertain,
  });

  Future<void> clear();
  Future<void> close();
}

/// Adapter over the shared mail repository, including blob quotas and CAS.
///
/// Native hosts use the app-container opener. The public repository seam also
/// supports deterministic tests and other hosts with their own store lifetime.
final class SqliteStudioMailDraftStore
    implements StudioMailDraftStore, StudioMailOutboxStore {
  SqliteStudioMailDraftStore({
    required SqliteMailRepository repository,
    required this.account,
    this.ownsRepository = false,
    DateTime Function()? clock,
  }) : _repository = repository,
       _clock = clock ?? DateTime.now {
    if (repository.profile != account.profile) {
      throw const StudioMailDraftStoreException(
        MailProblemCode.permissionDenied,
      );
    }
  }

  static const draftId = 'studio-foreground-compose';
  static const maxOutboxEntries = 100;

  final SqliteMailRepository _repository;
  final DateTime Function() _clock;
  @override
  final MailAccountId account;
  final bool ownsRepository;
  Future<void> _pending = Future<void>.value();
  bool _closing = false;
  bool _loaded = false;
  bool _submissionUncertain = false;
  int? _revision;
  Future<void>? _closeResult;
  final Map<String, String> _activeOutboxAttempts = {};

  Future<T> _serialize<T>(Future<T> Function() action) {
    if (_closing) {
      return Future<T>.error(
        const StudioMailDraftStoreException(MailProblemCode.unavailable),
      );
    }
    final result = _pending.then((_) => action());
    // A failed save must be reported to that caller without breaking the queue
    // or silently suppressing a later explicit retry/close.
    _pending = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  static T _value<T>(MailResult<T> result) => switch (result) {
    MailSuccess<T>(:final value) => value,
    MailFailure<T>(:final problem) => throw StudioMailDraftStoreException(
      problem.code,
    ),
  };

  void _requireLoaded() {
    if (!_loaded) {
      throw const StudioMailDraftStoreException(MailProblemCode.conflict);
    }
  }

  @override
  Future<StudioMailStoredDraft?> load() => _serialize(() async {
    final stored = _value(await _repository.loadDraft(account, draftId));
    final snapshot = stored == null ? null : _restore(stored);
    _revision = stored?.revision;
    _loaded = true;
    _submissionUncertain = snapshot?.submissionUncertain ?? false;
    return snapshot;
  });

  @override
  Future<void> save(
    StudioMailDraft draft, {
    required bool submissionUncertain,
  }) => _serialize(() async {
    _requireLoaded();
    final uncertain = submissionUncertain || _submissionUncertain;
    await _persistDraft(draft, uncertain: uncertain);
  });

  @override
  Future<void> saveRejectedDraft(
    StudioMailDraft draft, {
    required bool wasPreviouslyUncertain,
  }) => _serialize(() async {
    _requireLoaded();
    // A verified outcome must follow this owner's durable attempt marker. It
    // cannot manufacture a result for a draft that was never marked in flight.
    if (!_submissionUncertain) {
      throw const StudioMailDraftStoreException(MailProblemCode.conflict);
    }
    await _persistDraft(draft, uncertain: wasPreviouslyUncertain);
  });

  Future<void> _persistDraft(
    StudioMailDraft draft, {
    required bool uncertain,
  }) async {
    final revision = (_revision ?? -1) + 1;
    final prepared = MailDraft(
      id: draftId,
      account: account,
      revision: revision,
      envelope: MailEnvelope(
        subject: draft.subject,
        inReplyTo: draft.thread.inReplyTo,
        references: draft.thread.references?.split(' ') ?? const [],
      ),
      body: MailBody(plainText: draft.body),
      attachments: [
        for (var index = 0; index < draft.attachments.items.length; index++)
          MailAttachment(
            partPath: 'attachment-$index',
            mediaType: draft.attachments.items[index].mediaType,
            displayName: draft.attachments.items[index].name,
            content: draft.attachments.items[index].content,
          ),
      ],
      editorState: MailDraftEditorState(
        to: draft.to,
        cc: draft.cc,
        bcc: draft.bcc,
        submissionUncertain: uncertain,
      ),
    );
    _value(await _repository.saveDraft(prepared, expectedRevision: _revision));
    _revision = revision;
    _submissionUncertain = uncertain;
  }

  void _requireOutboxAccount(MailOutboxEntry entry) {
    if (entry.prepared.account != account) {
      throw const StudioMailDraftStoreException(
        MailProblemCode.permissionDenied,
      );
    }
  }

  static Never _outboxConflict() =>
      throw const StudioMailDraftStoreException(MailProblemCode.conflict);

  static String _newOutboxIdentity(String prefix) {
    final random = Random.secure();
    final entropy = List<String>.generate(
      24,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    return '$prefix-$entropy';
  }

  DateTime _outboxTime([MailOutboxEntry? entry]) {
    final now = _clock().toUtc();
    return entry != null && now.isBefore(entry.updatedAt)
        ? entry.updatedAt
        : now;
  }

  Future<List<MailOutboxEntry>> _loadOutbox() async {
    final entries = _value(await _repository.recoverOutbox(account));
    final recovered = <MailOutboxEntry>[];
    for (var entry in entries) {
      _requireOutboxAccount(entry);
      // The repository recovers interrupted attempts from an earlier owner.
      // This owner can also lose a result commit while still open. Only its
      // explicitly active transports remain in-flight during a refresh.
      if (entry.state == MailOutboxState.submitting &&
          _activeOutboxAttempts[entry.id] != entry.attemptId) {
        final interrupted = entry.recoverInterrupted(now: _outboxTime(entry));
        _value(
          await _repository.saveOutbox(
            interrupted,
            expectedState: entry.state,
            expectedAttemptId: entry.attemptId,
          ),
        );
        entry = interrupted;
      }
      recovered.add(entry);
    }
    recovered.sort((a, b) {
      final time = a.createdAt.compareTo(b.createdAt);
      return time == 0 ? a.id.compareTo(b.id) : time;
    });
    return List.unmodifiable(recovered);
  }

  @override
  Future<List<MailOutboxEntry>> loadOutbox() => _serialize(_loadOutbox);

  @override
  Future<MailOutboxEntry> enqueueOutbox(
    StudioMailDraft draft,
    String sender,
  ) => _serialize(() async {
    _requireLoaded();
    // Save the exact editor snapshot before validation or queue admission, so
    // even an invalid recipient or full queue leaves the user's work durable.
    await _persistDraft(draft, uncertain: _submissionUncertain);
    if (draft.problem != null || !StudioMailDraft.isSupportedAddress(sender)) {
      throw const StudioMailDraftStoreException(MailProblemCode.invalidInput);
    }
    if ((await _loadOutbox()).length >= maxOutboxEntries) {
      throw const StudioMailDraftStoreException(MailProblemCode.quotaExceeded);
    }
    final sourceRevision = _revision!;
    // Generate Date, Message-ID, boundaries and attachment encodings once.
    // Every later attempt uses this immutable wire/envelope pair.
    final message = buildStudioMailMessage(draft, sender);
    final prepared = MailPreparedMessage(
      account: account,
      draftId: draftId,
      draftRevision: sourceRevision,
      wire: MailBytes(utf8.encode(message.renderMessage())),
      envelope: MailTransportEnvelope(
        sender: sender,
        recipients: draft.recipients.envelope,
      ),
    );
    final queued = MailOutboxEntry.queued(
      id: _newOutboxIdentity('outbox'),
      prepared: prepared,
      now: _outboxTime(),
      priorSubmissionUncertain: _submissionUncertain,
    );
    _value(
      await _repository.enqueueDraft(
        queued,
        expectedDraftRevision: sourceRevision,
      ),
    );
    _revision = sourceRevision + 1;
    _submissionUncertain = false;
    return queued;
  });

  @override
  Future<MailOutboxEntry> beginOutboxAttempt(
    MailOutboxEntry entry, {
    bool acknowledgeUncertain = false,
  }) => _serialize(() async {
    _requireOutboxAccount(entry);
    final MailOutboxEntry attempt;
    if (acknowledgeUncertain && entry.canBeginAcknowledgedAttempt) {
      attempt = entry.beginAcknowledgedAttempt(
        attemptId: _newOutboxIdentity('attempt'),
        now: _outboxTime(entry),
      );
    } else if (entry.canBeginAttempt) {
      attempt = entry.beginAttempt(
        attemptId: _newOutboxIdentity('attempt'),
        now: _outboxTime(entry),
      );
    } else {
      _outboxConflict();
    }
    _value(
      await _repository.saveOutbox(
        attempt,
        expectedState: entry.state,
        expectedAttemptId: entry.attemptId,
      ),
    );
    _activeOutboxAttempts[attempt.id] = attempt.attemptId!;
    return attempt;
  });

  @override
  Future<MailOutboxEntry> completeOutboxAttempt(
    MailOutboxEntry entry,
    MailSubmissionResult result,
  ) => _serialize(() async {
    _requireOutboxAccount(entry);
    try {
      if (entry.state != MailOutboxState.submitting ||
          entry.attemptId != result.attemptId ||
          _activeOutboxAttempts[entry.id] != entry.attemptId) {
        _outboxConflict();
      }
      if (result.recipients.any(
        (response) =>
            !entry.prepared.envelope.recipients.contains(response.recipient),
      )) {
        throw const StudioMailDraftStoreException(MailProblemCode.invalidInput);
      }
      final completed = entry.complete(result, now: _outboxTime(entry));
      _value(
        await _repository.saveOutbox(
          completed,
          expectedState: entry.state,
          expectedAttemptId: entry.attemptId,
        ),
      );
      return completed;
    } finally {
      // A failure after provider acceptance must remain an uncertain recovery
      // record, never an ordinary queued retry or a permanently busy UI.
      if (_activeOutboxAttempts[entry.id] == entry.attemptId) {
        _activeOutboxAttempts.remove(entry.id);
      }
    }
  });

  @override
  Future<MailOutboxEntry> cancelOutbox(MailOutboxEntry entry) =>
      _serialize(() async {
        _requireOutboxAccount(entry);
        if (!entry.canCancel) _outboxConflict();
        final cancelled = entry.cancel(now: _outboxTime(entry));
        _value(
          await _repository.saveOutbox(
            cancelled,
            expectedState: entry.state,
            expectedAttemptId: entry.attemptId,
          ),
        );
        return cancelled;
      });

  @override
  Future<void> removeOutbox(MailOutboxEntry entry) => _serialize(() async {
    _requireOutboxAccount(entry);
    _value(
      await _repository.removeOutbox(
        account,
        entry.id,
        expectedState: entry.state,
        expectedAttemptId: entry.attemptId,
      ),
    );
  });

  @override
  Future<void> clear() => _serialize(() async {
    _requireLoaded();
    final revision = (_revision ?? -1) + 1;
    _value(
      await _repository.saveDraft(
        MailDraft(
          id: draftId,
          account: account,
          revision: revision,
          envelope: MailEnvelope(),
          body: const MailBody(),
          editorState: MailDraftEditorState(isCleared: true),
        ),
        expectedRevision: _revision,
      ),
    );
    // The empty revision marker prevents stale editors from recreating a sent
    // or discarded draft. Shared-store blob collection releases attachments.
    _revision = revision;
    _submissionUncertain = false;
  });

  @override
  Future<void> close() {
    if (_closeResult case final result?) return result;
    _closing = true;
    final result = _pending.then((_) async {
      if (ownsRepository) await _repository.close();
    });
    _closeResult = result;
    return result;
  }

  static StudioMailStoredDraft? _restore(MailDraft stored) {
    try {
      final editor = stored.editorState;
      if (editor == null) throw const FormatException();
      if (editor.isCleared) {
        if (stored.envelope.subject.isNotEmpty ||
            stored.envelope.inReplyTo != null ||
            stored.envelope.references.isNotEmpty ||
            stored.body.plainText != null ||
            stored.body.html != null ||
            stored.attachments.isNotEmpty) {
          throw const FormatException();
        }
        return null;
      }
      final envelope = stored.envelope;
      final thread = envelope.inReplyTo == null
          ? const StudioMailThread.empty()
          : StudioMailThread.replyTo(
              MailEnvelope(
                messageId: envelope.inReplyTo,
                references: envelope.references,
              ),
            );
      if (thread.inReplyTo != envelope.inReplyTo ||
          (thread.references ?? '') != envelope.references.join(' ')) {
        throw const FormatException();
      }
      return StudioMailStoredDraft(
        draft: StudioMailDraft(
          to: editor.to,
          cc: editor.cc,
          bcc: editor.bcc,
          subject: envelope.subject,
          body: stored.body.plainText ?? '',
          thread: thread,
          attachments: StudioMailAttachments.from([
            for (final attachment in stored.attachments)
              StudioMailAttachment(
                name: attachment.displayName,
                bytes: attachment.content.copyBytes(),
                mediaType: attachment.mediaType,
              ),
          ]),
        ),
        submissionUncertain: editor.submissionUncertain,
      );
    } on Object {
      throw const StudioMailDraftStoreException(MailProblemCode.storageFailure);
    }
  }
}

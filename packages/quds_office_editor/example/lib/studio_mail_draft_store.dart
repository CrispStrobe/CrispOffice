import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_store/quds_mail_store.dart';

import 'studio_mail_compose_tools.dart';
import 'studio_mail_draft.dart';
import 'studio_mail_flag_journal.dart';
import 'studio_mail_mailbox_store.dart';
import 'studio_mail_outbox.dart';
import 'studio_mail_outbox_content.dart';
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
      uri.toString(),
      parts[1],
      parts[2],
    );
  }

  const StudioMailDraftAccount._(
    this.provider,
    this.account,
    this.endpoint,
    this.login,
    this.sender,
  );

  final MailProviderKind provider;
  final MailAccountId account;
  final String endpoint;
  final String login;
  final String sender;
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

/// A reviewable, account-scoped catalog row pinned to its stored revision.
/// It contains no body text or attachment bytes.
final class StudioMailDraftSummary {
  const StudioMailDraftSummary({
    required this.account,
    required this.id,
    required this.revision,
    required this.subject,
    required this.to,
    required this.cc,
    required this.bcc,
    required this.attachmentCount,
    required this.submissionUncertain,
  });

  final MailAccountId account;
  final String id;
  final int revision;
  final String subject;
  final String to;
  final String cc;
  final String bcc;
  final int attachmentCount;
  final bool submissionUncertain;
}

final class StudioMailDraftCatalogPage {
  StudioMailDraftCatalogPage({
    required List<StudioMailDraftSummary> drafts,
    this.nextAfterId,
  }) : drafts = List.unmodifiable(drafts);

  final List<StudioMailDraftSummary> drafts;
  final String? nextAfterId;
}

/// Optional multiple-draft support; existing single-draft host fakes remain
/// valid. Save/close the current editor before changing the selected draft.
/// Composer callbacks capture both [selectedDraftId] and [selectionEpoch] and
/// reject changes before invoking the legacy store methods. Store operations
/// also capture the epoch when invoked, rejecting writes queued before a switch.
abstract interface class StudioMailDraftCatalog {
  MailAccountId get account;
  String get selectedDraftId;
  int get selectionEpoch;
  Future<StudioMailDraftCatalogPage> listDrafts({String? afterId});
  Future<StudioMailStoredDraft> selectDraft(StudioMailDraftSummary summary);
  Future<StudioMailStoredDraft> createDraft(StudioMailDraft initial);

  /// Clears only the listed account/ID/revision. An unselected draft may be
  /// discarded without changing the current editor or its uncertainty state.
  Future<void> discardDraft(StudioMailDraftSummary summary);
}

/// Content-redacted storage failure. Hosts supply localized user feedback.
final class StudioMailDraftStoreException implements Exception {
  const StudioMailDraftStoreException(this.code);

  final MailProblemCode code;

  @override
  String toString() => 'StudioMailDraftStoreException(${code.name})';
}

typedef StudioMailDraftStoreFactory = Future<StudioMailDraftStore> Function(
  StudioMailDraftAccount account,
);

/// One selected foreground draft per scoped account, never an automatic sender.
/// Hosts may additionally expose [StudioMailDraftCatalog] when implemented.
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
    implements
        StudioMailDraftStore,
        StudioMailDraftCatalog,
        StudioMailComposeToolsStore,
        StudioMailMailboxStoreOwner,
        StudioMailFlagJournalOwner,
        StudioMailOutboxStore,
        StudioMailOutboxManagementStore {
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
  static const maxDrafts = 100;
  static const maxOutboxEntries = 100;

  final SqliteMailRepository _repository;
  @override
  late final StudioMailFlagJournalStore flagJournal =
      SqliteStudioMailFlagJournalStore(
        repository: _repository,
        account: account,
        serialize: _serialize,
      );
  @override
  late final StudioMailMailboxStore mailboxStore = SqliteStudioMailMailboxStore(
    repository: _repository,
    account: account,
    serialize: _serialize,
  );
  final DateTime Function() _clock;
  @override
  final MailAccountId account;
  final bool ownsRepository;
  Future<void> _pending = Future<void>.value();
  bool _closing = false;
  bool _loaded = false;
  bool _submissionUncertain = false;
  String _selectedDraftId = draftId;
  int _selectionEpoch = 0;
  int? _revision;
  Future<void>? _closeResult;
  final Map<String, String> _activeOutboxAttempts = {};

  @override
  String get selectedDraftId => _selectedDraftId;

  @override
  int get selectionEpoch => _selectionEpoch;

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

  Future<T> _serializeSelection<T>(Future<T> Function() action) {
    final epoch = _selectionEpoch;
    return _serialize(() async {
      if (epoch != _selectionEpoch) {
        throw const StudioMailDraftStoreException(
          MailProblemCode.staleOperation,
        );
      }
      return action();
    });
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
  Future<MailComposeSettings> loadComposeSettings() => _serialize(() async {
    return _value(await _repository.loadComposeSettings(account));
  });

  @override
  Future<MailComposeSettings> saveComposeSettings(
    MailComposeSettings settings,
  ) => _serialize(() async {
    if (settings.account != account) {
      throw const StudioMailDraftStoreException(
        MailProblemCode.permissionDenied,
      );
    }
    return _value(
      await _repository.saveComposeSettings(
        settings,
        expectedRevision: settings.revision,
      ),
    );
  });

  @override
  Future<StudioMailStoredDraft?> load() => _serializeSelection(() async {
    final stored = _value(
      await _repository.loadDraft(account, _selectedDraftId),
    );
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
  }) => _serializeSelection(() async {
    _requireLoaded();
    final uncertain = submissionUncertain || _submissionUncertain;
    await _persistDraft(draft, uncertain: uncertain);
  });

  @override
  Future<void> saveRejectedDraft(
    StudioMailDraft draft, {
    required bool wasPreviouslyUncertain,
  }) => _serializeSelection(() async {
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
    final prepared = _prepareDraft(
      draft,
      id: _selectedDraftId,
      revision: revision,
      uncertain: uncertain,
    );
    _value(
      await _repository.saveDraft(
        prepared,
        expectedRevision: _revision,
        maxActiveDrafts: maxDrafts,
      ),
    );
    _revision = revision;
    _submissionUncertain = uncertain;
  }

  MailDraft _prepareDraft(
    StudioMailDraft draft, {
    required String id,
    required int revision,
    required bool uncertain,
  }) => MailDraft(
    id: id,
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

  @override
  Future<StudioMailDraftCatalogPage> listDrafts({String? afterId}) =>
      _serialize(() async {
        final page = _value(
          await _repository.listDrafts(account, afterId: afterId),
        );
        final summaries = <StudioMailDraftSummary>[];
        for (final draft in page.drafts) {
          final editor = draft.editorState;
          if (editor == null || editor.isCleared) {
            throw const StudioMailDraftStoreException(
              MailProblemCode.storageFailure,
            );
          }
          summaries.add(
            StudioMailDraftSummary(
              account: draft.account,
              id: draft.id,
              revision: draft.revision,
              subject: draft.envelope.subject,
              to: editor.to,
              cc: editor.cc,
              bcc: editor.bcc,
              attachmentCount: draft.attachmentCount,
              submissionUncertain: editor.submissionUncertain,
            ),
          );
        }
        return StudioMailDraftCatalogPage(
          drafts: summaries,
          nextAfterId: page.nextAfterId,
        );
      });

  void _requireSummaryAccount(StudioMailDraftSummary summary) {
    if (summary.account != account) {
      throw const StudioMailDraftStoreException(
        MailProblemCode.permissionDenied,
      );
    }
    if (summary.id.isEmpty || summary.revision < 0) {
      throw const StudioMailDraftStoreException(MailProblemCode.invalidInput);
    }
  }

  @override
  Future<StudioMailStoredDraft> selectDraft(StudioMailDraftSummary summary) =>
      _serialize(() async {
        _requireSummaryAccount(summary);
        final stored = _value(await _repository.loadDraft(account, summary.id));
        if (stored == null || stored.revision != summary.revision) {
          throw const StudioMailDraftStoreException(MailProblemCode.conflict);
        }
        final restored = _restore(stored);
        if (restored == null) {
          throw const StudioMailDraftStoreException(MailProblemCode.conflict);
        }
        _selectedDraftId = summary.id;
        _revision = stored.revision;
        _loaded = true;
        _submissionUncertain = restored.submissionUncertain;
        _selectionEpoch++;
        return restored;
      });

  @override
  Future<StudioMailStoredDraft> createDraft(StudioMailDraft initial) =>
      _serialize(() async {
        final id = _newOutboxIdentity('studio-draft');
        final prepared = _prepareDraft(
          initial,
          id: id,
          revision: 0,
          uncertain: false,
        );
        _value(
          await _repository.saveDraft(
            prepared,
            expectedRevision: null,
            maxActiveDrafts: maxDrafts,
          ),
        );
        _selectedDraftId = id;
        _revision = 0;
        _loaded = true;
        _submissionUncertain = false;
        _selectionEpoch++;
        return StudioMailStoredDraft(
          draft: initial,
          submissionUncertain: false,
        );
      });

  @override
  Future<void> discardDraft(StudioMailDraftSummary summary) =>
      _serialize(() async {
        _requireSummaryAccount(summary);
        await _clearDraft(summary.id, summary.revision);
        if (_selectedDraftId == summary.id) {
          _revision = summary.revision + 1;
          _loaded = true;
          _submissionUncertain = false;
          _selectionEpoch++;
        }
      });

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
  ) => _serializeSelection(() async {
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
      draftId: _selectedDraftId,
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
    _selectionEpoch++;
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
  Future<StudioMailDraft> editOutboxAsDraft(
    MailOutboxEntry entry,
  ) => _serializeSelection(() async {
    _requireOutboxAccount(entry);
    if (!entry.canCancel) _outboxConflict();
    // Decode the bounded immutable snapshot before starting the storage
    // transaction. Unsupported content leaves both queue and drafts intact.
    final restored = StudioMailOutboxContent.fromEntry(entry).draft;
    final id = _newOutboxIdentity('studio-draft');
    final prepared = _prepareDraft(
      restored,
      id: id,
      revision: 0,
      uncertain: false,
    );
    _value(
      await _repository.editOutboxAsDraft(
        entry,
        prepared,
        now: _outboxTime(entry),
        maxActiveDrafts: maxDrafts,
      ),
    );
    // Only a successful atomic handoff changes selection. Existing drafts
    // keep their IDs, bytes and revisions, including the original tombstone.
    _selectedDraftId = id;
    _revision = 0;
    _loaded = true;
    _submissionUncertain = false;
    _selectionEpoch++;
    return restored;
  });

  @override
  Future<MailOutboxEntry> closeUncertainOutbox(MailOutboxEntry entry) =>
      _serialize(() async {
        _requireOutboxAccount(entry);
        if (!entry.canCloseUncertain) _outboxConflict();
        final closed = entry.closeUncertain(now: _outboxTime(entry));
        _value(
          await _repository.saveOutbox(
            closed,
            expectedState: entry.state,
            expectedAttemptId: entry.attemptId,
          ),
        );
        return closed;
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
  Future<void> clear() => _serializeSelection(() async {
    _requireLoaded();
    await _clearDraft(_selectedDraftId, _revision);
    _revision = (_revision ?? -1) + 1;
    _submissionUncertain = false;
    _selectionEpoch++;
  });

  Future<void> _clearDraft(String id, int? expectedRevision) async {
    final revision = (expectedRevision ?? -1) + 1;
    _value(
      await _repository.saveDraft(
        MailDraft(
          id: id,
          account: account,
          revision: revision,
          envelope: MailEnvelope(),
          body: const MailBody(),
          editorState: MailDraftEditorState(isCleared: true),
        ),
        expectedRevision: expectedRevision,
      ),
    );
    // The empty revision marker prevents stale editors from recreating a sent
    // or discarded draft. Shared-store blob collection releases attachments.
  }

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

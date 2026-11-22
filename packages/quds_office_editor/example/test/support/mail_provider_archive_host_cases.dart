part of '../studio_mail_journal_host_test.dart';

/// Retains the real SQLite draft, mailbox cache and command journal, while
/// making an accidental Gmail access to folder-based Archive settings fail.
final class _ArchiveSettingsSpy extends Fake
    implements
        StudioMailDraftStore,
        StudioMailArchiveSettingsStore,
        StudioMailMailboxStoreOwner,
        StudioMailFlagJournalOwner {
  _ArchiveSettingsSpy(this.harness);

  final _Harness harness;
  SqliteStudioMailDraftStore get owner => harness.fixture.owner;

  @override
  MailAccountId get account => owner.account;
  @override
  StudioMailFlagJournalStore get flagJournal => owner.flagJournal;
  @override
  StudioMailMailboxStore get mailboxStore => owner.mailboxStore;
  @override
  Future<StudioMailStoredDraft?> load() => owner.load();
  @override
  Future<void> close() => owner.close();
  @override
  Future<MailArchiveDestinationSettings> loadArchiveSettings() async {
    harness.archiveSettingsReads++;
    throw StateError('Gmail Archive must not read folder preferences.');
  }

  @override
  Future<MailArchiveDestinationSettings> saveArchiveSettings(
    MailArchiveDestinationSettings settings, {
    required int expectedRevision,
  }) async {
    harness.archiveSettingsWrites++;
    throw StateError('Gmail Archive must not write folder preferences.');
  }
}

String _customArchiveId(_Harness harness) =>
    harness.kind == MailProviderKind.imap
    ? ' Projects/2026 Filed '
    : 'opaque-custom-archive-ID';

String _inboxId(_Harness harness) =>
    harness.kind == MailProviderKind.imap ? 'INBOX' : 'inbox';

/// Installed after connection so the new choice is absent from the cached
/// navigation tree. Default and custom folders deliberately share a name.
void _setArchiveCatalog(
  _Harness harness, {
  bool includeCustom = true,
  bool label = false,
  bool foreign = false,
  bool selectable = true,
  bool unavailable = false,
}) {
  harness.imapFolders = () async {
    if (unavailable) throw StateError('Synthetic LIST unavailable.');
    return [
      mail.Mailbox(
        encodedName: 'INBOX',
        encodedPath: 'INBOX',
        pathSeparator: '/',
        flags: [mail.MailboxFlag.inbox],
      )..uidValidity = 71,
      mail.Mailbox(
        encodedName: 'Archive',
        encodedPath: 'Archive',
        pathSeparator: '/',
        flags: [],
      )..uidValidity = 72,
      if (includeCustom)
        mail.Mailbox(
          encodedName: 'Archive',
          encodedPath: _customArchiveId(harness),
          pathSeparator: '/',
          flags: [if (!selectable) mail.MailboxFlag.noSelect],
        )..uidValidity = 73,
    ];
  };
  harness.providerFolders = (lease) async {
    lease.checkCurrent();
    if (unavailable) {
      return const MailFailure(MailProblem(MailProblemCode.unavailable));
    }
    return MailSuccess([
      MailMailbox(
        id: MailMailboxId('inbox', account: lease.account),
        displayName: 'Inbox',
      ),
      MailMailbox(
        id: MailMailboxId('archive', account: lease.account),
        displayName: 'Archive',
      ),
      if (includeCustom)
        MailMailbox(
          id: MailMailboxId(
            _customArchiveId(harness),
            account: foreign
                ? MailAccountId(
                    'another-account',
                    profile: lease.account.profile,
                  )
                : lease.account,
          ),
          displayName: 'Archive',
          isLabel: label,
        ),
    ]);
  };
}

Future<MailArchiveDestinationSettings> _readArchivePreference(
  WidgetTester tester,
  _Harness harness,
) async {
  late MailArchiveDestinationSettings settings;
  await settleMailJournal(tester, () async {
    settings = await harness.fixture.owner.loadArchiveSettings();
  });
  return settings;
}

Future<MailArchiveDestinationSettings> _writeArchivePreference(
  WidgetTester tester,
  _Harness harness,
  String? destination,
) async {
  final previous = await _readArchivePreference(tester, harness);
  late MailArchiveDestinationSettings settings;
  await settleMailJournal(tester, () async {
    settings = await harness.fixture.owner.saveArchiveSettings(
      MailArchiveDestinationSettings(
        account: harness.fixture.account,
        revision: previous.revision,
        destination: destination == null
            ? null
            : MailMailboxId(destination, account: harness.fixture.account),
      ),
      expectedRevision: previous.revision,
    );
  });
  return settings;
}

Future<void> _expectNoArchiveIntent(
  WidgetTester tester,
  _Harness harness,
) async {
  expect(harness.commands, isEmpty);
  expect(harness.atDispatch, isEmpty);
  await settleMailJournal(tester, () async {
    expect((await harness.fixture.store.list()).batches, isEmpty);
  });
  expect(harness.sends, 0);
}

Future<void> _openArchiveSettings(
  WidgetTester tester, {
  bool failed = false,
}) async {
  await tester.tap(_key('studio-mail-archive-settings'));
  await _until(
    tester,
    () =>
        _key('studio-mail-archive-settings-dialog').evaluate().isNotEmpty &&
        _key(
          failed
              ? 'studio-mail-archive-settings-error'
              : 'studio-mail-archive-settings-folder-0',
        ).evaluate().isNotEmpty,
  );
}

Future<void> _saveArchiveChoice(WidgetTester tester, int index) async {
  final folder = _key('studio-mail-archive-settings-folder-$index');
  await tester.ensureVisible(folder);
  await tester.tap(folder);
  await tester.pump();
  await tester.tap(_key('studio-mail-archive-settings-save'));
  await _until(
    tester,
    () => _key('studio-mail-archive-settings-dialog').evaluate().isEmpty,
  );
}

void _requestArchive(WidgetTester tester) {
  final list = _list(tester);
  list.onBulkAction!(MailBulkFlagAction.archive, [list.items.first.id]);
}

Future<void> _startProviderArchive(
  WidgetTester tester,
  _Harness harness, {
  int count = 2,
  bool single = false,
  bool confirm = true,
}) async {
  if (single) {
    await _openFirst(tester);
    await tester.tap(_key('studio-mail-archive-message'));
  } else {
    final list = _list(tester);
    expect(list.supportedBulkActions, contains(MailBulkFlagAction.archive));
    list.onBulkAction!(
      MailBulkFlagAction.archive,
      list.items.take(count).map((row) => row.id).toList(),
    );
  }
  await _until(
    tester,
    () => _key('studio-mail-archive-selection-dialog').evaluate().isNotEmpty,
  );
  expect(harness.commands, isEmpty);
  if (!confirm) return;
  await _confirmProviderArchive(tester);
}

Future<void> _confirmProviderArchive(WidgetTester tester) async {
  if (_key('studio-mail-archive-destination-0').evaluate().isNotEmpty) {
    await tester.tap(_key('studio-mail-archive-destination-0'));
    await tester.pump();
  }
  await tester.tap(_key('studio-mail-archive-apply'));
}

void providerArchiveHostTests() {
  rememberedArchiveHostTests();
  for (final kind in [
    MailProviderKind.imap,
    MailProviderKind.ews,
    MailProviderKind.gmail,
    MailProviderKind.graph,
  ]) {
    for (final single in [false, true]) {
      testWidgets(
        '${kind.name} ${single ? 'single' : 'bulk'} provider Archive persists exact reviewed intent',
        (tester) async {
          final harness = _Harness(kind)..archiveEnabled = true;
          await _show(tester, harness);
          await _startProviderArchive(tester, harness, single: single);
          final count = single ? 1 : 2;
          await _until(
            tester,
            () => harness.commands.length == count && !_list(tester).busy,
          );
          expect(
            harness.commands,
            everyElement(
              kind == MailProviderKind.gmail
                  ? isA<MailArchive>()
                  : isA<MailMove>(),
            ),
          );
          final action = kind == MailProviderKind.gmail
              ? MailBulkFlagAction.archive
              : MailBulkFlagAction.move;
          expect(
            harness.atDispatch.map((receipt) => receipt.summary.action),
            everyElement(action),
          );
          if (kind == MailProviderKind.gmail) {
            expect(harness.atDispatch.first.summary.mailbox.value, 'INBOX');
            expect(harness.atDispatch.first.summary.destination, isNull);
            expect(harness.archiveResolutionReads, 0);
          } else {
            final destination = kind == MailProviderKind.imap
                ? 'Archive'
                : 'archive';
            expect(
              harness.commands.cast<MailMove>().map(
                (command) => command.destination.value,
              ),
              everyElement(destination),
            );
            expect(
              harness.atDispatch.first.summary.destination?.value,
              destination,
            );
          }
          expect(_list(tester).items, hasLength(3 - count));
          expect(_list(tester).bulkActionsEnabled, isFalse);
          final receipt = await _reopenMembershipReceipt(tester, harness);
          expect(receipt.report.confirmedCount, count);
          expect(receipt.summary.action, action);
          expect(receipt.summary.canCheckFlags, isFalse);
          expect(
            harness.commands,
            hasLength(count),
            reason: 'Reopening cannot replay Archive',
          );
          expect(harness.sends, 0);
        },
      );
    }

    testWidgets(
      '${kind.name} stale single Archive button cannot act on another reader',
      (tester) async {
        final harness = _Harness(kind)..archiveEnabled = true;
        await _show(tester, harness);
        await _openFirst(tester);
        final oldAction = tester
            .widget<IconButton>(_key('studio-mail-archive-message'))
            .onPressed!;
        final otherId = _list(tester).items[1].id;
        _list(tester).onOpen(otherId);
        await _until(
          tester,
          () => _list(tester).selectedId == otherId && !_list(tester).busy,
        );
        oldAction();
        await tester.pump(const Duration(milliseconds: 350));
        expect(_key('studio-mail-archive-selection-dialog'), findsNothing);
        expect(harness.commands, isEmpty);
      },
    );

    testWidgets('${kind.name} cancelled provider Archive saves no command', (
      tester,
    ) async {
      final harness = _Harness(kind)..archiveEnabled = true;
      await _show(tester, harness);
      final commits = harness.fixture.commits;
      await _startProviderArchive(tester, harness, confirm: false);
      expect(find.text(_strings.mailOrganizationCount(2)), findsOneWidget);
      await tester.tap(_key('studio-mail-organization-cancel'));
      await _until(tester, () => !_list(tester).busy);
      expect(harness.commands, isEmpty);
      expect(harness.fixture.commits, commits);
      expect(_list(tester).items, hasLength(3));
    });

    testWidgets(
      '${kind.name} uncertain Archive saves evidence and stops remaining messages',
      (tester) async {
        final harness = _Harness(kind)..archiveEnabled = true;
        harness.respond = (_) async => const MailFailure(
          MailProblem(
            MailProblemCode.unavailable,
            mutationMayHaveOccurred: true,
          ),
        );
        await _show(tester, harness);
        await _startProviderArchive(tester, harness);
        await _until(
          tester,
          () => harness.commands.length == 1 && !_list(tester).busy,
        );
        expect(_status(tester).report.uncertainCount, 1);
        expect(_status(tester).report.unattemptedCount, 1);
        expect(_list(tester).items, hasLength(3));
        final receipt = await _reopenMembershipReceipt(tester, harness);
        expect(receipt.summary.canCheckMembership, isTrue);
        expect(receipt.summary.unresolvedCount, 1);
        expect(receipt.report.unattemptedCount, 1);
        expect(harness.commands, hasLength(1));
      },
    );
  }

  testWidgets(
    'Gmail Archive is absent outside exact Inbox despite advertised capability',
    (tester) async {
      final harness = _Harness(MailProviderKind.gmail)..archiveEnabled = true;
      await _show(tester, harness);
      expect(
        _list(tester).supportedBulkActions,
        contains(MailBulkFlagAction.archive),
      );
      await tester.tap(find.text('Archive'));
      await _until(
        tester,
        () => harness.headerReads == 2 && !_list(tester).busy,
      );
      final list = _list(tester);
      expect(
        list.supportedBulkActions,
        isNot(contains(MailBulkFlagAction.archive)),
      );
      list.onBulkAction!(MailBulkFlagAction.archive, [list.items.first.id]);
      await tester.pump();
      expect(_key('studio-mail-archive-selection-dialog'), findsNothing);
      expect(harness.commands, isEmpty);
    },
  );

  for (final kind in [MailProviderKind.imap, MailProviderKind.graph]) {
    testWidgets(
      '${kind.name} Archive reviews a newly resolved folder outside the earlier catalog',
      (tester) async {
        final harness = _Harness(kind)..archiveEnabled = true;
        harness.archiveResolution = (lease) async => MailSuccess(
          MailMailbox(
            id: MailMailboxId('newly-resolved-archive', account: lease.account),
            displayName: 'Server filing folder',
          ),
        );
        await _show(tester, harness);
        await _startProviderArchive(tester, harness, confirm: false);
        expect(find.text('newly-resolved-archive'), findsOneWidget);
        expect(_key('studio-mail-archive-destination-0'), findsNothing);
        await _confirmProviderArchive(tester);
        await _until(
          tester,
          () => harness.commands.length == 2 && !_list(tester).busy,
        );
        expect(
          harness.commands.cast<MailMove>().map(
            (command) => command.destination.value,
          ),
          everyElement('newly-resolved-archive'),
        );
        final receipt = await _reopenMembershipReceipt(tester, harness);
        expect(receipt.summary.destination?.value, 'newly-resolved-archive');
      },
    );

    testWidgets(
      '${kind.name} Archive resolution failure never opens manual fallback',
      (tester) async {
        final harness = _Harness(kind)..archiveEnabled = true;
        harness.archiveResolution = (_) async =>
            const MailFailure(MailProblem(MailProblemCode.unavailable));
        await _show(tester, harness);
        final list = _list(tester);
        list.onBulkAction!(MailBulkFlagAction.archive, [list.items.first.id]);
        await _until(
          tester,
          () => harness.archiveResolutionReads == 1 && !_list(tester).busy,
        );
        expect(find.text(_strings.mailMutationCheckFailed), findsOneWidget);
        expect(_key('studio-mail-archive-selection-dialog'), findsNothing);
        expect(harness.commands, isEmpty);
      },
    );

    testWidgets(
      '${kind.name} Archive requires explicit choice when server reports unsupported',
      (tester) async {
        final harness = _Harness(kind)..archiveEnabled = true;
        harness.archiveResolution = (_) async =>
            const MailFailure(MailProblem(MailProblemCode.unsupported));
        await _show(tester, harness);
        await _startProviderArchive(tester, harness, confirm: false);
        expect(
          find.text(_strings.mailArchiveChooseExplanation),
          findsOneWidget,
        );
        expect(
          tester
              .widget<FilledButton>(_key('studio-mail-archive-apply'))
              .onPressed,
          isNull,
        );
        await _confirmProviderArchive(tester);
        await _until(
          tester,
          () => harness.commands.length == 2 && !_list(tester).busy,
        );
        expect(harness.commands, everyElement(isA<MailMove>()));
      },
    );

    testWidgets(
      '${kind.name} late Archive resolution cannot enter a replaced account',
      (tester) async {
        final gate = Completer<MailResult<MailMailbox>>();
        final harness = _Harness(kind)..archiveEnabled = true;
        harness.archiveResolution = (_) => gate.future;
        await _show(tester, harness);
        final list = _list(tester);
        list.onBulkAction!(MailBulkFlagAction.archive, [list.items.first.id]);
        await _until(tester, () => harness.archiveResolutionReads == 1);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        gate.complete(
          MailSuccess(
            MailMailbox(
              id: MailMailboxId('late-archive', account: harness.liveAccount!),
              displayName: 'Archive',
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 350));
        expect(harness.commands, isEmpty);
        expect(_key('studio-mail-archive-selection-dialog'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('IMAP Archive confirmation rejects a changed UID generation', (
    tester,
  ) async {
    final harness = _Harness(MailProviderKind.imap)..archiveEnabled = true;
    await _show(tester, harness);
    await _startProviderArchive(tester, harness, confirm: false);
    final browser = harness.imapBrowser!;
    final message = browser.observations.keys.first;
    final old = browser.observations[message]!;
    final identity = old.remote as MailImapIdentity;
    browser.observations[message] = MailHeaderRecord(
      id: old.id,
      remote: MailImapIdentity(
        mailbox: identity.mailbox,
        uidValidity: identity.uidValidity + 1,
        uid: identity.uid,
      ),
      envelope: old.envelope,
      flags: old.flags,
    );
    await _confirmProviderArchive(tester);
    await _until(tester, () => !_list(tester).busy);
    expect(harness.commands, isEmpty);
  });
}

void rememberedArchiveHostTests() {
  for (final kind in [
    MailProviderKind.imap,
    MailProviderKind.ews,
    MailProviderKind.graph,
  ]) {
    for (final single in [false, true]) {
      testWidgets(
        '${kind.name} remembered Archive ${single ? 'single after reopen' : 'bulk'} moves to the exact saved folder',
        (tester) async {
          final harness = _Harness(kind)..archiveEnabled = true;
          await _show(tester, harness);
          final initialReads = harness.folderReads;
          _setArchiveCatalog(harness);
          await _openArchiveSettings(tester);
          expect(harness.folderReads, initialReads + 1);
          await _saveArchiveChoice(tester, 2);
          final saved = await _readArchivePreference(tester, harness);
          expect(saved.account, harness.fixture.account);
          expect(saved.revision, 1);
          expect(
            saved.destination,
            MailMailboxId(_customArchiveId(harness), account: saved.account),
          );
          await _expectNoArchiveIntent(tester, harness);
          if (single) {
            final originalOwner = harness.fixture.owner;
            final originalConnection = harness.liveAccount;
            await tester.pumpWidget(const SizedBox.shrink());
            await tester.pump();
            await settleMailJournal(tester, originalOwner.close);
            await _show(tester, harness);
            expect(harness.fixture.owner, isNot(same(originalOwner)));
            if (kind == MailProviderKind.imap) {
              expect(harness.liveAccount, isNot(originalConnection));
            }
            final reopened = await _readArchivePreference(tester, harness);
            expect(reopened.revision, saved.revision);
            expect(reopened.destination, saved.destination);
          }
          final readsBeforeArchive = harness.folderReads;
          await _startProviderArchive(
            tester,
            harness,
            single: single,
            confirm: false,
          );
          expect(harness.folderReads, readsBeforeArchive + 1);
          expect(harness.archiveResolutionReads, 0);
          expect(
            find.text(_strings.mailArchiveSettingsSavedDestination),
            findsOneWidget,
          );
          expect(find.text(_customArchiveId(harness)), findsOneWidget);
          expect(_key('studio-mail-archive-destination-0'), findsNothing);
          await _confirmProviderArchive(tester);
          final count = single ? 1 : 2;
          await _until(
            tester,
            () => harness.commands.length == count && !_list(tester).busy,
          );
          for (final command in harness.commands.cast<MailMove>()) {
            expect(
              command.destination,
              MailMailboxId(
                _customArchiveId(harness),
                account: harness.liveAccount!,
              ),
            );
          }
          for (final receipt in harness.atDispatch) {
            expect(receipt.summary.action, MailBulkFlagAction.move);
            expect(receipt.summary.destination, saved.destination);
            expect(receipt.summary.mailbox.account, saved.account);
          }
          final receipt = await _reopenMembershipReceipt(tester, harness);
          expect(receipt.report.confirmedCount, count);
          expect(receipt.summary.destination, saved.destination);
          final retained = await _readArchivePreference(tester, harness);
          expect(retained.revision, saved.revision);
          expect(retained.destination, saved.destination);
          expect(harness.commands, hasLength(count));
          expect(harness.sends, 0);
        },
      );
    }

    testWidgets(
      '${kind.name} remembered Archive settings work in an empty mailbox and can clear its own folder',
      (tester) async {
        final harness = _Harness(kind)
          ..archiveEnabled = true
          ..messageCount = 0;
        await _show(tester, harness);
        expect(_list(tester).items, isEmpty);
        await _openArchiveSettings(tester);
        await _saveArchiveChoice(tester, 0);
        final saved = await _readArchivePreference(tester, harness);
        expect(saved.destination?.value, _inboxId(harness));
        await _openArchiveSettings(tester);
        expect(
          tester
              .widget<ListTile>(_key('studio-mail-archive-settings-folder-0'))
              .selected,
          isTrue,
        );
        await tester.tap(_key('studio-mail-archive-settings-clear'));
        await _until(
          tester,
          () => _key('studio-mail-archive-settings-dialog').evaluate().isEmpty,
        );
        final cleared = await _readArchivePreference(tester, harness);
        expect(cleared.destination, isNull);
        expect(cleared.revision, saved.revision + 1);
        await _expectNoArchiveIntent(tester, harness);
      },
    );

    testWidgets(
      '${kind.name} remembered Archive never moves messages already in its saved folder',
      (tester) async {
        final harness = _Harness(kind)..archiveEnabled = true;
        await _show(tester, harness);
        await _writeArchivePreference(tester, harness, _inboxId(harness));
        final commits = harness.fixture.commits;
        _requestArchive(tester);
        await _until(
          tester,
          () => find.text(_strings.mailArchiveSameFolder).evaluate().isNotEmpty,
        );
        expect(_key('studio-mail-archive-selection-dialog'), findsNothing);
        expect(harness.archiveResolutionReads, 0);
        expect(harness.fixture.commits, commits);
        await _expectNoArchiveIntent(tester, harness);
        await _openArchiveSettings(tester);
        expect(
          tester
              .widget<TextButton>(_key('studio-mail-archive-settings-clear'))
              .onPressed,
          isNotNull,
        );
        await tester.tap(_key('studio-mail-archive-settings-cancel'));
        await tester.pumpAndSettle();
      },
    );

    testWidgets(
      '${kind.name} remembered Archive rejects an ABA preference change during confirmation before journaling',
      (tester) async {
        final harness = _Harness(kind)..archiveEnabled = true;
        await _show(tester, harness);
        _setArchiveCatalog(harness);
        final saved = await _writeArchivePreference(
          tester,
          harness,
          _customArchiveId(harness),
        );
        await _startProviderArchive(tester, harness, confirm: false);
        await _writeArchivePreference(tester, harness, null);
        final changed = await _writeArchivePreference(
          tester,
          harness,
          _customArchiveId(harness),
        );
        expect(changed.destination, saved.destination);
        expect(changed.revision, saved.revision + 2);
        final commits = harness.fixture.commits;
        await _confirmProviderArchive(tester);
        await _until(
          tester,
          () =>
              find
                  .text(
                    _strings.mailArchiveDestinationFailure(
                      StudioMailArchiveDestinationFailure.changed,
                    ),
                  )
                  .evaluate()
                  .isNotEmpty &&
              !_list(tester).busy,
        );
        expect(harness.fixture.commits, commits);
        expect(_list(tester).items, hasLength(3));
        await _expectNoArchiveIntent(tester, harness);
      },
    );

    testWidgets(
      '${kind.name} missing remembered Archive folder remains visible and never falls back by name',
      (tester) async {
        final harness = _Harness(kind)..archiveEnabled = true;
        await _show(tester, harness);
        _setArchiveCatalog(harness, includeCustom: false);
        final saved = await _writeArchivePreference(
          tester,
          harness,
          _customArchiveId(harness),
        );
        final commits = harness.fixture.commits;
        _requestArchive(tester);
        await _until(
          tester,
          () => find
              .text(
                _strings.mailArchiveDestinationFailure(
                  StudioMailArchiveDestinationFailure.missing,
                ),
              )
              .evaluate()
              .isNotEmpty,
        );
        expect(_key('studio-mail-archive-selection-dialog'), findsNothing);
        expect(harness.archiveResolutionReads, 0);
        expect(harness.fixture.commits, commits);
        await _expectNoArchiveIntent(tester, harness);
        await _openArchiveSettings(tester);
        expect(_key('studio-mail-archive-settings-missing'), findsOneWidget);
        expect(
          tester.widget<Text>(_key('studio-mail-archive-settings-saved')).data,
          saved.destination!.value,
        );
        expect(
          tester
              .widget<FilledButton>(_key('studio-mail-archive-settings-save'))
              .onPressed,
          isNull,
        );
        await tester.tap(_key('studio-mail-archive-settings-clear'));
        await _until(
          tester,
          () => _key('studio-mail-archive-settings-dialog').evaluate().isEmpty,
        );
        final cleared = await _readArchivePreference(tester, harness);
        expect(cleared.destination, isNull);
        expect(cleared.revision, saved.revision + 1);
        await _startProviderArchive(tester, harness, confirm: false);
        expect(harness.archiveResolutionReads, 1);
        expect(
          find.text(_strings.mailArchiveSettingsSavedDestination),
          findsNothing,
        );
        await tester.tap(_key('studio-mail-organization-cancel'));
        await _until(tester, () => !_list(tester).busy);
        await _expectNoArchiveIntent(tester, harness);
      },
    );

    testWidgets(
      '${kind.name} fresh folder failure blocks remembered Archive but still permits explicit clear',
      (tester) async {
        final harness = _Harness(kind)..archiveEnabled = true;
        await _show(tester, harness);
        _setArchiveCatalog(harness, unavailable: true);
        final saved = await _writeArchivePreference(
          tester,
          harness,
          _customArchiveId(harness),
        );
        final commits = harness.fixture.commits;
        _requestArchive(tester);
        await _until(
          tester,
          () => find
              .text(_strings.mailArchiveSettingsLoadFailed)
              .evaluate()
              .isNotEmpty,
        );
        expect(_key('studio-mail-archive-selection-dialog'), findsNothing);
        expect(harness.archiveResolutionReads, 0);
        expect(harness.fixture.commits, commits);
        await _expectNoArchiveIntent(tester, harness);
        await _openArchiveSettings(tester, failed: true);
        expect(_key('studio-mail-archive-settings-saved'), findsOneWidget);
        expect(
          tester
              .widget<FilledButton>(_key('studio-mail-archive-settings-save'))
              .onPressed,
          isNull,
        );
        expect(_key('studio-mail-archive-settings-missing'), findsNothing);
        await tester.tap(_key('studio-mail-archive-settings-clear'));
        await _until(
          tester,
          () => _key('studio-mail-archive-settings-dialog').evaluate().isEmpty,
        );
        final cleared = await _readArchivePreference(tester, harness);
        expect(cleared.destination, isNull);
        expect(cleared.revision, saved.revision + 1);
        await _expectNoArchiveIntent(tester, harness);
      },
    );

    testWidgets(
      '${kind.name} cancelled remembered Archive choice preserves the saved revision',
      (tester) async {
        final harness = _Harness(kind)..archiveEnabled = true;
        await _show(tester, harness);
        _setArchiveCatalog(harness);
        final saved = await _writeArchivePreference(
          tester,
          harness,
          _customArchiveId(harness),
        );
        final commits = harness.fixture.commits;
        await _openArchiveSettings(tester);
        await tester.tap(_key('studio-mail-archive-settings-folder-1'));
        await tester.tap(_key('studio-mail-archive-settings-cancel'));
        await _until(
          tester,
          () => _key('studio-mail-archive-settings-dialog').evaluate().isEmpty,
        );
        final retained = await _readArchivePreference(tester, harness);
        expect(retained.destination, saved.destination);
        expect(retained.revision, saved.revision);
        expect(harness.fixture.commits, commits);
        await _expectNoArchiveIntent(tester, harness);
      },
    );

    testWidgets(
      '${kind.name} retained Archive settings toolbar callback cannot touch a replacement account',
      (tester) async {
        final original = _Harness(kind)..archiveEnabled = true;
        await _show(tester, original);
        final callback = tester
            .widget<IconButton>(_key('studio-mail-archive-settings'))
            .onPressed!;
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await settleMailJournal(tester, original.fixture.owner.close);
        final replacement = _Harness(kind)..archiveEnabled = true;
        await _show(tester, replacement, mailbox: 'replacement@example.test');
        expect(replacement.fixture.account, isNot(original.fixture.account));
        final replacementReads = replacement.folderReads;
        final originalReads = original.folderReads;
        final commits = replacement.fixture.commits;
        callback();
        await tester.pump(const Duration(milliseconds: 350));
        expect(_key('studio-mail-archive-settings-dialog'), findsNothing);
        expect(replacement.folderReads, replacementReads);
        expect(original.folderReads, originalReads);
        expect(replacement.fixture.commits, commits);
        expect(tester.takeException(), isNull);
        await _expectNoArchiveIntent(tester, replacement);
        expect(original.commands, isEmpty);
      },
    );

    testWidgets(
      '${kind.name} Archive settings are absent without Move capability',
      (tester) async {
        final harness = _Harness(kind)
          ..archiveEnabled = true
          ..allowMembership = false;
        await _show(tester, harness);
        expect(_key('studio-mail-archive-settings'), findsNothing);
        await _expectNoArchiveIntent(tester, harness);
      },
    );
  }

  for (final kind in [MailProviderKind.ews, MailProviderKind.graph]) {
    for (final foreign in [false, true]) {
      testWidgets(
        '${kind.name} remembered Archive rejects a ${foreign ? 'foreign' : 'label'} folder with the saved ID',
        (tester) async {
          final harness = _Harness(kind)..archiveEnabled = true;
          await _show(tester, harness);
          _setArchiveCatalog(harness, foreign: foreign, label: !foreign);
          await _writeArchivePreference(
            tester,
            harness,
            _customArchiveId(harness),
          );
          final commits = harness.fixture.commits;
          _requestArchive(tester);
          await _until(
            tester,
            () => find
                .text(
                  _strings.mailArchiveDestinationFailure(
                    foreign
                        ? StudioMailArchiveDestinationFailure.unavailable
                        : StudioMailArchiveDestinationFailure.missing,
                  ),
                )
                .evaluate()
                .isNotEmpty,
          );
          expect(_key('studio-mail-archive-selection-dialog'), findsNothing);
          expect(harness.archiveResolutionReads, 0);
          expect(harness.fixture.commits, commits);
          await _expectNoArchiveIntent(tester, harness);
        },
      );
    }
  }

  testWidgets('IMAP remembered Archive refuses a now non-selectable folder', (
    tester,
  ) async {
    final harness = _Harness(MailProviderKind.imap)..archiveEnabled = true;
    await _show(tester, harness);
    _setArchiveCatalog(harness, selectable: false);
    await _writeArchivePreference(tester, harness, _customArchiveId(harness));
    final commits = harness.fixture.commits;
    _requestArchive(tester);
    await _until(
      tester,
      () => find
          .text(
            _strings.mailArchiveDestinationFailure(
              StudioMailArchiveDestinationFailure.missing,
            ),
          )
          .evaluate()
          .isNotEmpty,
    );
    expect(harness.archiveResolutionReads, 0);
    expect(harness.fixture.commits, commits);
    await _expectNoArchiveIntent(tester, harness);
  });

  testWidgets('Gmail Archive never reads or exposes saved folder settings', (
    tester,
  ) async {
    final harness = _Harness(MailProviderKind.gmail)
      ..archiveEnabled = true
      ..spyArchiveSettings = true;
    await _show(tester, harness);
    await _writeArchivePreference(tester, harness, 'unrelated-saved-folder');
    expect(_key('studio-mail-archive-settings'), findsNothing);
    final folderReads = harness.folderReads;
    await _startProviderArchive(tester, harness);
    await _until(
      tester,
      () => harness.commands.length == 2 && !_list(tester).busy,
    );
    expect(harness.commands, everyElement(isA<MailArchive>()));
    expect(harness.archiveSettingsReads, 0);
    expect(harness.archiveSettingsWrites, 0);
    expect(harness.archiveResolutionReads, 0);
    expect(harness.folderReads, folderReads);
    final receipt = await _reopenMembershipReceipt(tester, harness);
    expect(receipt.summary.action, MailBulkFlagAction.archive);
    expect(receipt.summary.destination, isNull);
    expect(receipt.summary.mailbox.value, 'INBOX');
    expect(receipt.report.confirmedCount, 2);
    final retained = await _readArchivePreference(tester, harness);
    expect(retained.destination?.value, 'unrelated-saved-folder');
    expect(retained.revision, 1);
  });
}

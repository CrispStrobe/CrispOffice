import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_office_studio/studio_mail_compose_tools.dart';
import 'package:quds_office_studio/studio_mail_draft.dart';
import 'package:quds_office_studio/studio_mail_draft_store.dart';
import 'package:quds_office_studio/studio_mail_draft_store_native.dart';
import 'package:quds_office_studio/studio_mail_outbox.dart';
import 'package:quds_office_studio/studio_mail_outbox_content.dart';
import 'package:quds_office_studio/studio_mail_threading.dart';

void main() {
  final identity = _identity();

  test('new and reply defaults are independent and preserve draft fields', () {
    final attachment = StudioMailAttachment(
      name: 'keep.pdf',
      bytes: Uint8List.fromList([0, 128, 255]),
    );
    final draft = StudioMailDraft(
      to: 'reader@example.test',
      cc: 'copy@example.test',
      bcc: 'hidden@example.test',
      subject: 'Re: retained subject',
      body: '\n\n> Original text',
      thread: StudioMailThread.replyTo(
        MailEnvelope(messageId: '<original@example.test>'),
      ),
      attachments: StudioMailAttachments.from([attachment]),
    );
    final settings = MailComposeSettings(
      account: identity.account,
      signature: 'Regards\r\nمرحبا',
      signatureForReplies: true,
    );
    expect(
      applyStudioMailDefaultSignature(
        draft,
        settings,
        replyOrForward: false,
      ),
      same(draft),
    );
    final reply = applyStudioMailDefaultSignature(
      draft,
      settings,
      replyOrForward: true,
    );
    expect(reply.body, '\n\n-- \nRegards\nمرحبا\n\n> Original text');
    expect(reply.to, draft.to);
    expect(reply.cc, draft.cc);
    expect(reply.bcc, draft.bcc);
    expect(reply.subject, draft.subject);
    expect(reply.thread, same(draft.thread));
    expect(reply.attachments, same(draft.attachments));
    expect(draft.body, '\n\n> Original text');
    final newMessage = applyStudioMailDefaultSignature(
      _draft('Personal text'),
      settings.copyWith(
        signatureForNewMessages: true,
        signatureForReplies: false,
      ),
      replyOrForward: false,
    );
    expect(newMessage.body, 'Personal text\n\n-- \nRegards\nمرحبا');
  });

  test('empty/disabled signatures do not change a draft or evaluate text', () {
    final draft = _draft('Hello');
    for (final settings in [
      MailComposeSettings(account: identity.account),
      MailComposeSettings(
        account: identity.account,
        signature: '<b>literal</b> {{recipient}}',
      ),
      MailComposeSettings(
        account: identity.account,
        signatureForNewMessages: true,
      ),
    ]) {
      expect(
        applyStudioMailDefaultSignature(
          draft,
          settings,
          replyOrForward: false,
        ),
        same(draft),
      );
    }
    final literal = applyStudioMailDefaultSignature(
      draft,
      MailComposeSettings(
        account: identity.account,
        signature: '<b>literal</b> {{recipient}}',
        signatureForNewMessages: true,
      ),
      replyOrForward: false,
    );
    expect(literal.body, 'Hello\n\n-- \n<b>literal</b> {{recipient}}');
  });

  test('default insertion refuses invalid metadata and UTF-8 body overflow', () {
    expect(
      () => applyStudioMailDefaultSignature(
        _draft('kept'),
        MailComposeSettings(
          account: identity.account,
          signature: '\u0000',
          signatureForNewMessages: true,
        ),
        replyOrForward: false,
      ),
      throwsA(isA<StudioMailComposeToolsException>()),
    );
    final oversized = _draft('é' * (StudioMailDraft.maxBodyBytes ~/ 2));
    expect(
      () => applyStudioMailDefaultSignature(
        oversized,
        MailComposeSettings(
          account: identity.account,
          signature: 'Name',
          signatureForNewMessages: true,
        ),
        replyOrForward: false,
      ),
      throwsA(isA<StudioMailComposeToolsException>()),
    );
    expect(oversized.body.length, StudioMailDraft.maxBodyBytes ~/ 2);
  });

  test('new-draft preparation never loads a retired owner', () async {
    final tools = _Tools(identity.account);
    await expectLater(
      prepareStudioMailComposeDraft(
        tools,
        _draft(''),
        replyOrForward: false,
        isCurrent: () => false,
      ),
      throwsA(isA<StudioMailComposeToolsException>()),
    );
    expect(tools.loads, 0);
  });

  test('preparation rejects late account retirement and foreign settings', () async {
    final completion = Completer<MailComposeSettings>();
    final tools = _Tools(identity.account, load: () => completion.future);
    var current = true;
    final prepared = prepareStudioMailComposeDraft(
      tools,
      _draft(''),
      replyOrForward: false,
      isCurrent: () => current,
    );
    final rejection = expectLater(
      prepared,
      throwsA(isA<StudioMailComposeToolsException>()),
    );
    current = false;
    completion.complete(MailComposeSettings(account: identity.account));
    await rejection;
    final foreign = _Tools(
      identity.account,
      load: () async => MailComposeSettings(
        account: _identity(sender: 'other@example.test').account,
      ),
    );
    await expectLater(
      prepareStudioMailComposeDraft(
        foreign,
        _draft('kept'),
        replyOrForward: true,
        isCurrent: () => true,
      ),
      throwsA(isA<StudioMailComposeToolsException>()),
    );
  });

  test('legacy owners preserve their existing composition behavior', () async {
    final draft = _draft('Legacy draft');
    expect(
      await prepareStudioMailComposeDraft(
        Object(),
        draft,
        replyOrForward: false,
        isCurrent: () => true,
      ),
      same(draft),
    );
  });

  group('native account adapter', () {
    late Directory directory;
    final opened = <StudioMailDraftStore>[];

    setUp(() async {
      directory = await Directory.systemTemp.createTemp('mail-compose-tools-');
    });
    tearDown(() async {
      for (final store in opened.reversed) {
        await store.close();
      }
      opened.clear();
      await directory.delete(recursive: true);
    });

    Future<StudioMailDraftStore> open([StudioMailDraftAccount? account]) async {
      final store = await openStudioMailDraftStore(
        account ?? identity,
        appDirectory: directory,
      );
      opened.add(store);
      return store;
    }

    test('settings survive reopen without creating a draft or crossing accounts', () async {
      final store = await open();
      final tools = store as StudioMailComposeToolsStore;
      expect(await store.load(), isNull);
      final defaults = await tools.loadComposeSettings();
      final saved = await tools.saveComposeSettings(
        defaults.copyWith(
          signature: 'Account signature',
          signatureForNewMessages: true,
          quickTexts: const [
            MailQuickText(id: 'thanks', name: 'Thanks', text: 'Thank you.\nNext step'),
          ],
        ),
      );
      expect(saved.revision, 1);
      expect(await store.load(), isNull);
      await store.close();
      final reopened = await open();
      final restored = await (reopened as StudioMailComposeToolsStore)
          .loadComposeSettings();
      expect(restored.signature, 'Account signature');
      expect(restored.quickTexts.single.text, 'Thank you.\nNext step');
      expect(restored.revision, 1);
      final other = await open(_identity(sender: 'other@example.test'));
      final otherTools = other as StudioMailComposeToolsStore;
      final otherSettings = await otherTools.loadComposeSettings();
      expect(otherSettings.signature, isEmpty);
      expect(otherSettings.quickTexts, isEmpty);
      await expectLater(
        otherTools.saveComposeSettings(restored),
        throwsA(
          isA<StudioMailDraftStoreException>().having(
            (error) => error.code,
            'code',
            MailProblemCode.permissionDenied,
          ),
        ),
      );
    });

    test('stale settings fail without replacing the last saved revision', () async {
      final tools = (await open()) as StudioMailComposeToolsStore;
      final first = await tools.loadComposeSettings();
      final second = await tools.loadComposeSettings();
      await tools.saveComposeSettings(first.copyWith(signature: 'kept'));
      await expectLater(
        tools.saveComposeSettings(second.copyWith(signature: 'stale')),
        throwsA(
          isA<StudioMailDraftStoreException>().having(
            (error) => error.code,
            'code',
            MailProblemCode.conflict,
          ),
        ),
      );
      expect((await tools.loadComposeSettings()).signature, 'kept');
    });

    test('settings updates preserve resumed drafts and frozen Outbox bytes', () async {
      final store = await open();
      final tools = store as StudioMailComposeToolsStore;
      final settings = await tools.saveComposeSettings(
        (await tools.loadComposeSettings()).copyWith(
          signature: 'Original signature',
          signatureForNewMessages: true,
        ),
      );
      final initial = await prepareStudioMailComposeDraft(
        tools,
        _draft('Body'),
        replyOrForward: false,
        isCurrent: () => true,
      );
      await (store as StudioMailDraftCatalog).createDraft(initial);
      await tools.saveComposeSettings(settings.copyWith(signature: 'Changed'));
      final resumed = (await store.load())!;
      expect(resumed.draft.body, 'Body\n\n-- \nOriginal signature');
      final outbox = store as StudioMailOutboxStore;
      final queued = await outbox.enqueueOutbox(resumed.draft, identity.sender);
      final wireHash = queued.prepared.wire.sha256;
      await tools.saveComposeSettings(
        (await tools.loadComposeSettings()).copyWith(signature: ''),
      );
      await store.close();
      final reopened = await open();
      final retained = (await (reopened as StudioMailOutboxStore)
          .loadOutbox()).single;
      expect(retained.prepared.wire.sha256, wireHash);
      expect(
        StudioMailOutboxContent.fromEntry(retained).draft.body,
        'Body\n\n-- \nOriginal signature',
      );
    });

    test('settings preserve uncertainty and close drains accepted writes', () async {
      final store = await open();
      await store.load();
      await store.save(_draft('Uncertain draft'), submissionUncertain: true);
      final tools = store as StudioMailComposeToolsStore;
      final settings = await tools.loadComposeSettings();
      final pending = tools.saveComposeSettings(settings.copyWith(signature: 'Saved'));
      final closing = store.close();
      await pending;
      await closing;
      await expectLater(
        tools.loadComposeSettings(),
        throwsA(
          isA<StudioMailDraftStoreException>().having(
            (error) => error.code,
            'code',
            MailProblemCode.unavailable,
          ),
        ),
      );
      final reopened = await open();
      expect((await reopened.load())!.submissionUncertain, isTrue);
      expect(
        (await (reopened as StudioMailComposeToolsStore).loadComposeSettings())
            .signature,
        'Saved',
      );
    });
  });
}

StudioMailDraftAccount _identity({String sender = 'sender@example.test'}) =>
    StudioMailDraftAccount(
      provider: 'imap',
      endpoint: 'imaps://mail.example.test:993',
      login: sender,
      sender: sender,
    );

StudioMailDraft _draft(String body) => StudioMailDraft(
  to: 'recipient@example.test',
  subject: 'Writing tools',
  body: body,
);

final class _Tools implements StudioMailComposeToolsStore {
  _Tools(this.account, {Future<MailComposeSettings> Function()? load})
      : _load = load;

  @override
  final MailAccountId account;
  final Future<MailComposeSettings> Function()? _load;
  int loads = 0;

  @override
  Future<MailComposeSettings> loadComposeSettings() async {
    loads++;
    final loader = _load;
    return loader == null ? MailComposeSettings(account: account) : await loader();
  }

  @override
  Future<MailComposeSettings> saveComposeSettings(MailComposeSettings settings) =>
      Future.error(StateError('Unexpected settings write.'));
}

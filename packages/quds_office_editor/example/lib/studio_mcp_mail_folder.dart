import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_office_engine/quds_productivity_automation.dart';

ProductivityFolderBrowser studioMcpMailFolder({
  required MailMailboxId mailbox,
  required bool allowText,
  required bool Function() isScoped,
  required Future<MailHeaderPage?> Function(String? after) load,
  required Future<ProductivityMailText?> Function(
    MailRemoteIdentity,
    bool Function(),
  )
  read,
}) => ProductivityFolderBrowser(
  allowText: allowText,
  load: (cursor, current) async {
    bool allowed() => current() && isScoped();
    if (!allowed()) return null;
    final page = await load(cursor);
    if (!allowed() ||
        page == null ||
        (page.next != null && page.next!.mailbox != mailbox)) {
      return null;
    }
    final identities = <MailRemoteIdentity>{};
    final messages = <ProductivityFolderMessage>[];
    for (final row in page.messages) {
      final identity = row.remote;
      if (identity.account != mailbox.account || !identities.add(identity)) {
        return null;
      }
      messages.add(
        ProductivityFolderMessage(
          subject: row.envelope.subject,
          date: row.envelope.sentAt,
          unread: row.flags == null ? null : !row.flags!.isRead,
          read: (readCurrent) async {
            bool canRead() => readCurrent() && isScoped();
            return canRead() ? await read(identity, canRead) : null;
          },
        ),
      );
    }
    return (messages: messages, next: page.next?.value);
  },
);

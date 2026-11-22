import 'dart:async';

import 'package:enough_mail/enough_mail.dart' as mail;
import 'package:quds_mail_core/quds_mail_core.dart';

/// Fields accepted by the bounded provider-side search. Body search is executed
/// by the IMAP server; the client never downloads every body to filter locally.
enum StudioMailServerSearchField { body, subject, from, to }

/// One completed server-side search over the currently selected folder.
///
/// [totalMatches] is the provider's matching count before the result cap.
/// [messages] contains at most the requested page and never fabricates missing
/// rows. [truncated] is true when more matches exist than were returned.
final class StudioMailServerSearchResult {
  StudioMailServerSearchResult({
    required this.field,
    required this.query,
    required this.mailboxName,
    required this.totalMatches,
    required List<mail.MimeMessage> messages,
    required this.truncated,
  }) : messages = List.unmodifiable(messages);

  final StudioMailServerSearchField field;
  final String query;
  final String mailboxName;
  final int totalMatches;
  final List<mail.MimeMessage> messages;
  final bool truncated;

  bool get isEmpty => messages.isEmpty;
}

/// Runs a bounded IMAP `SEARCH` and fetches envelope data for the first page.
///
/// The selected folder is searched as a whole at the provider's current
/// snapshot. Attachment text, unindexed server content and folders other than
/// [mailbox] are outside this coverage. Cancellation is cooperative: an
/// in-flight `SEARCH` command cannot be interrupted by enough_mail, but its
/// result is discarded and no later page is requested after [cancellation].
Future<StudioMailServerSearchResult> studioMailServerSearch({
  required mail.MailClient client,
  required mail.Mailbox mailbox,
  required StudioMailServerSearchField field,
  required String query,
  int limit = 50,
  MailCancellationToken? cancellation,
}) async {
  final text = query.trim();
  if (text.isEmpty ||
      text.length > 512 ||
      RegExp(r'[\x00-\x1f\x7f]').hasMatch(text)) {
    throw const FormatException('Invalid server search query.');
  }
  if (limit < 1 || limit > 100) {
    throw const FormatException('Invalid server search limit.');
  }
  if (mailbox.isNotSelectable) {
    throw StateError('The selected folder cannot be searched.');
  }
  cancellation?.throwIfCancelled();
  await client.selectMailbox(mailbox);
  cancellation?.throwIfCancelled();
  final result = await client.searchMessages(
    mail.MailSearch(
      text,
      switch (field) {
        StudioMailServerSearchField.body => mail.SearchQueryType.body,
        StudioMailServerSearchField.subject => mail.SearchQueryType.subject,
        StudioMailServerSearchField.from => mail.SearchQueryType.from,
        StudioMailServerSearchField.to => mail.SearchQueryType.to,
      },
      pageSize: limit,
      fetchPreference: mail.FetchPreference.envelope,
    ),
  );
  cancellation?.throwIfCancelled();
  final messages = result.messages.take(limit).toList(growable: false);
  if (messages.any((message) => message.uid == null)) {
    throw StateError('Server search returned a message without a UID.');
  }
  return StudioMailServerSearchResult(
    field: field,
    query: text,
    mailboxName: mailbox.name,
    totalMatches: result.length,
    messages: messages,
    truncated: result.length > messages.length,
  );
}

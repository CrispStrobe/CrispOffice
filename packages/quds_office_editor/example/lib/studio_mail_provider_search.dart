import 'package:quds_mail_core/quds_mail_core.dart';

import 'studio_mail_server_search.dart';

/// A redacted provider failure that the dialog can translate without exposing
/// server responses, endpoints, authorization tokens or message content.
final class StudioMailProviderSearchFailure implements Exception {
  const StudioMailProviderSearchFailure(this.code);
  final MailProblemCode code;

  @override
  String toString() => 'StudioMailProviderSearchFailure(${code.name})';
}

MailProviderSearchRequest studioMailProviderSearchRequest({
  required MailMailboxId mailbox,
  required MailProviderSearchField field,
  required StudioMailServerSearchRange range,
  required String query,
  DateTime? now,
}) {
  final instant = (now ?? DateTime.now()).toUtc();
  // Use a UTC day boundary that all exposed provider date grammars represent.
  // Graph's KQL search accepts calendar-day bounds, while EWS and Gmail can
  // also express finer timestamps. Do not offer an unusable range in Graph.
  final current = DateTime.utc(instant.year, instant.month, instant.day);
  final days = switch (range) {
    StudioMailServerSearchRange.anyTime => null,
    StudioMailServerSearchRange.last7Days => 7,
    StudioMailServerSearchRange.last30Days => 30,
    StudioMailServerSearchRange.last90Days => 90,
  };
  return MailProviderSearchRequest(
    mailbox: mailbox,
    field: field,
    query: query.trim(),
    receivedAfter: days == null ? null : current.subtract(Duration(days: days)),
    maxResults: 50,
  );
}

/// Search keeps the same exact account lease and folder across every await.
/// The caller additionally checks its displayed-folder generation before
/// adopting the returned snapshot or opening a chosen message.
Future<MailProviderSearchResult> runStudioMailProviderSearch({
  required MailProviderSearch provider,
  required MailProviderSearchRequest request,
  required MailOperationLease lease,
}) async {
  lease.checkCurrent();
  if (request.mailbox.account != lease.account || !request.isValid) {
    throw const StudioMailProviderSearchFailure(MailProblemCode.invalidInput);
  }
  if (!provider.searchFields.contains(request.field)) {
    throw const StudioMailProviderSearchFailure(MailProblemCode.unsupported);
  }
  final response = await provider.search(request, lease: lease);
  lease.checkCurrent();
  final result = switch (response) {
    MailSuccess<MailProviderSearchResult>(:final value) => value,
    MailFailure<MailProviderSearchResult>(:final problem) =>
      throw StudioMailProviderSearchFailure(problem.code),
  };
  if (result.mailbox != request.mailbox ||
      result.messages.length > request.maxResults ||
      result.messages.map((message) => message.id).toSet().length !=
          result.messages.length) {
    throw const StudioMailProviderSearchFailure(MailProblemCode.conflict);
  }
  return result;
}

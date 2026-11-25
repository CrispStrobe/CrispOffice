part of 'provider.dart';

extension _EwsProviderSearch on NativeMailEwsProvider {
  Future<MailResult<MailProviderSearchResult>> _search(
    MailProviderSearchRequest request, {
    required MailOperationLease lease,
  }) async {
    if (!request.isValid || !_mailboxValid(request.mailbox)) {
      return _failure(MailProblemCode.invalidInput);
    }
    if (!searchFields.contains(request.field)) {
      return _failure(MailProblemCode.unsupported);
    }
    return _run(lease, (client, operation) async {
      final messages = <MailHeaderRecord>[];
      final seen = <String>{};
      var offset = 0;
      var pages = 0;
      var scanned = 0;
      var more = false;
      int? total;
      var exact = true;
      final candidateLimit = request.maxResults + 1;
      do {
        operation.check();
        final limit = math.min(limits.maxPageSize, candidateLimit - scanned);
        final page = _soap.itemIdsPage(
          await operation.post(
            client,
            'FindItem',
            _soap.findItems(
              request.mailbox.value,
              offset: offset,
              limit: limit,
              search: request,
            ),
          ),
        );
        if (page.items.length > limit) {
          throw const EwsException(MailProblemCode.quotaExceeded);
        }
        if (pages == 0) total = page.totalCount;
        if (total == null || page.totalCount != total) exact = false;
        for (final item in page.items) {
          if (!seen.add(item.id)) {
            throw const EwsException(MailProblemCode.providerFailure);
          }
        }
        final items = await _items(
          client,
          operation,
          page.items.map((item) => item.id).toList(),
          allowMissing: true,
          includeMembership: true,
        );
        for (final item in items) {
          if (item == null || item.parentFolderId != request.mailbox.value) {
            // Search and GetItem are separate observations. An intervening
            // delete/move is not evidence of membership in the searched folder.
            exact = false;
            continue;
          }
          messages.add(_record(item));
        }
        scanned += page.items.length;
        more = !page.lastPage;
        if (more) {
          final next = page.nextOffset;
          if (next == null || next <= offset || next > 0x7fffffff) {
            throw const EwsException(MailProblemCode.providerFailure);
          }
          offset = next;
        }
        pages++;
      } while (more && scanned < candidateLimit && pages < 8);
      if (total != null && total! < messages.length) {
        throw const EwsException(MailProblemCode.providerFailure);
      }
      return MailProviderSearchResult(
        mailbox: request.mailbox,
        messages: messages.take(request.maxResults).toList(),
        hasMore: more || messages.length > request.maxResults,
        totalCount: total,
        countPrecision: total == null
            ? MailSearchCountPrecision.unknown
            : exact
            ? MailSearchCountPrecision.exact
            : MailSearchCountPrecision.estimate,
      );
    });
  }
}

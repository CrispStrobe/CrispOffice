part of 'provider.dart';

extension _CloudProviderSearch on ApiMailCloudProvider {
  Future<MailResult<MailProviderSearchResult>> _search(
    MailProviderSearchRequest request, {
    required MailOperationLease lease,
  }) async {
    if (!request.isValid || !_mailboxValid(request.mailbox)) {
      return _failure(MailProblemCode.invalidInput);
    }
    if (!searchFields.contains(request.field) ||
        // Neither API documents a portable literal escape for embedded phrase
        // delimiters/wildcards. Refuse these rather than broaden the search.
        request.query.contains(RegExp(r'["\\*]')) ||
        (!_gmail &&
            [request.receivedAfter, request.receivedBefore].any(
              (value) =>
                  value != null &&
                  (value.hour != 0 || value.minute != 0 || value.second != 0),
            ))) {
      return _failure(MailProblemCode.unsupported);
    }
    return _run(lease, MailCloudOperation.search, (operation) async {
      return _gmail
          ? _searchGmail(request, operation)
          : _searchGraph(request, operation);
    });
  }

  /// Phrase quoting prevents a literal such as `x OR from:y` from creating
  /// an additional provider clause. Field names come only from the typed enum.
  String _searchPhrase(MailProviderSearchRequest request) =>
      '${request.field.name}:"${request.query}"';

  Future<MailProviderSearchResult> _searchGmail(
    MailProviderSearchRequest request,
    _Operation operation,
  ) async {
    final parts = [_searchPhrase(request)];
    if (request.receivedAfter case final date?
        when date.millisecondsSinceEpoch > 0) {
      // Gmail's after: bound is exclusive. Widen by one second, then check
      // internalDate after retrieval to implement an exact inclusive bound.
      parts.add('after:${date.millisecondsSinceEpoch ~/ 1000 - 1}');
    }
    if (request.receivedBefore case final date?) {
      parts.add('before:${date.millisecondsSinceEpoch ~/ 1000}');
    }
    final records = <MailHeaderRecord>[];
    final seen = <String>{};
    final tokens = <String>{};
    String? token;
    int? estimate;
    var pages = 0;
    var scanned = 0;
    var more = false;
    // One look-ahead match establishes truncation without trusting an estimate.
    final candidateLimit = request.maxResults + 1;
    do {
      operation.check();
      final pageSize = math.min(limits.maxPageSize, candidateLimit - scanned);
      final data = await _json(
        operation,
        'GET',
        _gmailUri(
          ['messages'],
          {
            'labelIds': request.mailbox.value,
            'q': parts.join(' '),
            'maxResults': '$pageSize',
            'includeSpamTrash': 'true',
            'pageToken': ?token,
          },
        ),
      );
      final reported = data['resultSizeEstimate'];
      if (reported != null) {
        if (reported is! int || reported < 0 || reported > 0xffffffff) {
          _fail(MailProblemCode.providerFailure);
        }
        // An estimate can change during pagination, but is never exact.
        estimate = reported;
      }
      final ids = _gmailListIds(data, pageSize);
      scanned += ids.length;
      for (final id in ids) {
        if (!seen.add(id)) _fail(MailProblemCode.providerFailure);
        final item = await _gmailMetadata(operation, id, allowMissing: true);
        if (item == null) continue;
        // Require explicit membership, including empty labels for a message
        // moved after search. Missing/corrupt membership cannot imply success.
        final labels = _archiveLabels(item);
        if (!labels.contains(request.mailbox.value)) continue;
        if (request.receivedAfter != null || request.receivedBefore != null) {
          final raw = _text(item['internalDate'], max: 20);
          if (!RegExp(r'^\d{1,16}$').hasMatch(raw)) {
            _fail(MailProblemCode.providerFailure);
          }
          final milliseconds = int.tryParse(raw);
          if (milliseconds == null || milliseconds > 253402300799999) {
            _fail(MailProblemCode.providerFailure);
          }
          final date = DateTime.fromMillisecondsSinceEpoch(
            milliseconds,
            isUtc: true,
          );
          if (!_withinSearchDates(date, request)) continue;
        }
        records.add(_gmailRecord(item));
      }
      token = data['nextPageToken'] == null
          ? null
          : _text(data['nextPageToken'], max: limits.maxCursorBytes);
      if (token != null && !tokens.add(token)) {
        _fail(MailProblemCode.providerFailure);
      }
      pages++;
      more = token != null;
      // Empty pages with distinct tokens still have a fixed operation bound.
    } while (more && scanned < candidateLimit && pages < 8);
    operation.itemCount = math.min(records.length, request.maxResults);
    return MailProviderSearchResult(
      mailbox: request.mailbox,
      messages: records.take(request.maxResults).toList(),
      hasMore: more || records.length > request.maxResults,
      totalCount: estimate,
      countPrecision: estimate == null
          ? MailSearchCountPrecision.unknown
          : MailSearchCountPrecision.estimate,
    );
  }

  Future<MailProviderSearchResult> _searchGraph(
    MailProviderSearchRequest request,
    _Operation operation,
  ) async {
    final clauses = [_searchPhrase(request)];
    if (request.receivedAfter case final date?) {
      clauses.add('received>=${_searchDay(date)}');
    }
    if (request.receivedBefore case final date?) {
      clauses.add('received<${_searchDay(date)}');
    }
    final route = ['mailFolders', request.mailbox.value, 'messages'];
    final candidateLimit = request.maxResults + 1;
    final pageSize = math.min(limits.maxPageSize, candidateLimit);
    Uri? uri = _graphUri(route, {
      r'$search': jsonEncode(clauses.join(' AND ')),
      r'$select': '${ApiMailCloudProvider._graphSelect},receivedDateTime',
      r'$top': '$pageSize',
    });
    final records = <MailHeaderRecord>[];
    final seen = <String>{};
    final visited = <String>{};
    var scanned = 0;
    var pages = 0;
    while (uri != null && scanned < candidateLimit && pages < 8) {
      operation.check();
      if (!visited.add(uri.toString())) {
        _fail(MailProblemCode.providerFailure);
      }
      final data = await _json(operation, 'GET', uri);
      final values = _array(data['value']);
      if (values.length > pageSize) _fail(MailProblemCode.quotaExceeded);
      for (final value in values) {
        final item = _object(value);
        final id = _text(item['id']);
        if (!seen.add(id)) _fail(MailProblemCode.providerFailure);
        // No foreign-folder rows are accepted, even from a valid continuation.
        if (_text(item['parentFolderId']) != request.mailbox.value) {
          _fail(MailProblemCode.providerFailure);
        }
        if (request.receivedAfter != null || request.receivedBefore != null) {
          final raw = _text(item['receivedDateTime'], max: 64);
          final date = DateTime.tryParse(raw);
          if (date == null || !date.isUtc) {
            _fail(MailProblemCode.providerFailure);
          }
          if (!_withinSearchDates(date, request)) continue;
        }
        // The response page has already been bounded and checked. Limit the
        // returned projection, including a single look-ahead record.
        if (records.length < candidateLimit) records.add(_graphRecord(item));
      }
      scanned += values.length;
      uri = data['@odata.nextLink'] == null
          ? null
          : _graphContinuation(
              _text(data['@odata.nextLink'], max: limits.maxCursorBytes),
              route,
              operation,
            );
      pages++;
    }
    operation.itemCount = math.min(records.length, request.maxResults);
    return MailProviderSearchResult(
      mailbox: request.mailbox,
      messages: records.take(request.maxResults).toList(),
      hasMore: uri != null || records.length > request.maxResults,
      // Graph message search is index-backed and capped by the service. An
      // exhausted response never establishes an exact global cardinality.
      countPrecision: MailSearchCountPrecision.unknown,
    );
  }

  static bool _withinSearchDates(
    DateTime value,
    MailProviderSearchRequest request,
  ) =>
      (request.receivedAfter == null ||
          !value.isBefore(request.receivedAfter!)) &&
      (request.receivedBefore == null ||
          value.isBefore(request.receivedBefore!));

  static String _searchDay(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
}

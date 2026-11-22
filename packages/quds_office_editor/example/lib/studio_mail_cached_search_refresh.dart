import 'package:quds_mail_core/quds_mail_core.dart';

import 'studio_mail_cached_search.dart';
import 'studio_mail_mailbox_store.dart';

/// A staged replacement for one saved-header search, never an incremental
/// append to an earlier refresh. Completion describes only retained headers.
final class StudioMailCachedSearchRefreshBatch {
  StudioMailCachedSearchRefreshBatch._({
    required List<StudioMailCachedSearchHit> hits,
    required List<StudioMailCachedSearchCoverage> coverage,
    required this.hasMore,
    required this.pagesRead,
    required this.resultLimitReached,
    required this.pageLimitReached,
  }) : hits = List<StudioMailCachedSearchHit>.unmodifiable(hits),
       coverage = List<StudioMailCachedSearchCoverage>.unmodifiable(coverage);

  final List<StudioMailCachedSearchHit> hits;
  final List<StudioMailCachedSearchCoverage> coverage;
  final bool hasMore;
  final int pagesRead;

  /// True only when the result allowance stopped remaining discovery.
  final bool resultLimitReached;

  /// True only when the page allowance stopped remaining discovery. Each page
  /// inspects at most 500 headers, including pages with no matching results.
  final bool pageLimitReached;

  bool get limited => resultLimitReached || pageLimitReached;

  /// Includes unfinished account coverage as well as explicit account errors.
  bool get hasCoverageProblems => coverage.any(
    (account) =>
        !account.complete ||
        account.problem != null ||
        account.missingMailboxIds.isNotEmpty,
  );

  /// Suitable for scheduling another automatic refresh only while the host
  /// still owns this query and account scope.
  bool get complete => !hasMore && !hasCoverageProblems;
}

/// Collects a bounded replacement using a fresh [session] for each refresh.
///
/// Pages run sequentially and never read bodies, drafts, credentials or a
/// provider. Result identity includes both account and local message ID. If an
/// account fails after earlier pages, all its staged hits are discarded while
/// its failure remains in [StudioMailCachedSearchRefreshBatch.coverage].
///
/// [isCurrent] can fence the host's refresh generation independently of the
/// session. A stale operation throws without publishing a batch. The caller
/// retains ownership of [session] and must close/drain it, including on failure
/// or cancellation; this helper never closes the supplied session.
/// [maxPages] must be 1–100 and [maxResults] must be 1–1000; both limits are
/// validated before any profile is opened or read.
Future<StudioMailCachedSearchRefreshBatch> refreshStudioMailCachedSearch(
  StudioMailCachedSearchSession session, {
  int maxPages = 100,
  int maxResults = 1000,
  bool Function()? isCurrent,
}) async {
  if (maxPages < 1 || maxPages > 100 || maxResults < 1 || maxResults > 1000) {
    throw const StudioMailMailboxStoreException(MailProblemCode.invalidInput);
  }

  void checkCurrent() {
    if (!session.isActive || (isCurrent != null && !isCurrent())) {
      throw const StudioMailMailboxStoreException(
        MailProblemCode.staleOperation,
      );
    }
  }

  checkCurrent();
  final hits = <String, StudioMailCachedSearchHit>{};
  var pagesRead = 0;
  while (session.hasMore && pagesRead < maxPages && hits.length < maxResults) {
    checkCurrent();
    final remaining = maxResults - hits.length;
    final List<StudioMailCachedSearchHit> page;
    try {
      page = await session.nextPage(
        limit: remaining < 100 ? remaining : 100,
        scanLimit: 500,
      );
    } on Object {
      checkCurrent();
      rethrow;
    }
    checkCurrent();
    pagesRead++;
    final failedAccounts = <String>{
      for (final account in session.coverage)
        if (account.problem != null) account.account.id,
    };
    hits.removeWhere((_, hit) => failedAccounts.contains(hit.account.id));
    for (final hit in page) {
      if (!failedAccounts.contains(hit.account.id)) hits[hit.key] = hit;
    }
  }

  checkCurrent();
  // Earlier accounts have already released their owners. Recheck the whole
  // directory and explicitly selected local folders after later accounts finish
  // before publishing any replacement.
  await session.validateAccountScope();
  checkCurrent();
  final invalidAccounts = <String>{
    for (final account in session.coverage)
      if (account.problem != null) account.account.id,
  };
  hits.removeWhere((_, hit) => invalidAccounts.contains(hit.account.id));
  final hasMore = session.hasMore;
  return StudioMailCachedSearchRefreshBatch._(
    hits: hits.values.toList(growable: false),
    coverage: session.coverage,
    hasMore: hasMore,
    pagesRead: pagesRead,
    resultLimitReached: hasMore && hits.length >= maxResults,
    pageLimitReached: hasMore && pagesRead >= maxPages,
  );
}

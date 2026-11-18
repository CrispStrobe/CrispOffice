import 'package:quds_proofing_spacy/quds_proofing_spacy.dart';

import 'studio_spacy_host.dart';

StudioSpacyHost createHost() => _UnsupportedStudioSpacyHost();

/// Browser builds have no native analysis and never download anything.
class _UnsupportedStudioSpacyHost extends StudioSpacyHost {
  @override
  final StudioSpacyStatus status = StudioSpacyStatus(
    platformLabel: SpacyPlatform.web.id,
    source: StudioSpacySource.none,
    unavailableReason: spacyPlatformStatus(SpacyPlatform.web).reason,
  );

  @override
  Future<void> refresh() async {}

  @override
  Future<void> restoreGrammarOptIn() async {}

  @override
  Future<void> install({
    void Function(int received, int total)? onProgress,
    StudioSpacyInstallCancellation? cancellation,
  }) async => throw const SpacyUnavailableException(
    'Native analysis is unavailable in the browser.',
  );

  @override
  Future<void> remove() async {}

  @override
  Future<void> setAnalysisEnabled(bool enabled) async {}

  @override
  Future<void> setGrammarEnabled(bool enabled) async {}

  @override
  Future<SpacyTransport> openTransport() async =>
      throw const SpacyUnavailableException(
        'Local German analysis is unavailable in the browser.',
      );
}

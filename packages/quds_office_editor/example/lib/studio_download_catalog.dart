import 'package:flutter/foundation.dart';
import 'package:quds_proofing_spacy/quds_proofing_spacy.dart';

import 'studio_font_pack_host.dart';

import 'studio_arabic_morph_host.dart';
import 'studio_hunspell_host.dart';
import 'studio_spacy_host.dart';

/// What a downloadable language package does; drives the leading icon.
enum StudioDownloadKind {
  spelling,
  morphology,
  contextModel,
  analysis,
  entities,
  fonts,
}

/// The state a package row shows in its status chip.
enum StudioDownloadState {
  notInstalled,
  installed,
  downloading,

  /// Installed files failed verification or loading.
  needsRepair,

  /// Another package must be installed first (shown with [StudioDownloadItem.requires]).
  needsPrerequisite,

  /// This host cannot offer the package ([StudioDownloadItem.unavailableReason]).
  unavailable,
}

/// Which existing review dialog shows source, files, SHA-256 and licence and
/// performs the explicit install.
enum StudioDownloadReview { dictionaries, analysis, fontPack }

/// One downloadable package, read from the hosts. The Language downloads
/// overview lists exactly these; the review dialogs install them.
@immutable
class StudioDownloadItem {
  const StudioDownloadItem({
    required this.id,
    required this.kind,
    required this.language,
    required this.title,
    required this.bytes,
    required this.licence,
    required this.licenceUrl,
    required this.state,
    required this.review,
    this.exactSizeOnDisk = true,
    this.note,
    this.description,
    this.problem,
    this.unavailableReason,
    this.requires,
    this.progress,
    this.remove,
    this.cancel,
  });

  /// Stable id; also the [StudioDownloadActivity] key.
  final String id;
  final StudioDownloadKind kind;

  /// Primary language subtag (`ar`, `de`, `en`, `fr`), or [studioFontGroup].
  final String language;
  final String title;

  /// Download size (and, when [exactSizeOnDisk], the verified size on disk).
  final int bytes;
  final bool exactSizeOnDisk;

  /// Short licence name (e.g. `MPL 1.1`) and the page with its terms.
  final String licence;
  final Uri licenceUrl;
  final StudioDownloadState state;
  final StudioDownloadReview review;

  /// One short qualifier shown under the metadata, translated by the dialog.
  final StudioDownloadNote? note;

  /// The package's own one-line description (font packs), untranslated.
  final String? description;
  final String? problem;
  final String? unavailableReason;

  /// The [id] of the package this one needs.
  final String? requires;

  /// Download progress 0..1 while [state] is downloading (null: unknown).
  final double? progress;

  /// Removes the downloaded data; null when nothing is installed.
  final Future<void> Function()? remove;

  /// Cancels a running download.
  final VoidCallback? cancel;
}

/// Fixed qualifiers shown on a row, translated by the dialog.
enum StudioDownloadNote {
  modelFilesOnly,
  includesNativePackage,
  includesSharedRuntime,
  developerConfiguration,
  analysisOnly,
}

/// Tracks downloads that a review dialog started, so the overview can show
/// their progress and cancel them.
class StudioDownloadActivity extends ChangeNotifier {
  final Map<String, ({double? progress, VoidCallback cancel})> _active = {};

  ({double? progress, VoidCallback cancel})? operator [](String id) =>
      _active[id];

  bool get isEmpty => _active.isEmpty;

  /// Runs [download] as package [id]; the reporter it receives updates the
  /// progress. The entry is removed when [download] completes or fails.
  Future<void> track(
    String id, {
    required VoidCallback cancel,
    required Future<void> Function(void Function(int received, int total))
    download,
  }) async {
    _active[id] = (progress: 0, cancel: cancel);
    notifyListeners();
    try {
      await download((received, total) {
        final entry = _active[id];
        if (entry == null || total <= 0) return;
        _active[id] = (progress: received / total, cancel: entry.cancel);
        notifyListeners();
      });
    } finally {
      _active.remove(id);
      notifyListeners();
    }
  }

  void cancel(String id) => _active[id]?.cancel();
}

/// The process-wide download activity shared by the review dialogs and the
/// overview.
final StudioDownloadActivity studioDownloadActivity = StudioDownloadActivity();

/// Ids of the spaCy packages (German, its NER model, other languages).
const studioSpacyGermanId = 'spacy-de';
const studioSpacyNerId = 'spacy-ner-de';
String studioSpacyLanguageId(SpacyLanguage language) =>
    'spacy-${language.code}';

/// Short licence names and their pages for the licences the catalog uses.
String studioShortLicence(String licence) {
  var short = licence.split(' (').first.split('. ').first.split(',').first;
  short = short.trim();
  return switch (short) {
    'CC-BY-4.0' => 'CC BY 4.0',
    'CC-BY-SA-4.0' => 'CC BY-SA 4.0',
    'SIL Open Font License 1.1' => 'OFL 1.1',
    _ => short,
  };
}

Uri studioLicenceUrl(String shortLicence) => Uri.parse(switch (shortLicence) {
  'MPL 1.1' => 'https://www.mozilla.org/en-US/MPL/1.1/',
  'CC BY 4.0' => 'https://creativecommons.org/licenses/by/4.0/',
  'CC BY-SA 4.0' => 'https://creativecommons.org/licenses/by-sa/4.0/',
  'LGPL-LR' => 'https://spdx.org/licenses/LGPLLR.html',
  _ => 'https://opensource.org/license/mit',
});

/// Every downloadable package the three hosts offer, in catalog order. This
/// is the single list the Language downloads overview renders; the
/// Dictionaries dialog ([StudioDownloadReview.dictionaries]) and Analysis
/// setup ([StudioDownloadReview.analysis]) review and install the same ids.
List<StudioDownloadItem> studioDownloadCatalog({
  required StudioHunspellHost hunspell,
  required StudioArabicMorphHost morphology,
  required StudioSpacyHost spacy,
  StudioFontPackHost? fontPacks,
  StudioDownloadActivity? activity,
}) {
  final items = <StudioDownloadItem>[];
  StudioDownloadState state({
    required String id,
    required bool installed,
    String? problem,
    String? unavailable,
    bool prerequisiteMissing = false,
  }) {
    if (activity?[id] != null) return StudioDownloadState.downloading;
    if (problem != null) return StudioDownloadState.needsRepair;
    if (installed) return StudioDownloadState.installed;
    if (unavailable != null) return StudioDownloadState.unavailable;
    if (prerequisiteMissing) return StudioDownloadState.needsPrerequisite;
    return StudioDownloadState.notInstalled;
  }

  StudioDownloadItem item({
    required String id,
    required StudioDownloadKind kind,
    required String language,
    required String title,
    required int bytes,
    required String licence,
    required StudioDownloadReview review,
    required bool installed,
    String? problem,
    String? unavailable,
    String? requires,
    bool prerequisiteMissing = false,
    bool exactSizeOnDisk = true,
    StudioDownloadNote? note,
    String? description,
    Future<void> Function()? remove,
    Uri? licenceUrl,
  }) {
    final short = studioShortLicence(licence);
    final running = activity?[id];
    return StudioDownloadItem(
      id: id,
      kind: kind,
      language: language,
      title: title,
      bytes: bytes,
      licence: short,
      licenceUrl: licenceUrl ?? studioLicenceUrl(short),
      review: review,
      state: state(
        id: id,
        installed: installed,
        problem: problem,
        unavailable: unavailable,
        prerequisiteMissing: prerequisiteMissing,
      ),
      exactSizeOnDisk: exactSizeOnDisk,
      note: note,
      description: description,
      problem: problem,
      unavailableReason: unavailable,
      requires: requires,
      progress: running?.progress,
      cancel: running == null ? null : () => activity!.cancel(id),
      remove: installed || problem != null ? remove : null,
    );
  }

  for (final status in hunspell.statuses) {
    final bundle = status.bundle;
    items.add(
      item(
        id: bundle.id,
        kind: StudioDownloadKind.spelling,
        language: bundle.languages.first,
        title: bundle.displayName,
        bytes: bundle.totalBytes,
        licence: bundle.license,
        review: StudioDownloadReview.dictionaries,
        installed: status.installed,
        problem: status.problem,
        unavailable: status.unavailableReason,
        remove: () => hunspell.remove(bundle),
      ),
    );
  }

  final morph = morphology.status;
  items.add(
    item(
      id: morph.bundle.id,
      kind: StudioDownloadKind.morphology,
      language: 'ar',
      title: morph.bundle.displayName,
      bytes: morph.bundle.totalBytes,
      licence: morph.bundle.license,
      licenceUrl: Uri.parse(morph.bundle.licenseUrl),
      review: StudioDownloadReview.dictionaries,
      installed: morph.installed,
      problem: morph.problem,
      unavailable: morph.unavailableReason,
      remove: morphology.remove,
    ),
  );
  final model = morphology.modelStatus;
  items.add(
    item(
      id: model.bundle.id,
      kind: StudioDownloadKind.contextModel,
      language: 'ar',
      title: model.bundle.displayName,
      bytes: model.bundle.totalBytes,
      licence: model.bundle.license,
      licenceUrl: Uri.parse(model.bundle.licenseUrl),
      review: StudioDownloadReview.dictionaries,
      installed: model.installed,
      problem: model.problem,
      unavailable: model.unavailableReason,
      requires: morph.bundle.id,
      prerequisiteMissing: !morph.installed,
      remove: morphology.removeModel,
    ),
  );

  final spacyStatus = spacy.status;
  final germanInstalled = spacyStatus.source != StudioSpacySource.none;
  items.add(
    item(
      id: studioSpacyGermanId,
      kind: StudioDownloadKind.analysis,
      language: 'de',
      title: spacyStatus.bundledLibrary
          ? 'German spaCy analysis model'
          : 'German spaCy analysis package',
      bytes: spacyStatus.downloadBytes,
      licence: 'MIT',
      review: StudioDownloadReview.analysis,
      installed: germanInstalled,
      problem: spacyStatus.problem,
      unavailable: spacyStatus.installOffered || germanInstalled
          ? null
          : (spacyStatus.unavailableReason ?? 'No package for this platform.'),
      exactSizeOnDisk: spacyStatus.bundledLibrary,
      note: spacyStatus.source == StudioSpacySource.developer
          ? StudioDownloadNote.developerConfiguration
          : spacyStatus.bundledLibrary
          ? StudioDownloadNote.modelFilesOnly
          : StudioDownloadNote.includesNativePackage,
      remove: spacyStatus.source == StudioSpacySource.installed
          ? spacy.remove
          : null,
    ),
  );
  final ner = spacyNerDownload;
  if (ner != null) {
    items.add(
      item(
        id: studioSpacyNerId,
        kind: StudioDownloadKind.entities,
        language: 'de',
        title: 'German named-entity model (NER)',
        bytes: ner.bytes,
        licence: 'MIT',
        review: StudioDownloadReview.analysis,
        installed: spacyStatus.nerInstalled,
        problem: spacyStatus.nerProblem,
        requires: studioSpacyGermanId,
        prerequisiteMissing: !germanInstalled,
        note: StudioDownloadNote.analysisOnly,
        remove: spacy.removeNer,
      ),
    );
  }
  for (final language in spacyStatus.languages) {
    final download = language.download;
    items.add(
      item(
        id: studioSpacyLanguageId(language.language),
        kind: StudioDownloadKind.analysis,
        language: language.language.code,
        title: '${language.language.displayName} spaCy analysis model',
        bytes: language.installed
            ? (download?.totalBytes ?? 0)
            : language.downloadBytes,
        licence: download?.license ?? 'MIT',
        review: StudioDownloadReview.analysis,
        installed: language.installed,
        problem: language.problem,
        unavailable: language.offered
            ? null
            : (language.unavailableReason ?? 'Not available here.'),
        note:
            language.installed ||
                language.runtimeInstalled ||
                language.bundledRuntime
            ? StudioDownloadNote.analysisOnly
            : StudioDownloadNote.includesSharedRuntime,
        remove: () => spacy.removeLanguage(language.language),
      ),
    );
  }
  for (final status in fontPacks?.statuses ?? const []) {
    final pack = status.pack;
    items.add(
      item(
        id: pack.id,
        kind: StudioDownloadKind.fonts,
        language: studioFontGroup,
        title: pack.title,
        bytes: status.installed && status.bytesOnDisk > 0
            ? status.bytesOnDisk
            : pack.bytes,
        licence: pack.licence,
        licenceUrl: Uri.parse(pack.licenceUrl),
        review: StudioDownloadReview.fontPack,
        description: pack.description,
        installed: status.installed,
        problem: status.problem,
        remove: () => fontPacks!.remove(pack),
      ),
    );
  }
  return items;
}

/// The group key of open font packs; listed after every language.
const studioFontGroup = 'fonts';

/// Display order of language groups; others follow alphabetically.
const studioDownloadLanguageOrder = <String>['ar', 'de', 'en', 'fr'];

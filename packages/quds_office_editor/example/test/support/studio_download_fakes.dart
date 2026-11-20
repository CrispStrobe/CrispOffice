import 'package:flutter/widgets.dart';
import 'package:quds_arabic_morph/quds_arabic_morph.dart';
import 'package:quds_office_editor/quds_office_editor.dart';
import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:quds_proofing_hunspell/quds_proofing_hunspell.dart';
import 'package:quds_proofing_spacy/quds_proofing_spacy.dart';
import 'package:quds_office_studio/studio_arabic_morph_host.dart';
import 'package:quds_office_studio/studio_downloads_manager.dart';
import 'package:quds_office_studio/studio_font_pack_host.dart';
import 'package:quds_office_studio/studio_hunspell_host.dart';
import 'package:quds_office_studio/studio_spacy_host.dart';
import 'package:quds_office_studio/studio_strings.dart';

/// Hunspell host with one Arabic dictionary; records every call.
class FakeDictionaries extends StudioHunspellHost {
  FakeDictionaries({this.installed = true, this.problem});
  final calls = <String>[];
  bool installed;
  String? problem;
  @override
  List<StudioHunspellStatus> get statuses => <StudioHunspellStatus>[
    StudioHunspellStatus(
      bundle: ayaspellArabic,
      installed: installed,
      problem: problem,
      location: installed ? '/owned/ar' : null,
    ),
  ];
  @override
  Future<void> refresh() async => calls.add('refresh');
  @override
  Future<void> install(
    HunspellBundleDownload bundle, {
    void Function(int, int)? onProgress,
    StudioHunspellCancellation? cancellation,
  }) async => calls.add('install');
  @override
  Future<void> remove(HunspellBundleDownload bundle) async {
    calls.add('remove');
    installed = false;
    problem = null;
    notifyListeners();
  }

  @override
  List<OfficeProofingProvider> createProviders(
    OfficeProofingVocabulary vocabulary,
  ) => <OfficeProofingProvider>[];
}

/// Arabic morphology host offering the database and the context model.
class FakeMorphology extends StudioArabicMorphHost {
  FakeMorphology({this.installed = false, this.modelInstalled = false});
  final calls = <String>[];
  bool installed;
  bool modelInstalled;
  @override
  StudioArabicMorphStatus get status => StudioArabicMorphStatus(
    bundle: camelMorphMsaProofingBin,
    installed: installed,
    loaded: installed,
  );
  @override
  StudioArabicMorphStatus get modelStatus => StudioArabicMorphStatus(
    bundle: camelMorphMsaDisambig,
    installed: modelInstalled,
    loaded: modelInstalled,
  );
  @override
  Future<void> refresh() async => calls.add('refresh');
  @override
  Future<void> install({
    void Function(int, int)? onProgress,
    StudioHunspellCancellation? cancellation,
  }) async => calls.add('install');
  @override
  Future<void> remove() async {
    calls.add('remove');
    installed = false;
    notifyListeners();
  }

  @override
  Future<void> removeModel() async {
    calls.add('remove-model');
    modelInstalled = false;
    notifyListeners();
  }

  @override
  ArabicMorphology get morphology => const UnavailableArabicMorphology();
}

/// spaCy host with German, NER, English and French.
class FakeModels extends StudioSpacyHost {
  FakeModels({
    this.bundledLibrary = false,
    this.package = spacyMacosArm64Package,
    this.ner = true,
    this.frenchProblem,
  });

  final bool bundledLibrary;
  final SpacyPlatformPackage? package;
  final String? frenchProblem;
  final calls = <String>[];
  bool ner;
  bool german = false;
  @override
  StudioSpacyStatus get status => StudioSpacyStatus(
    platformLabel: 'fixture',
    source: german ? StudioSpacySource.installed : StudioSpacySource.none,
    bundledLibrary: bundledLibrary,
    package: package,
    nerOffered: true,
    nerInstalled: ner,
    languages: <StudioSpacyLanguageStatus>[
      StudioSpacyLanguageStatus(
        language: SpacyLanguage.english,
        download: spacyEnglishDownload,
        runtime: package,
        installed: true,
        runtimeInstalled: true,
      ),
      StudioSpacyLanguageStatus(
        language: SpacyLanguage.french,
        download: spacyFrenchDownload,
        runtime: package,
        problem: frenchProblem,
      ),
    ],
  );
  @override
  Future<void> refresh() async => calls.add('refresh');
  @override
  Future<void> restoreGrammarOptIn() async {}
  @override
  Future<void> install({
    void Function(int, int)? onProgress,
    StudioSpacyInstallCancellation? cancellation,
  }) async => calls.add('install');
  @override
  Future<void> remove() async {
    calls.add('remove');
    german = false;
    notifyListeners();
  }

  @override
  Future<void> removeNer() async {
    calls.add('remove-ner');
    ner = false;
    notifyListeners();
  }

  @override
  Future<void> removeLanguage(SpacyLanguage language) async =>
      calls.add('remove-${language.code}');
  @override
  Future<void> setAnalysisEnabled(bool enabled) async {}
  @override
  Future<void> setGrammarEnabled(bool enabled) async {}
  @override
  Future<SpacyTransport> openTransport() async => throw UnimplementedError();
}

typedef CaptureVariant = ({
  String name,
  Size size,
  bool dark,
  bool rtl,
  StudioLanguage language,
});

const captureVariants = <CaptureVariant>[
  (
    name: 'wide-light',
    size: Size(1200, 900),
    dark: false,
    rtl: false,
    language: StudioLanguage.en,
  ),
  (
    name: 'wide-dark',
    size: Size(1200, 900),
    dark: true,
    rtl: false,
    language: StudioLanguage.en,
  ),
  (
    name: 'narrow-light',
    size: Size(360, 780),
    dark: false,
    rtl: false,
    language: StudioLanguage.en,
  ),
  (
    name: 'narrow-dark',
    size: Size(360, 780),
    dark: true,
    rtl: false,
    language: StudioLanguage.en,
  ),
  (
    name: 'wide-rtl',
    size: Size(1200, 900),
    dark: false,
    rtl: true,
    language: StudioLanguage.ar,
  ),
  (
    name: 'narrow-rtl-dark',
    size: Size(360, 780),
    dark: true,
    rtl: true,
    language: StudioLanguage.ar,
  ),
  (
    name: 'wide-german',
    size: Size(1200, 900),
    dark: false,
    rtl: false,
    language: StudioLanguage.de,
  ),
];

/// The capture fixture: a mix of installed, missing and broken packages.
Widget buildCaptureManager(CaptureVariant variant) => StudioDownloadsManager(
  hunspell: FakeDictionaries(),
  morphology: FakeMorphology(),
  spacy: FakeModels(frenchProblem: 'Verification failed: tok2vec.gguf'),
  language: variant.language,
  languages: const <String>{'ar-SA'},
  openLicence: (_) async {},
);

/// Font-pack host with a fixed inventory; never reaches the filesystem.
class FakeFontPacks extends StudioFontPackHost {
  FakeFontPacks(this.items);
  final List<OfficeFontPackStatus> items;
  final calls = <String>[];
  @override
  List<OfficeFontPackStatus> get statuses => items;
  @override
  Future<void> refresh() async => calls.add('refresh');
}

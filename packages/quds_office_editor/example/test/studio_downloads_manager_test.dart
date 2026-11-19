import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_proofing_hunspell/quds_proofing_hunspell.dart';
import 'package:quds_arabic_morph/quds_arabic_morph.dart';
import 'package:quds_proofing_spacy/quds_proofing_spacy.dart';
import 'package:quds_office_studio/main.dart';
import 'package:quds_office_editor/quds_office_editor.dart';
import 'package:quds_office_studio/crisp_office_sample.dart';
import 'package:quds_office_studio/studio_downloads_manager.dart';
import 'package:quds_office_studio/studio_hunspell_host.dart';
import 'package:quds_office_studio/studio_arabic_morph_host.dart';
import 'package:quds_office_studio/studio_spacy_host.dart';

class _Dictionaries extends StudioHunspellHost {
  final calls = <String>[];
  bool installed = true;
  @override
  List<StudioHunspellStatus> get statuses => <StudioHunspellStatus>[
    StudioHunspellStatus(
      bundle: ayaspellArabic,
      installed: installed,
      location: installed ? '/owned/ar' : null,
    ),
  ];
  @override
  Future<void> refresh() async {
    calls.add('refresh');
  }

  @override
  Future<void> install(
    HunspellBundleDownload bundle, {
    void Function(int, int)? onProgress,
    StudioHunspellCancellation? cancellation,
  }) async {
    calls.add('install');
  }

  @override
  Future<void> remove(HunspellBundleDownload bundle) async {
    calls.add('remove');
    installed = false;
    notifyListeners();
  }

  @override
  List<OfficeProofingProvider> createProviders(
    OfficeProofingVocabulary vocabulary,
  ) => <OfficeProofingProvider>[];
}

class _Morphology extends StudioArabicMorphHost {
  final calls = <String>[];
  @override
  StudioArabicMorphStatus get status =>
      const StudioArabicMorphStatus(bundle: camelMorphMsaProofingBin);
  @override
  Future<void> refresh() async {
    calls.add('refresh');
  }

  @override
  Future<void> install({
    void Function(int, int)? onProgress,
    StudioHunspellCancellation? cancellation,
  }) async {
    calls.add('install');
  }

  @override
  Future<void> remove() async {
    calls.add('remove');
  }

  @override
  ArabicMorphology get morphology => const UnavailableArabicMorphology();
}

class _Models extends StudioSpacyHost {
  final calls = <String>[];
  bool ner = true;
  @override
  StudioSpacyStatus get status => StudioSpacyStatus(
    platformLabel: 'fixture',
    source: StudioSpacySource.none,
    nerInstalled: ner,
    languages: const <StudioSpacyLanguageStatus>[
      StudioSpacyLanguageStatus(
        language: SpacyLanguage.english,
        download: spacyEnglishDownload,
        installed: true,
        runtimeInstalled: true,
      ),
    ],
  );
  @override
  Future<void> refresh() async {
    calls.add('refresh');
  }

  @override
  Future<void> restoreGrammarOptIn() async {}
  @override
  Future<void> install({
    void Function(int, int)? onProgress,
    StudioSpacyInstallCancellation? cancellation,
  }) async {
    calls.add('install');
  }

  @override
  Future<void> remove() async {
    calls.add('remove');
  }

  @override
  Future<void> removeNer() async {
    calls.add('remove-ner');
    ner = false;
    notifyListeners();
  }

  @override
  Future<void> removeLanguage(SpacyLanguage language) async {
    calls.add('remove-${language.code}');
  }

  @override
  Future<void> setAnalysisEnabled(bool enabled) async {}
  @override
  Future<void> setGrammarEnabled(bool enabled) async {}
  @override
  Future<SpacyTransport> openTransport() async => throw UnimplementedError();
}

void main() {
  test('English sample language survives DOCX export and import', () {
    final document = CrispOfficeSample.build();
    expect(document.proofingLanguage, 'en-GB');
    final bytes = WordSerializer().writeBytes(document);
    final reopened = WordDeserializer().readBytes(bytes);
    expect(reopened.proofingLanguage, 'en-GB');
    expect(
      reopened.paragraphs.map((p) => p.text).join(' '),
      contains('CrispOffice product brief'),
    );
  });
  testWidgets(
    'workspace language change opens support review before any download',
    (tester) async {
      final dictionaries = _Dictionaries();
      final morphology = _Morphology();
      final models = _Models();
      final previousDictionaries = studioHunspellHost;
      final previousMorphology = studioArabicMorphHost;
      final previousModels = studioSpacyHost;
      studioHunspellHost = dictionaries;
      studioArabicMorphHost = morphology;
      studioSpacyHost = models;
      addTearDown(() {
        studioHunspellHost = previousDictionaries;
        studioArabicMorphHost = previousMorphology;
        studioSpacyHost = previousModels;
      });
      await tester.binding.setSurfaceSize(const Size(1440, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(const QudsOfficeStudioApp());
      await tester.pump();
      final editor = tester.widget<QudsWordEditor>(find.byType(QudsWordEditor));
      expect(editor.controller.document.proofingLanguage, 'en-GB');
      editor.controller.setProofingLanguage('fr-FR');
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(StudioDownloadsManager), findsOneWidget);
      expect(
        find.textContaining('does not provide a French spelling'),
        findsOneWidget,
      );
      expect(dictionaries.calls, isNot(contains('install')));
      expect(models.calls, isNot(contains('install')));
      await tester.tap(find.text('Not now'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
      expect(find.byType(StudioDownloadsManager), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'language change review lists coverage and never downloads on open or decline',
    (tester) async {
      final dictionaries = _Dictionaries();
      final morphology = _Morphology();
      final models = _Models();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StudioDownloadsManager(
              hunspell: dictionaries,
              morphology: morphology,
              spacy: models,
              languages: const <String>{'en-GB', 'fr-FR'},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.textContaining('No dictionary download is required'),
        findsOneWidget,
      );
      expect(
        find.textContaining('does not provide a French spelling'),
        findsOneWidget,
      );
      expect(dictionaries.calls, <String>['refresh']);
      expect(morphology.calls, <String>['refresh']);
      expect(models.calls, <String>['refresh']);
      expect(find.text('Not now'), findsOneWidget);
      expect(find.textContaining('Remove downloaded data'), findsWidgets);
    },
  );
  testWidgets('removing a dictionary leaves models and morphology untouched', (
    tester,
  ) async {
    final dictionaries = _Dictionaries();
    final morphology = _Morphology();
    final models = _Models();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StudioDownloadsManager(
            hunspell: dictionaries,
            morphology: morphology,
            spacy: models,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final card = find.ancestor(
      of: find.text(ayaspellArabic.displayName),
      matching: find.byType(Card),
    );
    final remove = find.descendant(
      of: card,
      matching: find.widgetWithText(TextButton, 'Remove downloaded data'),
    );
    await tester.ensureVisible(remove);
    await tester.tap(remove);
    await tester.pumpAndSettle();
    expect(dictionaries.calls, <String>['refresh', 'remove']);
    expect(dictionaries.installed, isFalse);
    expect(models.calls, <String>['refresh']);
    expect(morphology.calls, <String>['refresh']);
  });
  testWidgets('NER removal is offered even when the model is not enabled', (
    tester,
  ) async {
    final models = _Models();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StudioDownloadsManager(
            hunspell: _Dictionaries(),
            morphology: _Morphology(),
            spacy: models,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final card = find.ancestor(
      of: find.text('German named-entity model (NER)'),
      matching: find.byType(Card),
    );
    final remove = find.descendant(
      of: card,
      matching: find.widgetWithText(TextButton, 'Remove downloaded data'),
    );
    await tester.ensureVisible(remove);
    await tester.tap(remove);
    await tester.pumpAndSettle();
    expect(models.calls, <String>['refresh', 'remove-ner']);
    expect(models.ner, isFalse);
  });
}

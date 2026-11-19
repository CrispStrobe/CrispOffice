import 'dart:convert';
import 'dart:io';

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
import 'package:quds_office_studio/studio_spacy_host_native.dart';
import 'package:quds_proofing_spacy/quds_proofing_spacy_install.dart'
    show SpacyPackageInstaller;

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
  _Models({this.bundledLibrary = false, this.package});

  final bool bundledLibrary;
  final SpacyPlatformPackage? package;
  final calls = <String>[];
  bool ner = true;
  @override
  StudioSpacyStatus get status => StudioSpacyStatus(
    platformLabel: 'fixture',
    source: StudioSpacySource.none,
    bundledLibrary: bundledLibrary,
    package: package,
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

  for (final fixture
      in <
        ({String name, bool bundled, SpacyPlatformPackage? package, int bytes})
      >[
        (
          name: 'bundled runtime with a downloadable package',
          bundled: true,
          package: spacyMacosArm64Package,
          bytes: spacyBundleDownload.totalBytes,
        ),
        (
          name: 'bundled runtime without a downloadable package',
          bundled: true,
          package: null,
          bytes: spacyBundleDownload.totalBytes,
        ),
        (
          name: 'downloaded runtime',
          bundled: false,
          package: spacyLinuxX64Package,
          bytes: spacyLinuxX64Package.archiveBytes,
        ),
      ]) {
    testWidgets('German download size reflects ${fixture.name}', (
      tester,
    ) async {
      final models = _Models(
        bundledLibrary: fixture.bundled,
        package: fixture.package,
      );
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
        of: find.text(
          fixture.bundled
              ? 'German spaCy analysis model'
              : 'German spaCy analysis package',
        ),
        matching: find.byType(Card),
      );
      expect(
        find.descendant(
          of: card,
          matching: find.textContaining(
            '${(fixture.bytes / 1048576).toStringAsFixed(1)} MB',
          ),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: card,
          matching: find.textContaining('No package for this platform'),
        ),
        findsNothing,
      );
      expect(models.calls, <String>['refresh']);
    });
  }

  testWidgets('a bundled library lists only the model download', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StudioDownloadsManager(
            hunspell: _Dictionaries(),
            morphology: _Morphology(),
            spacy: _Models(bundledLibrary: true),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('German spaCy analysis model'), findsOneWidget);
    expect(find.text('German spaCy analysis package'), findsNothing);
    expect(
      find.textContaining('model files only (library built into the app)'),
      findsOneWidget,
    );
  });

  for (final bundled in <bool>[false, true]) {
    test(
      '${bundled ? 'Bundled' : 'Downloaded'} runtime verifies optional NER independently',
      () async {
        final root = Directory.systemTemp.createTempSync('spacy-ner-status-');
        addTearDown(() => root.deleteSync(recursive: true));
        File(
          '${root.path}/settings.json',
        ).writeAsStringSync(jsonEncode(<String, Object>{'ner_enabled': true}));
        final sentinel = File('${root.path}/runtime-sentinel')
          ..writeAsStringSync('keep the native runtime');
        final host = NativeStudioSpacyHost(
          root: root,
          environment: const <String, String>{},
          platform: SpacyPlatform.linuxX64,
          detectBundledLibrary: false,
          bundledLibrary: bundled
              ? const StudioSpacyBundledLibrary(
                  path: '/app/Contents/Frameworks/libcrispembed-spacy.dylib',
                  sha256:
                      '66d54a6090ae65a8fd57d79115d1d1afcc4ab8d8dabcefb8c95bf38717224044',
                )
              : null,
          installer: SpacyPackageInstaller(
            root: root,
            httpClientFactory: () =>
                throw StateError('Refreshing model status must not download.'),
          ),
        );
        addTearDown(host.dispose);
        await host.refresh();
        expect(host.status.bundledLibrary, bundled);
        expect(host.status.nerInstalled, isFalse);
        expect(host.status.nerProblem, isNull);
        expect(host.status.nerEnabled, isFalse);

        final ner = spacyNerDownload!;
        final model = File('${root.path}/ner/${ner.sha256}/ner.gguf')
          ..createSync(recursive: true)
          ..writeAsStringSync('damaged model bytes');
        await host.refresh();
        expect(host.status.nerInstalled, isFalse);
        expect(host.status.nerProblem, isNotNull);
        expect(host.status.nerEnabled, isFalse);
        expect(model.existsSync(), isTrue);

        await host.removeNer();
        expect(model.existsSync(), isFalse);
        expect(host.status.nerInstalled, isFalse);
        expect(host.status.nerProblem, isNull);
        expect(host.status.nerEnabled, isFalse);
        expect(sentinel.readAsStringSync(), 'keep the native runtime');
        final settings =
            jsonDecode(File('${root.path}/settings.json').readAsStringSync())
                as Map<String, Object?>;
        expect(settings['ner_enabled'], isFalse);
      },
    );
  }
}

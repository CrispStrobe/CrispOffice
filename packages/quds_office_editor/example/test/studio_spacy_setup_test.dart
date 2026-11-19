import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_studio/main.dart';
import 'package:quds_office_studio/studio_spacy_host.dart';
import 'package:quds_office_studio/studio_spacy_host_native.dart';
import 'package:quds_office_studio/studio_spacy_setup.dart';
import 'package:quds_proofing_spacy/quds_proofing_spacy.dart';

final class _Transport implements SpacyTransport {
  var disposals = 0;
  @override
  SpacyBackendIdentity get identity =>
      const SpacyBackendIdentity(librarySha256: spacyLinuxX64LibrarySha256);
  @override
  Future<LinguisticAnalysisResult> analyze(LinguisticAnalysisRequest request) =>
      Completer<LinguisticAnalysisResult>().future;
  @override
  void cancel(String key) {}
  @override
  Future<void> dispose() async => disposals++;
}

class _FakeHost extends StudioSpacyHost {
  _FakeHost(this._status);
  StudioSpacyStatus _status;
  final calls = <String>[];
  final transports = <_Transport>[];
  Completer<void>? installGate;

  @override
  StudioSpacyStatus get status => _status;
  set current(StudioSpacyStatus value) {
    _status = value;
    notifyListeners();
  }

  @override
  Future<void> refresh() async => calls.add('refresh');
  @override
  Future<void> restoreGrammarOptIn() async {
    calls.add('restore');
    notifyListeners();
  }

  @override
  Future<void> install({
    void Function(int received, int total)? onProgress,
    StudioSpacyInstallCancellation? cancellation,
  }) async {
    calls.add('install');
    onProgress?.call(1, 2);
    await installGate?.future;
    current = _installed(analysis: true);
  }

  @override
  Future<void> remove() async {
    calls.add('remove');
    current = _available();
  }

  @override
  Future<void> setAnalysisEnabled(bool enabled) async =>
      calls.add('analysis:$enabled');
  @override
  Future<void> setGrammarEnabled(bool enabled) async {
    calls.add('grammar:$enabled');
    current = _installed(analysis: true, grammar: enabled);
  }

  @override
  Future<void> installLanguage(
    SpacyLanguage language, {
    void Function(int received, int total)? onProgress,
    StudioSpacyInstallCancellation? cancellation,
  }) async {
    calls.add('install:${language.code}');
    onProgress?.call(1, 2);
  }

  @override
  Future<void> removeLanguage(SpacyLanguage language) async =>
      calls.add('remove:${language.code}');

  @override
  Future<SpacyTransport> openTransport() async {
    calls.add('open');
    final transport = _Transport();
    transports.add(transport);
    return transport;
  }
}

StudioSpacyStatus _available() => const StudioSpacyStatus(
  platformLabel: 'linux-x86_64',
  source: StudioSpacySource.none,
  package: spacyLinuxX64Package,
);

StudioSpacyStatus _installed({
  bool analysis = false,
  bool grammar = false,
  String library = spacyLinuxX64LibrarySha256,
}) => StudioSpacyStatus(
  platformLabel: 'linux-x86_64',
  source: StudioSpacySource.installed,
  package: spacyLinuxX64Package,
  installedDirectory: '/private/spacy',
  librarySha256: library,
  qualification: spacyQualificationFor(library),
  analysisEnabled: analysis,
  grammarEnabled: grammar,
);

Future<void> _pumpSetup(WidgetTester tester, StudioSpacyHost host) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: StudioSpacySetupDialog(host: host)),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('unpublished platform explains why nothing is offered', (
    tester,
  ) async {
    final host = _FakeHost(
      StudioSpacyStatus(
        platformLabel: 'macos-arm64',
        source: StudioSpacySource.none,
        unavailableReason: spacyPlatformStatus(SpacyPlatform.macosArm64).reason,
      ),
    );
    await _pumpSetup(tester, host);
    expect(find.byKey(const Key('spacy-setup-unavailable')), findsOneWidget);
    expect(find.byKey(const Key('spacy-setup-install')), findsNothing);
    expect(host.calls, ['refresh']);
  });

  testWidgets('download is explicit and names immutable source and digest', (
    tester,
  ) async {
    final host = _FakeHost(_available())..installGate = Completer<void>();
    await _pumpSetup(tester, host);
    final source = tester.widget<SelectableText>(
      find.byKey(const Key('spacy-setup-source')),
    );
    expect(source.data, contains('/resolve/$spacyLinuxPublicationRevision/'));
    expect(source.data, contains(spacyLinuxX64Package.archiveSha256));
    expect(host.calls, ['refresh'], reason: 'nothing downloads on open');
    await tester.tap(find.byKey(const Key('spacy-setup-install')));
    await tester.pump();
    expect(host.calls, ['refresh', 'install']);
    expect(find.text('Cancel download'), findsOneWidget);
    host.installGate!.complete();
    await tester.pumpAndSettle();
    expect(find.text('Installed and verified'), findsOneWidget);
    final grammar = tester.widget<SwitchListTile>(
      find.byKey(const Key('spacy-setup-grammar')),
    );
    expect(grammar.value, isFalse, reason: 'grammar stays default off');
    expect(grammar.onChanged, isNotNull);
  });

  testWidgets('grammar opt-in is unavailable for an unrecorded build', (
    tester,
  ) async {
    final host = _FakeHost(_installed(analysis: true, library: 'e' * 64));
    await _pumpSetup(tester, host);
    final grammar = tester.widget<SwitchListTile>(
      find.byKey(const Key('spacy-setup-grammar')),
    );
    expect(grammar.onChanged, isNull);
    expect(find.textContaining('no recorded'), findsWidgets);
  });

  testWidgets('qualified build exposes manual grammar and removal', (
    tester,
  ) async {
    final host = _FakeHost(_installed(analysis: true));
    await _pumpSetup(tester, host);
    await tester.tap(find.byKey(const Key('spacy-setup-grammar')));
    await tester.pump();
    expect(host.calls, contains('grammar:true'));
    await tester.tap(find.byKey(const Key('spacy-setup-remove')));
    await tester.pump();
    expect(host.calls, contains('remove'));
  });

  testWidgets(
    'workspace registers manual grammar only while enabled and releases it',
    (tester) async {
      final host = _FakeHost(_installed(analysis: true));
      studioSpacyHost = host;
      await tester.binding.setSurfaceSize(const Size(1440, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(const QudsOfficeStudioApp());
      await tester.pump();
      expect(host.calls, contains('restore'));
      expect(host.calls, isNot(contains('open')));

      host.current = _installed(analysis: true, grammar: true);
      await tester.pump();
      expect(host.calls.where((call) => call == 'open'), hasLength(1));
      expect(host.transports.single.disposals, 0);

      host.current = _installed(analysis: true);
      await tester.pump();
      expect(host.transports.single.disposals, 1);

      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('English and French are offered as explicit downloads', (
    tester,
  ) async {
    final host = _FakeHost(
      StudioSpacyStatus(
        platformLabel: 'linux-x86_64',
        source: StudioSpacySource.none,
        package: spacyLinuxX64Package,
        languages: [
          StudioSpacyLanguageStatus(
            language: SpacyLanguage.english,
            download: spacyEnglishDownload,
            runtime: spacyRuntimePackage(SpacyPlatform.linuxX64),
          ),
          StudioSpacyLanguageStatus(
            language: SpacyLanguage.french,
            download: spacyFrenchDownload,
            runtime: spacyRuntimePackage(SpacyPlatform.linuxX64),
            installed: true,
            runtimeInstalled: true,
          ),
        ],
      ),
    );
    await _pumpSetup(tester, host);
    expect(find.text('More analysis languages'), findsOneWidget);
    expect(find.byKey(const Key('spacy-language-fr-install')), findsNothing);
    expect(find.byKey(const Key('spacy-language-fr-remove')), findsOneWidget);
    final install = find.byKey(const Key('spacy-language-en-install'));
    await tester.ensureVisible(install);
    await tester.tap(install);
    await tester.pump();
    final remove = find.byKey(const Key('spacy-language-fr-remove'));
    await tester.ensureVisible(remove);
    await tester.tap(remove);
    await tester.pump();
    expect(host.calls, ['refresh', 'install:en', 'remove:fr']);
    final details = find.byKey(const Key('spacy-language-fr-details'));
    await tester.ensureVisible(details);
    await tester.tap(details);
    await tester.pumpAndSettle();
    final source = tester.widget<SelectableText>(
      find.byKey(const Key('spacy-language-fr-source')),
    );
    expect(source.data, contains(spacyFrenchDownload.revision));
    expect(source.data, contains('LGPL-LR'));
    expect(source.data, contains('Native package already installed'));
  });

  testWidgets('bundled library downloads only the model files', (tester) async {
    const digest =
        '66d54a6090ae65a8fd57d79115d1d1afcc4ab8d8dabcefb8c95bf38717224044';
    final host = _FakeHost(
      StudioSpacyStatus(
        platformLabel: 'macos-arm64',
        source: StudioSpacySource.none,
        package: spacyMacosArm64Package,
        bundledLibrary: true,
        librarySha256: digest,
        languages: [
          StudioSpacyLanguageStatus(
            language: SpacyLanguage.english,
            download: spacyEnglishDownload,
            runtimeInstalled: true,
            bundledRuntime: true,
          ),
        ],
      ),
    );
    await _pumpSetup(tester, host);
    final source = tester.widget<SelectableText>(
      find.byKey(const Key('spacy-setup-source')),
    );
    expect(source.data, contains('built into this app'));
    expect(source.data, contains(spacyBundleDownload.revision));
    expect(source.data, isNot(contains(spacyMacosArm64Package.archivePath)));
    final install = find.byKey(const Key('spacy-setup-install'));
    expect(install, findsOneWidget);
    expect(
      find.descendant(of: install, matching: find.textContaining('MB')),
      findsOneWidget,
    );
    expect(host.status.downloadBytes, spacyBundleDownload.totalBytes);
    expect(host.status.language(SpacyLanguage.english)!.offered, isTrue);
    expect(
      host.status.language(SpacyLanguage.english)!.downloadBytes,
      spacyEnglishDownload.totalBytes,
    );
    await tester.ensureVisible(
      find.byKey(const Key('spacy-language-en-details')),
    );
    await tester.tap(find.byKey(const Key('spacy-language-en-details')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<SelectableText>(
            find.byKey(const Key('spacy-language-en-source')),
          )
          .data,
      contains('built into this app'),
    );
  });

  group('native host without downloads', () {
    late Directory root;
    setUp(() => root = Directory.systemTemp.createTempSync('studio-spacy-'));
    tearDown(() => root.deleteSync(recursive: true));

    test('developer environment keeps precedence and its digest', () async {
      final host = NativeStudioSpacyHost(
        root: root,
        environment: {
          'QUDS_SPACY_BUNDLE': '/bundle',
          'QUDS_SPACY_LIBRARY': '/lib',
          'QUDS_SPACY_LIBRARY_SHA256': spacyLinuxX64LibrarySha256,
        },
        platform: SpacyPlatform.linuxX64,
      );
      await host.refresh();
      expect(host.status.source, StudioSpacySource.developer);
      expect(host.status.grammarOffered, isTrue);
      await expectLater(
        host.openTransport(),
        throwsA(
          isA<SpacyUnavailableException>().having(
            (error) => error.message,
            'message',
            contains('disabled'),
          ),
        ),
      );
    });

    test('nothing installed: no grammar, no worker, no network', () async {
      final host = NativeStudioSpacyHost(
        root: root,
        environment: const {},
        platform: SpacyPlatform.linuxX64,
      );
      await host.refresh();
      expect(host.status.source, StudioSpacySource.none);
      expect(host.status.package, spacyLinuxX64Package);
      expect(host.status.grammarOffered, isFalse);
      await expectLater(
        host.setGrammarEnabled(true),
        throwsA(isA<SpacyUnavailableException>()),
      );
      await expectLater(
        host.openTransport(),
        throwsA(isA<SpacyUnavailableException>()),
      );
      expect(Directory('${root.path}/packages').existsSync(), isFalse);
    });

    test('unpublished platform has a reason and refuses install', () async {
      final host = NativeStudioSpacyHost(
        root: root,
        environment: const {},
        platform: SpacyPlatform.windowsX64,
      );
      await host.refresh();
      expect(host.status.package, isNull);
      expect(host.status.unavailableReason, isNotEmpty);
      await expectLater(host.install(), throwsA(isA<Exception>()));
    });

    test('languages need a published v2 runtime for the platform', () async {
      final linux = NativeStudioSpacyHost(
        root: root,
        environment: const {},
        platform: SpacyPlatform.linuxX64,
      );
      await linux.refresh();
      final english = linux.status.language(SpacyLanguage.english)!;
      expect(english.offered, isTrue);
      expect(english.installed, isFalse);
      expect(english.runtime!.opensVersion2Bundles, isTrue);
      expect(
        english.downloadBytes,
        spacyEnglishDownload.totalBytes + english.runtime!.archiveBytes,
      );
      await expectLater(
        linux.openLanguageTransport(SpacyLanguage.french),
        throwsA(isA<SpacyUnavailableException>()),
      );
      final web = NativeStudioSpacyHost(
        root: root,
        environment: const {},
        platform: SpacyPlatform.web,
      );
      await web.refresh();
      for (final item in web.status.languages) {
        expect(item.offered, isFalse);
        expect(item.unavailableReason, isNotEmpty);
      }
      await expectLater(
        web.installLanguage(SpacyLanguage.english),
        throwsA(isA<Exception>()),
      );
      expect(Directory('${root.path}/bundles').existsSync(), isFalse);
    });

    test('bundled library: model-only setup on any platform', () async {
      const digest =
          '66d54a6090ae65a8fd57d79115d1d1afcc4ab8d8dabcefb8c95bf38717224044';
      final host = NativeStudioSpacyHost(
        root: root,
        environment: const {},
        platform: SpacyPlatform.windowsX64,
        bundledLibrary: const StudioSpacyBundledLibrary(
          path: '/app/Contents/Frameworks/libcrispembed-spacy.dylib',
          sha256: digest,
        ),
      );
      await host.refresh();
      final status = host.status;
      expect(status.bundledLibrary, isTrue);
      expect(status.unavailableReason, isNull);
      expect(status.installOffered, isTrue);
      expect(status.downloadBytes, spacyBundleDownload.totalBytes);
      expect(status.source, StudioSpacySource.none);
      expect(status.librarySha256, digest);
      expect(status.grammarOffered, isFalse);
      expect(status.nerInstalled, isFalse);
      expect(status.nerEnabled, isFalse);
      final english = status.language(SpacyLanguage.english)!;
      expect(english.offered, isTrue);
      expect(english.bundledRuntime, isTrue);
      expect(english.downloadBytes, spacyEnglishDownload.totalBytes);
      await expectLater(
        host.openTransport(),
        throwsA(isA<SpacyUnavailableException>()),
      );
      await expectLater(
        host.openLanguageTransport(SpacyLanguage.english),
        throwsA(isA<SpacyUnavailableException>()),
      );
      expect(Directory('${root.path}/packages').existsSync(), isFalse);
      expect(Directory('${root.path}/bundles').existsSync(), isFalse);
      // A damaged model-only tree is reported, not used.
      Directory(
        '${root.path}/bundles/$spacyBundleManifestSha256',
      ).createSync(recursive: true);
      await host.refresh();
      expect(host.status.problem, isNotNull);
      expect(host.status.analysisEnabled, isFalse);
    });

    test('the first analysis verifies the saved setup itself', () async {
      final host = NativeStudioSpacyHost(
        root: root,
        environment: const {},
        platform: SpacyPlatform.macosArm64,
        bundledLibrary: const StudioSpacyBundledLibrary(
          path: '/app/Contents/Frameworks/libcrispembed-spacy.dylib',
          sha256:
              '66d54a6090ae65a8fd57d79115d1d1afcc4ab8d8dabcefb8c95bf38717224044',
        ),
      );
      var refreshed = 0;
      host.addListener(() => refreshed++);
      // No refresh() before the explicit action (Studio refreshes lazily).
      await expectLater(
        host.openTransport(),
        throwsA(isA<SpacyUnavailableException>()),
      );
      expect(refreshed, 1);
      await expectLater(
        host.openLanguageTransport(SpacyLanguage.english),
        throwsA(isA<SpacyUnavailableException>()),
      );
      expect(refreshed, 1, reason: 'verified once, then status is current');
    });

    test('bundled library is found next to the executable', () {
      final contents = Directory('${root.path}/Studio.app/Contents');
      final executable = File('${contents.path}/MacOS/Studio')
        ..createSync(recursive: true);
      File(
        '${contents.path}/Frameworks/libcrispembed-spacy.dylib',
      ).createSync(recursive: true);
      final description = File('${contents.path}/Resources/spacy-native.json')
        ..createSync(recursive: true);
      const digest =
          '66d54a6090ae65a8fd57d79115d1d1afcc4ab8d8dabcefb8c95bf38717224044';
      description.writeAsStringSync(
        '{"library":"libcrispembed-spacy.dylib","sha256":"$digest"}',
      );
      final found = detectBundledSpacyLibrary(
        const {},
        executable: executable.path,
      );
      expect(found?.sha256, digest);
      expect(found?.path, endsWith('Frameworks/libcrispembed-spacy.dylib'));
      expect(
        detectBundledSpacyLibrary(const {
          'QUDS_SPACY_BUNDLED': '0',
        }, executable: executable.path),
        isNull,
      );
      expect(
        detectBundledSpacyLibrary(const {
          'QUDS_SPACY_BUNDLED': '1',
        }, executable: executable.path)?.sha256,
        digest,
      );
      description.writeAsStringSync(
        '{"library":"../libcrispembed-spacy.dylib","sha256":"$digest"}',
      );
      expect(
        detectBundledSpacyLibrary(const {}, executable: executable.path),
        isNull,
      );
      description.writeAsStringSync(
        '{"library":"libcrispembed-spacy.dylib","sha256":"short"}',
      );
      expect(
        detectBundledSpacyLibrary(const {}, executable: executable.path),
        isNull,
      );
    });

    test('damaged installation is reported, not used', () async {
      Directory(
        '${root.path}/packages/${spacyLinuxX64Package.archiveSha256}',
      ).createSync(recursive: true);
      final host = NativeStudioSpacyHost(
        root: root,
        environment: const {},
        platform: SpacyPlatform.linuxX64,
      );
      await host.refresh();
      expect(host.status.problem, isNotNull);
      expect(host.status.analysisEnabled, isFalse);
      expect(host.status.grammarOffered, isFalse);
    });
  });
}

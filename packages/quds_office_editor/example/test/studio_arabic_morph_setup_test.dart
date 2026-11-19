// Dictionaries dialog section and host for the Arabic morphology database.
// The real-backend test needs:
//   QUDS_ARABIC_MORPH_TEST_LIBRARY=<.../libquds_arabic_morph.dylib> \
//   QUDS_ARABIC_MORPH_TEST_BUNDLE=<directory with the verified proofing-bin bundle>
// and is skipped (with the reason) when either variable is missing.
import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_arabic_morph/installer_io.dart';
import 'package:quds_arabic_morph/quds_arabic_morph.dart';
import 'package:quds_office_editor/quds_office_editor.dart';
import 'package:quds_office_studio/studio_arabic_morph_host.dart';
import 'package:quds_office_studio/studio_arabic_morph_host_native.dart';
import 'package:quds_office_studio/studio_hunspell_host.dart';
import 'package:quds_office_studio/studio_hunspell_setup.dart';
import 'package:quds_office_studio/studio_licenses.dart';
import 'package:quds_proofing_hunspell/quds_proofing_hunspell.dart';

class _NoDictionaries extends StudioHunspellHost {
  @override
  List<StudioHunspellStatus> get statuses => const [
    StudioHunspellStatus(bundle: ayaspellArabic),
  ];
  @override
  Future<void> refresh() async {}
  @override
  Future<void> install(
    HunspellBundleDownload bundle, {
    void Function(int received, int total)? onProgress,
    StudioHunspellCancellation? cancellation,
  }) async {}
  @override
  Future<void> remove(HunspellBundleDownload bundle) async {}
  @override
  List<OfficeProofingProvider> createProviders(
    OfficeProofingVocabulary vocabulary,
  ) => const [];
}

class _RealHttp extends HttpOverrides {}

/// Records host calls; installation completes only when the test allows it.
class _FakeMorphHost extends StudioArabicMorphHost {
  var _status = const StudioArabicMorphStatus(bundle: camelMorphMsaProofingBin);
  final calls = <String>[];
  Completer<void>? installGate;
  void Function(int, int)? progress;

  @override
  StudioArabicMorphStatus get status => _status;

  @override
  ArabicMorphology get morphology => const UnavailableArabicMorphology();

  void _set(StudioArabicMorphStatus value) {
    _status = value;
    notifyListeners();
  }

  @override
  Future<void> refresh() async => calls.add('refresh');

  @override
  Future<void> install({
    void Function(int received, int total)? onProgress,
    StudioHunspellCancellation? cancellation,
  }) async {
    calls.add('install');
    progress = onProgress;
    installGate = Completer<void>();
    await installGate!.future;
    if (cancellation?.isCancelled ?? false) {
      throw StateError('Download cancelled.');
    }
    _set(
      const StudioArabicMorphStatus(
        bundle: camelMorphMsaProofingBin,
        installed: true,
        loaded: true,
        location: '/x',
      ),
    );
  }

  @override
  Future<void> remove() async {
    calls.add('remove');
    _set(const StudioArabicMorphStatus(bundle: camelMorphMsaProofingBin));
  }
}

Future<void> _open(WidgetTester tester, StudioArabicMorphHost host) async {
  tester.view
    ..physicalSize = const Size(1000, 2400)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: StudioHunspellSetupDialog(
          host: _NoDictionaries(),
          morphHost: host,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'morphology download is explicit and shows source, size and CC BY',
    (tester) async {
      final host = _FakeMorphHost();
      await _open(tester, host);
      expect(host.calls, ['refresh']);
      expect(find.text('Dictionaries and language data'), findsOneWidget);
      final section = find.byKey(const ValueKey('arabic-morph'));
      expect(section, findsOneWidget);
      String text() => tester
          .widgetList<SelectableText>(
            find.descendant(of: section, matching: find.byType(SelectableText)),
          )
          .map((widget) => widget.data)
          .join('\n');
      expect(
        text(),
        contains(
          'cstr/camel-morph-msa-v1.0/tree/'
          'd5364e04af7a40b0c9044ed127606e585be15272/proofing-bin',
        ),
      );
      expect(text(), contains('CC BY 4.0'));
      expect(text(), contains('New York University Abu Dhabi'));
      expect(text(), contains('github.com/CAMeL-Lab/camel_morph'));
      expect(text(), contains('11.6 MB'));
      expect(text(), contains('database fc9d9109ddb5'));
      expect(
        find.descendant(
          of: section,
          matching: find.textContaining('Not installed'),
        ),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const ValueKey('arabic-morph-install')));
      await tester.pump();
      expect(host.calls, ['refresh', 'install']);
      host.progress!(1, 4);
      await tester.pump();
      final bar = tester.widget<LinearProgressIndicator>(
        find.descendant(
          of: section,
          matching: find.byType(LinearProgressIndicator),
        ),
      );
      expect(bar.value, 0.25);
      host.installGate!.complete();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('arabic-morph-loaded')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('arabic-morph-remove')));
      await tester.pumpAndSettle();
      expect(host.calls.last, 'remove');
      expect(
        find.descendant(
          of: section,
          matching: find.textContaining('Not installed'),
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets('cancelling the morphology download installs nothing', (
    tester,
  ) async {
    final host = _FakeMorphHost();
    await _open(tester, host);
    await tester.tap(find.byKey(const ValueKey('arabic-morph-install')));
    await tester.pump();
    await tester.tap(find.text('Cancel'));
    host.installGate!.complete();
    await tester.pumpAndSettle();
    expect(find.textContaining('Download cancelled.'), findsOneWidget);
    expect(find.byKey(const ValueKey('arabic-morph-install')), findsOneWidget);
  });

  testWidgets('without a morphology host the dialog keeps its old title', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StudioHunspellSetupDialog(host: _NoDictionaries()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Spelling dictionaries'), findsOneWidget);
    expect(find.byKey(const ValueKey('arabic-morph')), findsNothing);
  });

  test('native host without an installation offers no analyzer', () async {
    final root = Directory.systemTemp.createTempSync('arabic-morph-host-');
    addTearDown(() => root.deleteSync(recursive: true));
    final host = NativeStudioArabicMorphHost(root: root);
    await host.refresh();
    expect(host.status.installed, isFalse);
    expect(host.configurationKey, isEmpty);
    expect(host.morphology.isAvailable, isFalse);
    expect(Directory('${root.path}/arabic_morph').existsSync(), isFalse);
  });

  final library = Platform.environment['QUDS_ARABIC_MORPH_TEST_LIBRARY'];
  final bundle = Platform.environment['QUDS_ARABIC_MORPH_TEST_BUNDLE'];
  test(
    'native host installs, loads, serves the analyzer and removes it',
    () async {
      final root = Directory.systemTemp.createTempSync('arabic-morph-host-');
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() async {
        await server.close(force: true);
        root.deleteSync(recursive: true);
      });
      server.listen((request) async {
        final file = File('$bundle/${request.uri.pathSegments.last}');
        request.response.statusCode = file.existsSync() ? 200 : 404;
        if (file.existsSync()) {
          await request.response.addStream(file.openRead());
        }
        await request.response.close();
      });
      MorphInstaller installer() => MorphInstaller(
        root,
        resolveUrl: (b, artifact) =>
            Uri.http('127.0.0.1:${server.port}', '/${artifact.file}'),
      );
      final host = NativeStudioArabicMorphHost(
        root: root,
        libraryPath: library,
        installer: installer(),
      );
      final keys = <String>[];
      host.addListener(() => keys.add(host.configurationKey));
      // The widget-test binding fakes HttpClient; this test serves locally.
      await HttpOverrides.runWithHttpOverrides(host.install, _RealHttp());
      expect(host.status.installed, isTrue);
      expect(host.status.loaded, isTrue, reason: host.status.problem);
      expect(keys.last, endsWith(':true'));
      final morphology = host.morphology;
      expect(morphology.isAvailable, isTrue);
      final result = await morphology.analyzeWords(['كتبوا']);
      expect(
        result['كتبوا']!.any(
          (a) => a['lex'] == 'كَتَب' && a['pos'] == 'verb' && a['num'] == 'p',
        ),
        isTrue,
      );

      // A fresh host (next app start) finds and loads it without network.
      await server.close(force: true);
      final restarted = NativeStudioArabicMorphHost(
        root: root,
        libraryPath: library,
        installer: installer(),
      );
      await restarted.refresh();
      expect(restarted.status.loaded, isTrue);
      await restarted.remove();

      await host.remove();
      expect(host.status.installed, isFalse);
      expect(morphology.isAvailable, isFalse);
      expect(host.morphology.isAvailable, isFalse);
      expect(host.configurationKey, isEmpty);
    },
    skip: library == null || bundle == null
        ? 'Set QUDS_ARABIC_MORPH_TEST_LIBRARY and QUDS_ARABIC_MORPH_TEST_BUNDLE.'
        : null,
    timeout: const Timeout(Duration(minutes: 2)),
  );

  testWidgets('the licence page lists the analyzer code and the CC BY data', (
    tester,
  ) async {
    registerStudioLicenses();
    final entries = await LicenseRegistry.licenses.toList();
    String textOf(String package) => entries
        .where((entry) => entry.packages.contains(package))
        .expand((entry) => entry.paragraphs)
        .map((paragraph) => paragraph.text)
        .join('\n');
    expect(
      textOf('camel_tools 1.6.0 (MIT)'),
      contains('New York University Abu Dhabi'),
    );
    expect(textOf('Ryu (Apache-2.0)'), contains('Apache License'));
    expect(
      textOf('Arabic morphology analyzer (CrispEmbed, MIT)'),
      contains('MIT License'),
    );
    final data = textOf('Camel Morph MSA v1.0 (CC BY 4.0, downloaded data)');
    expect(data, contains('licensed under CC BY 4.0'));
    expect(data, contains('creativecommons.org/licenses/by/4.0'));
  });
}

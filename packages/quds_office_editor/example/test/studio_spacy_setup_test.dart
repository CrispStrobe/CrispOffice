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
        platform: SpacyPlatform.macosArm64,
      );
      await host.refresh();
      expect(host.status.package, isNull);
      expect(host.status.unavailableReason, isNotEmpty);
      await expectLater(host.install(), throwsA(isA<Exception>()));
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

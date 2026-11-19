import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';
import 'package:quds_office_studio/studio_hunspell_host.dart';
import 'package:quds_office_studio/studio_hunspell_host_native.dart';
import 'package:quds_office_studio/studio_hunspell_setup.dart';
import 'package:quds_proofing_hunspell/quds_proofing_hunspell.dart';

/// Records host calls; installation completes only when the test allows it.
class _FakeHost extends StudioHunspellHost {
  var _status = const StudioHunspellStatus(bundle: ayaspellArabic);
  final calls = <String>[];
  Completer<void>? installGate;
  void Function(int, int)? progress;

  @override
  List<StudioHunspellStatus> get statuses => [_status];

  void _set(StudioHunspellStatus value) {
    _status = value;
    notifyListeners();
  }

  @override
  Future<void> refresh() async => calls.add('refresh');

  @override
  Future<void> install(
    HunspellBundleDownload bundle, {
    void Function(int received, int total)? onProgress,
    StudioHunspellCancellation? cancellation,
  }) async {
    calls.add('install:${bundle.id}');
    progress = onProgress;
    installGate = Completer<void>();
    await installGate!.future;
    if (cancellation?.isCancelled ?? false) {
      throw StateError('Download cancelled.');
    }
    _set(StudioHunspellStatus(bundle: bundle, installed: true, location: '/x'));
  }

  @override
  Future<void> remove(HunspellBundleDownload bundle) async {
    calls.add('remove:${bundle.id}');
    _set(StudioHunspellStatus(bundle: bundle));
  }

  @override
  List<OfficeProofingProvider> createProviders(
    OfficeProofingVocabulary vocabulary,
  ) => const [];
}

Future<void> _open(WidgetTester tester, StudioHunspellHost host) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: StudioHunspellSetupDialog(host: host)),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('download is explicit, shows source, licence and digests', (
    tester,
  ) async {
    final host = _FakeHost();
    await _open(tester, host);
    expect(host.calls, ['refresh']);
    expect(find.textContaining('Not installed'), findsOneWidget);
    expect(
      find.textContaining('cstr/ayaspell-ar-hunspell/tree/e9ace7cca384'),
      findsOneWidget,
    );
    expect(find.textContaining('MPL 1.1'), findsWidgets);
    expect(find.textContaining('ar.dic 2a3e5367f61c'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('hunspell-ayaspell-ar-install')),
    );
    await tester.pump();
    expect(host.calls, ['refresh', 'install:ayaspell-ar']);
    host.progress!(3, 6);
    await tester.pump();
    final bar = tester.widget<LinearProgressIndicator>(
      find.byType(LinearProgressIndicator),
    );
    expect(bar.value, 0.5);
    host.installGate!.complete();
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('hunspell-ayaspell-ar-installed')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('hunspell-ayaspell-ar-remove')));
    await tester.pumpAndSettle();
    expect(host.calls.last, 'remove:ayaspell-ar');
    expect(find.textContaining('Not installed'), findsOneWidget);
  });

  testWidgets('cancelling a download reports it and installs nothing', (
    tester,
  ) async {
    final host = _FakeHost();
    await _open(tester, host);
    await tester.tap(
      find.byKey(const ValueKey('hunspell-ayaspell-ar-install')),
    );
    await tester.pump();
    await tester.tap(find.text('Cancel'));
    host.installGate!.complete();
    await tester.pumpAndSettle();
    expect(find.textContaining('Download cancelled.'), findsOneWidget);
    expect(find.textContaining('Not installed'), findsOneWidget);
  });

  test('native host without an installation offers no provider', () async {
    final root = Directory.systemTemp.createTempSync('hunspell-host-');
    addTearDown(() => root.deleteSync(recursive: true));
    final host = NativeStudioHunspellHost(root: root);
    await host.refresh();
    expect(host.status(ayaspellArabic).installed, isFalse);
    expect(host.configurationKey, isEmpty);
    expect(host.createProviders(OfficeProofingVocabulary()), isEmpty);
  });
}

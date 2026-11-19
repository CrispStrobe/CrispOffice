// Real Arabic morphology host acceptance. Run with both pinned native inputs:
//   QUDS_ARABIC_MORPH_TEST_LIBRARY=<native library>
//   QUDS_ARABIC_MORPH_TEST_BUNDLE=<verified proofing-bin bundle directory>
// Ordinary dialog, missing-install and licence checks stay in
// studio_arabic_morph_setup_test.dart.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:quds_arabic_morph/installer_io.dart';
import 'package:quds_office_studio/studio_arabic_morph_host_native.dart';

class _RealHttp extends HttpOverrides {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
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
}

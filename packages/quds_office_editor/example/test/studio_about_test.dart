import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_studio/studio_about.dart';
import 'package:quds_office_studio/studio_strings.dart';

void main() {
  const channel = MethodChannel('plugins.flutter.io/url_launcher');
  const strings = StudioStrings(StudioLanguage.en);

  for (final capabilityThrows in [false, true]) {
    for (final link in [
      (
        label: strings.sourceCode,
        url: 'https://github.com/CrispStrobe/quds_office_suite',
      ),
      (label: strings.website, url: 'https://www.crispstro.be'),
      (
        label: strings.privacyPolicy,
        url: 'https://www.crispstro.be/en/crispoffice-privacy/',
      ),
    ]) {
      testWidgets('${link.label} launches when the capability query '
          '${capabilityThrows ? 'would throw' : 'would return false'}', (
        tester,
      ) async {
        await tester.binding.setSurfaceSize(const Size(1000, 1000));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final calls = <MethodCall>[];
        final messenger = tester.binding.defaultBinaryMessenger;
        messenger.setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          if (call.method == 'canLaunch') {
            if (capabilityThrows) {
              throw PlatformException(code: 'capability-query-denied');
            }
            return false;
          }
          if (call.method == 'launch') return true;
          throw PlatformException(code: 'unexpected-${call.method}');
        });
        addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: StudioAboutDialog(
                strings: strings,
                version: StudioAppVersion('1.0.0', '1'),
              ),
            ),
          ),
        );
        final button = find.widgetWithText(TextButton, link.label);
        await tester.ensureVisible(button);
        await tester.tap(button);
        await tester.pump();

        expect(calls.map((call) => call.method), ['launch']);
        final arguments = calls.single.arguments as Map<Object?, Object?>;
        expect(arguments['url'], link.url);
        expect(arguments['useWebView'], isFalse);
        expect(arguments['useSafariVC'], isFalse);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }

  group('version', () {
    String versionText(WidgetTester tester) => tester
        .widget<SelectableText>(
          find.byKey(const ValueKey<String>('studio-about-version')),
        )
        .data!;

    testWidgets('shows the injected bundle version and build', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      var loads = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StudioAboutDialog(
              strings: strings,
              version: const StudioAppVersion('2.3.4', '567'),
              versionLoader: () async {
                loads++;
                return const StudioAppVersion('9.9.9', '9');
              },
            ),
          ),
        ),
      );
      await tester.pump();
      expect(versionText(tester), 'Version 2.3.4 (567)');
      expect(find.textContaining('1.0.0'), findsNothing);
      expect(loads, 0);

      final licences = find.widgetWithText(
        OutlinedButton,
        strings.viewLicences,
      );
      await tester.ensureVisible(licences);
      await tester.tap(licences);
      await tester.pumpAndSettle();
      expect(find.text('2.3.4 (567)'), findsOneWidget);
    });

    testWidgets('reads the version from the bundle loader', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StudioAboutDialog(
              strings: const StudioStrings(StudioLanguage.de),
              versionLoader: () async => const StudioAppVersion('1.4.0', '12'),
            ),
          ),
        ),
      );
      expect(versionText(tester), isEmpty);
      await tester.pump();
      expect(versionText(tester), 'Version 1.4.0 (12)');
    });

    testWidgets('an unavailable bundle version shows no made-up number', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1000, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StudioAboutDialog(
              strings: strings,
              versionLoader: () async => null,
            ),
          ),
        ),
      );
      await tester.pump();
      expect(versionText(tester), isEmpty);
      expect(tester.takeException(), isNull);
    });

    test('label omits a missing or duplicate build', () {
      expect(const StudioAppVersion('1.2.0', '').label, '1.2.0');
      expect(const StudioAppVersion('1.2.0', '1.2.0').label, '1.2.0');
      expect(const StudioAppVersion('1.2.0', '7').label, '1.2.0 (7)');
    });
  });

  test('German UI links the German privacy policy', () {
    expect(
      const StudioStrings(StudioLanguage.de).privacyPolicyUrl,
      'https://www.crispstro.be/de/crispoffice-datenschutz/',
    );
  });
}

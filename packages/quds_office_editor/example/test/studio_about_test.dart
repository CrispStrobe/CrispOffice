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
            home: Scaffold(body: StudioAboutDialog(strings: strings)),
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

  test('German UI links the German privacy policy', () {
    expect(
      const StudioStrings(StudioLanguage.de).privacyPolicyUrl,
      'https://www.crispstro.be/de/crispoffice-datenschutz/',
    );
  });
}

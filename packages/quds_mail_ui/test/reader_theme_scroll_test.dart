import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_mail_ui/quds_mail_ui.dart';
import 'fixtures/mail_fixture.dart';

void main() {
  for (final dark in [false, true]) {
    testWidgets('reader colors and scrolling preserve its surface, dark=$dark', (
      tester,
    ) async {
      final controller = MailReaderController(
        result: mailFixture(
          html:
              '<a href="https://example.invalid">Link</a><p>${'Long mail text. ' * 2000}</p>',
        ),
      );
      addTearDown(controller.dispose);
      final theme = ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: dark ? Brightness.dark : Brightness.light,
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: Scaffold(body: MailMessageView(controller: controller)),
        ),
      );
      await tester.pumpAndSettle();
      final surface = tester.renderObject<RenderMailSelectionSurface>(
        find.byType(MailSelectionSurface),
      );
      expect(surface.textStyle.color, theme.colorScheme.onSurface);
      expect(surface.linkColor, theme.colorScheme.primary);
      final luminance = theme.colorScheme.surface.computeLuminance();
      final foreground = surface.textStyle.color!.computeLuminance();
      final ratio = foreground > luminance
          ? (foreground + .05) / (luminance + .05)
          : (luminance + .05) / (foreground + .05);
      expect(ratio, greaterThan(4.5));
      expect(
        tester.renderObject(
          find.byKey(const ValueKey('mail-reader-repaint-boundary')),
        ),
        isA<RenderRepaintBoundary>(),
      );
      final scroll = tester.state<ScrollableState>(
        find
            .descendant(
              of: find.byKey(const ValueKey('mail-reader-scroll')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.sendEventToBinding(
        PointerScrollEvent(
          position: tester.getCenter(
            find.byKey(const ValueKey('mail-reader-scroll')),
          ),
          scrollDelta: const Offset(0, 350),
        ),
      );
      await tester.pumpAndSettle();
      expect(scroll.position.pixels, greaterThan(0));
      expect(
        tester.renderObject(find.byType(MailSelectionSurface)),
        same(surface),
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}

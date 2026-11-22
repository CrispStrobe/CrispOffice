import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_office_studio/studio_mail_rules_dialog.dart';
import 'package:quds_office_studio/studio_strings.dart';

MailRule _rule({int position = 0, String query = 'from:shop'}) =>
    MailRule.parse(
      id: 'rule-$position',
      name: 'Shop $position',
      query: query,
      position: position,
      addTags: const ['Receipts'],
    );

Widget _host({
  required List<MailRule> rules,
  required StudioMailRulePreview preview,
  required StudioMailRuleApply apply,
  required StudioMailRuleSave save,
}) => MaterialApp(
  home: Builder(
    builder: (context) => TextButton(
      onPressed: () => showStudioMailRulesDialog(
        context,
        strings: const StudioStrings(StudioLanguage.en),
        rules: rules,
        preview: preview,
        apply: apply,
        save: save,
      ),
      child: const Text('open'),
    ),
  ),
);

void main() {
  testWidgets('adds and saves a rule in order', (tester) async {
    List<MailRule>? saved;
    await tester.pumpWidget(
      _host(
        rules: [_rule()],
        preview: (_) async => 0,
        apply: (_) async => 0,
        save: (rules) async => saved = rules,
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('studio-mail-rule-add')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('studio-mail-rule-name')),
      'Travel',
    );
    await tester.enterText(
      find.byKey(const ValueKey('studio-mail-rule-query')),
      'subject:booking',
    );
    await tester.enterText(
      find.byKey(const ValueKey('studio-mail-rule-add-tags')),
      'Travel',
    );
    await tester.tap(find.byKey(const ValueKey('studio-mail-rule-save')));
    await tester.pumpAndSettle();
    expect(saved, isNotNull);
    expect(saved!.map((rule) => rule.name), ['Shop 0', 'Travel']);
    expect(saved!.last.position, 1);
    expect(saved!.last.addTags.single.name, 'Travel');
    expect(find.text('Travel'), findsOneWidget);
  });

  testWidgets('previews saved matches for enabled rules', (tester) async {
    await tester.pumpWidget(
      _host(
        rules: [_rule()],
        preview: (rule) async {
          expect(rule.id, 'rule-0');
          return 7;
        },
        apply: (_) async => 0,
        save: (_) async {},
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('studio-mail-rule-preview')));
    await tester.pumpAndSettle();
    expect(find.textContaining('7 saved matches'), findsOneWidget);
  });

  testWidgets('applies rules only after confirmation', (tester) async {
    var applied = false;
    await tester.pumpWidget(
      _host(
        rules: [_rule()],
        preview: (_) async => 1,
        apply: (rules) async {
          applied = true;
          expect(rules.single.id, 'rule-0');
          return 2;
        },
        save: (_) async {},
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('studio-mail-rule-apply')));
    await tester.pumpAndSettle();
    expect(applied, isFalse);
    await tester.tap(
      find.byKey(const ValueKey('studio-mail-rule-apply-confirm')),
    );
    await tester.pumpAndSettle();
    expect(applied, isTrue);
    expect(find.text('Updated 2 messages.'), findsOneWidget);
  });

  testWidgets('invalid rule stays in the editor with an error', (tester) async {
    await tester.pumpWidget(
      _host(
        rules: const [],
        preview: (_) async => 0,
        apply: (_) async => 0,
        save: (_) async {},
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('studio-mail-rule-add')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('studio-mail-rule-name')),
      'Broken',
    );
    await tester.enterText(
      find.byKey(const ValueKey('studio-mail-rule-query')),
      'subject:(',
    );
    await tester.enterText(
      find.byKey(const ValueKey('studio-mail-rule-add-tags')),
      'Work',
    );
    await tester.tap(find.byKey(const ValueKey('studio-mail-rule-save')));
    await tester.pump();
    expect(
      find.byKey(const ValueKey('studio-mail-rule-error')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('studio-mail-rule-save')), findsOneWidget);
  });
}

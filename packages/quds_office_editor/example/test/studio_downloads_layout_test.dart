import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_arabic_morph/quds_arabic_morph.dart';
import 'package:quds_office_editor/quds_office_editor.dart';
import 'package:quds_proofing_hunspell/quds_proofing_hunspell.dart';
import 'package:quds_office_studio/studio_download_catalog.dart';
import 'package:quds_office_studio/studio_downloads_manager.dart';
import 'package:quds_office_studio/studio_hunspell_setup.dart';
import 'package:quds_office_studio/studio_material_theme.dart';
import 'package:quds_office_studio/studio_spacy_setup.dart';
import 'package:quds_office_studio/studio_strings.dart';

import 'support/studio_download_fakes.dart';

/// Every package the fixture hosts offer, in catalog order.
final _ids = <String>[
  ayaspellArabic.id,
  camelMorphMsaProofingBin.id,
  camelMorphMsaDisambig.id,
  studioSpacyGermanId,
  studioSpacyNerId,
  'spacy-en',
  'spacy-fr',
];

Finder _row(String id) => find.byKey(ValueKey<String>('download-$id'));

Future<void> _open(
  WidgetTester tester, {
  Size size = const Size(1200, 900),
  bool dark = false,
  bool rtl = false,
  StudioLanguage language = StudioLanguage.en,
  FakeDictionaries? dictionaries,
  FakeMorphology? morphology,
  FakeModels? models,
  StudioDownloadActivity? activity,
  Future<void> Function(Uri)? openLicence,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      theme: studioMaterialTheme(
        ThemeData(),
        office: dark ? OfficeTheme.dark : OfficeTheme.light,
        accent: const Color(0xFF2B579A),
        dark: dark,
      ),
      home: Directionality(
        textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
        child: StudioDownloadsManager(
          hunspell: dictionaries ?? FakeDictionaries(),
          morphology: morphology ?? FakeMorphology(),
          spacy: models ?? FakeModels(frenchProblem: 'Verification failed: x'),
          language: language,
          activity: activity ?? StudioDownloadActivity(),
          openLicence: openLicence ?? (_) async {},
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  for (final width in <double>[360, 1200]) {
    for (final dark in <bool>[false, true]) {
      for (final rtl in <bool>[false, true]) {
        testWidgets('uniform rows at ${width.toInt()} px'
            '${dark ? ', dark' : ''}${rtl ? ', RTL' : ''}', (tester) async {
          await _open(
            tester,
            size: Size(width, 800),
            dark: dark,
            rtl: rtl,
            language: rtl ? StudioLanguage.ar : StudioLanguage.en,
          );
          expect(tester.takeException(), isNull);

          // Every package is present, once.
          for (final id in _ids) {
            expect(_row(id), findsOneWidget, reason: id);
          }
          // All rows share one width and one left edge.
          final rects = <Rect>[for (final id in _ids) tester.getRect(_row(id))];
          for (final rect in rects) {
            expect(rect.width, moreOrLessEquals(rects.first.width));
            expect(rect.left, moreOrLessEquals(rects.first.left));
          }
          expect(rects.first.width, lessThanOrEqualTo(width));

          // The footer never overlaps the scrolling list.
          final list = tester.getRect(
            find.byKey(const ValueKey('downloads-scroll')),
          );
          final close = tester.getRect(
            find.widgetWithText(TextButton, rtl ? 'إغلاق' : 'Close'),
          );
          expect(close.top, greaterThanOrEqualTo(list.bottom));

          final manager = tester.element(find.byType(StudioDownloadsManager));
          expect(
            Theme.of(manager).brightness,
            dark ? Brightness.dark : Brightness.light,
          );
          final rowElement = tester.element(_row(ayaspellArabic.id));
          expect(
            Directionality.of(rowElement),
            rtl ? TextDirection.rtl : TextDirection.ltr,
          );

          // Leading icon sits at the start edge (right in RTL).
          final avatar = tester.getRect(
            find.descendant(
              of: _row(ayaspellArabic.id),
              matching: find.byType(CircleAvatar),
            ),
          );
          final title = tester.getRect(
            find.textContaining(ayaspellArabic.displayName),
          );
          if (rtl) {
            expect(avatar.left, greaterThan(title.left));
          } else {
            expect(avatar.right, lessThanOrEqualTo(title.left));
          }

          final install = tester.getRect(
            find.byKey(
              ValueKey('download-${camelMorphMsaProofingBin.id}-install'),
            ),
          );
          final morphTitle = tester.getRect(
            find
                .descendant(
                  of: _row(camelMorphMsaProofingBin.id),
                  matching: find.textContaining(
                    camelMorphMsaProofingBin.displayName,
                  ),
                )
                .first,
          );
          if (width < 600) {
            // Phone layout: actions under the text.
            expect(install.top, greaterThan(morphTitle.bottom));
          } else {
            // Wide layout: status chips and actions in aligned columns.
            final chips = <Rect>[
              for (final id in _ids)
                tester.getRect(find.byKey(ValueKey('download-$id-status'))),
            ];
            for (final chip in chips) {
              if (rtl) {
                expect(chip.right, moreOrLessEquals(chips.first.right));
              } else {
                expect(chip.left, moreOrLessEquals(chips.first.left));
              }
            }
            expect(install.top, lessThan(morphTitle.bottom));
          }
        });
      }
    }
  }

  testWidgets('status chips reflect installed, missing, broken and blocked', (
    tester,
  ) async {
    await _open(tester);
    String chip(String id) => tester
        .widgetList<Text>(
          find.descendant(
            of: find.byKey(ValueKey('download-$id-status')),
            matching: find.byType(Text),
          ),
        )
        .single
        .data!;
    expect(chip(ayaspellArabic.id), 'Installed · 7.0 MB');
    expect(chip(camelMorphMsaProofingBin.id), 'Not installed');
    expect(chip(camelMorphMsaDisambig.id), 'Needs base package');
    expect(
      find.descendant(
        of: find.byKey(
          ValueKey('download-${camelMorphMsaDisambig.id}-requires'),
        ),
        matching: find.text(camelMorphMsaProofingBin.displayName),
        matchRoot: true,
      ),
      findsOneWidget,
    );
    expect(chip('spacy-fr'), 'Needs repair');
    expect(find.text('Verification failed: x'), findsOneWidget);
    expect(find.byKey(const ValueKey('download-spacy-fr-install')), findsOne);
    expect(find.byKey(const ValueKey('download-spacy-fr-remove')), findsOne);
    expect(find.byKey(const ValueKey('downloads-summary')), findsOneWidget);
    expect(find.textContaining('3 of 7 packages installed'), findsOneWidget);
  });

  testWidgets('a running download shows progress and can be cancelled', (
    tester,
  ) async {
    final activity = StudioDownloadActivity();
    final done = Completer<void>();
    var cancelled = false;
    late void Function(int, int) report;
    final tracked = activity.track(
      camelMorphMsaProofingBin.id,
      cancel: () {
        cancelled = true;
        done.complete();
      },
      download: (reporter) {
        report = reporter;
        return done.future;
      },
    );
    report(42, 100);
    await _open(tester, activity: activity);
    final id = camelMorphMsaProofingBin.id;
    expect(
      find.descendant(
        of: find.byKey(ValueKey('download-$id-status')),
        matching: find.text('Downloading 42%'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: _row(id),
        matching: find.byType(LinearProgressIndicator),
      ),
      findsOneWidget,
    );
    await tester.tap(find.byKey(ValueKey('download-$id-cancel')));
    await tracked;
    await tester.pumpAndSettle();
    expect(cancelled, isTrue);
    expect(find.byKey(ValueKey('download-$id-install')), findsOneWidget);
  });

  testWidgets('install opens the review dialog and never downloads', (
    tester,
  ) async {
    final dictionaries = FakeDictionaries(installed: false);
    final morphology = FakeMorphology();
    final models = FakeModels();
    await _open(
      tester,
      dictionaries: dictionaries,
      morphology: morphology,
      models: models,
    );
    final install = find.byKey(
      ValueKey('download-${ayaspellArabic.id}-install'),
    );
    await tester.ensureVisible(install);
    await tester.tap(install);
    await tester.pumpAndSettle();
    expect(find.byType(StudioHunspellSetupDialog), findsOneWidget);
    expect(dictionaries.calls, isNot(contains('install')));
    Navigator.of(tester.element(find.byType(StudioHunspellSetupDialog))).pop();
    await tester.pumpAndSettle();

    final german = find.byKey(const ValueKey('download-spacy-de-install'));
    await tester.ensureVisible(german);
    await tester.tap(german);
    await tester.pumpAndSettle();
    expect(find.byType(StudioSpacySetupDialog), findsOneWidget);
    expect(models.calls, isNot(contains('install')));
  });

  testWidgets('licence link opens the licence page', (tester) async {
    final opened = <Uri>[];
    await _open(tester, openLicence: (url) async => opened.add(url));
    final link = find.byKey(
      ValueKey('download-${camelMorphMsaDisambig.id}-licence'),
    );
    await tester.ensureVisible(link);
    await tester.tap(link);
    await tester.pump();
    expect(opened, <Uri>[Uri.parse(camelMorphMsaDisambig.licenseUrl)]);
    expect(find.text('CC BY-SA 4.0'), findsOneWidget);
    expect(find.text('MPL 1.1'), findsOneWidget);
    expect(find.text('LGPL-LR'), findsOneWidget);
  });

  testWidgets('German and Arabic labels come from the Studio strings', (
    tester,
  ) async {
    await _open(tester, language: StudioLanguage.de);
    expect(find.text('Sprachdownloads'), findsOneWidget);
    expect(find.text('In der App enthalten'), findsOneWidget);
    expect(find.text('Arabisch'), findsOneWidget);
    expect(find.text('Installieren…'), findsWidgets);
    expect(find.text('Schließen'), findsOneWidget);
    await _open(tester, language: StudioLanguage.ar, rtl: true);
    expect(find.text('تنزيلات اللغة'), findsOneWidget);
    expect(find.text('العربية'), findsOneWidget);
  });

  testWidgets('rows expose a semantic label with title and status', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await _open(tester);
    expect(
      find.bySemanticsLabel(
        RegExp('^${RegExp.escape(ayaspellArabic.displayName)}, Installed'),
      ),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel('Licence MPL 1.1 (opens in browser)'),
      findsOneWidget,
    );
    handle.dispose();
  });

  testWidgets('each catalog package has an entry in its review dialog', (
    tester,
  ) async {
    final dictionaries = FakeDictionaries(installed: false);
    final morphology = FakeMorphology(installed: true);
    final models = FakeModels()..german = true;
    final catalog = studioDownloadCatalog(
      hunspell: dictionaries,
      morphology: morphology,
      spacy: models,
    );
    expect(catalog.map((item) => item.id), _ids);
    await tester.binding.setSurfaceSize(const Size(1200, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: StudioHunspellSetupDialog(
          host: dictionaries,
          morphHost: morphology,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final dictionaryKeys = <String, String>{
      ayaspellArabic.id: 'hunspell-${ayaspellArabic.id}',
      camelMorphMsaProofingBin.id: 'arabic-morph',
      camelMorphMsaDisambig.id: 'arabic-morph-model',
    };
    for (final item in catalog.where(
      (item) => item.review == StudioDownloadReview.dictionaries,
    )) {
      expect(find.byKey(ValueKey(dictionaryKeys[item.id]!)), findsOneWidget);
    }

    await tester.pumpWidget(
      MaterialApp(home: StudioSpacySetupDialog(host: models)),
    );
    await tester.pumpAndSettle();
    final analysisKeys = <String, String>{
      studioSpacyNerId: 'spacy-setup-ner',
      'spacy-en': 'spacy-language-en-details',
      'spacy-fr': 'spacy-language-fr-details',
    };
    for (final item in catalog.where(
      (item) =>
          item.review == StudioDownloadReview.analysis &&
          item.id != studioSpacyGermanId,
    )) {
      expect(find.byKey(Key(analysisKeys[item.id]!)), findsOneWidget);
    }
    // The German package is reviewed before it is installed.
    models.german = false;
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(
      MaterialApp(home: StudioSpacySetupDialog(host: models)),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('spacy-setup-source')), findsOneWidget);
    expect(find.byKey(const Key('spacy-setup-install')), findsOneWidget);
  });
}

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Notices of components compiled into the app that are not Dart packages
/// (their package LICENSE files are collected by Flutter automatically).
///
/// The Hunspell 1.7.2 library files are used unmodified under the MPL 1.1
/// option of their MPL/GPL/LGPL tri-licence; the exact sources are in
/// `packages/quds_proofing_hunspell/licenses/`. Downloaded dictionaries carry
/// their own notices and are shown in the dictionary setup.
///
/// The Arabic morphology analyzer compiles the MIT CrispEmbed port of MIT
/// camel_tools together with Ryu (Apache-2.0 option) and Unicode/CPython
/// character tables (`packages/quds_arabic_morph/licenses/`). Its Camel Morph
/// MSA database is CC BY 4.0 data the user downloads; its attribution is
/// listed here and in the Dictionaries dialog.
///
/// Automatic language detection compiles CrispASR's MIT CLD3 runtime and
/// bundles Google's CLD3 model (Apache-2.0) as an app asset
/// (`packages/quds_language_id/licenses/`).
///
/// English proofing compiles Harper (Apache-2.0) and its Rust crates
/// (`packages/quds_proofing_harper/licenses/`; the complete notice archive
/// ships in the app's `Resources/harper-licenses`).
///
/// Local text analysis compiles the CrispEmbed spaCy runtime (MIT) with
/// ggml, PCRE2, Thinc/spaCy-derived code and Unicode/CPython character data
/// (`packages/quds_proofing_spacy/licenses/`). The spaCy models are MIT data
/// the user downloads.
void registerStudioLicenses() {
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks(
      const ['CrispOffice open font pack (SIL Open Font License 1.1)'],
      await rootBundle.loadString('assets/licenses/open_font_pack/LICENSE.txt'),
    );
  });
  LicenseRegistry.addLicense(() async* {
    const base = 'assets/licenses/hunspell';
    final notice = await rootBundle.loadString('$base/license.hunspell');
    final myspell = await rootBundle.loadString('$base/license.myspell');
    final mpl = await rootBundle.loadString('$base/COPYING.MPL');
    yield LicenseEntryWithLineBreaks(const [
      'Hunspell 1.7.2 (MPL 1.1)',
    ], '$notice\n\n$myspell');
    yield LicenseEntryWithLineBreaks(const ['Hunspell 1.7.2 (MPL 1.1)'], mpl);
    yield LicenseEntryWithLineBreaks(
      const ['AyaSpell Arabic dictionary (MPL 1.1, downloaded data)'],
      'AyaSpell Arabic spelling dictionary (LibreOffice packaging 3.5), '
      'downloaded unmodified from cstr/ayaspell-ar-hunspell revision '
      'e9ace7cc and used under the MPL 1.1 option of its GPL 2.0 / LGPL 2.1 '
      '/ MPL 1.1 tri-licence. Its COPYING, AUTHORS and README files are '
      'installed with the dictionary and shown in Dictionaries and language '
      'data.\n\n$mpl',
    );
  });
  LicenseRegistry.addLicense(() async* {
    const base = 'assets/licenses/harper';
    Future<String> load(String name) => rootBundle.loadString('$base/$name');
    yield LicenseEntryWithLineBreaks(const [
      'Harper 3.2.0 English grammar checker (Apache-2.0)',
    ], await load('HARPER-LICENSE'));
    yield LicenseEntryWithLineBreaks(const [
      'Harper 3.2.0 English grammar checker (Apache-2.0)',
    ], await load('DEPENDENCIES.txt'));
  });
  LicenseRegistry.addLicense(() async* {
    const base = 'assets/licenses/spacy';
    Future<String> load(String name) => rootBundle.loadString('$base/$name');
    yield LicenseEntryWithLineBreaks(const [
      'Local text analysis runtime (CrispEmbed spaCy, MIT)',
    ], await load('CrispEmbed-LICENSE'));
    yield LicenseEntryWithLineBreaks(const [
      'Local text analysis runtime (CrispEmbed spaCy, MIT)',
    ], await load('THIRD_PARTY_NOTICES'));
    yield LicenseEntryWithLineBreaks(const [
      'ggml (MIT)',
    ], await load('ggml-LICENSE'));
    yield LicenseEntryWithLineBreaks(const [
      'PCRE2 10.46 (BSD)',
    ], await load('PCRE2-LICENCE.md'));
    yield LicenseEntryWithLineBreaks(const [
      'spaCy (MIT)',
    ], await load('spaCy-LICENSE'));
    yield LicenseEntryWithLineBreaks(const [
      'Thinc (MIT)',
    ], await load('Thinc-LICENSE'));
    yield LicenseEntryWithLineBreaks(const [
      'Unicode character data',
    ], await load('Unicode-LICENSE.txt'));
    yield LicenseEntryWithLineBreaks(const [
      'CPython character data (PSF)',
    ], await load('CPython-LICENSE'));
    yield LicenseEntryWithLineBreaks(
      const ['spaCy models de/en/fr_core_*_sm 3.8.0 (downloaded data)'],
      'The German de_core_news_sm and English en_core_web_sm models are MIT '
      '(ExplosionAI GmbH); the French fr_core_news_sm model is LGPL-LR. Each '
      'model\'s LICENSE and training-source notices are downloaded and '
      'installed with it and summarized in Analysis setup.\n\n'
      '${await load('de_core_news_sm-LICENSE')}',
    );
  });
  LicenseRegistry.addLicense(() async* {
    const base = 'assets/licenses/language_id';
    Future<String> load(String name) => rootBundle.loadString('$base/$name');
    yield LicenseEntryWithLineBreaks(
      const ['CLD3 language detection model (Apache-2.0)'],
      'Google CLD3 (Compact Language Detector v3), Copyright 2016 Google '
      'Inc. The bundled model is cstr/cld3-GGUF revision 56e8a57d, a format '
      'conversion of the upstream weights.\n\n${await load('CLD3-LICENSE')}',
    );
    yield LicenseEntryWithLineBreaks(const [
      'Language identification runtime (CrispASR, MIT)',
    ], await load('CrispASR-LICENSE'));
  });
  LicenseRegistry.addLicense(() async* {
    const base = 'assets/licenses/arabic_morph';
    Future<String> load(String name) => rootBundle.loadString('$base/$name');
    yield LicenseEntryWithLineBreaks(const [
      'Arabic morphology analyzer (CrispEmbed, MIT)',
    ], await load('CrispEmbed-LICENSE'));
    yield LicenseEntryWithLineBreaks(const [
      'camel_tools 1.6.0 (MIT)',
    ], await load('camel_tools-LICENSE'));
    yield LicenseEntryWithLineBreaks(const [
      'Ryu (Apache-2.0)',
    ], await load('Ryu-LICENSE-Apache2'));
    yield LicenseEntryWithLineBreaks(const [
      'Unicode character data',
    ], await load('Unicode-LICENSE.txt'));
    yield LicenseEntryWithLineBreaks(const [
      'CPython character data (PSF)',
    ], await load('CPython-LICENSE'));
    yield LicenseEntryWithLineBreaks(const [
      'Arabic morphology analyzer (CrispEmbed, MIT)',
    ], await load('THIRD_PARTY_NOTICES'));
    yield LicenseEntryWithLineBreaks(
      const ['Camel Morph MSA v1.0 (CC BY 4.0, downloaded data)'],
      '${await load('camel-morph-msa-NOTICE')}\n\n'
      '${await load('camel-morph-msa-LICENSE')}',
    );
    yield LicenseEntryWithLineBreaks(
      const [
        'Arabic context model for Camel Morph (CC BY-SA 4.0, downloaded data)',
      ],
      '${await load('camel-morph-msa-disambig-NOTICE')}\n\n'
      '${await load('camel-morph-msa-disambig-LICENSE')}',
    );
  });
}

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
void registerStudioLicenses() {
  LicenseRegistry.addLicense(() async* {
    const base = 'assets/licenses/hunspell';
    final notice = await rootBundle.loadString('$base/license.hunspell');
    final myspell = await rootBundle.loadString('$base/license.myspell');
    final mpl = await rootBundle.loadString('$base/COPYING.MPL');
    yield LicenseEntryWithLineBreaks(const [
      'Hunspell 1.7.2 (MPL 1.1)',
    ], '$notice\n\n$myspell');
    yield LicenseEntryWithLineBreaks(const ['Hunspell 1.7.2 (MPL 1.1)'], mpl);
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
  });
}

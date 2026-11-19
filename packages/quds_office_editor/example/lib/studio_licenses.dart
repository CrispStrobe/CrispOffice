import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Notices of components compiled into the app that are not Dart packages
/// (their package LICENSE files are collected by Flutter automatically).
///
/// The Hunspell 1.7.2 library files are used unmodified under the MPL 1.1
/// option of their MPL/GPL/LGPL tri-licence; the exact sources are in
/// `packages/quds_proofing_hunspell/licenses/`. Downloaded dictionaries carry
/// their own notices and are shown in the dictionary setup.
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
}

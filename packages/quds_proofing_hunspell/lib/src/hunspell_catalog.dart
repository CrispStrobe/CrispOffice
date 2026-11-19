import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// One pinned file of a published dictionary bundle.
final class HunspellArtifact {
  const HunspellArtifact(this.file, this.sha256, this.bytes);
  final String file;
  final String sha256;
  final int bytes;

  /// True only when [data] has exactly the pinned length and SHA-256.
  bool matches(List<int> data) =>
      data.length == bytes && sha256Hex(data) == sha256;
}

String sha256Hex(List<int> data) => sha256.convert(data).toString();

/// A dictionary bundle published at an immutable Hugging Face revision.
/// Every value is compiled into the app; downloaded files can never widen or
/// replace these pins. Bundles hold data only (no executable code).
final class HunspellBundleDownload {
  const HunspellBundleDownload({
    required this.id,
    required this.displayName,
    required this.languages,
    required this.repository,
    required this.revision,
    required this.license,
    required this.aff,
    required this.dic,
    required this.notices,
  });

  final String id;
  final String displayName;

  /// Primary language subtags served by this dictionary (e.g. `ar`).
  final Set<String> languages;
  final String repository;

  /// Full 40-hex Hub commit; never a branch name.
  final String revision;

  /// User-facing licence summary; the full texts are installed as files.
  final String license;
  final HunspellArtifact aff;
  final HunspellArtifact dic;

  /// Licence, author and provenance files installed next to the dictionary.
  final List<HunspellArtifact> notices;

  List<HunspellArtifact> get files => [aff, dic, ...notices];
  int get totalBytes => files.fold(0, (sum, file) => sum + file.bytes);

  Uri url(HunspellArtifact artifact) {
    if (!RegExp(r'^[0-9a-f]{40}$').hasMatch(revision) ||
        !RegExp(r'^[A-Za-z0-9._-]+$').hasMatch(artifact.file)) {
      throw ArgumentError('Only immutable revision paths can be resolved.');
    }
    return Uri.https(
      'huggingface.co',
      '/$repository/resolve/$revision/${artifact.file}',
    );
  }
}

/// AyaSpell Arabic (LibreOffice packaging 3.5), published unmodified under
/// the MPL 1.1 option of its GPL/LGPL/MPL tri-licence. The thesaurus file in
/// the same repository is not part of spelling and is not downloaded here.
const ayaspellArabic = HunspellBundleDownload(
  id: 'ayaspell-ar',
  displayName: 'Arabic (AyaSpell)',
  languages: {'ar'},
  repository: 'cstr/ayaspell-ar-hunspell',
  revision: 'e9ace7cca3844bef906d8d9fc5431c4e15bd2740',
  license: 'MPL 1.1 (offered as GPL 2.0 / LGPL 2.1 / MPL 1.1, or later)',
  aff: HunspellArtifact(
    'ar.aff',
    'cec30b8621001e49618feb05aec1984c5fcfbf7d2ec309901d5cbf66585217a3',
    86949,
  ),
  dic: HunspellArtifact(
    'ar.dic',
    '2a3e5367f61c1583734db9d66734f5603e6be5c2d227cf5c5cd7e4ca586e34fe',
    7217161,
  ),
  notices: [
    HunspellArtifact(
      'COPYING.txt',
      '73480d918cd78d655508e80aa88c022cbd53634524a0f714b5f2519f2cf19124',
      532,
    ),
    HunspellArtifact(
      'AUTHORS.txt',
      'bade1d2d0d47dff5956c08732cdb9c02432d9b0b8016a56e27f58b8d7e842462',
      200,
    ),
    HunspellArtifact(
      'README_ar.txt',
      '5ead684ae5211ccf615686959e24bd21ef6eebbb6195997529fda08b993f615e',
      420,
    ),
    HunspellArtifact(
      'MPL-1.1.txt',
      '6214f8b1300bb9f37b16ebc146f8f61af0187e0025042ff95c8b3030744a8795',
      23669,
    ),
    HunspellArtifact(
      'README.md',
      '84a4cf6b537069d98fd438d37ea7e8b08b2c74565d76cb553be47bd4aeb426ad',
      1427,
    ),
    HunspellArtifact(
      'manifest.json',
      '37ef845d5527fe0f0a693ba6854e43bde73acdf2cc5164a8209552ecb20f5e31',
      2333,
    ),
  ],
);

/// All dictionaries a host may offer for download.
const hunspellCatalog = [ayaspellArabic];

/// Dictionary input for a transport: verified files on disk (native) or
/// verified bytes in memory (web).
sealed class HunspellDictionary {
  const HunspellDictionary();
}

final class HunspellDictionaryFiles extends HunspellDictionary {
  const HunspellDictionaryFiles({required this.affPath, required this.dicPath});
  final String affPath;
  final String dicPath;
}

final class HunspellDictionaryBytes extends HunspellDictionary {
  HunspellDictionaryBytes({required this.aff, required this.dic});
  final Uint8List aff;
  final Uint8List dic;

  /// Verified bytes for [bundle]; throws [FormatException] on any mismatch.
  factory HunspellDictionaryBytes.verified(
    HunspellBundleDownload bundle, {
    required Uint8List aff,
    required Uint8List dic,
  }) {
    if (!bundle.aff.matches(aff) || !bundle.dic.matches(dic)) {
      throw const FormatException(
        'Dictionary bytes do not match the pinned bundle.',
      );
    }
    return HunspellDictionaryBytes(aff: aff, dic: dic);
  }
}

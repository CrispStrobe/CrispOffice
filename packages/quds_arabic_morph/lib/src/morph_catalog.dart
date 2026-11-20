import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// One pinned file of a published morphology database bundle.
final class MorphArtifact {
  const MorphArtifact(this.file, this.sha256, this.bytes);

  /// File name inside the bundle directory (no path separators).
  final String file;
  final String sha256;
  final int bytes;

  /// True only when [data] has exactly the pinned length and SHA-256.
  bool matches(List<int> data) =>
      data.length == bytes && sha256Hex(data) == sha256;
}

String sha256Hex(List<int> data) => sha256.convert(data).toString();

/// A Camel Morph database (or context model) bundle published at an
/// immutable Hugging Face revision. Every value is compiled into the app; downloaded files can never
/// widen or replace these pins. Bundles hold data only (no executable code).
final class MorphBundleDownload {
  const MorphBundleDownload({
    required this.id,
    required this.displayName,
    required this.repository,
    required this.revision,
    required this.directory,
    required this.license,
    required this.licenseUrl,
    required this.attribution,
    required this.sourceUrl,
    required this.manifest,
    required this.database,
    required this.notices,
  });

  final String id;
  final String displayName;
  final String repository;

  /// Full 40-hex Hub commit; never a branch name.
  final String revision;

  /// Variant directory inside the repository (for example `noprob`).
  final String directory;

  /// SPDX identifier of the data licence.
  final String license;
  final String licenseUrl;

  /// Attribution the app must show (CC BY 4.0 section 3(a)).
  final String attribution;

  /// The upstream data project.
  final String sourceUrl;

  /// `manifest.json`: its SHA-256 is the analyzer's trust anchor.
  final MorphArtifact manifest;

  /// The database (or, for a context model bundle, the model file).
  final MorphArtifact database;

  /// `NOTICE` and `LICENSE`, required next to the database by the manifest.
  final List<MorphArtifact> notices;

  List<MorphArtifact> get files => [manifest, database, ...notices];
  int get totalBytes => files.fold(0, (sum, file) => sum + file.bytes);

  /// The bundle on the Hub, at the pinned revision.
  Uri get browseUrl =>
      Uri.https('huggingface.co', '/$repository/tree/$revision/$directory');

  Uri url(MorphArtifact artifact) {
    if (!RegExp(r'^[0-9a-f]{40}$').hasMatch(revision) ||
        !RegExp(r'^[A-Za-z0-9._-]+$').hasMatch(directory) ||
        !RegExp(r'^[A-Za-z0-9._-]+$').hasMatch(artifact.file)) {
      throw ArgumentError('Only immutable revision paths can be resolved.');
    }
    return Uri.https(
      'huggingface.co',
      '/$repository/resolve/$revision/$directory/${artifact.file}',
    );
  }
}

/// Camel Morph MSA v1.0 (NYU Abu Dhabi, CC BY 4.0), `proofing-bin` variant:
/// the `noprob` database (no treebank-derived `*_logprob` values) in
/// CrispEmbed's memory-mapped binary format, reduced to the features the
/// proofing rules use (`diac`, `lex`, `root`, `pos`, the clitics `prc0`-`prc3`
/// and `enc0`-`enc2`, the inflectional features and `source`). Analyses and
/// those feature values are exactly camel_tools'; 12 MB instead of 78 MB, and
/// the analyzer maps it instead of parsing it. Rules reason over all analyses,
/// so no ranking is needed (see the package README).
const camelMorphMsaProofingBin = MorphBundleDownload(
  id: 'camel-morph-msa-proofing-bin',
  displayName: 'Arabic morphology (Camel Morph MSA v1.0)',
  repository: 'cstr/camel-morph-msa-v1.0',
  revision: 'd5364e04af7a40b0c9044ed127606e585be15272',
  directory: 'proofing-bin',
  license: 'CC-BY-4.0',
  licenseUrl: 'https://creativecommons.org/licenses/by/4.0/',
  attribution:
      'Camel Morph MSA v1.0 (c) 2024 by New York University Abu Dhabi is '
      'licensed under CC BY 4.0. Changes: the treebank-derived '
      'pos_logprob/lex_logprob/pos_lex_logprob values and all features other '
      'than the proofing profile were removed, and the database was converted '
      'to a binary format.',
  sourceUrl: 'https://github.com/CAMeL-Lab/camel_morph',
  manifest: MorphArtifact(
    'manifest.json',
    '357540af897af5dd2a0f7fc84518cc875c4481e3e566c30ca0a5043a52290f71',
    2064,
  ),
  database: MorphArtifact(
    'camel_morph_msa_v1.0.proofing.cmorph',
    'fc9d9109ddb5430da94def715df05b563cb37ffaec508f3514668ded19438909',
    12166992,
  ),
  notices: [
    MorphArtifact(
      'NOTICE',
      'ce2f9c051786a37e4eb72367e6a6c9ea256b702137d4187bb0bfbda38f860efd',
      1799,
    ),
    MorphArtifact(
      'LICENSE',
      '214965747a90efe3e5268d367192bb077f1101620662cba71d59d902000b2d94',
      442,
    ),
  ],
);

/// The earlier `noprob` text bundle (78 MB ALMOR text, every feature). Still
/// opened by the analyzer, but no longer offered for download: installs of
/// it are removed in favour of [camelMorphMsaProofingBin].
const camelMorphMsaNoprob = MorphBundleDownload(
  id: 'camel-morph-msa-noprob',
  displayName: 'Arabic morphology (Camel Morph MSA v1.0)',
  repository: 'cstr/camel-morph-msa-v1.0',
  revision: 'b31cf4a83f8ad63bb1989cf2879e72f23fadbfb0',
  directory: 'noprob',
  license: 'CC-BY-4.0',
  licenseUrl: 'https://creativecommons.org/licenses/by/4.0/',
  attribution:
      'Camel Morph MSA v1.0 (c) 2024 by New York University Abu Dhabi is '
      'licensed under CC BY 4.0. Changes: the treebank-derived '
      'pos_logprob/lex_logprob/pos_lex_logprob values were removed.',
  sourceUrl: 'https://github.com/CAMeL-Lab/camel_morph',
  manifest: MorphArtifact(
    'manifest.json',
    '96b949981e76c0d2b4892ec7aac1f1e519813ac6d55d4e39303d94822df68050',
    1430,
  ),
  database: MorphArtifact(
    'camel_morph_msa_v1.0.noprob.db',
    '2dfbec413288e7da96723d7926c0e74f2e90ef6994c6f7e995a27a8df079ecff',
    78083392,
  ),
  notices: [
    MorphArtifact(
      'NOTICE',
      'b10936a72acb6f6dbc246ed75003e45f5f130deb6c7a0003c0a54ec11785bc9f',
      1381,
    ),
    MorphArtifact(
      'LICENSE',
      '214965747a90efe3e5268d367192bb077f1101620662cba71d59d902000b2d94',
      442,
    ),
  ],
);

/// The context disambiguation model for [camelMorphMsaProofingBin]
/// (CrispEmbed `crispembed-camel-morph-disambig-v1`): a bigram hidden Markov
/// model over the database's analyses, trained without annotations on Arabic
/// Wikipedia. It ranks each word's analyses in its sentence, so grammar rules
/// can rely on a clearly leading reading. CC BY-SA 4.0 (Wikipedia
/// contributors; Camel Morph MSA v1.0 (c) 2024 NYU Abu Dhabi, CC BY 4.0).
/// Its `database` artifact is the model file.
const camelMorphMsaDisambig = MorphBundleDownload(
  id: 'camel-morph-msa-disambig',
  displayName: 'Arabic context model (Camel Morph disambiguation)',
  repository: 'cstr/camel-morph-msa-disambig',
  revision: '07fd9e65200a3ea92a081efa9b0714817178df5f',
  directory: 'bigram-v1',
  license: 'CC-BY-SA-4.0',
  licenseUrl: 'https://creativecommons.org/licenses/by-sa/4.0/',
  attribution:
      'Camel Morph MSA context disambiguation model, CC BY-SA 4.0. Trained on '
      'Arabic Wikipedia text by Wikipedia contributors (CC BY-SA 4.0) over '
      'Camel Morph MSA v1.0 (c) 2024 by New York University Abu Dhabi '
      '(CC BY 4.0). Changes: the text was reduced to smoothed tag-transition '
      'and lexeme probabilities; it contains no sentence of the text.',
  sourceUrl:
      'https://github.com/CrispStrobe/CrispEmbed/blob/main/docs/arabic-morph-disambig-format.md',
  manifest: MorphArtifact(
    'manifest.json',
    '02b8fc1cdfd8c925f6737029eafd79aea22148f2ce0af31b8b0e07a95053cbaa',
    1753,
  ),
  database: MorphArtifact(
    'camel_morph_msa_v1.0.disambig.cmdis',
    '987250d64ec36e631b125f9f7ba52f4e5fe48da694ea3a6a21786b4ac4aabf61',
    4487296,
  ),
  notices: [
    MorphArtifact(
      'NOTICE',
      '12f44e5787019e5eb5595663cb7275408d961f430b74d108fa77006235e2638b',
      1484,
    ),
    MorphArtifact(
      'LICENSE',
      'ef2c6367af269181d259bbda4b6167684f85242bb04b28923f91e2861be4c695',
      363,
    ),
  ],
);

/// All morphology databases a host may offer for download.
const morphCatalog = [camelMorphMsaProofingBin];

/// Database input for a transport: a verified bundle on disk (native) or
/// verified bytes in memory (web).
sealed class MorphDatabase {
  const MorphDatabase(this.bundle);
  final MorphBundleDownload bundle;
}

/// A verified installed bundle; [manifestPath] points at its `manifest.json`
/// with the other files next to it. The analyzer re-checks every file
/// against the manifest, and the manifest against the compiled-in pin.
final class MorphDatabaseFiles extends MorphDatabase {
  const MorphDatabaseFiles(super.bundle, {required this.manifestPath});
  final String manifestPath;
}

/// Verified bundle bytes (web), keyed by file name.
final class MorphDatabaseBytes extends MorphDatabase {
  MorphDatabaseBytes._(super.bundle, this.files);
  final Map<String, Uint8List> files;

  /// Verified bytes for [bundle]; throws [FormatException] on any mismatch
  /// or a missing or extra file.
  factory MorphDatabaseBytes.verified(
    MorphBundleDownload bundle,
    Map<String, Uint8List> files,
  ) {
    final expected = {for (final a in bundle.files) a.file: a};
    if (files.length != expected.length ||
        !files.entries.every(
          (entry) => expected[entry.key]?.matches(entry.value) ?? false,
        )) {
      throw const FormatException(
        'Morphology bundle bytes do not match the pinned bundle.',
      );
    }
    return MorphDatabaseBytes._(bundle, Map.unmodifiable(files));
  }
}

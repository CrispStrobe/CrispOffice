import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;

/// The CLD3 model bundled with the app.
abstract final class Cld3Model {
  /// `cstr/cld3-GGUF` at this immutable Hugging Face revision.
  static const repository = 'https://huggingface.co/cstr/cld3-GGUF';
  static const revision = '56e8a57d479faa184dceede5f985d08d9816e999';
  static const file = 'cld3-f16.gguf';
  static const sha256 =
      '900813b635fa7f472beac213f521d57dd12378099b0623a8a36de0310b6bf892';
  static const bytes = 439712;
  static const license = 'Apache-2.0';

  /// Flutter asset key of the bundled copy.
  static const assetKey = 'packages/quds_language_id/assets/cld3-f16.gguf';

  /// Licence-page attribution.
  static const attribution =
      'Language detection uses Google CLD3 (Compact Language Detector v3), '
      'Copyright 2016 Google Inc., licensed under the Apache License 2.0. '
      'Model converted to GGUF (cstr/cld3-GGUF, revision 56e8a57d); runtime '
      'from CrispASR (MIT).';

  /// Whether [data] is exactly the pinned model.
  static bool verify(Uint8List data) =>
      data.length == bytes && sha256Of(data) == sha256;

  static String sha256Of(List<int> data) =>
      crypto.sha256.convert(data).toString();
}

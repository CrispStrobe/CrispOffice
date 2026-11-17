import 'dart:typed_data';

const String gectorModelRevision = '8e3b50beef7d775cedb7b876009e88bcf2e8d6af';
const String gectorSourceModelSha256 =
    '6d7b43b4bd95c7a00c02c8babc7569d28558df894afe4874d96c202e6ab9a464';

/// An explicit artifact pin supplied by the host's qualification manifest.
/// Naming a hash does not assert that a precision or model is qualified.
final class GectorModelArtifact {
  GectorModelArtifact({
    required this.file,
    required this.sha256,
    required this.bytes,
    this.sourceModelSha256 = gectorSourceModelSha256,
    this.revision = gectorModelRevision,
  }) {
    if (!RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]*$').hasMatch(file) ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(sha256) ||
        bytes < 1 ||
        sourceModelSha256 != gectorSourceModelSha256 ||
        revision != gectorModelRevision) {
      throw ArgumentError('Invalid or unsupported GECToR artifact identity.');
    }
  }
  final String file;
  final String sha256;
  final int bytes;
  final String sourceModelSha256;
  final String revision;
}

/// Identity of the bytes actually loaded by a backend, not a copied filename.
final class GectorBackendIdentity {
  const GectorBackendIdentity({
    required this.artifactSha256,
    required this.sourceModelSha256,
    this.revision = gectorModelRevision,
    this.vocabularySize = 31102,
    this.labelCount = 5000,
    this.detectionCount = 2,
    this.maximumTokens = 512,
  });
  final String artifactSha256;
  final String sourceModelSha256;
  final String revision;
  final int vocabularySize;
  final int labelCount;
  final int detectionCount;
  final int maximumTokens;

  void validate(GectorModelArtifact artifact) {
    if (artifactSha256 != artifact.sha256 ||
        sourceModelSha256 != artifact.sourceModelSha256 ||
        revision != artifact.revision ||
        vocabularySize != 31102 ||
        labelCount != 5000 ||
        detectionCount != 2 ||
        maximumTokens != 512) {
      throw const GectorUnavailableException(
        'The loaded backend does not match the verified model artifact/profile.',
      );
    }
  }
}

/// Batch one, unpadded input. CLS represents START; SEP has no word prediction.
final class GectorPreparedInput {
  GectorPreparedInput({
    required Iterable<int> inputIds,
    required Iterable<int> firstSubwordIndices,
  }) : inputIds = Int64List.fromList(inputIds.toList(growable: false)),
       firstSubwordIndices = List<int>.unmodifiable(firstSubwordIndices) {
    if (this.inputIds.length < 2 ||
        this.inputIds.length > 512 ||
        this.inputIds.any((id) => id < 0 || id >= 31102) ||
        this.firstSubwordIndices.isEmpty ||
        this.firstSubwordIndices.first != 0) {
      throw const FormatException('Invalid GECToR prepared input.');
    }
    var previous = -1;
    for (final index in this.firstSubwordIndices) {
      if (index <= previous || index >= this.inputIds.length - 1) {
        throw const FormatException('Invalid first-subword alignment.');
      }
      previous = index;
    }
    attentionMask = Int64List(this.inputIds.length)
      ..fillRange(0, this.inputIds.length, 1);
  }
  final Int64List inputIds;
  late final Int64List attentionMask;
  final List<int> firstSubwordIndices;
  int get tokenCount => inputIds.length;
}

/// Row-major raw logits [1, tokens, labels] and [1, tokens, 2].
/// Backends must return owned arrays whose values remain valid after forward.
final class GectorLogits {
  GectorLogits({
    required this.tokenCount,
    required this.labels,
    required this.detection,
    this.labelCount = 5000,
    this.detectionCount = 2,
  });
  final int tokenCount;
  final int labelCount;
  final int detectionCount;
  final Float32List labels;
  final Float32List detection;

  void validate(GectorPreparedInput input, int expectedLabels) {
    if (tokenCount != input.tokenCount ||
        labelCount != expectedLabels ||
        detectionCount != 2 ||
        labels.length != tokenCount * labelCount ||
        detection.length != tokenCount * detectionCount ||
        labels.any((v) => !v.isFinite) ||
        detection.any((v) => !v.isFinite)) {
      throw const FormatException(
        'GECToR returned missing, malformed or non-finite logits.',
      );
    }
  }
}

/// A factory is sent to the persistent isolate. Store only sendable paths,
/// immutable options or bytes in it. Create native pointers inside [open].
abstract interface class GectorBackendFactory {
  Future<GectorBackend> open(GectorModelArtifact artifact);
}

abstract interface class GectorBackend {
  GectorBackendIdentity get identity;
  Future<GectorLogits> forward(GectorPreparedInput input);
  Future<void> dispose();
}

final class GectorUnavailableException implements Exception {
  const GectorUnavailableException(this.message);
  final String message;
  @override
  String toString() => message;
}

final class GectorCancelledException implements Exception {
  const GectorCancelledException();
  @override
  String toString() => 'GECToR request was superseded or cancelled.';
}

final class GectorCapacityException implements Exception {
  const GectorCapacityException(this.message);
  final String message;
  @override
  String toString() => message;
}

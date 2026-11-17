import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:quds_proofing_gector/quds_proofing_gector.dart';

/// Replays original ONNX Runtime logits through the actual Dart decoder.
/// It measures decoder agreement, never backend inference speed or quality.
Future<void> main(List<String> arguments) async {
  if (arguments.length == 1 && arguments.single == '--help') {
    stdout.writeln(_usage);
    return;
  }
  try {
    final options = <String, String>{};
    for (var i = 0; i < arguments.length; i += 2) {
      if (i + 1 == arguments.length ||
          !const <String>{
            '--assets',
            '--reference',
            '--output',
          }.contains(arguments[i]) ||
          options.containsKey(arguments[i])) {
        throw const FormatException(_usage);
      }
      options[arguments[i]] = arguments[i + 1];
    }
    if (options.length != 3) throw const FormatException(_usage);
    final referenceFile = File(options['--reference']!);
    final referenceBytes = await referenceFile.readAsBytes();
    final reference = _object(jsonDecode(utf8.decode(referenceBytes)));
    if (reference['schema_version'] != 1 ||
        reference['kind'] != 'quds-gector-reference' ||
        reference['revision'] != gectorModelRevision) {
      throw const FormatException('Unsupported reference identity or schema.');
    }
    final model = _object(reference['inference_model']);
    if (model['file'] != 'model.onnx' ||
        model['variant'] != 'float32' ||
        model['sha256'] != gectorSourceModelSha256 ||
        model['source_model_sha256'] != gectorSourceModelSha256) {
      throw const FormatException('The reference is not the frozen F32 model.');
    }
    final artifact = GectorModelArtifact(
      file: 'model.onnx',
      sha256: gectorSourceModelSha256,
      bytes: _integer(model['size_bytes']),
    );
    final bundle = await GectorVerifiedBundle.load(
      read: (name) => File('${options['--assets']}/$name').openRead(),
      artifact: artifact,
    );
    final referencePins = _object(reference['input_sha256']);
    for (final entry in bundle.assetDigests.entries) {
      if (referencePins[entry.key] != entry.value) {
        throw FormatException('Reference asset pin differs: ${entry.key}');
      }
    }
    final policy = _object(reference['decoder']);
    if (policy['keep_label_id'] != bundle.configuration.keepIndex ||
        policy['incorrect_label_id'] != bundle.configuration.incorrectIndex) {
      throw const FormatException(
        'Reference classifier label identity differs.',
      );
    }
    final decodeOptions = GectorDecodeOptions(
      keepConfidence: _number(policy['keep_confidence']),
      minimumErrorProbability: _number(policy['min_error_prob']),
    );
    final cases = _list(reference['cases']);
    if (cases.isEmpty) throw const FormatException('Reference has no cases.');
    final results = <Map<String, Object?>>[];
    var expectedPasses = 0;
    var comparedPasses = 0;
    var maximumLabelProbabilityDrift = 0.0;
    var maximumDetectionProbabilityDrift = 0.0;
    for (final rawCase in cases) {
      final sample = _object(rawCase);
      final id = _string(sample['id']);
      final expected = _list(sample['passes']).map(_object).toList();
      expectedPasses += expected.length;
      final backend = _ReplayBackend(referenceFile.parent, artifact, expected);
      final decoder = GectorDecoder.reference(
        configuration: bundle.configuration,
        tokenizer: bundle.tokenizer,
        backend: backend,
        options: decodeOptions,
      );
      final errors = <String>[];
      void compare(String field, Object? actual, Object? wanted) {
        if (!_same(actual, wanted)) {
          errors.add(
            '$field differs: ${jsonEncode(actual)} != ${jsonEncode(wanted)}',
          );
        }
      }

      GectorDecodedText? actual;
      try {
        actual = await decoder.correct(_string(sample['input']));
        compare('complete', actual.complete, true);
        compare('corrected', actual.corrected, sample['corrected']);
        compare('pass count', actual.passes.length, expected.length);
        compare('UTF-16 edits', <Object>[
          for (final edit in actual.edits)
            <String, Object>{
              'start': edit.start,
              'end': edit.end,
              'original': edit.original,
              'replacement': edit.replacement,
            },
        ], sample['suggestions_utf16']);
        final source = GectorSourceText(actual.original, bundle.configuration);
        for (
          var i = 0;
          i < math.min(actual.passes.length, expected.length);
          i++
        ) {
          final pass = actual.passes[i];
          final saved = expected[i];
          final selected = _object(saved['selected']);
          compare('pass ${i + 1} words', pass.words, saved['words']);
          compare('pass ${i + 1} tags', <String>[
            for (final tag in pass.tags) tag.label,
          ], selected['labels']);
          final referenceDecoding = _object(saved['reference_decoding']);
          compare(
            'pass ${i + 1} edited words',
            pass.editedWords,
            source.words(_string(referenceDecoding['result'])),
          );
          final labelProbabilities = _list(selected['label_probabilities']);
          final detectionProbabilities = _list(
            selected['incorrect_probabilities'],
          );
          if (labelProbabilities.length != pass.tags.length ||
              detectionProbabilities.length != pass.tags.length) {
            throw const FormatException(
              'Reference probability alignment differs.',
            );
          }
          for (var j = 0; j < pass.tags.length; j++) {
            maximumLabelProbabilityDrift = math.max(
              maximumLabelProbabilityDrift,
              (pass.tags[j].probability - _number(labelProbabilities[j])).abs(),
            );
            maximumDetectionProbabilityDrift = math.max(
              maximumDetectionProbabilityDrift,
              (pass.tags[j].incorrectProbability -
                      _number(detectionProbabilities[j]))
                  .abs(),
            );
          }
          comparedPasses++;
        }
      } on Object catch (error) {
        errors.add(error.toString());
      } finally {
        await backend.dispose();
      }
      results.add(<String, Object?>{
        'id': id,
        'pass': errors.isEmpty,
        'expected_passes': expected.length,
        'actual_passes': actual?.passes.length,
        'corrected': actual?.corrected,
        'errors': errors,
      });
    }
    final passed = results.where((result) => result['pass'] == true).length;
    final receipt = <String, Object?>{
      'schema_version': 1,
      'kind': 'quds-gector-dart-reference-replay',
      'pass': passed == cases.length,
      'model_revision': gectorModelRevision,
      'model_sha256': gectorSourceModelSha256,
      'reference_sha256': sha256.convert(referenceBytes).toString(),
      'reference_cases_sha256': reference['cases_sha256'],
      'reference_runtime': reference['runtime'],
      'dart_version': Platform.version,
      'verified_asset_sha256': bundle.assetDigests,
      'cases': cases.length,
      'cases_passed': passed,
      'expected_passes': expectedPasses,
      'compared_passes': comparedPasses,
      'maximum_label_probability_drift': maximumLabelProbabilityDrift,
      'maximum_detection_probability_drift': maximumDetectionProbabilityDrift,
      'limits': <String>[
        'Replays authenticated F32 output tensors; does not execute native inference.',
        'Reference mode omits application guards, as does the frozen original runner.',
        'Dart softmax uses double intermediates; the original uses NumPy float32.',
        'Cases measure bounded trace agreement, not broad German correction quality.',
        'No replay timing is reported as model inference latency.',
      ],
      'results': results,
    };
    final output = File(options['--output']!);
    await output.parent.create(recursive: true);
    await output.writeAsString(
      '${const JsonEncoder.withIndent('  ').convert(receipt)}\n',
    );
    stdout.writeln(
      '$passed/${cases.length} cases and $comparedPasses/$expectedPasses passes compared; '
      'receipt: ${output.path}',
    );
    if (passed != cases.length) exitCode = 1;
  } on Object catch (error) {
    stderr.writeln('GECToR reference replay failed: $error');
    exitCode = 1;
  }
}

const _usage =
    'dart run tool/replay_reference.dart --assets SOURCE_BUNDLE '
    '--reference reference.json --output receipt.json';

final class _ReplayBackend implements GectorBackend {
  _ReplayBackend(this.directory, this.artifact, this.passes);
  final Directory directory;
  final GectorModelArtifact artifact;
  final List<Map<String, Object?>> passes;
  var _next = 0;
  @override
  GectorBackendIdentity get identity => GectorBackendIdentity(
    artifactSha256: artifact.sha256,
    sourceModelSha256: gectorSourceModelSha256,
  );

  @override
  Future<GectorLogits> forward(GectorPreparedInput input) async {
    if (_next == passes.length) {
      throw const FormatException('Dart requested an additional unsaved pass.');
    }
    final pass = passes[_next++];
    if (!_same(input.inputIds.toList(), _list(pass['input_ids']).single) ||
        !_same(
          input.attentionMask.toList(),
          _list(pass['attention_mask']).single,
        ) ||
        !_same(input.firstSubwordIndices, pass['first_subword_indices'])) {
      throw FormatException('Prepared input differs on pass $_next.');
    }
    final outputs = _object(pass['outputs']);
    final tensors = await Future.wait<Float32List>(<Future<Float32List>>[
      _tensor(_object(outputs['logits_labels']), input.tokenCount, 5000),
      _tensor(_object(outputs['logits_d']), input.tokenCount, 2),
    ]);
    return GectorLogits(
      tokenCount: input.tokenCount,
      labels: tensors[0],
      detection: tensors[1],
    );
  }

  Future<Float32List> _tensor(
    Map<String, Object?> spec,
    int tokens,
    int width,
  ) async {
    final name = _string(spec['file']);
    if (!RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]*$').hasMatch(name) ||
        spec['dtype'] != 'float32' ||
        spec['byte_order'] != 'little' ||
        spec['layout'] != 'row-major' ||
        !_same(spec['shape'], <int>[1, tokens, width]) ||
        spec['size_bytes'] != tokens * width * 4) {
      throw const FormatException('Invalid reference tensor schema.');
    }
    final bytes = await File('${directory.path}/$name').readAsBytes();
    if (bytes.length != spec['size_bytes'] ||
        sha256.convert(bytes).toString() != spec['sha256']) {
      throw FormatException(
        'Reference tensor failed size/hash verification: $name',
      );
    }
    final view = ByteData.sublistView(bytes);
    return Float32List.fromList(<double>[
      for (var offset = 0; offset < bytes.length; offset += 4)
        view.getFloat32(offset, Endian.little),
    ]);
  }

  @override
  Future<void> dispose() async {}
}

Map<String, Object?> _object(Object? value) {
  if (value is! Map<String, Object?>) {
    throw const FormatException('Expected an object.');
  }
  return value;
}

List<Object?> _list(Object? value) {
  if (value is! List<Object?>) throw const FormatException('Expected a list.');
  return value;
}

String _string(Object? value) {
  if (value is! String) throw const FormatException('Expected a string.');
  return value;
}

int _integer(Object? value) {
  if (value is! int) throw const FormatException('Expected an integer.');
  return value;
}

double _number(Object? value) {
  if (value is! num || !value.isFinite) {
    throw const FormatException('Expected a finite number.');
  }
  return value.toDouble();
}

bool _same(Object? left, Object? right) {
  if (left is List<Object?> && right is List<Object?>) {
    return left.length == right.length &&
        List<bool>.generate(
          left.length,
          (i) => _same(left[i], right[i]),
        ).every((value) => value);
  }
  if (left is Map<String, Object?> && right is Map<String, Object?>) {
    return left.length == right.length &&
        left.keys.every(
          (key) => right.containsKey(key) && _same(left[key], right[key]),
        );
  }
  return left == right;
}

import 'dart:convert';
import 'dart:js_interop';
import 'package:quds_proofing_harper/quds_proofing_harper.dart';
import 'harper_dialect_common.dart';

@JS('qudsHarperWorkerUrl') external JSString get workerUrl;
@JS('qudsHarperSmokeDone') external void complete(JSString result);

Future<void> main() async {
  final provider = HarperProofingProvider(workerUrl: Uri.parse(workerUrl.toDart));
  complete(jsonEncode(await probeDialects(provider)).toJS);
}

import 'dart:convert';
import 'dart:io';
import 'package:quds_proofing_harper/quds_proofing_harper.dart';
import 'harper_dialect_common.dart';

Future<void> main() async {
  final provider = HarperProofingProvider(nativeLibraryPath: Platform.environment['QUDS_HARPER_TEST_LIBRARY']);
  final result = await probeDialects(provider);
  print(const JsonEncoder.withIndent('  ').convert(result));
  if(result['status']!='passed') exitCode=1;
}

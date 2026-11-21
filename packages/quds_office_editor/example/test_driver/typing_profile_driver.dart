// Host side of integration_test/typing_profile_test.dart: writes the
// report and the recorded timeline to build/typing_profile.json.
import 'dart:convert';
import 'dart:io';

import 'package:integration_test/integration_test_driver.dart';

Future<void> main() => integrationDriver(
  responseDataCallback: (Map<String, dynamic>? data) async {
    if (data == null) return;
    Directory('build').createSync(recursive: true);
    File('build/typing_profile.json').writeAsStringSync(jsonEncode(data));
  },
);

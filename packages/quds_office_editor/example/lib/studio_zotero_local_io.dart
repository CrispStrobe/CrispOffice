import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

bool get studioZoteroLocalSupported =>
    Platform.isLinux || Platform.isMacOS || Platform.isWindows;

http.Client createStudioZoteroLocalClient() =>
    IOClient(HttpClient()..findProxy = (_) => 'DIRECT');

/// Native HTTP client for the CalDAV provider.
library;

import 'dart:io';

import 'package:http/io_client.dart';

export 'quds_tasks_caldav.dart';

/// Use one client per connected account. Closing it aborts in-flight requests.
IOClient createNativeCalDavClient() => IOClient(
  HttpClient()
    ..connectionTimeout = const Duration(seconds: 15)
    ..idleTimeout = const Duration(seconds: 10)
    ..maxConnectionsPerHost = 4,
);

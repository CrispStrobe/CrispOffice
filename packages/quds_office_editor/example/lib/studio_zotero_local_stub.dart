import 'package:http/http.dart' as http;

bool get studioZoteroLocalSupported => false;

http.Client createStudioZoteroLocalClient() =>
    throw UnsupportedError('Desktop Zotero requires a native desktop app.');

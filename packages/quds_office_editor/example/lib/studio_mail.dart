// Studio Mail keeps native account transports outside the browser import graph.
export 'studio_mail_web.dart' if (dart.library.io) 'studio_mail_native.dart';

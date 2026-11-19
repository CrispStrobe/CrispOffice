/// Native archives are durable and separate from the session-only mail reader.
library;

export 'studio_mail_archive_stub.dart'
    if (dart.library.io) 'studio_mail_archive_native.dart';

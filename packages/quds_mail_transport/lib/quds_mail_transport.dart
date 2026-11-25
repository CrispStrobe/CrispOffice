/// Native IMAP, EWS, Gmail and Graph; browser entries return typed unsupported.
library;

export 'src/configuration.dart';
export 'src/cloud/configuration.dart'
    hide validCloudMailAddress, emitMailCloudLog;
export 'src/cloud/task_reader.dart'
    show
        GoogleTaskReader,
        GoogleTaskProvider,
        googleTaskIsAssigned,
        googleTaskMatchesUpdate;
export 'src/cloud/unsupported.dart'
    if (dart.library.io) 'src/cloud/native/factory.dart';
export 'src/ews/configuration.dart' hide validEwsAddress;
export 'src/ews/tasks.dart';
export 'src/ews/unsupported.dart'
    if (dart.library.io) 'src/ews/native/factory.dart';
export 'src/unsupported/provider.dart'
    if (dart.library.io) 'src/native/factory.dart';

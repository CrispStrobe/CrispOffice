/// Optional analysis and proofing through a managed local AOT native worker.
///
/// The default requires no daemon or listening port. An explicit HTTP transport
/// remains available for existing services. Native engine and language resource
/// installation is separate from the pure Dart package.
library;

export 'src/client.dart';
export 'src/german_rules.dart';
export 'src/models.dart';
export 'src/provider.dart';
export 'src/transport.dart';
export 'src/transport_process.dart';

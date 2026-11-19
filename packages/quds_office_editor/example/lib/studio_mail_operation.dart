import 'dart:async';

/// Contains unconditional protocol-library prints within one Mail operation.
///
/// `isLogEnabled: false` disables normal protocol logging but some legacy parser
/// diagnostics still print raw server fields. Creating the client and its event
/// listeners inside this zone also contains their later asynchronous prints.
/// Failures propagate unchanged for the host's fixed, content-free UI handling;
/// output from callers and unrelated operations is unaffected.
T runStudioMailOperation<T>(T Function() operation) => runZoned(
  operation,
  zoneSpecification: ZoneSpecification(
    print: (self, parent, zone, line) {
      // Server replies, message data and credentials must not reach logs.
    },
  ),
);

// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

/// A content-free, deterministic protocol input budget failure.
class ProtocolResourceLimit implements Exception {
  /// Creates a failure with a fixed, content-free explanation.
  const ProtocolResourceLimit(this.message);

  /// Fixed explanation; never includes server payloads.
  final String message;
  @override
  String toString() => message;
}

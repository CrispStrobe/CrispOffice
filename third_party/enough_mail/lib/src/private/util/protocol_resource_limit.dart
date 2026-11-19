// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

/// A content-free, deterministic protocol input budget failure.
class ProtocolResourceLimit extends FormatException {
  /// Creates a failure with a fixed, content-free explanation.
  const ProtocolResourceLimit(super.message);

  @override
  String toString() => message;
}

/// A host-owned account identity within one provider, never an access token.
final class TaskAccountId {
  TaskAccountId(this.value, {required this.provider}) {
    validateTaskIdentity(value);
    validateTaskIdentity(provider);
  }

  final String value;
  final String provider;

  @override
  bool operator ==(Object other) =>
      other is TaskAccountId &&
      other.value == value &&
      other.provider == provider;

  @override
  int get hashCode => Object.hash(value, provider);

  @override
  String toString() => 'TaskAccountId(redacted)';
}

final class TaskListId {
  TaskListId(this.value, {required this.account}) {
    validateTaskIdentity(value);
  }

  final String value;
  final TaskAccountId account;

  @override
  bool operator ==(Object other) =>
      other is TaskListId && other.value == value && other.account == account;

  @override
  int get hashCode => Object.hash(value, account);

  @override
  String toString() => 'TaskListId(redacted)';
}

/// The remote identity includes its account and list; titles are never IDs.
final class TaskId {
  TaskId(this.value, {required this.list}) {
    validateTaskIdentity(value);
  }

  final String value;
  final TaskListId list;
  TaskAccountId get account => list.account;

  @override
  bool operator ==(Object other) =>
      other is TaskId && other.value == value && other.list == list;

  @override
  int get hashCode => Object.hash(value, list);

  @override
  String toString() => 'TaskId(redacted)';
}

void validateTaskIdentity(String value) {
  if (value.isEmpty ||
      value.length > 16384 ||
      value.contains(RegExp(r'[\x00-\x1f\x7f]'))) {
    throw ArgumentError('Task identities must be bounded, nonempty strings.');
  }
}

import 'package:drift/drift.dart';

/// The lease outlives pending database operations and is released even on close
/// failure. Repeated close calls share the same completion.
final class OwnerLockedMailExecutor extends LazyDatabase {
  OwnerLockedMailExecutor(QueryExecutor executor, this._release)
    : super(() => executor, openImmediately: true);

  final Future<void> Function() _release;
  Future<void>? _closing;

  @override
  Future<void> close() => _closing ??= _closeAndRelease();

  Future<void> _closeAndRelease() async {
    try {
      await super.close();
    } finally {
      await _release();
    }
  }
}

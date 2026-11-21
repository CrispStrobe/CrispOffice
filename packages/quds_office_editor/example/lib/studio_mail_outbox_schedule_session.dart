import 'package:quds_mail_core/quds_mail_core.dart';

/// Explicit, foreground-only permission to attempt saved schedules once.
///
/// The durable deadline belongs to the entry. This session is deliberately not
/// persisted: reopening, refreshing or reconnecting never grants permission to
/// send. A host clears it when hidden, suspended, closed or switched to another
/// account. A due entry is removed before dispatch, including failed dispatch.
final class StudioMailOutboxScheduleSession {
  StudioMailOutboxScheduleSession({required this.clock, required this.elapsed});

  final DateTime Function() clock;
  final Duration Function() elapsed;
  final Map<String, _ArmedSchedule> _armed = {};

  bool get isEmpty => _armed.isEmpty;

  bool isArmed(MailOutboxEntry entry) =>
      _armed[entry.id]?.matches(entry) ?? false;

  void arm(MailOutboxEntry entry, {Duration minimumWait = Duration.zero}) {
    if (!entry.canSchedule ||
        entry.sendNotBefore == null ||
        minimumWait.isNegative) {
      throw StateError('Only a saved, never-attempted schedule can be armed.');
    }
    _armed[entry.id] = _ArmedSchedule(entry, elapsed() + minimumWait);
  }

  void pause(MailOutboxEntry entry) {
    if (isArmed(entry)) _armed.remove(entry.id);
  }

  void pauseAll() => _armed.clear();

  /// A new schedule revision invalidates old permission even when the same
  /// deadline is restored. A refresh cannot arm entries it did not already own.
  void reconcile(List<MailOutboxEntry> entries) {
    final current = {for (final entry in entries) entry.id: entry};
    _armed.removeWhere((id, armed) {
      final entry = current[id];
      return entry == null || !armed.matches(entry);
    });
  }

  /// Both clocks must permit sending: the wall clock observes a fixed UTC
  /// deadline, while elapsed time preserves the live undo window if the system
  /// clock jumps forward. A backward jump defers rather than advances sending.
  Duration remaining(MailOutboxEntry entry) {
    final armed = _armed[entry.id];
    if (armed == null || !armed.matches(entry)) return Duration.zero;
    final wall = entry.sendNotBefore!.difference(clock());
    final monotonic = armed.eligibleElapsed - elapsed();
    final remaining = wall > monotonic ? wall : monotonic;
    return remaining.isNegative ? Duration.zero : remaining;
  }

  MailOutboxEntry? takeDue(List<MailOutboxEntry> entries) {
    reconcile(entries);
    final due =
        entries.where((entry) {
          return isArmed(entry) &&
              entry.isDueAt(clock()) &&
              remaining(entry) == Duration.zero;
        }).toList()..sort((a, b) {
          final time = a.sendNotBefore!.compareTo(b.sendNotBefore!);
          return time == 0 ? a.id.compareTo(b.id) : time;
        });
    if (due.isEmpty) return null;
    final entry = due.first;
    _armed.remove(entry.id);
    return entry;
  }
}

final class _ArmedSchedule {
  const _ArmedSchedule(this.entry, this.eligibleElapsed);

  final MailOutboxEntry entry;
  final Duration eligibleElapsed;

  bool matches(MailOutboxEntry other) =>
      other.canSchedule &&
      other.id == entry.id &&
      other.prepared.account == entry.prepared.account &&
      other.scheduleRevision == entry.scheduleRevision &&
      other.sendNotBefore == entry.sendNotBefore &&
      other.prepared.wireHash == entry.prepared.wireHash;
}

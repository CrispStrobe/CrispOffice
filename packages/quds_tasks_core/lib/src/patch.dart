import 'model.dart';

enum TaskPatchKind { unchanged, set, clear }

/// Explicitly distinguishes a field omitted from a request from one cleared by
/// the user. Null is never used to mean both operations.
final class TaskFieldPatch<T extends Object> {
  const TaskFieldPatch.unchanged()
    : kind = TaskPatchKind.unchanged,
      value = null;
  const TaskFieldPatch.set(T this.value) : kind = TaskPatchKind.set;
  const TaskFieldPatch.clear() : kind = TaskPatchKind.clear, value = null;

  final TaskPatchKind kind;
  final T? value;
  bool get isChanged => kind != TaskPatchKind.unchanged;
  bool get isClear => kind == TaskPatchKind.clear;
  T? apply(T? current) => switch (kind) {
    TaskPatchKind.unchanged => current,
    TaskPatchKind.set => value,
    TaskPatchKind.clear => null,
  };
}

enum TaskField {
  title,
  notes,
  status,
  priority,
  start,
  due,
  reminder,
  completedAt,
}

final class TaskPatch {
  const TaskPatch({
    this.title = const TaskFieldPatch<String>.unchanged(),
    this.notes = const TaskFieldPatch<TaskText>.unchanged(),
    this.status = const TaskFieldPatch<TaskStatus>.unchanged(),
    this.priority = const TaskFieldPatch<TaskPriority>.unchanged(),
    this.start = const TaskFieldPatch<TaskDateValue>.unchanged(),
    this.due = const TaskFieldPatch<TaskDateValue>.unchanged(),
    this.reminder = const TaskFieldPatch<TaskDateValue>.unchanged(),
    this.completedAt = const TaskFieldPatch<TaskDateValue>.unchanged(),
  });

  factory TaskPatch.between(TaskFields before, TaskFields after) => TaskPatch(
    title: _difference(before.title, after.title),
    notes: _difference(before.notes, after.notes),
    status: _difference(before.status, after.status),
    priority: _difference(before.priority, after.priority),
    start: _difference(before.start, after.start),
    due: _difference(before.due, after.due),
    reminder: _difference(before.reminder, after.reminder),
    completedAt: _difference(before.completedAt, after.completedAt),
  );

  final TaskFieldPatch<String> title;
  final TaskFieldPatch<TaskText> notes;
  final TaskFieldPatch<TaskStatus> status;
  final TaskFieldPatch<TaskPriority> priority;
  final TaskFieldPatch<TaskDateValue> start;
  final TaskFieldPatch<TaskDateValue> due;
  final TaskFieldPatch<TaskDateValue> reminder;
  final TaskFieldPatch<TaskDateValue> completedAt;

  bool get isEmpty =>
      !title.isChanged &&
      !notes.isChanged &&
      !status.isChanged &&
      !priority.isChanged &&
      !start.isChanged &&
      !due.isChanged &&
      !reminder.isChanged &&
      !completedAt.isChanged;

  Set<TaskField> get changedFields => Set.unmodifiable(<TaskField>[
    if (title.isChanged) TaskField.title,
    if (notes.isChanged) TaskField.notes,
    if (status.isChanged) TaskField.status,
    if (priority.isChanged) TaskField.priority,
    if (start.isChanged) TaskField.start,
    if (due.isChanged) TaskField.due,
    if (reminder.isChanged) TaskField.reminder,
    if (completedAt.isChanged) TaskField.completedAt,
  ]);

  TaskFields applyTo(TaskFields fields) {
    if (title.isClear || status.isClear || priority.isClear) {
      throw ArgumentError('Title, status and priority cannot be cleared.');
    }
    return TaskFields(
      title: title.apply(fields.title)!,
      notes: notes.apply(fields.notes),
      status: status.apply(fields.status)!,
      priority: priority.apply(fields.priority)!,
      start: start.apply(fields.start),
      due: due.apply(fields.due),
      reminder: reminder.apply(fields.reminder),
      completedAt: completedAt.apply(fields.completedAt),
    );
  }
}

TaskFieldPatch<T> _difference<T extends Object>(T? before, T? after) {
  if (before == after) return TaskFieldPatch<T>.unchanged();
  return after == null
      ? TaskFieldPatch<T>.clear()
      : TaskFieldPatch<T>.set(after);
}

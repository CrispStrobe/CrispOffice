import 'package:flutter/material.dart';
import 'package:quds_tasks_core/quds_tasks_core.dart';

String studioTaskDueDate(TaskDateValue date) => switch (date) {
  TaskDate(:final year, :final month, :final day) =>
    '${year.toString().padLeft(4, '0')}-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}',
  TaskDateTime(:final localDateTime) => localDateTime.substring(0, 10),
};

class StudioTaskFieldsDialog extends StatefulWidget {
  const StudioTaskFieldsDialog({super.key, this.fields, this.draft});
  final TaskFields? fields;
  final TaskFields? draft;
  @override
  State<StudioTaskFieldsDialog> createState() => _StudioTaskFieldsDialogState();
}

class _StudioTaskFieldsDialogState extends State<StudioTaskFieldsDialog> {
  TaskFields? get _initial => widget.fields ?? widget.draft;

  late final _title = TextEditingController(text: _initial?.title);
  late final _notes = TextEditingController(text: _initial?.notes?.value);
  TaskDateValue? _due;
  bool _dueChanged = false;

  @override
  void dispose() {
    _title.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final due = _dueChanged ? _due : _initial?.due;
    return AlertDialog(
      scrollable: true,
      title: Text(widget.fields == null ? 'New task' : 'Edit task'),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.draft != null)
              const Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text('On this device'),
              ),
            TextField(
              controller: _title,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Title'),
            ),
            TextField(
              controller: _notes,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Notes'),
            ),
            Row(
              children: [
                TextButton(
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: context,
                      firstDate: DateTime(1900),
                      lastDate: DateTime(2200, 12, 31),
                      initialDate:
                          due is TaskDate &&
                              due.year >= 1900 &&
                              due.year <= 2200
                          ? DateTime(due.year, due.month, due.day)
                          : DateTime.now(),
                    );
                    if (mounted && picked != null) {
                      setState(() {
                        _dueChanged = true;
                        _due = TaskDate(picked.year, picked.month, picked.day);
                      });
                    }
                  },
                  child: Text(
                    due == null ? 'Set due date' : studioTaskDueDate(due),
                  ),
                ),
                if (due != null)
                  IconButton(
                    tooltip: 'Clear due date',
                    onPressed: () => setState(() {
                      _dueChanged = true;
                      _due = null;
                    }),
                    icon: const Icon(Icons.clear),
                  ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            final title = _title.text.trim();
            if (title.isEmpty) return;
            final fields = _initial ?? const TaskFields(title: '');
            final notes = _notes.text;
            final patch = TaskPatch(
              title: TaskFieldPatch.set(title),
              notes: notes == (fields.notes?.value ?? '')
                  ? const TaskFieldPatch.unchanged()
                  : notes.isEmpty
                  ? const TaskFieldPatch.clear()
                  : TaskFieldPatch.set(TaskText(notes)),
              due: !_dueChanged
                  ? const TaskFieldPatch.unchanged()
                  : due == null
                  ? const TaskFieldPatch.clear()
                  : TaskFieldPatch.set(due),
            );
            Navigator.pop(context, patch.applyTo(fields));
          },
          child: const Text('Save task'),
        ),
      ],
    );
  }
}

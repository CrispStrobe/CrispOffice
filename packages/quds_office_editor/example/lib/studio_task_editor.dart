import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:quds_tasks_core/quds_tasks_core.dart';

import 'studio_strings.dart';

String studioTaskDueDate(TaskDateValue date) => switch (date) {
  TaskDate(:final year, :final month, :final day) =>
    '${year.toString().padLeft(4, '0')}-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}',
  TaskDateTime(:final localDateTime) => localDateTime.substring(0, 10),
};

class StudioTaskFieldsDialog extends StatefulWidget {
  const StudioTaskFieldsDialog({
    super.key,
    this.fields,
    this.draft,
    this.language = StudioLanguage.en,
  });
  final TaskFields? fields;
  final TaskFields? draft;
  final StudioLanguage language;
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

  void _submit() {
    final due = _dueChanged ? _due : _initial?.due;
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
  }

  @override
  Widget build(BuildContext context) {
    final due = _dueChanged ? _due : _initial?.due;
    final label = StudioStrings(widget.language).productivity;
    return AlertDialog(
      scrollable: true,
      title: Text(label(widget.fields == null ? 'New task' : 'Edit task')),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.draft != null)
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text(label('On this device')),
              ),
            CallbackShortcuts(
              bindings: {
                const SingleActivator(LogicalKeyboardKey.enter): _submit,
                const SingleActivator(LogicalKeyboardKey.numpadEnter): _submit,
              },
              child: TextField(
                controller: _title,
                autofocus: true,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _submit(),
                decoration: InputDecoration(labelText: label('Title')),
              ),
            ),
            TextField(
              controller: _notes,
              maxLines: 3,
              decoration: InputDecoration(labelText: label('Notes')),
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
                    due == null
                        ? label('Set due date')
                        : studioTaskDueDate(due),
                  ),
                ),
                if (due != null)
                  IconButton(
                    tooltip: label('Clear due date'),
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
          child: Text(label('Cancel')),
        ),
        FilledButton(onPressed: _submit, child: Text(label('Save task'))),
      ],
    );
  }
}

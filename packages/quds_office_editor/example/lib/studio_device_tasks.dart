import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:quds_tasks_core/quds_tasks_core.dart';
import 'package:quds_tasks_store/quds_tasks_store.dart';
import 'package:sqlite3/sqlite3.dart' show Database, sqlite3;

import 'studio_mail_strings.dart';
import 'studio_strings.dart';
import 'studio_task_editor.dart';

final studioDeviceTaskList = TaskList(
  id: TaskListId(
    'personal',
    account: TaskAccountId('personal', provider: 'local'),
  ),
  name: 'On this device',
);

final studioDeviceTaskChanges = ValueNotifier(0);

Future<Database> openStudioTasksDatabase() async {
  final directory = await getApplicationSupportDirectory();
  await directory.create(recursive: true);
  return sqlite3.open(path.join(directory.path, 'tasks.sqlite3'));
}

TaskResult<LocalTaskEdit> saveStudioDeviceTask(
  Database database,
  TaskFields fields,
) {
  final store = TaskPullStore(database);
  switch (store.connect(studioDeviceTaskList.id.account)) {
    case TaskSuccess(:final value):
      return store.saveEdit(value, studioDeviceTaskList.id, fields: fields);
    case TaskFailure(:final problem):
      return TaskFailure(problem);
  }
}

Future<void> createStudioFollowUpTask(
  BuildContext context, {
  required String title,
  String? notes,
  TaskDateValue? due,
  Future<Database> Function() openDatabase = openStudioTasksDatabase,
}) async {
  final draft = TaskFields(
    title: title.trim(),
    notes: notes == null || notes.isEmpty ? null : TaskText(notes),
    due: due,
  );
  final fields = await showDialog<TaskFields>(
    context: context,
    builder: (_) => StudioTaskFieldsDialog(draft: draft),
  );
  if (fields == null || !context.mounted) return;

  var saved = false;
  try {
    final database = await openDatabase();
    try {
      saved = saveStudioDeviceTask(database, fields) is TaskSuccess;
    } finally {
      database.close();
    }
  } on Exception {
    // A failed write is reported to the user without exposing storage details.
  }

  if (saved) studioDeviceTaskChanges.value++;
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          saved ? 'Task saved on this device.' : 'Could not save the task.',
        ),
      ),
    );
  }
}

final class StudioMailFollowUpButton extends StatelessWidget {
  const StudioMailFollowUpButton({
    super.key,
    required this.strings,
    required this.subject,
    required this.senders,
  });

  final StudioStrings strings;
  final String? subject;
  final Iterable<String> senders;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: strings.mailFollowUpTask,
    icon: const Icon(Icons.add_task_outlined),
    onPressed: subject == null
        ? null
        : () => createStudioFollowUpTask(
            context,
            title: subject!.trim().isEmpty
                ? strings.mailUntitledFollowUp
                : subject!,
            notes: senders.isEmpty
                ? null
                : strings.mailAccountSender(senders.join(', ')),
          ),
  );
}

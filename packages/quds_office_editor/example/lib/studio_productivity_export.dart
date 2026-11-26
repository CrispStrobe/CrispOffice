import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_office_engine/quds_productivity_automation.dart';

import 'studio_mail_outbox_export_native.dart';

export 'package:quds_office_engine/quds_productivity_automation.dart'
    show ProductivityKind;

const studioProductivityExportLabel = 'Export automation snapshot';

Future<void> exportStudioProductivityView(
  BuildContext context, {
  required ProductivityKind kind,
  required String scope,
  required Iterable<Map<String, Object>> rows,
  required bool Function() isCurrent,
}) async {
  if (!isCurrent()) return;
  final snapshot = ProductivitySnapshot.capture(
    kind: kind,
    capturedAt: DateTime.now(),
    rows: rows,
  );
  final allowed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text(studioProductivityExportLabel),
      content: Text(
        'Save up to ${ProductivitySnapshot.maxRows} entries from $scope. '
        'The JSON file contains subjects or titles and selected display fields. '
        'A client that opens the file can read and share those fields.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Choose file'),
        ),
      ],
    ),
  );
  if (allowed != true || !context.mounted || !isCurrent()) return;
  final result = await exportStudioMailOutboxFile(
    'crispoffice-${kind.name}-snapshot.json',
    MailBytes(Uint8List.fromList(utf8.encode(jsonEncode(snapshot.toJson())))),
    cancellation: MailCancellationSource().token,
    isCurrent: isCurrent,
  );
  if (context.mounted && isCurrent() && result is MailFailure<bool>) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      const SnackBar(
        content: Text('The snapshot could not be saved. Choose a new file.'),
      ),
    );
  }
}

import 'package:flutter/material.dart';

import 'studio_mail_archive_strings.dart';
import 'studio_strings.dart';

const studioMailArchiveAvailable = false;

class StudioMailArchiveDialog extends StatelessWidget {
  const StudioMailArchiveDialog({super.key, required this.strings});

  final StudioStrings strings;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(strings.archiveTitle),
    content: Text(strings.archiveDesktopRequired),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: Text(strings.close),
      ),
    ],
  );
}

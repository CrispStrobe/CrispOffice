import 'package:flutter/material.dart';

import 'studio_credential_storage.dart';
import 'studio_productivity_accounts.dart';

Future<void> showStudioConnections(BuildContext context) {
  final storage = StudioCredentialStorage.instance;
  final revision = storage.revision;
  final accounts = () async {
    final vault = await storage.storage;
    final rows = await loadStudioProductivityAccounts(vault);
    if (revision != storage.revision) {
      throw StateError('Credential storage changed.');
    }
    return rows;
  }();
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Connections'),
      content: SizedBox(
        width: 460,
        child: FutureBuilder<List<StudioProductivityAccount>>(
          future: accounts,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return const Text('Saved connections could not be read.');
            }
            final rows = snapshot.data;
            if (rows == null) return const LinearProgressIndicator();
            if (rows.isEmpty) return const Text('No saved connections.');
            return ListView(
              shrinkWrap: true,
              children: [
                for (final row in rows)
                  ListTile(
                    title: Text(row.label),
                    subtitle: Text(
                      row.services
                          .map(
                            (service) => switch (service) {
                              StudioProductivityService.mail => 'Mail',
                              StudioProductivityService.tasks => 'Tasks',
                              StudioProductivityService.calendar => 'Calendar',
                            },
                          )
                          .join(' · '),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    ),
  );
}

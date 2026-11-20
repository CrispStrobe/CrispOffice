import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'studio_font_pack_host.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

/// Reviews source, size, licence and exact downloaded files before installing
/// an optional open font pack. Downloading is always an explicit action.
class StudioFontPackSetupDialog extends StatelessWidget {
  const StudioFontPackSetupDialog({
    super.key,
    required this.status,
    required this.host,
  });

  final OfficeFontPackStatus status;
  final StudioFontPackHost host;

  String _size(int bytes) => '${(bytes / 1048576).toStringAsFixed(1)} MB';

  @override
  Widget build(BuildContext context) {
    final pack = status.pack;
    return AnimatedBuilder(
      animation: host,
      builder: (context, _) {
        final theme = Theme.of(context);
        final current = host.statuses
            .where((item) => item.pack.id == status.pack.id)
            .firstOrNull;
        final installed = current?.installed ?? status.installed;
        return AlertDialog(
          title: Text(pack.title),
          scrollable: true,
          content: SizedBox(
            width: 540,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(pack.description),
                const SizedBox(height: 12),
                Text('Source: ${pack.source}'),
                Text('Licence: ${pack.licence}'),
                Text('Download size: ${_size(pack.bytes)}'),
                const SizedBox(height: 8),
                Text(
                  installed
                      ? 'Installed in the application-support folder. No document is modified.'
                      : 'Downloads start only when you choose Install. Every file is verified by SHA-256 before it is registered.',
                  style: theme.textTheme.bodySmall,
                ),
                if (current?.problem != null || status.problem != null)
                  Text(
                    current?.problem ?? status.problem!,
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                if (host.error != null)
                  Text(
                    host.error!,
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                const SizedBox(height: 12),
                Text('Files', style: theme.textTheme.titleSmall),
                for (final file in pack.files)
                  Text(
                    '${file.family} ${file.weight}'
                    '${file.italic ? ' Italic' : ''} · ${file.fileName}',
                    style: theme.textTheme.bodySmall,
                  ),
                if (host.busy) ...<Widget>[
                  const SizedBox(height: 12),
                  const LinearProgressIndicator(),
                ],
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => launchUrl(
                Uri.parse(pack.licenceUrl),
                mode: LaunchMode.externalApplication,
              ),
              child: const Text('Open licence'),
            ),
            if (installed)
              TextButton(
                onPressed: host.busy ? null : () => host.remove(pack),
                child: const Text('Remove'),
              ),
            TextButton(
              onPressed: host.busy
                  ? null
                  : () async {
                      try {
                        await host.install(pack);
                      } on Object {
                        // The error is displayed above and remains actionable.
                      }
                    },
              child: Text(installed ? 'Repair' : 'Install'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }
}

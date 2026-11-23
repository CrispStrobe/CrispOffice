import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'studio_iso_image.dart';
import 'studio_strings.dart';

Future<void> showStudioIsoImageDialog(
  BuildContext context, {
  required StudioStrings strings,
  required StudioIsoImage image,
  required Future<void> Function(StudioIsoEntry entry, Uint8List bytes)
  onExtract,
}) => showDialog<void>(
  context: context,
  builder: (_) => _StudioIsoImageDialog(
    strings: strings,
    image: image,
    onExtract: onExtract,
  ),
);

class _StudioIsoImageDialog extends StatefulWidget {
  const _StudioIsoImageDialog({
    required this.strings,
    required this.image,
    required this.onExtract,
  });

  final StudioStrings strings;
  final StudioIsoImage image;
  final Future<void> Function(StudioIsoEntry entry, Uint8List bytes) onExtract;

  @override
  State<_StudioIsoImageDialog> createState() => _StudioIsoImageDialogState();
}

class _StudioIsoImageDialogState extends State<_StudioIsoImageDialog> {
  String _path = '';
  String? _busy;
  String? _error;

  String _t(String en, String de, String ar) =>
      switch (widget.strings.language) {
        StudioLanguage.en => en,
        StudioLanguage.de => de,
        StudioLanguage.ar => ar,
      };

  Future<void> _extract(StudioIsoEntry entry) async {
    if (entry.isDirectory || _busy != null) return;
    setState(() {
      _busy = entry.path;
      _error = null;
    });
    try {
      final bytes = widget.image.read(entry);
      await widget.onExtract(entry, bytes);
    } on Object {
      if (mounted) {
        setState(
          () => _error = _t(
            'The selected file could not be extracted.',
            'Die ausgewählte Datei konnte nicht entpackt werden.',
            'تعذر استخراج الملف المحدد.',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  String _size(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).round()} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final children = widget.image.children(_path)
      ..sort((a, b) {
        if (a.isDirectory != b.isDirectory) return a.isDirectory ? -1 : 1;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.album_outlined),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              widget.image.label.isEmpty ? 'ISO image' : widget.image.label,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 680,
        height: 460,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                IconButton(
                  key: const ValueKey('studio-iso-back'),
                  tooltip: _t('Back', 'Zurück', 'رجوع'),
                  onPressed: _path.isEmpty
                      ? null
                      : () {
                          final slash = _path.lastIndexOf('/');
                          setState(
                            () => _path = slash < 0
                                ? ''
                                : _path.substring(0, slash),
                          );
                        },
                  icon: const Icon(Icons.arrow_upward),
                ),
                Expanded(
                  child: Text(
                    '/${_path.isEmpty ? '' : _path}',
                    key: const ValueKey('studio-iso-path'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  _t(
                    '${children.length} items',
                    '${children.length} Einträge',
                    '${children.length} عناصر',
                  ),
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ],
            ),
            if (_error case final error?)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  error,
                  key: const ValueKey('studio-iso-error'),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            const SizedBox(height: 6),
            Expanded(
              child: children.isEmpty
                  ? Center(
                      child: Text(
                        _t(
                          'This folder is empty.',
                          'Dieser Ordner ist leer.',
                          'هذا المجلد فارغ.',
                        ),
                      ),
                    )
                  : ListView.separated(
                      itemCount: children.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final entry = children[index];
                        return ListTile(
                          key: ValueKey('studio-iso-entry-${entry.path}'),
                          leading: Icon(
                            entry.isDirectory
                                ? Icons.folder_outlined
                                : Icons.insert_drive_file_outlined,
                          ),
                          title: Text(entry.name),
                          subtitle: entry.isDirectory
                              ? null
                              : Text(_size(entry.size)),
                          trailing: entry.isDirectory
                              ? const Icon(Icons.chevron_right)
                              : IconButton(
                                  key: ValueKey(
                                    'studio-iso-extract-${entry.path}',
                                  ),
                                  tooltip: _t(
                                    'Save extracted file',
                                    'Entpackte Datei speichern',
                                    'حفظ الملف المستخرج',
                                  ),
                                  onPressed: _busy == null
                                      ? () => _extract(entry)
                                      : null,
                                  icon: _busy == entry.path
                                      ? const SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Icon(Icons.download_outlined),
                                ),
                          onTap: entry.isDirectory
                              ? () => setState(() => _path = entry.path)
                              : () => _extract(entry),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(MaterialLocalizations.of(context).closeButtonLabel),
        ),
      ],
    );
  }
}

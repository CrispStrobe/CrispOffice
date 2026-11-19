import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:quds_mail_mime/quds_mail_mime.dart';
import 'package:quds_mail_ui/quds_mail_ui.dart';

import 'studio_strings.dart';

/// Account-free saved-message reader used by the Studio Mail module.
class StudioMailDialog extends StatefulWidget {
  const StudioMailDialog({super.key, required this.strings});

  final StudioStrings strings;

  @override
  State<StudioMailDialog> createState() => _StudioMailDialogState();
}

class _StudioMailDialogState extends State<StudioMailDialog> {
  late MailReaderController _controller;
  MailReaderMode _mode = MailReaderMode.full;
  String? _name = 'Welcome.eml';

  @override
  void initState() {
    super.initState();
    _controller = _fromBytes(_sampleMessage());
  }

  MailReaderController _fromBytes(Uint8List bytes) =>
      MailReaderController.fromBytes(
        bytes,
        codec: const QudsMimeCodec(),
        mode: _mode,
      );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _open() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const <String>['eml'],
      withData: true,
    );
    if (!mounted || result == null || result.files.isEmpty) return;
    final file = result.files.single;
    final bytes =
        file.bytes ??
        (file.path == null ? null : await File(file.path!).readAsBytes());
    if (!mounted || bytes == null) return;
    final previous = _controller;
    setState(() {
      _controller = _fromBytes(Uint8List.fromList(bytes));
      _name = file.name;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => previous.dispose());
  }

  void _setMode(MailReaderMode mode) {
    final previous = _controller;
    setState(() {
      _mode = mode;
      _controller = MailReaderController(result: previous.result, mode: mode);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => previous.dispose());
  }

  @override
  Widget build(BuildContext context) => Dialog.fullscreen(
    child: Scaffold(
      appBar: AppBar(
        title: Text('${widget.strings.mailTitle} · ${_name ?? ''}'),
        actions: <Widget>[
          SegmentedButton<MailReaderMode>(
            segments: <ButtonSegment<MailReaderMode>>[
              ButtonSegment(
                value: MailReaderMode.full,
                label: Text(widget.strings.fullView),
              ),
              ButtonSegment(
                value: MailReaderMode.preview,
                label: Text(widget.strings.compactView),
              ),
            ],
            selected: <MailReaderMode>{_mode},
            onSelectionChanged: (value) => _setMode(value.first),
          ),
          const SizedBox(width: 12),
          TextButton.icon(
            onPressed: _open,
            icon: const Icon(Icons.file_open_outlined),
            label: Text(widget.strings.openMessage),
          ),
          const SizedBox(width: 8),
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            tooltip: widget.strings.close,
            icon: const Icon(Icons.close),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: MailMessageView(controller: _controller),
    ),
  );
}

Uint8List _sampleMessage() => Uint8List.fromList(
  utf8.encode(
    <String>[
      'From: CrispOffice <welcome@crispoffice.invalid>',
      'To: You <you@example.invalid>',
      'Subject: Welcome to CrispOffice Mail',
      'Date: Thu, 19 Nov 2026 09:00:00 +0000',
      'MIME-Version: 1.0',
      'Content-Type: text/plain; charset=utf-8',
      '',
      'This is a local, read-only message. No account, network connection or',
      'remote content is used. Open any saved .eml file to read it here.',
      '',
      '— CrispOffice',
      '',
    ].join('\r\n'),
  ),
);

import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:quds_mail_mime/quds_mail_mime.dart';
import 'package:quds_mail_ui/quds_mail_ui.dart';

import 'studio_mail_archive.dart';
import 'studio_mail_archive_strings.dart';
import 'studio_mail_file.dart';
import 'studio_strings.dart';
import 'studio_mail_reader_labels.dart';

/// The account-free saved-message view shared by native and browser Studio.
class StudioSavedMailView extends StatefulWidget {
  const StudioSavedMailView({
    super.key,
    required this.strings,
    this.onAccounts,
    this.accountNotice,
  });

  final StudioStrings strings;
  final VoidCallback? onAccounts;
  final String? accountNotice;

  @override
  State<StudioSavedMailView> createState() => _StudioSavedMailViewState();
}

class _StudioSavedMailViewState extends State<StudioSavedMailView> {
  late MailReaderController _controller;
  MailReaderMode _mode = MailReaderMode.full;
  String _name = 'Welcome.eml';
  bool _opening = false;
  String? _error;

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
        preferHtml: false,
        includeHeaders: false,
        labels: StudioMailReaderLabels(widget.strings.language),
      );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _open() async {
    if (_opening) return;
    setState(() {
      _opening = true;
      _error = null;
    });
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const <String>['eml'],
        withData: true,
      );
      if (!mounted || result == null || result.files.isEmpty) return;
      final file = result.files.single;
      final bytes =
          file.bytes ??
          (file.path == null ? null : await readStudioMailFile(file.path!));
      if (!mounted) return;
      if (bytes == null) {
        setState(() => _error = widget.strings.openMessageFailed);
        return;
      }
      final next = _fromBytes(bytes);
      final previous = _controller;
      setState(() {
        _controller = next;
        _name = file.name;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) => previous.dispose());
    } on Object {
      if (mounted) {
        setState(() => _error = widget.strings.openMessageFailed);
      }
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  void _setMode(MailReaderMode mode) {
    if (mode == _mode) return;
    final previous = _controller;
    setState(() {
      _mode = mode;
      _controller = MailReaderController(
        result: previous.result,
        mode: mode,
        preferHtml: false,
        includeHeaders: false,
        labels: previous.labels,
      );
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => previous.dispose());
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        '${widget.strings.mailTitle} · $_name',
        overflow: TextOverflow.ellipsis,
      ),
      actions: <Widget>[
        if (widget.onAccounts != null)
          IconButton(
            onPressed: widget.onAccounts,
            tooltip: widget.strings.mailAccounts,
            icon: const Icon(Icons.manage_accounts_outlined),
          ),
        IconButton(
          onPressed: () => Navigator.of(context).pop(),
          tooltip: widget.strings.close,
          icon: const Icon(Icons.close),
        ),
      ],
    ),
    body: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (widget.accountNotice case final String notice)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text(notice),
          ),
        Padding(
          padding: const EdgeInsets.all(12),
          child: Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: <Widget>[
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
              if (studioMailArchiveAvailable)
                TextButton.icon(
                  key: const ValueKey('studio-saved-mail-archive'),
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (_) =>
                        StudioMailArchiveDialog(strings: widget.strings),
                  ),
                  icon: const Icon(Icons.inventory_2_outlined),
                  label: Text(widget.strings.archiveTitle),
                ),
              TextButton.icon(
                onPressed: _opening ? null : _open,
                icon: _opening
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.file_open_outlined),
                label: Text(widget.strings.openMessage),
              ),
            ],
          ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        Expanded(child: MailMessageView(controller: _controller)),
      ],
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
      'Content-Transfer-Encoding: 8bit',
      '',
      'This is a local, read-only message. No account, network connection or',
      'remote content is used. Open any saved .eml file to read it here.',
      '',
      '— CrispOffice',
      '',
    ].join('\r\n'),
  ),
);

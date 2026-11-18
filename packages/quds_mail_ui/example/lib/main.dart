import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_mime/quds_mail_mime.dart';
import 'package:quds_mail_ui/quds_mail_ui.dart';

void main() => runApp(const _ReaderApp());

/// An independently authored multipart fixture. The projection shown on screen
/// is produced from these exact bytes by the public MIME codec.
Uint8List exampleMessage() {
  final subject = base64Encode(utf8.encode('Offline reader — قارئ البريد'));
  final html = base64Encode(
    utf8.encode(
      '<h2>Meeting agenda</h2>'
      '<p>This message stays <b>on your device</b>. مرحبًا</p>'
      '<img src="cid:local-pixel" alt="Local pixel">'
      '<script>fetch("https://blocked.invalid/script")</script>'
      '<style>@import url(https://blocked.invalid/style);</style>'
      '<img src="https://blocked.invalid/tracker" srcset="//blocked.invalid/large 2x">',
    ),
  );
  const png =
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGMwaDjwHwAExAJwNooHGQAAAABJRU5ErkJggg==';
  return Uint8List.fromList(
    utf8.encode(
      [
        'From: Reader <reader@example.invalid>',
        'To: You <you@example.invalid>',
        'Subject: =?UTF-8?B?$subject?=',
        'MIME-Version: 1.0',
        'Content-Type: multipart/mixed; boundary="quds-outer"',
        '',
        '--quds-outer',
        'Content-Type: multipart/alternative; boundary="quds-alt"',
        '',
        '--quds-alt',
        'Content-Type: text/plain; charset=utf-8',
        '',
        'Meeting agenda.\r\nThis message stays on your device.',
        '--quds-alt',
        'Content-Type: text/html; charset=utf-8',
        'Content-Transfer-Encoding: base64',
        '',
        html,
        '--quds-alt--',
        '--quds-outer',
        'Content-Type: image/png',
        'Content-ID: <local-pixel>',
        'Content-Disposition: inline; filename="pixel.png"',
        'Content-Transfer-Encoding: base64',
        '',
        png,
        '--quds-outer',
        'Content-Type: application/octet-stream',
        'Content-Disposition: attachment; filename="original.bin"',
        'Content-Transfer-Encoding: base64',
        '',
        'AAEA/w==',
        '--quds-outer--',
        '',
      ].join('\r\n'),
    ),
  );
}

class _ReaderApp extends StatefulWidget {
  const _ReaderApp();
  @override
  State<_ReaderApp> createState() => _ReaderAppState();
}

class _ReaderAppState extends State<_ReaderApp> {
  late MailReaderController controller;
  final Uint8List raw = exampleMessage();
  MailReaderMode mode = MailReaderMode.full;

  MailReaderController _create() => MailReaderController.fromBytes(
    raw,
    codec: const QudsMimeCodec(),
    mode: mode,
  );

  @override
  void initState() {
    super.initState();
    controller = _create();
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  void _changeMode(MailReaderMode value) {
    final previous = controller;
    setState(() {
      mode = value;
      controller = _create();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => previous.dispose());
  }

  Future<void> _showBytes(
    BuildContext context,
    MailBytes bytes,
    String title, {
    bool hex = false,
  }) async {
    final text = hex
        ? bytes.bytes
              .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
              .join(' ')
        : latin1.decode(bytes.bytes);
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 560,
          height: 360,
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Text(
                  text,
                  style: const TextStyle(fontFamily: 'monospace'),
                ),
              ),
            ],
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

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Quds saved-message reader',
    home: Scaffold(
      appBar: AppBar(title: const Text('Quds saved-message reader')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8),
            child: SegmentedButton<MailReaderMode>(
              segments: const [
                ButtonSegment(value: MailReaderMode.full, label: Text('Full')),
                ButtonSegment(
                  value: MailReaderMode.preview,
                  label: Text('Compact preview'),
                ),
              ],
              selected: {mode},
              onSelectionChanged: (selection) => _changeMode(selection.single),
            ),
          ),
          Expanded(
            child: Builder(
              builder: (context) => MailMessageView(
                controller: controller,
                compact: mode == MailReaderMode.preview,
                onOpenSource: (bytes, view) => _showBytes(
                  context,
                  bytes,
                  view == MailSourceView.hex
                      ? 'Exact source hex'
                      : 'Raw MIME source',
                  hex: view == MailSourceView.hex,
                ),
                onOpenAttachmentReadOnly: (attachment) => _showBytes(
                  context,
                  attachment.content,
                  '${attachment.displayName} — read only',
                  hex: true,
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

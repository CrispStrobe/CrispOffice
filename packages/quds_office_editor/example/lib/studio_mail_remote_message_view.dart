import 'package:flutter/material.dart';
import 'package:quds_mail_ui/quds_mail_ui.dart';

import 'studio_mail_remote_images.dart';

/// Handles explicitly loaded images in saved and provider-backed readers.
class StudioMailRemoteMessageView extends StatefulWidget {
  const StudioMailRemoteMessageView({
    super.key,
    required this.controller,
    this.imageLoaderFactory,
  });

  final MailReaderController controller;
  final StudioMailRemoteImageLoader Function()? imageLoaderFactory;

  @override
  State<StudioMailRemoteMessageView> createState() =>
      _StudioMailRemoteMessageViewState();
}

class _StudioMailRemoteMessageViewState
    extends State<StudioMailRemoteMessageView> {
  StudioMailRemoteImageLoader? _pending;

  @override
  void didUpdateWidget(StudioMailRemoteMessageView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.controller, oldWidget.controller)) {
      _pending?.cancel();
      _pending = null;
    }
  }

  @override
  void dispose() {
    _pending?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final reader = widget.controller;
    if (_pending != null ||
        reader.isDisposed ||
        reader.presentation.remoteImageUrls.isEmpty) {
      return;
    }
    final loader =
        widget.imageLoaderFactory?.call() ?? StudioMailRemoteImageLoader();
    bool current() =>
        mounted &&
        identical(_pending, loader) &&
        identical(widget.controller, reader) &&
        !reader.isDisposed;
    setState(() => _pending = loader);
    try {
      final loaded = await loader.loadInto(reader, isCurrent: current);
      if (mounted && current()) {
        showStudioMailImageResult(context, reader, loaded);
      }
    } finally {
      if (current()) setState(() => _pending = null);
    }
  }

  @override
  Widget build(BuildContext context) => MailMessageView(
    controller: widget.controller,
    richHtml: true,
    onLoadRemoteImages: _pending == null ? _load : null,
    remoteImagesLoading: _pending != null,
  );
}

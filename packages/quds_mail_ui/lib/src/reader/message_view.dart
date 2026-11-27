import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:quds_mail_core/quds_mail_core.dart';

import 'controller.dart';
import 'html_body.dart';
import 'labels.dart';
import 'presentation.dart';
import 'selection_surface.dart';

enum MailSourceView { source, hex }

typedef MailReadOnlyAttachmentAction =
    Future<void> Function(MailAttachment attachment);
typedef MailSourceAction =
    Future<void> Function(MailBytes bytes, MailSourceView view);
typedef MailApprovedLinkAction = Future<void> Function(Uri target);
typedef MailCopyAction = Future<void> Function(String decodedText);

/// The same account-free reader can be embedded in a full or compact host.
///
/// The host supplies explicit source, attachment and approved-link actions.
/// There is no automatic external-resource loading. Source/attachment callbacks
/// receive immutable snapshots, never a writable path or a reconstructed MIME.
class MailMessageView extends StatefulWidget {
  const MailMessageView({
    super.key,
    required this.controller,
    this.compact = false,
    this.textDirection,
    this.externalResources = const MailDenyExternalResources(),
    this.onOpenApprovedLink,
    this.onOpenAttachmentReadOnly,
    this.onOpenSource,
    this.onCopy,
    this.onFindRequested,
    this.onLoadRemoteImages,
    this.remoteImagesLoading = false,
    this.richHtml = false,
  });
  final MailReaderController controller;
  final bool compact;
  final TextDirection? textDirection;
  final MailExternalResourcePolicy externalResources;
  final MailApprovedLinkAction? onOpenApprovedLink;
  final MailReadOnlyAttachmentAction? onOpenAttachmentReadOnly;
  final MailSourceAction? onOpenSource;
  final MailCopyAction? onCopy;
  final ValueChanged<MailReaderController>? onFindRequested;

  /// Explicit host action that may load remote images into this controller.
  final VoidCallback? onLoadRemoteImages;
  final bool remoteImagesLoading;

  /// Render the sanitized HTML body with the bounded rich renderer. Hosts opt
  /// in explicitly; the default text surface remains available for find/copy.
  final bool richHtml;

  @override
  State<MailMessageView> createState() => _MailMessageViewState();
}

class _MailMessageViewState extends State<MailMessageView> {
  final FocusNode _focus = FocusNode(debugLabel: 'Decoded mail selection');
  final TextEditingController _findInput = TextEditingController();
  final FocusNode _findFocus = FocusNode(debugLabel: 'Find decoded mail');
  final ScrollController _scroll = ScrollController();
  final GlobalKey _surfaceKey = GlobalKey(debugLabel: 'Decoded mail body');
  bool _findVisible = false;
  String? _notice;
  int _action = 0;

  @override
  void didUpdateWidget(MailMessageView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      _action++;
      _notice = null;
    }
  }

  @override
  void dispose() {
    _action++;
    _focus.dispose();
    _findInput.dispose();
    _findFocus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  bool _current(MailReaderController controller, int revision, int action) =>
      mounted &&
      !controller.isDisposed &&
      identical(controller, widget.controller) &&
      controller.revision == revision &&
      action == _action;

  Future<void> _hostAction(Future<void> Function() callback) async {
    final controller = widget.controller;
    final revision = controller.revision, action = ++_action;
    try {
      await callback();
      if (_current(controller, revision, action)) {
        setState(() => _notice = null);
      }
    } on Object {
      if (_current(controller, revision, action)) {
        setState(
          () => _notice =
              'The host action failed. The saved message is unchanged.',
        );
      }
    }
  }

  Future<void> _openLink(Uri target) async {
    final callback = widget.onOpenApprovedLink;
    if (callback == null || approvedMailLink(target.toString()) == null) return;
    final controller = widget.controller;
    final revision = controller.revision, action = ++_action;
    try {
      final decision = await widget.externalResources.openLink(target);
      if (!_current(controller, revision, action)) return;
      if (decision == MailResourceDecision.deny) {
        setState(() => _notice = 'The host did not approve this link.');
        return;
      }
      await callback(target);
      if (_current(controller, revision, action)) {
        setState(() => _notice = null);
      }
    } on Object {
      if (_current(controller, revision, action)) {
        setState(() => _notice = 'The host could not open this link.');
      }
    }
  }

  Future<void> _copy() async {
    final text = widget.controller.selectedText;
    if (text.isEmpty) return;
    await _hostAction(
      () =>
          widget.onCopy?.call(text) ??
          Clipboard.setData(ClipboardData(text: text)),
    );
  }

  void _showFind() {
    widget.onFindRequested?.call(widget.controller);
    _findInput.text = widget.controller.searchQuery;
    setState(() => _findVisible = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _findFocus.requestFocus();
    });
  }

  void _next({bool backwards = false}) {
    if (widget.controller.nextSearchMatch(backwards: backwards) == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      final render = _surfaceKey.currentContext?.findRenderObject();
      if (render is! RenderMailSelectionSurface ||
          render.selectionRect == null) {
        return;
      }
      final viewport = RenderAbstractViewport.of(render);
      final target = viewport
          .getOffsetToReveal(render, .3, rect: render.selectionRect)
          .offset;
      _scroll.jumpTo(
        target.clamp(
          _scroll.position.minScrollExtent,
          _scroll.position.maxScrollExtent,
        ),
      );
    });
  }

  KeyEventResult _key(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final control =
        HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed;
    final controller = widget.controller;
    if (control && event.logicalKey == LogicalKeyboardKey.keyA) {
      controller.selectAll();
      return KeyEventResult.handled;
    }
    if (control && event.logicalKey == LogicalKeyboardKey.keyC) {
      unawaited(_copy());
      return KeyEventResult.handled;
    }
    if (control && event.logicalKey == LogicalKeyboardKey.keyF) {
      _showFind();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.f3) {
      _next(backwards: HardwareKeyboard.instance.isShiftPressed);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape && _findFocus.hasFocus) {
      setState(() => _findVisible = false);
      _focus.requestFocus();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      controller.select(
        TextSelection.collapsed(offset: controller.selection.extentOffset),
      );
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  String _rawHeaders() {
    final bytes =
        widget.controller.result.original?.bytes ??
        widget.controller.result.message?.raw.bytes;
    if (bytes == null) return widget.controller.labels.headersUnavailable;
    final limited = bytes.length > 65536 ? bytes.sublist(0, 65536) : bytes;
    final decoded = utf8.decode(limited, allowMalformed: true);
    var end = decoded.indexOf('\r\n\r\n');
    var separator = 4;
    final lf = decoded.indexOf('\n\n');
    if (lf != -1 && (end == -1 || lf < end)) {
      end = lf;
      separator = 2;
    }
    final block = end == -1 ? decoded : decoded.substring(0, end);
    return end != -1 && end + separator < decoded.length ? '$block\n…' : block;
  }

  Future<void> _inspectHeaders() async {
    final headers = _rawHeaders();
    final labels = widget.controller.labels;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(labels.headers),
        content: SizedBox(
          width: 720,
          height: 480,
          child: SelectableText(
            headers,
            key: const ValueKey('mail-headers-text'),
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 12,
              height: 1.35,
            ),
          ),
        ),
        actions: [
          TextButton.icon(
            key: const ValueKey('mail-copy-headers'),
            onPressed: headers == labels.headersUnavailable
                ? null
                : () => Clipboard.setData(ClipboardData(text: headers)),
            icon: const Icon(Icons.copy),
            label: Text(labels.copyHeaders),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(MaterialLocalizations.of(context).closeButtonLabel),
          ),
        ],
      ),
    );
  }

  Widget _metadata(
    BuildContext context,
    MailEnvelope envelope,
    MailReaderLabels labels,
  ) {
    String addresses(List<MailAddress> values) => values
        .map(
          (address) => address.displayName?.isNotEmpty == true
              ? '${address.displayName} <${address.address}>'
              : address.address,
        )
        .join(', ');
    final rows = <(String, String, String)>[
      if (envelope.from.isNotEmpty)
        ('from', labels.from, addresses(envelope.from)),
      if (envelope.to.isNotEmpty) ('to', labels.to, addresses(envelope.to)),
      if (envelope.cc.isNotEmpty) ('cc', labels.cc, addresses(envelope.cc)),
      if (envelope.bcc.isNotEmpty) ('bcc', labels.bcc, addresses(envelope.bcc)),
      if (envelope.replyTo.isNotEmpty)
        ('reply', labels.replyTo, addresses(envelope.replyTo)),
    ];
    final date = envelope.sentAt;
    if (rows.isEmpty && date == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    Widget line(String id, String label, String value, {bool right = false}) =>
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 1),
          child: Text.rich(
            key: ValueKey('mail-metadata-$id'),
            TextSpan(
              children: [
                TextSpan(
                  text: '$label: ',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                TextSpan(text: value),
              ],
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: right ? TextAlign.end : TextAlign.start,
          ),
        );
    final left = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [for (final (id, label, value) in rows) line(id, label, value)],
    );
    final dateLine = date == null
        ? null
        : line('date', labels.date, labels.formatDate(date), right: true);
    return Container(
      key: const ValueKey('mail-metadata'),
      margin: const EdgeInsets.only(bottom: 8),
      padding: EdgeInsets.symmetric(
        horizontal: widget.compact ? 10 : 12,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: .35),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final twoColumns = dateLine != null && constraints.maxWidth >= 480;
          if (!twoColumns) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [if (rows.isNotEmpty) left, ?dateLine],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: left),
              const SizedBox(width: 16),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 240),
                child: dateLine,
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _actionsBar(BuildContext context, List<_ReaderAction> actions) =>
      LayoutBuilder(
        builder: (context, constraints) {
          final showLabels = !widget.compact && constraints.maxWidth >= 1000;
          return SingleChildScrollView(
            key: const ValueKey('mail-reader-actions'),
            scrollDirection: Axis.horizontal,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final action in actions)
                  if (showLabels)
                    Padding(
                      padding: const EdgeInsetsDirectional.only(end: 4),
                      child: TextButton.icon(
                        key: action.key,
                        onPressed: action.onPressed,
                        icon: Icon(action.icon, size: 19),
                        label: Text(action.label),
                      ),
                    )
                  else
                    IconButton(
                      key: action.key,
                      tooltip: action.label,
                      onPressed: action.onPressed,
                      visualDensity: VisualDensity.compact,
                      iconSize: 20,
                      icon: Icon(action.icon),
                    ),
              ],
            ),
          );
        },
      );

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final direction = widget.textDirection ?? Directionality.of(context);
    return Directionality(
      textDirection: direction,
      child: Focus(
        focusNode: _focus,
        onKeyEvent: _key,
        child: AnimatedBuilder(
          animation: controller,
          builder: (context, child) {
            final result = controller.result;
            final presentation = controller.presentation;
            final rich =
                widget.richHtml &&
                presentation.usedHtml &&
                presentation.safeHtml != null;
            final message = result.message;
            final links = presentation.runs
                .map((run) => run.link)
                .whereType<Uri>()
                .toSet()
                .toList(growable: false);
            final labels = controller.labels;
            final padding = widget.compact ? 12.0 : 20.0;
            final actions = <_ReaderAction>[
              if (!rich)
                _ReaderAction(
                  key: const ValueKey('mail-select-all'),
                  icon: Icons.select_all,
                  label: labels.selectAll,
                  onPressed: presentation.text.isEmpty
                      ? null
                      : controller.selectAll,
                ),
              if (!rich)
                _ReaderAction(
                  key: const ValueKey('mail-copy'),
                  icon: Icons.copy,
                  label: labels.copySelection,
                  onPressed: controller.selection.isCollapsed
                      ? null
                      : () => unawaited(_copy()),
                ),
              if (!rich)
                _ReaderAction(
                  key: const ValueKey('mail-find'),
                  icon: Icons.search,
                  label: labels.findInMessage,
                  onPressed: _showFind,
                ),
              if (result.original != null && widget.onOpenSource != null)
                for (final view in MailSourceView.values)
                  _ReaderAction(
                    key: ValueKey('mail-${view.name}'),
                    icon: view == MailSourceView.source
                        ? Icons.code
                        : Icons.data_array,
                    label: view == MailSourceView.source
                        ? labels.rawSource
                        : labels.hex,
                    onPressed: () => unawaited(
                      _hostAction(
                        () => widget.onOpenSource!(result.original!, view),
                      ),
                    ),
                  ),
              _ReaderAction(
                key: const ValueKey('mail-inspect-headers'),
                icon: Icons.view_headline,
                label: labels.inspectHeaders,
                onPressed: _inspectHeaders,
              ),
              if (message?.body.html != null && message?.body.plainText != null)
                _ReaderAction(
                  key: const ValueKey('mail-toggle-format'),
                  icon: controller.preferHtml
                      ? Icons.text_snippet_outlined
                      : Icons.html,
                  label: controller.preferHtml
                      ? labels.showPlainText
                      : labels.showStaticHtml,
                  onPressed: () =>
                      controller.setPreferHtml(!controller.preferHtml),
                ),
            ];
            return RepaintBoundary(
              key: const ValueKey('mail-reader-repaint-boundary'),
              child: Material(
                color: Theme.of(context).colorScheme.surface,
                child: CustomScrollView(
                  key: const ValueKey('mail-reader-scroll'),
                  controller: _scroll,
                  slivers: [
                    SliverPadding(
                      padding: EdgeInsets.all(padding),
                      sliver: SliverToBoxAdapter(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // A completely decoded message needs no status
                            // line; partial or failed decoding is reported.
                            if (presentation.rejected ||
                                result.status != MailParseStatus.complete) ...[
                              Text(
                                presentation.rejected
                                    ? labels.displayUnavailable
                                    : labels.status(result.status),
                                key: const ValueKey('mail-reader-status'),
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              const SizedBox(height: 8),
                            ],
                            if (message != null)
                              _metadata(context, message.envelope, labels),
                            _actionsBar(context, actions),
                            if ((_findVisible && !rich) ||
                                controller.searchQuery.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 6,
                                ),
                                child: Row(
                                  children: [
                                    if (_findVisible && !rich)
                                      Expanded(
                                        child: TextField(
                                          key: const ValueKey(
                                            'mail-find-input',
                                          ),
                                          controller: _findInput,
                                          focusNode: _findFocus,
                                          maxLength: 2048,
                                          decoration: InputDecoration(
                                            labelText: labels.findField,
                                            counterText: '',
                                            isDense: true,
                                            border: const OutlineInputBorder(),
                                          ),
                                          onChanged: controller.search,
                                          onSubmitted: (_) => _next(),
                                        ),
                                      ),
                                    if (controller.searchQuery.isNotEmpty) ...[
                                      if (_findVisible && !rich)
                                        const SizedBox(width: 8),
                                      Text(
                                        labels.matches(
                                          controller.searchMatches.length,
                                          more: controller.searchHasMore,
                                        ),
                                      ),
                                      IconButton(
                                        tooltip: labels.previousMatch,
                                        visualDensity: VisualDensity.compact,
                                        onPressed:
                                            controller.searchMatches.isEmpty
                                            ? null
                                            : () => _next(backwards: true),
                                        icon: const Icon(Icons.arrow_upward),
                                      ),
                                      IconButton(
                                        tooltip: labels.nextMatch,
                                        visualDensity: VisualDensity.compact,
                                        onPressed:
                                            controller.searchMatches.isEmpty
                                            ? null
                                            : _next,
                                        icon: const Icon(Icons.arrow_downward),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            if (_notice != null)
                              Semantics(
                                liveRegion: true,
                                child: Text(
                                  _notice!,
                                  key: const ValueKey('mail-host-notice'),
                                ),
                              ),
                            for (final diagnostic in presentation.diagnostics)
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 3,
                                ),
                                child: Semantics(
                                  liveRegion:
                                      diagnostic.severity ==
                                      MailDiagnosticSeverity.error,
                                  child: Text(
                                    diagnostic.message,
                                    style: TextStyle(
                                      color:
                                          diagnostic.severity ==
                                              MailDiagnosticSeverity.error
                                          ? Theme.of(context).colorScheme.error
                                          : null,
                                    ),
                                  ),
                                ),
                              ),
                            const Divider(),
                            if (!presentation.rejected)
                              if (rich)
                                MailHtmlMessageBody(
                                  key: const ValueKey('mail-rich-body'),
                                  presentation: presentation,
                                  textStyle:
                                      (Theme.of(context).textTheme.bodyLarge ??
                                              const TextStyle(fontSize: 16))
                                          .copyWith(
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.onSurface,
                                          ),
                                  onOpenLink: widget.onOpenApprovedLink == null
                                      ? null
                                      : _openLink,
                                  onLoadRemoteImages: widget.onLoadRemoteImages,
                                  remoteImagesLoading:
                                      widget.remoteImagesLoading,
                                  labels: labels,
                                )
                              else
                                MailSelectionSurface(
                                  key: _surfaceKey,
                                  controller: controller,
                                  textDirection: direction,
                                  style:
                                      (Theme.of(context).textTheme.bodyLarge ??
                                              const TextStyle(fontSize: 16))
                                          .copyWith(
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.onSurface,
                                          ),
                                  linkColor: Theme.of(
                                    context,
                                  ).colorScheme.primary,
                                  textScaler: MediaQuery.textScalerOf(context),
                                  onFocusRequest: _focus.requestFocus,
                                  onCopy: () => unawaited(_copy()),
                                  onLink: widget.onOpenApprovedLink == null
                                      ? null
                                      : (target) =>
                                            unawaited(_openLink(target)),
                                ),
                          ],
                        ),
                      ),
                    ),
                    if (!presentation.rejected &&
                        !rich &&
                        presentation.images.isNotEmpty)
                      SliverPadding(
                        padding: EdgeInsets.symmetric(horizontal: padding),
                        sliver: SliverList.builder(
                          itemCount: presentation.images.length,
                          itemBuilder: (context, index) => _CidImage(
                            key: ValueKey(
                              presentation.images[index].attachment.partPath,
                            ),
                            image: presentation.images[index],
                          ),
                        ),
                      ),
                    if (!presentation.rejected &&
                        !rich &&
                        links.isNotEmpty &&
                        widget.onOpenApprovedLink != null)
                      SliverPadding(
                        padding: EdgeInsets.all(padding),
                        sliver: SliverList.builder(
                          itemCount: links.length,
                          itemBuilder: (context, index) => Align(
                            alignment: AlignmentDirectional.centerStart,
                            child: TextButton.icon(
                              key: ValueKey('mail-link-$index'),
                              onPressed: () =>
                                  unawaited(_openLink(links[index])),
                              icon: const Icon(Icons.open_in_new),
                              label: Text(
                                'Open link: ${links[index]}',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                        ),
                      ),
                    if (!presentation.rejected &&
                        message != null &&
                        message.attachments.isNotEmpty)
                      SliverPadding(
                        padding: EdgeInsets.all(padding),
                        sliver: SliverList.builder(
                          itemCount: message.attachments.length,
                          itemBuilder: (context, index) {
                            final attachment = message.attachments[index];
                            return Semantics(
                              label:
                                  'Read-only attachment ${attachment.displayName}',
                              child: Card(
                                child: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Wrap(
                                    spacing: 12,
                                    runSpacing: 8,
                                    crossAxisAlignment:
                                        WrapCrossAlignment.center,
                                    children: [
                                      Text(
                                        '${attachment.displayName} · ${attachment.mediaType} · ${attachment.observedSize} bytes',
                                      ),
                                      if (widget.onOpenAttachmentReadOnly !=
                                          null)
                                        TextButton.icon(
                                          key: ValueKey(
                                            'mail-attachment-$index',
                                          ),
                                          onPressed: () => unawaited(
                                            _hostAction(
                                              () =>
                                                  widget
                                                      .onOpenAttachmentReadOnly!(
                                                    attachment,
                                                  ),
                                            ),
                                          ),
                                          icon: const Icon(
                                            Icons.visibility_outlined,
                                          ),
                                          label: Text(labels.openReadOnly),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _CidImage extends StatefulWidget {
  const _CidImage({super.key, required this.image});
  final MailInlineImage image;
  @override
  State<_CidImage> createState() => _CidImageState();
}

class _CidImageState extends State<_CidImage> {
  ui.Image? _image;
  bool _failed = false;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void didUpdateWidget(_CidImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(
      oldWidget.image.attachment.content,
      widget.image.attachment.content,
    )) {
      _image?.dispose();
      _image = null;
      _failed = false;
      unawaited(_load());
    }
  }

  Future<void> _load() async {
    final generation = ++_generation;
    final spec = widget.image;
    ui.Codec? codec;
    ui.Image? image;
    try {
      codec = await ui.instantiateImageCodec(spec.attachment.content.bytes);
      if (codec.frameCount != 1) {
        throw const FormatException('Animated image rejected');
      }
      image = (await codec.getNextFrame()).image;
      if (image.width != spec.width || image.height != spec.height) {
        throw const FormatException('Image dimensions changed during decode');
      }
      if (mounted && generation == _generation) {
        setState(() => _image = image);
        image = null;
      }
    } on Object {
      if (mounted && generation == _generation) setState(() => _failed = true);
    } finally {
      image?.dispose();
      codec?.dispose();
    }
  }

  @override
  void dispose() {
    _generation++;
    _image?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) return const Text('Inline image could not be decoded.');
    if (_image == null) return const Text('Decoding bounded inline image…');
    return Semantics(
      image: true,
      label: 'Inline image ${widget.image.attachment.displayName}',
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: SizedBox(
          height: widget.image.height.clamp(1, 320).toDouble(),
          child: RawImage(image: _image, fit: BoxFit.contain),
        ),
      ),
    );
  }
}

final class _ReaderAction {
  const _ReaderAction({
    required this.key,
    required this.icon,
    required this.label,
    this.onPressed,
  });

  final Key key;
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
}

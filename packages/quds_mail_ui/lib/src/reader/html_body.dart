import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:html/dom.dart' as dom;

import 'labels.dart';
import 'presentation.dart';

/// Rich, inert HTML rendering for an admitted [MailReaderPresentation].
///
/// This widget never receives a URL fetcher. Images are resolved only from the
/// already validated [MailReaderPresentation.images] snapshots; remote images
/// are placeholders until the host explicitly loads and admits them. Scripts,
/// forms, frames, CSS resources and event handlers are removed by the
/// sanitizer before this widget sees the fragment.
class MailHtmlMessageBody extends StatelessWidget {
  const MailHtmlMessageBody({
    super.key,
    required this.presentation,
    this.textStyle,
    this.onOpenLink,
    this.onLoadRemoteImages,
    this.remoteImagesLoading = false,
    this.labels = const MailReaderLabels(),
  });

  final MailReaderPresentation presentation;
  final TextStyle? textStyle;
  final Future<void> Function(Uri target)? onOpenLink;
  final VoidCallback? onLoadRemoteImages;
  final bool remoteImagesLoading;
  final MailReaderLabels labels;

  @override
  Widget build(BuildContext context) {
    final html = presentation.safeHtml;
    if (html == null) return const SizedBox.shrink();
    final images = _MailHtmlImages(presentation.images);
    return SelectionArea(
      child: HtmlWidget(
        html,
        // HtmlWidget caches its rendered node tree for the same source string.
        // Externally admitted images must recreate it so their placeholders are
        // replaced instead of keeping the widget captured on first paint.
        key: ValueKey<int>(
          Object.hashAll(<Object>[
            remoteImagesLoading,
            onLoadRemoteImages != null,
            labels.loadExternalImage,
            for (final image in presentation.images) ...[
              image.attachment.partPath,
              identityHashCode(image.attachment),
            ],
          ]),
        ),
        textStyle: textStyle,
        onTapUrl: (url) {
          final target = approvedMailLink(url);
          if (target != null) {
            final callback = onOpenLink;
            if (callback != null) {
              unawaited(callback(target));
            }
          }
          // Never fall through to the platform opener or any network action.
          return true;
        },
        customWidgetBuilder: (element) {
          switch (element.localName?.toLowerCase()) {
            case 'img':
              return _MailHtmlImage(
                element: element,
                images: images,
                textStyle: textStyle,
                onLoadRemoteImages: onLoadRemoteImages,
                remoteImagesLoading: remoteImagesLoading,
                labels: labels,
              );
            case 'iframe':
            case 'object':
            case 'embed':
            case 'video':
            case 'audio':
            case 'form':
              return const SizedBox.shrink();
          }
          return null;
        },
      ),
    );
  }
}

final class _MailHtmlImages {
  _MailHtmlImages(List<MailInlineImage> values) {
    for (final image in values) {
      final cid = image.attachment.contentId;
      if (cid != null) byCid[cid] = image;
      if (image.attachment.partPath.startsWith('remote:')) {
        byRemote[image.attachment.partPath.substring(7)] = image;
      }
    }
  }

  final Map<String, MailInlineImage> byCid = {};
  final Map<String, MailInlineImage> byRemote = {};

  MailInlineImage? find(String? cid, String? remote) {
    if (cid != null) return byCid[cid];
    if (remote != null) return byRemote[remote];
    return null;
  }
}

class _MailHtmlImage extends StatelessWidget {
  const _MailHtmlImage({
    required this.element,
    required this.images,
    this.textStyle,
    this.onLoadRemoteImages,
    this.remoteImagesLoading = false,
    this.labels = const MailReaderLabels(),
  });

  final dom.Element element;
  final _MailHtmlImages images;
  final TextStyle? textStyle;
  final VoidCallback? onLoadRemoteImages;
  final bool remoteImagesLoading;
  final MailReaderLabels labels;

  @override
  Widget build(BuildContext context) {
    final cid = element.attributes['data-mail-cid'];
    final remote = element.attributes['data-mail-remote'];
    final alt = element.attributes['alt'];
    final image = images.find(cid, remote);
    if (image == null) {
      final isRemote = remote != null;
      final label = isRemote
          ? remoteImagesLoading
                ? labels.loadingExternalImages
                : onLoadRemoteImages == null
                ? labels.externalImageBlocked
                : labels.loadExternalImage
          : (alt == null || alt.isEmpty ? 'Inline image unavailable' : alt);
      final placeholder = Container(
        constraints: const BoxConstraints(maxWidth: 420),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          border: Border.all(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isRemote
                  ? Icons.image_outlined
                  : Icons.image_not_supported_outlined,
              size: 18,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                style: textStyle?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      );
      if (isRemote && onLoadRemoteImages != null) {
        return InkWell(
          key: ValueKey<String>('mail-load-remote-$remote'),
          onTap: onLoadRemoteImages,
          child: placeholder,
        );
      }
      return placeholder;
    }
    final content = image.attachment.content;
    return Image.memory(
      Uint8List.fromList(content.bytes),
      width: image.width.toDouble(),
      height: image.height.toDouble(),
      fit: BoxFit.contain,
      gaplessPlayback: true,
      errorBuilder: (_, _, _) => const SizedBox.shrink(),
    );
  }
}

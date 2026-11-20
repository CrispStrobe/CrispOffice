import 'dart:typed_data';

import 'package:quds_mail_core/quds_mail_core.dart';

/// Static text styling. No source HTML or CSS reaches the rendering surface.
final class MailTextRun {
  const MailTextRun({
    required this.start,
    required this.end,
    this.bold = false,
    this.italic = false,
    this.link,
  });
  final int start;
  final int end;
  final bool bold;
  final bool italic;
  final Uri? link;
}

/// A static raster admitted by the reader's byte, format and pixel limits.
final class MailInlineImage {
  const MailInlineImage({
    required this.attachment,
    required this.width,
    required this.height,
  });
  final MailAttachment attachment;
  final int width;
  final int height;
}

/// A bounded inert presentation. Rejection never exposes a truncated success.
final class MailReaderPresentation {
  MailReaderPresentation({
    required this.text,
    required List<MailTextRun> runs,
    required List<MailInlineImage> images,
    required List<MailDiagnostic> diagnostics,
    this.bodyText = '',
    this.rejected = false,
    this.usedHtml = false,
    this.blockedResourceCount = 0,
    List<Uri> remoteImageUrls = const [],
  }) : runs = List.unmodifiable(runs),
       images = List.unmodifiable(images),
       diagnostics = List.unmodifiable(diagnostics),
       remoteImageUrls = List.unmodifiable(remoteImageUrls);
  final String text;

  /// The bounded body projection, without envelope or attachment summaries.
  ///
  /// HTML uses the same inert projection as [text]. Rejected presentations and
  /// presentations constructed without a body projection leave this empty.
  final String bodyText;
  final List<MailTextRun> runs;
  final List<MailInlineImage> images;
  final List<MailDiagnostic> diagnostics;
  final bool rejected;
  final bool usedHtml;
  final int blockedResourceCount;

  /// Approved absolute HTTP(S) sources from unsuppressed image elements only.
  /// Discovery never performs a request or authorizes the host to fetch them.
  final List<Uri> remoteImageUrls;
}

/// Structural dimensions of a static PNG/JPEG attachment, or null.
/// Callers must additionally enforce byte and cumulative pixel budgets.
(int, int)? mailRasterDimensions(MailAttachment attachment) =>
    _rasterDimensions(attachment);

/// A deliberately small HTML-to-static-text projection, not a browser engine.
///
/// It scans bounded input once without constructing a DOM. It supports paragraph
/// and list breaks, bold/italic text, approved-scheme link metadata and local CID
/// PNG/JPEG rasters. All CSS and other attributes are discarded. Active elements
/// and their contents are omitted. Nothing here can issue a resource request.
MailReaderPresentation buildMailPresentation(
  MailParseResult result, {
  MailReadBudget budget = const MailReadBudget(),
  bool preferHtml = true,
  bool externalImagePlaceholders = true,
  List<MailInlineImage> additionalImages = const [],
}) {
  budget.validate();
  final diagnostics = <MailDiagnostic>[...result.diagnostics];
  final message = result.message;
  MailReaderPresentation reject(
    MailDiagnosticCode code,
    String explanation,
    int observed,
    int limit,
  ) {
    diagnostics.add(
      MailDiagnostic(
        code: code,
        message: explanation,
        severity: MailDiagnosticSeverity.error,
        observed: observed,
        limit: limit,
      ),
    );
    return MailReaderPresentation(
      text: '',
      runs: const [],
      images: const [],
      diagnostics: diagnostics,
      rejected: true,
    );
  }

  if ((result.original?.length ?? 0) > budget.maxRawBytes) {
    return reject(
      MailDiagnosticCode.rawLimit,
      'The saved message exceeds this reader mode’s input limit.',
      result.original!.length,
      budget.maxRawBytes,
    );
  }
  if (message == null) {
    return MailReaderPresentation(
      text: '',
      runs: const [],
      images: const [],
      diagnostics: diagnostics,
      rejected: true,
    );
  }
  final attachmentCount = message.attachments.length + additionalImages.length;
  if (attachmentCount > budget.maxAttachments) {
    return reject(
      MailDiagnosticCode.attachmentCountLimit,
      'The attachment count exceeds the reader limit.',
      attachmentCount,
      budget.maxAttachments,
    );
  }
  var headerBytes = 0;
  MailReaderPresentation? admitHeader(String value) {
    final length = _utf8Length(value, budget.maxHeaderFieldBytes);
    if (length > budget.maxHeaderFieldBytes) {
      return reject(
        MailDiagnosticCode.headerFieldLimit,
        'A displayed header exceeds the reader limit.',
        length,
        budget.maxHeaderFieldBytes,
      );
    }
    headerBytes += length;
    if (headerBytes > budget.maxHeaderBytes) {
      return reject(
        MailDiagnosticCode.headerLimit,
        'Displayed headers exceed the reader limit.',
        headerBytes,
        budget.maxHeaderBytes,
      );
    }
    return null;
  }

  final subjectRejected = admitHeader(message.envelope.subject);
  if (subjectRejected != null) return subjectRejected;
  for (final addresses in [
    message.envelope.from,
    message.envelope.to,
    message.envelope.cc,
    message.envelope.bcc,
    message.envelope.replyTo,
  ]) {
    for (final address in addresses) {
      final rejected =
          admitHeader(address.address) ??
          (address.displayName == null
              ? null
              : admitHeader(address.displayName!));
      if (rejected != null) return rejected;
    }
  }
  var decodedBytes = 0;
  for (final attachment in message.attachments.followedBy(
    additionalImages.map((image) => image.attachment),
  )) {
    final nameRejected =
        admitHeader(attachment.displayName) ??
        admitHeader(attachment.mediaType);
    if (nameRejected != null) return nameRejected;
    if (attachment.content.length > budget.maxAttachmentBytes) {
      return reject(
        MailDiagnosticCode.attachmentLimit,
        'An attachment exceeds the reader limit.',
        attachment.content.length,
        budget.maxAttachmentBytes,
      );
    }
    decodedBytes += attachment.content.length;
    if (decodedBytes > budget.maxDecodedBytes) {
      return reject(
        MailDiagnosticCode.decodedLimit,
        'Decoded message content exceeds the reader limit.',
        decodedBytes,
        budget.maxDecodedBytes,
      );
    }
  }
  final body = message.body;
  var bodyBytes = 0;
  for (final text in [body.plainText, body.html]) {
    if (text == null) continue;
    final bytes = _utf8Length(text, budget.maxBodyBytes);
    bodyBytes += bytes;
    if (bodyBytes > budget.maxBodyBytes) {
      return reject(
        MailDiagnosticCode.bodyLimit,
        'Decoded bodies exceed the cumulative reader limit.',
        bodyBytes,
        budget.maxBodyBytes,
      );
    }
    decodedBytes += bytes;
    if (decodedBytes > budget.maxDecodedBytes) {
      return reject(
        MailDiagnosticCode.decodedLimit,
        'Decoded message content exceeds the reader limit.',
        decodedBytes,
        budget.maxDecodedBytes,
      );
    }
  }
  final useHtml = body.html != null && (preferHtml || body.plainText == null);
  final builder = _Projection(
    budget,
    message.attachments,
    externalImagePlaceholders: externalImagePlaceholders,
  );
  try {
    builder.add(
      message.envelope.subject.isEmpty
          ? '(No subject)\n'
          : '${_headerText(message.envelope.subject)}\n',
      bold: true,
    );
    void addresses(String label, List<MailAddress> values) {
      if (values.isEmpty) return;
      builder.add('$label: ', bold: true);
      for (var index = 0; index < values.length; index++) {
        if (index > 0) builder.add(', ');
        final address = values[index];
        final name = address.displayName;
        if (name != null && name.isNotEmpty) {
          builder.add('\u2068${_headerText(name)}\u2069 ');
        }
        builder.add('\u2066${_headerText(address.address)}\u2069');
      }
      builder.add('\n');
    }

    addresses('From', message.envelope.from);
    addresses('To', message.envelope.to);
    addresses('Cc', message.envelope.cc);
    addresses('Bcc', message.envelope.bcc);
    addresses('Reply-To', message.envelope.replyTo);
    final date = message.envelope.sentAt;
    if (date != null) builder.add('Date: ${date.toIso8601String()}\n');
    builder.add('\n');
    final bodyStart = builder.text.length;
    if (useHtml) {
      builder.html(body.html!);
    } else {
      builder.add(body.plainText ?? '(No supported decoded body)');
    }
    final allowedRemotePaths = {
      for (final uri in builder.remoteImageUrls) 'remote:$uri',
    };
    final imagePaths = {
      for (final attachment in message.attachments) attachment.partPath,
    };
    for (final image in additionalImages) {
      final attachment = image.attachment;
      final dimensions = _rasterDimensions(attachment);
      if (!allowedRemotePaths.contains(attachment.partPath) ||
          !imagePaths.add(attachment.partPath) ||
          dimensions == null) {
        return reject(
          MailDiagnosticCode.imageLimit,
          'A remote image is unsupported or does not belong to this projection.',
          additionalImages.length,
          budget.maxAttachments,
        );
      }
      final pixels = dimensions.$1 * dimensions.$2;
      if (pixels > budget.maxImagePixels - builder.pixels) {
        return reject(
          MailDiagnosticCode.imageLimit,
          'Inline and remote image pixels exceed the rendering limit.',
          builder.pixels + pixels,
          budget.maxImagePixels,
        );
      }
      builder.pixels += pixels;
      builder.images.add(
        MailInlineImage(
          attachment: attachment,
          width: dimensions.$1,
          height: dimensions.$2,
        ),
      );
    }
    final bodyEnd = builder.text.length;
    if (message.attachments.isNotEmpty) {
      builder.add('\nAttachments:\n', bold: true);
      for (final attachment in message.attachments) {
        builder.add(
          '${_headerText(attachment.displayName)} · '
          '${_headerText(attachment.mediaType)} · ${attachment.observedSize} bytes\n',
        );
      }
    }
    if (builder.blocked > 0) {
      diagnostics.add(
        const MailDiagnostic(
          code: MailDiagnosticCode.renderLimit,
          severity: MailDiagnosticSeverity.information,
          message: 'Active markup and external resources were blocked.',
        ),
      );
    }
    diagnostics.addAll(builder.diagnostics);
    final text = builder.text.toString();
    return MailReaderPresentation(
      text: text,
      bodyText: text.substring(bodyStart, bodyEnd),
      runs: builder.runs,
      images: builder.images,
      diagnostics: diagnostics,
      usedHtml: useHtml,
      blockedResourceCount: builder.blocked,
      remoteImageUrls: builder.remoteImageUrls.toList(growable: false),
    );
  } on _AdmissionFailure catch (failure) {
    return reject(
      failure.code,
      failure.message,
      failure.observed,
      failure.limit,
    );
  }
}

/// Projects only a decoded body for text quotation, without inspecting headers,
/// attachment names or attachment bytes. No image can be loaded or fetched.
///
/// Plain text is preferred by default, including an explicitly empty string.
/// HTML is used only when plain text is absent or [preferHtml] is true. Limits
/// apply to the selected alternative's UTF-8 input, output, nodes and depth;
/// the unselected alternative is not scanned. HTML uses the reader's inert
/// subset, with generic notices for omitted images. Incomplete markup rejects
/// the entire quotation instead of exposing a truncated successful prefix.
///
/// This API receives decoded content, not a MIME parse result. Callers remain
/// responsible for checking the source parser's status and diagnostics before
/// treating a quote as complete. It does not certify HTML/browser fidelity.
MailReaderPresentation buildMailBodyPresentation(
  MailBody body, {
  MailReadBudget budget = const MailReadBudget(),
  bool preferHtml = false,
}) {
  budget.validate();
  final useHtml = body.html != null && (preferHtml || body.plainText == null);
  final source = useHtml ? body.html : body.plainText;
  MailReaderPresentation reject(
    MailDiagnosticCode code,
    String explanation, {
    int? observed,
    int? limit,
  }) => MailReaderPresentation(
    text: '',
    runs: const [],
    images: const [],
    diagnostics: [
      MailDiagnostic(
        code: code,
        message: explanation,
        severity: MailDiagnosticSeverity.error,
        observed: observed,
        limit: limit,
      ),
    ],
    rejected: true,
    usedHtml: useHtml,
  );

  if (source == null) {
    return reject(
      MailDiagnosticCode.malformedMime,
      'No decoded message body is available.',
    );
  }
  final inputLimit = budget.maxBodyBytes < budget.maxDecodedBytes
      ? budget.maxBodyBytes
      : budget.maxDecodedBytes;
  final inputBytes = _utf8Length(source, inputLimit);
  if (inputBytes > budget.maxBodyBytes) {
    return reject(
      MailDiagnosticCode.bodyLimit,
      'The selected body exceeds the quotation input limit.',
      observed: inputBytes,
      limit: budget.maxBodyBytes,
    );
  }
  if (inputBytes > budget.maxDecodedBytes) {
    return reject(
      MailDiagnosticCode.decodedLimit,
      'The selected body exceeds the decoded content limit.',
      observed: inputBytes,
      limit: budget.maxDecodedBytes,
    );
  }

  final builder = _Projection(budget, const [], strictHtml: true);
  try {
    if (useHtml) {
      builder.html(source);
    } else {
      builder.add(source);
    }
    final text = builder.text.toString();
    return MailReaderPresentation(
      text: text,
      bodyText: text,
      runs: builder.runs,
      images: const [],
      diagnostics: [
        ...builder.diagnostics,
        if (builder.blocked > 0)
          const MailDiagnostic(
            code: MailDiagnosticCode.renderLimit,
            severity: MailDiagnosticSeverity.information,
            message: 'Active markup and external resources were blocked.',
          ),
      ],
      usedHtml: useHtml,
      blockedResourceCount: builder.blocked,
    );
  } on _AdmissionFailure catch (failure) {
    return reject(
      failure.code,
      failure.message,
      observed: failure.observed,
      limit: failure.limit,
    );
  } on _IncompleteHtml catch (failure) {
    return reject(MailDiagnosticCode.malformedMime, failure.message);
  }
}

String _headerText(String value) =>
    value.replaceAll(RegExp(r'[\x00-\x1f\x7f\u202a-\u202e\u2066-\u2069]'), ' ');

int _utf8Length(String value, int limit) {
  var count = 0;
  for (var i = 0; i < value.length; i++) {
    final unit = value.codeUnitAt(i);
    if (unit < 0x80) {
      count++;
    } else if (unit < 0x800) {
      count += 2;
    } else if (unit >= 0xd800 &&
        unit <= 0xdbff &&
        i + 1 < value.length &&
        value.codeUnitAt(i + 1) >= 0xdc00 &&
        value.codeUnitAt(i + 1) <= 0xdfff) {
      count += 4;
      i++;
    } else {
      count += 3;
    }
    if (count > limit) return count;
  }
  return count;
}

final class _AdmissionFailure implements Exception {
  const _AdmissionFailure(this.code, this.message, this.observed, this.limit);
  final MailDiagnosticCode code;
  final String message;
  final int observed;
  final int limit;
}

final class _IncompleteHtml implements Exception {
  const _IncompleteHtml(this.message);
  final String message;
}

final class _Tag {
  const _Tag(
    this.name, {
    this.bold = false,
    this.italic = false,
    this.link,
    this.suppressed = false,
  });
  final String name;
  final bool bold;
  final bool italic;
  final Uri? link;
  final bool suppressed;
}

const _voidTags = {
  'area',
  'base',
  'br',
  'col',
  'embed',
  'hr',
  'img',
  'input',
  'link',
  'meta',
  'param',
  'source',
  'track',
  'wbr',
};
const _blockedTags = {
  'script',
  'style',
  'form',
  'iframe',
  'object',
  'embed',
  'svg',
  'math',
  'audio',
  'video',
  'canvas',
  'template',
  'noscript',
  'textarea',
  'select',
  'button',
  'input',
  'link',
  'base',
  'meta',
  'frameset',
  'frame',
  'applet',
  'portal',
  'xmp',
  'plaintext',
};
const _blockTags = {
  'p',
  'div',
  'section',
  'article',
  'header',
  'footer',
  'h1',
  'h2',
  'h3',
  'h4',
  'h5',
  'h6',
  'ul',
  'ol',
  'li',
  'blockquote',
  'pre',
  'tr',
  'table',
  'dl',
  'dt',
  'dd',
};

final class _Projection {
  _Projection(
    this.budget,
    this.attachments, {
    this.strictHtml = false,
    this.externalImagePlaceholders = true,
  });
  final bool strictHtml;
  final bool externalImagePlaceholders;
  final MailReadBudget budget;
  final List<MailAttachment> attachments;
  final StringBuffer text = StringBuffer();
  final List<MailTextRun> runs = [];
  final List<MailInlineImage> images = [];
  final List<MailDiagnostic> diagnostics = [];
  final List<_Tag> stack = [];
  final Set<String> shownCids = {};
  final Set<Uri> remoteImageUrls = {};
  int bytes = 0;
  int nodes = 0;
  int blocked = 0;
  int pixels = 0;
  bool newline = true;
  bool trailingSpace = false;

  void add(String value, {bool? bold, bool? italic, Uri? link}) {
    if (value.isEmpty) return;
    bytes += _utf8Length(value, budget.maxRenderTextBytes);
    if (bytes > budget.maxRenderTextBytes) {
      throw _AdmissionFailure(
        MailDiagnosticCode.renderLimit,
        'Decoded text exceeds the rendering limit.',
        bytes,
        budget.maxRenderTextBytes,
      );
    }
    final start = text.length;
    text.write(value);
    final tag = stack.isEmpty ? null : stack.last;
    runs.add(
      MailTextRun(
        start: start,
        end: text.length,
        bold: bold ?? tag?.bold ?? false,
        italic: italic ?? tag?.italic ?? false,
        link: link ?? tag?.link,
      ),
    );
    newline = value.endsWith('\n');
    trailingSpace = value.endsWith(' ');
  }

  void node() {
    nodes++;
    if (nodes > budget.maxHtmlNodes) {
      throw _AdmissionFailure(
        MailDiagnosticCode.renderLimit,
        'HTML exceeds the rendering node limit.',
        nodes,
        budget.maxHtmlNodes,
      );
    }
  }

  void line() {
    if (!newline) add('\n');
  }

  /// HTML collapses source indentation and repeated whitespace. Without this,
  /// the padded `div`/table wrappers used by transactional mail become dozens
  /// of visually empty lines.
  void addHtmlText(String value) {
    var normalized = value.replaceAll(RegExp(r'[\t\r\n\f ]+'), ' ');
    // Collapse across inline element boundaries without discarding meaningful
    // word separation or nonbreaking spaces. Block indentation remains empty.
    if ((newline || trailingSpace) && normalized.startsWith(' ')) {
      normalized = normalized.substring(1);
    }
    add(normalized);
  }

  void incompleteHtml(String message) {
    if (strictHtml) throw _IncompleteHtml(message);
  }

  void html(String source) {
    var index = 0;
    while (index < source.length) {
      node();
      if (source.codeUnitAt(index) != 60) {
        final next = source.indexOf('<', index);
        final end = next < 0 ? source.length : next;
        if (!stack.any((tag) => tag.suppressed)) {
          addHtmlText(_entities(source.substring(index, end)));
        }
        index = end;
        continue;
      }
      if (source.startsWith('<!--', index)) {
        final end = source.indexOf('-->', index + 4);
        if (end < 0) {
          incompleteHtml(
            'Unterminated HTML comment prevents complete quotation.',
          );
          blocked++;
          break;
        }
        index = end + 3;
        continue;
      }
      var end = index + 1;
      var quote = 0;
      for (; end < source.length; end++) {
        final char = source.codeUnitAt(end);
        if (quote != 0) {
          if (char == quote) quote = 0;
        } else if (char == 34 || char == 39) {
          quote = char;
        } else if (char == 62) {
          break;
        }
      }
      if (end == source.length) {
        incompleteHtml('Unterminated HTML markup prevents complete quotation.');
        diagnostics.add(
          const MailDiagnostic(
            code: MailDiagnosticCode.malformedMime,
            message: 'Unterminated HTML markup was omitted.',
          ),
        );
        break;
      }
      final token = source.substring(index + 1, end).trim();
      index = end + 1;
      if (token.isEmpty) {
        incompleteHtml('Empty HTML markup prevents complete quotation.');
      }
      if (token.isEmpty || token.startsWith('!') || token.startsWith('?')) {
        blocked++;
        continue;
      }
      final closing = token.startsWith('/');
      final nameMatch = RegExp(
        r'^/?\s*([a-zA-Z][a-zA-Z0-9:-]*)',
      ).firstMatch(token);
      if (nameMatch == null) {
        incompleteHtml('Unsupported HTML markup prevents complete quotation.');
        add('<');
        continue;
      }
      final name = nameMatch.group(1)!.toLowerCase();
      if (closing) {
        final position = stack.lastIndexWhere((tag) => tag.name == name);
        if (position >= 0) stack.removeRange(position, stack.length);
        if (_blockTags.contains(name) && !stack.any((tag) => tag.suppressed)) {
          line();
        }
        continue;
      }
      final suppressed =
          stack.any((tag) => tag.suppressed) || _blockedTags.contains(name);
      if (_blockedTags.contains(name)) blocked++;
      final attributes = _attributes(token, nameMatch.end);
      if (name == 'plaintext') {
        incompleteHtml(
          'Unsupported HTML plaintext prevents complete quotation.',
        );
        break;
      }
      if (name == 'script' ||
          name == 'style' ||
          name == 'xmp' ||
          name == 'iframe') {
        // A raw-text body is skipped in one bounded scan, including fake tags.
        final matches = RegExp(
          '</\\s*$name\\s*>',
          caseSensitive: false,
        ).allMatches(source, index).iterator;
        if (matches.moveNext()) {
          index = matches.current.end;
        } else {
          incompleteHtml(
            'Unterminated active HTML prevents complete quotation.',
          );
          index = source.length;
        }
        continue;
      }
      if (!suppressed) {
        if (_blockTags.contains(name) || name == 'br' || name == 'hr') line();
        if (name == 'li') add('• ');
        if (name == 'td' || name == 'th') {
          if (!newline) add('  ');
        }
        if (name == 'img') _image(attributes['src'], attributes['alt']);
      }
      if (!_voidTags.contains(name) && !token.endsWith('/')) {
        if (stack.length >= budget.maxHtmlDepth) {
          throw _AdmissionFailure(
            MailDiagnosticCode.renderLimit,
            'HTML exceeds the rendering nesting limit.',
            stack.length + 1,
            budget.maxHtmlDepth,
          );
        }
        final parent = stack.isEmpty ? null : stack.last;
        final href = name == 'a' ? _link(attributes['href']) : parent?.link;
        stack.add(
          _Tag(
            name,
            suppressed: suppressed,
            bold:
                (parent?.bold ?? false) ||
                name == 'b' ||
                name == 'strong' ||
                RegExp(r'^h[1-6]$').hasMatch(name),
            italic: (parent?.italic ?? false) || name == 'i' || name == 'em',
            link: href,
          ),
        );
      }
    }
    if (stack.any((tag) => tag.suppressed)) {
      incompleteHtml('Unterminated active HTML prevents complete quotation.');
    }
  }

  Map<String, String> _attributes(String token, int start) {
    final result = <String, String>{};
    var index = start;
    while (index < token.length) {
      while (index < token.length && _space(token.codeUnitAt(index))) {
        index++;
      }
      if (index >= token.length || token[index] == '/') break;
      final nameStart = index;
      while (index < token.length &&
          !_space(token.codeUnitAt(index)) &&
          token[index] != '=' &&
          token[index] != '/') {
        index++;
      }
      if (index == nameStart) {
        index++;
        continue;
      }
      node();
      final name = token.substring(nameStart, index).toLowerCase();
      while (index < token.length && _space(token.codeUnitAt(index))) {
        index++;
      }
      var value = '';
      if (index < token.length && token[index] == '=') {
        index++;
        while (index < token.length && _space(token.codeUnitAt(index))) {
          index++;
        }
        if (index < token.length &&
            (token[index] == '"' || token[index] == "'")) {
          final quote = token[index++];
          final begin = index;
          while (index < token.length && token[index] != quote) {
            index++;
          }
          value = token.substring(begin, index);
          if (index < token.length) index++;
        } else {
          final begin = index;
          while (index < token.length && !_space(token.codeUnitAt(index))) {
            index++;
          }
          value = token.substring(begin, index);
        }
      }
      if (name == 'href' || name == 'src' || name == 'alt') {
        result.putIfAbsent(name, () => _entities(value));
      } else if (name == 'style' ||
          name == 'srcset' ||
          name.startsWith('on') ||
          name == 'background' ||
          name == 'poster' ||
          name == 'data' ||
          name == 'xlink:href' ||
          name == 'formaction') {
        blocked++;
      }
    }
    return result;
  }

  Uri? _link(String? value) {
    if (value == null) return null;
    final uri = approvedMailLink(value);
    if (uri == null) blocked++;
    return uri;
  }

  void _image(String? source, String? alt) {
    if (source == null || !source.toLowerCase().startsWith('cid:')) {
      blocked++;
      final uri = source == null ? null : approvedMailLink(source);
      if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) {
        remoteImageUrls.add(uri);
      }
      if (externalImagePlaceholders) {
        add(
          alt == null || alt.isEmpty
              ? '[External image blocked]'
              : '[External image blocked: $alt]',
        );
      }
      return;
    }
    String cid;
    try {
      cid = Uri.decodeComponent(source.substring(4));
    } on FormatException {
      blocked++;
      return;
    }
    final matches = attachments.where((part) => part.contentId == cid).toList();
    if (matches.length != 1) {
      diagnostics.add(
        const MailDiagnostic(
          code: MailDiagnosticCode.malformedMime,
          message: 'An inline image identifier is missing or ambiguous.',
        ),
      );
      add('[Inline image unavailable]');
      return;
    }
    final attachment = matches.single;
    final dimensions = _rasterDimensions(attachment);
    if (dimensions == null) {
      diagnostics.add(
        MailDiagnostic(
          code: MailDiagnosticCode.imageLimit,
          message:
              'Only validated static PNG and JPEG inline images are supported.',
          partPath: attachment.partPath,
        ),
      );
      add('[Unsupported inline image]');
      return;
    }
    if (!shownCids.contains(cid)) {
      final imagePixels = dimensions.$1 * dimensions.$2;
      if (imagePixels > budget.maxImagePixels - pixels) {
        diagnostics.add(
          MailDiagnostic(
            code: MailDiagnosticCode.imageLimit,
            message: 'Inline image pixels exceed the rendering limit.',
            partPath: attachment.partPath,
            observed: pixels + imagePixels,
            limit: budget.maxImagePixels,
          ),
        );
        add('[Inline image exceeds pixel limit]');
        return;
      }
      shownCids.add(cid);
      pixels += imagePixels;
      images.add(
        MailInlineImage(
          attachment: attachment,
          width: dimensions.$1,
          height: dimensions.$2,
        ),
      );
    }
    add('[Inline image: ${_headerText(attachment.displayName)}]');
  }
}

bool _space(int value) =>
    value == 32 || value == 9 || value == 10 || value == 13 || value == 12;

/// Only explicit absolute web/mail links are exposed to the host policy.
/// Redirect and destination authorization remain the host's responsibility.
Uri? approvedMailLink(String value) {
  if (value.length > 8192 ||
      RegExp(r'[\x00-\x20\x7f\u202a-\u202e\u2066-\u2069]').hasMatch(value)) {
    return null;
  }
  final uri = Uri.tryParse(value);
  if (uri == null || uri.userInfo.isNotEmpty) return null;
  if ((uri.scheme == 'https' || uri.scheme == 'http') && uri.host.isNotEmpty) {
    return uri;
  }
  if (uri.scheme == 'mailto' && uri.path.isNotEmpty) return uri;
  return null;
}

String _entities(String source) => source.replaceAllMapped(
  RegExp(r'&(#x[0-9a-fA-F]{1,6}|#[0-9]{1,7}|[a-zA-Z]{2,12});'),
  (match) {
    final entity = match.group(1)!;
    const named = <String, String>{
      'amp': '&',
      'lt': '<',
      'gt': '>',
      'quot': '"',
      'apos': "'",
      'nbsp': '\u00a0',
      'copy': '©',
      'reg': '®',
      'ndash': '–',
      'mdash': '—',
      'hellip': '…',
      'laquo': '«',
      'raquo': '»',
      'bull': '•',
    };
    if (!entity.startsWith('#')) return named[entity] ?? match.group(0)!;
    final hex = entity.startsWith('#x');
    final point = int.tryParse(
      entity.substring(hex ? 2 : 1),
      radix: hex ? 16 : 10,
    );
    if (point == null ||
        point == 0 ||
        point > 0x10ffff ||
        (point >= 0xd800 && point <= 0xdfff)) {
      return '\uFFFD';
    }
    return String.fromCharCode(point);
  },
);

(int, int)? _rasterDimensions(MailAttachment attachment) {
  final data = attachment.content.bytes;
  if (attachment.mediaType.toLowerCase() == 'image/png') {
    const signature = [137, 80, 78, 71, 13, 10, 26, 10];
    if (data.length < 33) return null;
    for (var i = 0; i < signature.length; i++) {
      if (data[i] != signature[i]) return null;
    }
    final view = ByteData.sublistView(data);
    if (view.getUint32(8) != 13 ||
        String.fromCharCodes(data.sublist(12, 16)) != 'IHDR') {
      return null;
    }
    final width = view.getUint32(16), height = view.getUint32(20);
    if (width == 0 || height == 0 || width > 32768 || height > 32768) {
      return null;
    }
    var offset = 8;
    var ended = false;
    var headers = 0;
    var hasData = false;
    while (offset + 12 <= data.length) {
      final length = view.getUint32(offset);
      if (length > data.length - offset - 12) return null;
      final type = String.fromCharCodes(data.sublist(offset + 4, offset + 8));
      if (type == 'acTL') return null;
      if (type == 'IHDR' && ++headers != 1) return null;
      if (type == 'IDAT') hasData = true;
      offset += length + 12;
      if (type == 'IEND') {
        ended = length == 0 && offset == data.length;
        break;
      }
    }
    return ended && hasData ? (width, height) : null;
  }
  if (attachment.mediaType.toLowerCase() == 'image/jpeg') {
    if (data.length < 4 || data[0] != 0xff || data[1] != 0xd8) return null;
    var index = 2;
    var entropy = false;
    (int, int)? dimensions;
    while (index < data.length) {
      if (entropy) {
        while (index < data.length && data[index] != 0xff) {
          index++;
        }
      }
      if (index >= data.length || data[index++] != 0xff) return null;
      while (index < data.length && data[index] == 0xff) {
        index++;
      }
      if (index >= data.length) return null;
      final marker = data[index++];
      if (entropy && (marker == 0 || marker >= 0xd0 && marker <= 0xd7)) {
        continue;
      }
      entropy = false;
      if (marker == 0xd9) return index == data.length ? dimensions : null;
      if (marker == 0xd8 || marker == 0) return null;
      if (marker == 0x01 || marker >= 0xd0 && marker <= 0xd7) continue;
      if (index + 2 > data.length) return null;
      final length = (data[index] << 8) | data[index + 1];
      if (length < 2 || length > data.length - index) return null;
      if (marker >= 0xc0 &&
          marker <= 0xcf &&
          !{0xc4, 0xc8, 0xcc}.contains(marker)) {
        if (!{0xc0, 0xc1, 0xc2}.contains(marker) ||
            dimensions != null ||
            length < 8) {
          return null;
        }
        final height = (data[index + 3] << 8) | data[index + 4];
        final width = (data[index + 5] << 8) | data[index + 6];
        if (width == 0 || height == 0 || width > 32768 || height > 32768) {
          return null;
        }
        dimensions = (width, height);
      }
      if (marker == 0xda) {
        if (dimensions == null) return null;
        entropy = true;
      }
      index += length;
    }
  }
  return null;
}

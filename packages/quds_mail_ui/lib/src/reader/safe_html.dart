import 'dart:convert';

import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:quds_mail_core/quds_mail_core.dart';

import 'presentation.dart';

/// Maximum sanitized markup retained for one reader view. The MIME body budget
/// has already bounded the source; this second bound limits DOM/attribute blowup.
const int maxSafeMailHtmlBytes = 2 * 1024 * 1024;

final class MailSafeHtml {
  const MailSafeHtml({
    required this.html,
    required this.blocked,
    required this.diagnostics,
  });

  /// Sanitized fragment, or null when the source cannot be rendered safely.
  final String? html;
  final int blocked;
  final List<MailDiagnostic> diagnostics;
}

/// Converts untrusted HTML mail into an inert, bounded fragment for the Flutter
/// HTML renderer. It preserves common layout/table/typography markup and inline
/// styles, but removes active elements, scripts, forms, external CSS resources,
/// event handlers and all direct image sources.
///
/// Images are emitted as `data-mail-cid` or `data-mail-remote` attributes and
/// are rendered only by the host widget from already-admitted bytes. No HTML
/// renderer can issue a network request from this fragment.
MailSafeHtml sanitizeMailHtml(String source, {required MailReadBudget budget}) {
  final diagnostics = <MailDiagnostic>[];
  var blocked = 0;
  try {
    final document = html_parser.parse(source);
    final styles = <String>[];
    for (final element in document.querySelectorAll('style').take(64)) {
      final css = _safeCss(element.text);
      if (css == null || css.trim().isEmpty) {
        blocked++;
        continue;
      }
      styles.add(css);
    }
    final output = StringBuffer('<style>');
    output.write(_baseCss);
    if (styles.isNotEmpty) {
      output.write('\n');
      output.write(styles.join('\n'));
    }
    output.write('</style>');
    var nodes = 0;
    var outputBytes = output.length;
    void visit(dom.Node node, int depth) {
      if (++nodes > budget.maxHtmlNodes) {
        throw const _SafeHtmlReject(
          'HTML exceeds the formatted-view node limit.',
        );
      }
      if (depth > budget.maxHtmlDepth) {
        throw const _SafeHtmlReject(
          'HTML exceeds the formatted-view nesting limit.',
        );
      }
      if (node is dom.Text) {
        final escaped = const HtmlEscape(
          HtmlEscapeMode.element,
        ).convert(node.data);
        output.write(escaped);
        outputBytes += escaped.length;
      } else if (node is dom.Element) {
        final tag = node.localName?.toLowerCase();
        if (tag == null || tag.isEmpty) return;
        if (_discarded.contains(tag)) {
          blocked++;
          return;
        }
        if (tag == 'style' || tag == 'link' || tag == 'meta') {
          blocked++;
          return;
        }
        if (!_allowed.contains(tag)) {
          // Unknown wrappers are unwrapped so their text is not lost, while
          // active/blocked elements above are discarded with their contents.
          for (final child in node.nodes) {
            visit(child, depth + 1);
          }
          return;
        }
        if (tag == 'img') {
          final image = _safeImage(node);
          if (image == null) {
            blocked++;
            return;
          }
          output.write(image);
          outputBytes += image.length;
          if (outputBytes > maxSafeMailHtmlBytes) {
            throw const _SafeHtmlReject(
              'Formatted HTML exceeds the reader size limit.',
            );
          }
          return;
        }
        final attributes = _safeAttributes(node);
        output.write('<$tag');
        for (final entry in attributes.entries) {
          output.write(' ${entry.key}="');
          output.write(
            const HtmlEscape(HtmlEscapeMode.attribute).convert(entry.value),
          );
          output.write('"');
        }
        output.write('>');
        if (!_void.contains(tag)) {
          for (final child in node.nodes) {
            visit(child, depth + 1);
          }
          output.write('</$tag>');
        }
        outputBytes = output.length;
        if (outputBytes > maxSafeMailHtmlBytes) {
          throw const _SafeHtmlReject(
            'Formatted HTML exceeds the reader size limit.',
          );
        }
      }
    }

    final root = document.body ?? document.documentElement;
    if (root == null) {
      return const MailSafeHtml(html: null, blocked: 0, diagnostics: []);
    }
    for (final child in root.nodes) {
      visit(child, 0);
    }
    return MailSafeHtml(
      html: output.toString(),
      blocked: blocked,
      diagnostics: diagnostics,
    );
  } on _SafeHtmlReject catch (error) {
    diagnostics.add(
      MailDiagnostic(
        code: MailDiagnosticCode.renderLimit,
        message: error.message,
        severity: MailDiagnosticSeverity.error,
      ),
    );
    return MailSafeHtml(html: null, blocked: blocked, diagnostics: diagnostics);
  } on Object {
    diagnostics.add(
      const MailDiagnostic(
        code: MailDiagnosticCode.malformedMime,
        message: 'The formatted HTML could not be safely rendered.',
        severity: MailDiagnosticSeverity.error,
      ),
    );
    return MailSafeHtml(html: null, blocked: blocked, diagnostics: diagnostics);
  }
}

final class _SafeHtmlReject implements Exception {
  const _SafeHtmlReject(this.message);
  final String message;
}

const _baseCss = '''
html,body{max-width:100%;overflow-x:hidden}
table{width:100%!important;max-width:100%;table-layout:auto}
td,th{word-break:normal;overflow-wrap:normal;vertical-align:top}
img{max-width:100%;height:auto}
''';

const _discarded = <String>{
  'script',
  'style',
  'head',
  'title',
  'iframe',
  'object',
  'embed',
  'form',
  'input',
  'button',
  'select',
  'textarea',
  'option',
  'svg',
  'math',
  'template',
  'noscript',
  'audio',
  'video',
  'canvas',
  'source',
  'track',
  'applet',
  'frame',
  'frameset',
  'portal',
  'xmp',
  'plaintext',
  'base',
  'link',
  'meta',
};

const _allowed = <String>{
  'a',
  'abbr',
  'address',
  'article',
  'aside',
  'b',
  'blockquote',
  'br',
  'caption',
  'center',
  'cite',
  'code',
  'col',
  'colgroup',
  'dd',
  'del',
  'details',
  'div',
  'dl',
  'dt',
  'em',
  'figcaption',
  'figure',
  'font',
  'footer',
  'h1',
  'h2',
  'h3',
  'h4',
  'h5',
  'h6',
  'header',
  'hr',
  'i',
  'img',
  'ins',
  'kbd',
  'li',
  'main',
  'mark',
  'ol',
  'p',
  'pre',
  'q',
  's',
  'samp',
  'section',
  'small',
  'span',
  'strike',
  'strong',
  'sub',
  'summary',
  'sup',
  'table',
  'tbody',
  'td',
  'tfoot',
  'th',
  'thead',
  'tr',
  'u',
  'ul',
  'var',
};

const _void = <String>{'br', 'hr', 'img', 'col'};

final _safeToken = RegExp(r'^[A-Za-z0-9_. -]{1,256}$');
final _safeColor = RegExp(r'^[#A-Za-z0-9(),.% -]{1,64}$');
final _safeDimension = RegExp(
  r'^(?:[0-9]{1,5}(?:px|pt|em|rem|%)?|[0-9]{1,3}%)$',
);

Map<String, String> _safeAttributes(dom.Element element) {
  final result = <String, String>{};
  for (final entry in element.attributes.entries) {
    final name = entry.key.toString().toLowerCase();
    if (name.startsWith('on') ||
        const {
          'srcset',
          'background',
          'poster',
          'data',
          'formaction',
          'action',
          'method',
          'xmlns',
        }.contains(name)) {
      continue;
    }
    final value = entry.value;
    switch (name) {
      case 'href':
        final uri = approvedMailLink(value);
        if (uri != null) result[name] = uri.toString();
      case 'style':
        final css = _safeCss(value);
        if (css != null && css.isNotEmpty) result[name] = css;
      case 'class':
      case 'id':
        if (_safeToken.hasMatch(value)) result[name] = value;
      case 'dir':
        if (const {'ltr', 'rtl', 'auto'}.contains(value.toLowerCase())) {
          result[name] = value.toLowerCase();
        }
      case 'lang':
        if (RegExp(r'^[A-Za-z0-9-]{1,32}$').hasMatch(value)) {
          result[name] = value;
        }
      case 'align':
      case 'valign':
        if (const {
          'left',
          'right',
          'center',
          'justify',
          'top',
          'middle',
          'bottom',
          'baseline',
        }.contains(value.toLowerCase())) {
          result[name] = value.toLowerCase();
        }
      case 'width':
      case 'height':
        if (_safeDimension.hasMatch(value)) result[name] = value;
      case 'colspan':
      case 'rowspan':
        final number = int.tryParse(value);
        if (number != null && number >= 1 && number <= 1000) {
          result[name] = '$number';
        }
      case 'border':
      case 'cellpadding':
      case 'cellspacing':
      case 'size':
        final number = int.tryParse(value);
        if (number != null && number >= 0 && number <= 1000) {
          result[name] = '$number';
        }
      case 'bgcolor':
      case 'color':
      case 'face':
        if (_safeColor.hasMatch(value)) result[name] = value;
      case 'title':
      case 'alt':
      case 'summary':
      case 'role':
      case 'aria-label':
        result[name] = value.length > 1024 ? value.substring(0, 1024) : value;
      default:
        if (name.startsWith('aria-') && value.length <= 1024) {
          result[name] = value;
        }
    }
  }
  return result;
}

String? _safeImage(dom.Element element) {
  final alt = element.attributes['alt']?.trim();
  final title = element.attributes['title']?.trim();
  final output = StringBuffer('<img');
  final src = element.attributes['src']?.trim();
  if (src != null && src.toLowerCase().startsWith('cid:')) {
    output.write(' data-mail-cid="');
    output.write(
      const HtmlEscape(HtmlEscapeMode.attribute).convert(src.substring(4)),
    );
    output.write('"');
  } else {
    final uri = src == null ? null : approvedMailLink(src);
    if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) {
      output.write(' data-mail-remote="');
      output.write(const HtmlEscape(HtmlEscapeMode.attribute).convert('$uri'));
      output.write('"');
    } else {
      output.write(' data-mail-blocked="1"');
    }
  }
  if (alt != null && alt.isNotEmpty) {
    output.write(' alt="');
    output.write(const HtmlEscape(HtmlEscapeMode.attribute).convert(alt));
    output.write('"');
  }
  if (title != null && title.isNotEmpty) {
    output.write(' title="');
    output.write(const HtmlEscape(HtmlEscapeMode.attribute).convert(title));
    output.write('"');
  }
  for (final name in const ['width', 'height']) {
    final value = element.attributes[name];
    if (value != null && _safeDimension.hasMatch(value)) {
      output.write(' $name="');
      output.write(const HtmlEscape(HtmlEscapeMode.attribute).convert(value));
      output.write('"');
    }
  }
  output.write('>');
  return output.toString();
}

String? _safeCss(String source) {
  if (source.isEmpty || source.length > 64 * 1024) return null;
  final lower = source.toLowerCase();
  if (const {
    'url(',
    '@import',
    '@font-face',
    'expression(',
    'behavior:',
    '-moz-binding',
    'javascript:',
    'vbscript:',
    'data:',
  }.any(lower.contains)) {
    return null;
  }
  // Positioning is unnecessary in a mail body and can create misleading
  // overlays inside the reader viewport.
  var value = source.replaceAll(
    RegExp(r'(^|;)\s*(position|z-index)\s*:[^;]*', caseSensitive: false),
    '',
  );
  value = value.trim();
  return value.isEmpty ? null : value;
}

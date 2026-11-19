/// A bounded query language for the local mail archive.
///
/// A word, a quoted phrase, or a word ending in `*` is a search term. Terms
/// separated by whitespace (or uppercase AND) must all match. Uppercase OR,
/// parentheses, unary `-`/NOT and `[one two]` alternatives are supported. Field
/// names are case-insensitive: subject, from, to, cc, bcc, bcontent, acontent,
/// attachment. Other words, including lowercase "and", are literal terms.
///
/// This is a deliberately explicit subset of MailStore search. Leading/infix
/// wildcards, `?`, and wildcards in phrases are rejected. Matching uses SQLite's
/// Unicode FTS tokenizer, so punctuation separates tokens and is not a byte or
/// substring comparison. Each user term becomes a bound, quoted FTS literal;
/// SQL structure and FTS column names always come from this implementation.
final class MailArchiveQuery {
  MailArchiveQuery._(this.predicateSql, List<String> parameters, this.termCount)
    : parameters = List.unmodifiable(parameters);

  factory MailArchiveQuery.parse(
    String input, {
    int maxCodeUnits = 1024,
    int maxTerms = 32,
    int maxDepth = 8,
  }) {
    if (maxCodeUnits < 1 ||
        maxCodeUnits > 65536 ||
        maxTerms < 1 ||
        maxTerms > 256 ||
        maxDepth < 1 ||
        maxDepth > 32) {
      throw const MailArchiveQueryException(
        MailArchiveQueryError.invalidLimits,
        0,
      );
    }
    if (input.length > maxCodeUnits) {
      throw MailArchiveQueryException(
        MailArchiveQueryError.queryTooLong,
        maxCodeUnits,
      );
    }
    final parser = _QueryParser(input, maxTerms: maxTerms, maxDepth: maxDepth);
    final expression = parser.parse();
    if (expression == null) return MailArchiveQuery._('1', const [], 0);
    final parameters = <String>[];
    final sql = expression.compile(parameters);
    return MailArchiveQuery._(sql, parameters, parser.termCount);
  }

  /// Combine this predicate with other bound filters on `archive_items AS a`.
  /// The archive FTS table must be named `archive_fts`, with `id UNINDEXED`.
  final String predicateSql;

  /// Bind these arguments in their existing order before any later filters.
  final List<String> parameters;
  final int termCount;
  bool get isEmpty => termCount == 0;
}

enum MailArchiveQueryError {
  invalidLimits,
  queryTooLong,
  tooManyTerms,
  tooDeep,
  invalidCharacter,
  unexpectedToken,
  unclosedQuote,
  unclosedGroup,
  emptyTerm,
  missingValue,
  unknownField,
  unsupportedWildcard,
  invalidEscape,
}

/// Safe to display or log: neither the query nor any message content is kept.
final class MailArchiveQueryException implements Exception {
  const MailArchiveQueryException(this.code, this.offset);

  final MailArchiveQueryError code;

  /// Zero-based UTF-16 code-unit offset, suitable for a Dart text selection.
  final int offset;

  @override
  String toString() =>
      'MailArchiveQueryException(${code.name}, offset=$offset)';
}

enum _Kind {
  word,
  phrase,
  colon,
  leftParen,
  rightParen,
  leftBracket,
  rightBracket,
  minus,
  and,
  or,
  not,
  end,
}

final class _Token {
  const _Token(this.kind, this.value, this.offset, this.end);

  final _Kind kind;
  final String value;
  final int offset;
  final int end;
}

const _fields = <String, String>{
  'subject': 'subject',
  'from': 'sender',
  'to': 'recipients_to',
  'cc': 'recipients_cc',
  'bcc': 'recipients_bcc',
  'bcontent': 'body',
  'acontent': 'attachment_text',
  'attachment': 'attachment_names',
};

bool _whitespace(int unit) =>
    unit == 0x20 || unit == 0x09 || unit == 0x0a || unit == 0x0d;

final class _QueryLexer {
  _QueryLexer(this.input);
  final String input;
  int offset = 0;

  List<_Token> scan() {
    final result = <_Token>[];
    while (offset < input.length) {
      final unit = input.codeUnitAt(offset);
      if (_whitespace(unit)) {
        offset++;
        continue;
      }
      if (unit < 0x20 || unit == 0x7f) {
        throw MailArchiveQueryException(
          MailArchiveQueryError.invalidCharacter,
          offset,
        );
      }
      final start = offset;
      final kind = switch (unit) {
        0x3a => _Kind.colon,
        0x28 => _Kind.leftParen,
        0x29 => _Kind.rightParen,
        0x5b => _Kind.leftBracket,
        0x5d => _Kind.rightBracket,
        0x2d => _Kind.minus,
        _ => null,
      };
      if (kind != null) {
        offset++;
        result.add(_Token(kind, '', start, offset));
      } else if (unit == 0x22) {
        result.add(_phrase());
      } else {
        result.add(_word());
      }
    }
    result.add(_Token(_Kind.end, '', input.length, input.length));
    return result;
  }

  _Token _phrase() {
    final start = offset++;
    final value = StringBuffer();
    while (offset < input.length) {
      final unit = input.codeUnitAt(offset++);
      if (unit == 0x22) {
        return _Token(_Kind.phrase, value.toString(), start, offset);
      }
      if ((unit < 0x20 && !_whitespace(unit)) || unit == 0x7f) {
        throw MailArchiveQueryException(
          MailArchiveQueryError.invalidCharacter,
          offset - 1,
        );
      }
      if (unit == 0x5c) {
        if (offset >= input.length) {
          throw MailArchiveQueryException(
            MailArchiveQueryError.invalidEscape,
            offset - 1,
          );
        }
        final escaped = input.codeUnitAt(offset++);
        if (escaped != 0x22 && escaped != 0x5c) {
          throw MailArchiveQueryException(
            MailArchiveQueryError.invalidEscape,
            offset - 2,
          );
        }
        value.writeCharCode(escaped);
      } else {
        value.writeCharCode(unit);
      }
    }
    throw MailArchiveQueryException(MailArchiveQueryError.unclosedQuote, start);
  }

  _Token _word() {
    final start = offset;
    while (offset < input.length) {
      final unit = input.codeUnitAt(offset);
      if (_whitespace(unit) ||
          unit == 0x3a ||
          unit == 0x22 ||
          unit == 0x28 ||
          unit == 0x29 ||
          unit == 0x5b ||
          unit == 0x5d) {
        break;
      }
      if (unit < 0x20 || unit == 0x7f) {
        throw MailArchiveQueryException(
          MailArchiveQueryError.invalidCharacter,
          offset,
        );
      }
      offset++;
    }
    final word = input.substring(start, offset);
    final kind = switch (word) {
      'AND' => _Kind.and,
      'OR' => _Kind.or,
      'NOT' => _Kind.not,
      _ => _Kind.word,
    };
    return _Token(kind, word, start, offset);
  }
}

sealed class _Expression {
  const _Expression();
  String compile(List<String> parameters);
}

final class _Term extends _Expression {
  const _Term(this.match);
  final String match;

  @override
  String compile(List<String> parameters) {
    parameters.add(match);
    return 'a.id IN (SELECT id FROM archive_fts WHERE archive_fts MATCH ?)';
  }
}

final class _Junction extends _Expression {
  const _Junction(this.expressions, {required this.isOr});
  final List<_Expression> expressions;
  final bool isOr;

  @override
  String compile(List<String> parameters) =>
      '(${expressions.map((item) => item.compile(parameters)).join(isOr ? ' OR ' : ' AND ')})';
}

final class _Not extends _Expression {
  const _Not(this.expression);
  final _Expression expression;

  @override
  String compile(List<String> parameters) =>
      'NOT (${expression.compile(parameters)})';
}

final class _QueryParser {
  _QueryParser(String input, {required this.maxTerms, required this.maxDepth})
    : tokens = _QueryLexer(input).scan();

  final List<_Token> tokens;
  final int maxTerms;
  final int maxDepth;
  int index = 0;
  int termCount = 0;
  _Token get current => tokens[index];
  _Token get previous => tokens[index - 1];

  _Expression? parse() {
    if (current.kind == _Kind.end) return null;
    final expression = _or(0);
    if (current.kind != _Kind.end) _unexpected();
    return expression;
  }

  _Expression _or(int depth) {
    final expressions = <_Expression>[_and(depth)];
    while (current.kind == _Kind.or) {
      index++;
      expressions.add(_and(depth));
    }
    return expressions.length == 1
        ? expressions.single
        : _Junction(expressions, isOr: true);
  }

  _Expression _and(int depth) {
    final expressions = <_Expression>[_unary(depth)];
    while (true) {
      if (current.kind == _Kind.and) {
        index++;
        expressions.add(_unary(depth));
      } else if (_startsExpression(current.kind)) {
        // Implicit conjunction requires a separator. This catches accidental
        // adjacency such as `one"two"` or `"phrase"*` instead of rewriting it.
        if (previous.end == current.offset) _unexpected();
        expressions.add(_unary(depth));
      } else {
        break;
      }
    }
    return expressions.length == 1
        ? expressions.single
        : _Junction(expressions, isOr: false);
  }

  _Expression _unary(int depth) {
    if (depth > maxDepth) {
      throw MailArchiveQueryException(
        MailArchiveQueryError.tooDeep,
        current.offset,
      );
    }
    if (current.kind == _Kind.minus || current.kind == _Kind.not) {
      index++;
      return _Not(_unary(depth + 1));
    }
    if (current.kind == _Kind.leftParen) {
      final start = current.offset;
      index++;
      final expression = _or(depth + 1);
      if (current.kind != _Kind.rightParen) {
        throw MailArchiveQueryException(
          MailArchiveQueryError.unclosedGroup,
          start,
        );
      }
      index++;
      return expression;
    }
    if (current.kind == _Kind.leftBracket) {
      return _alternatives(depth + 1);
    }
    return _term();
  }

  _Expression _alternatives(int depth) {
    final start = current.offset;
    index++;
    final expressions = <_Expression>[_unary(depth)];
    while (current.kind != _Kind.rightBracket) {
      if (current.kind == _Kind.end || current.kind == _Kind.rightParen) {
        throw MailArchiveQueryException(
          MailArchiveQueryError.unclosedGroup,
          start,
        );
      }
      if (current.kind == _Kind.or) {
        index++;
      } else if (!_startsExpression(current.kind) ||
          previous.end == current.offset) {
        _unexpected();
      }
      expressions.add(_unary(depth));
    }
    index++;
    return expressions.length == 1
        ? expressions.single
        : _Junction(expressions, isOr: true);
  }

  _Expression _term() {
    String? field;
    if (current.kind == _Kind.word && tokens[index + 1].kind == _Kind.colon) {
      field = _fields[current.value.toLowerCase()];
      if (field == null) {
        throw MailArchiveQueryException(
          MailArchiveQueryError.unknownField,
          current.offset,
        );
      }
      index += 2;
      if (current.kind != _Kind.word && current.kind != _Kind.phrase) {
        throw MailArchiveQueryException(
          MailArchiveQueryError.missingValue,
          current.offset,
        );
      }
    }
    final token = current;
    if (token.kind != _Kind.word && token.kind != _Kind.phrase) _unexpected();
    index++;
    termCount++;
    if (termCount > maxTerms) {
      throw MailArchiveQueryException(
        MailArchiveQueryError.tooManyTerms,
        token.offset,
      );
    }
    var value = token.value;
    var prefix = false;
    if (value.contains('?') ||
        (token.kind == _Kind.phrase && value.contains('*'))) {
      throw MailArchiveQueryException(
        MailArchiveQueryError.unsupportedWildcard,
        token.offset,
      );
    }
    if (value.contains('*')) {
      if (!value.endsWith('*') || value.indexOf('*') != value.length - 1) {
        throw MailArchiveQueryException(
          MailArchiveQueryError.unsupportedWildcard,
          token.offset,
        );
      }
      prefix = true;
      value = value.substring(0, value.length - 1);
    }
    if (!RegExp(r'[\p{L}\p{N}]', unicode: true).hasMatch(value)) {
      throw MailArchiveQueryException(
        MailArchiveQueryError.emptyTerm,
        token.offset,
      );
    }
    final quoted = '"${value.replaceAll('"', '""')}"${prefix ? '*' : ''}';
    return _Term(field == null ? quoted : '$field : $quoted');
  }

  Never _unexpected() => throw MailArchiveQueryException(
    MailArchiveQueryError.unexpectedToken,
    current.offset,
  );
}

bool _startsExpression(_Kind kind) => switch (kind) {
  _Kind.word ||
  _Kind.phrase ||
  _Kind.minus ||
  _Kind.not ||
  _Kind.leftParen ||
  _Kind.leftBracket => true,
  _ => false,
};

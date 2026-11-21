/// The visible header metadata searched in one loaded mailbox row.
///
/// Address fields contain the displayed names and addresses for their respective
/// header groups. Hosts must not put private envelope recipients or body content
/// into these fields. [date] is the message date as an instant; date predicates
/// compare its [DateTime.toLocal] calendar day, as shown by the mailbox UI.
/// Nullable observations remain unknown rather than becoming false.
final class MailHeaderSearchDocument {
  const MailHeaderSearchDocument({
    required this.subject,
    required this.sender,
    this.to = '',
    this.cc = '',
    this.date,
    this.isRead,
    this.isFlagged,
  });

  final String subject;
  final String sender;
  final String to;
  final String cc;
  final DateTime? date;
  final bool? isRead;
  final bool? isFlagged;
}

/// A bounded, portable predicate over already loaded header metadata.
///
/// Whitespace joins terms with AND. Uppercase standalone AND, OR and NOT and
/// parentheses compose expressions, with precedence NOT > AND > OR. A leading
/// minus is an alias for NOT. Adjacent operands require whitespace: `a (b)` is
/// valid but `a(b)`, `(a)b` and `(a)(b)` are rejected. Parentheses may touch
/// their contents and follow an operator directly, as in `NOT(a OR b)`.
///
/// Bare text and quoted phrases match
/// case-insensitive substrings of the subject or sender. The fields `from`,
/// `subject`, `to` and `cc` restrict that match to one header group. Field names
/// are case-insensitive and require an adjacent value, for example
/// `from:alice subject:"quarterly report"`.
///
/// `is:read`, `is:unread`, `is:flagged` and `is:unflagged` require an observed
/// flag value. `before:YYYY-MM-DD` and `after:YYYY-MM-DD` are exclusive calendar
/// day bounds; `on:YYYY-MM-DD` requires the same local calendar day. Missing
/// flags and dates evaluate to unknown, including under NOT; only an expression
/// known to be true matches. AND with false is false and OR with true is true,
/// even when the other operand is unknown.
///
/// Quoted values support only escaped quotes and backslashes. Lowercase
/// `and/or/not`, field values such as `subject:OR`, and quoted operators are
/// literal text. Wildcards, brackets, `&&` and `||` remain unsupported.
/// No provider, repository or body is consulted.
final class MailHeaderSearchQuery {
  MailHeaderSearchQuery._(this._expression, this._termCount);

  factory MailHeaderSearchQuery.parse(String input) {
    if (input.length > maxCodeUnits) {
      throw const MailHeaderSearchException(
        MailHeaderSearchError.queryTooLong,
        maxCodeUnits,
      );
    }
    return _HeaderSearchParser(input).parse();
  }

  static const int maxCodeUnits = 1024;
  static const int maxTerms = 32;
  static const int maxNestingDepth = 8;

  /// Maximum explicit AND, OR, NOT and minus operators in one query.
  ///
  /// Implicit AND is bounded by [maxTerms]. Exceeding this limit reports
  /// [MailHeaderSearchError.invalidExpression] at the offending operator.
  static const int maxOperators = 32;

  final _HeaderSearchTerm? _expression;
  final int _termCount;

  int get termCount => _termCount;
  bool get isEmpty => _expression == null;

  /// Match only a true expression; an empty query matches every document.
  bool matches(MailHeaderSearchDocument document) {
    final expression = _expression;
    if (expression == null) return true;
    return expression.matches(_SearchDocumentView(document)) == true;
  }
}

enum MailHeaderSearchError {
  queryTooLong,
  tooManyTerms,
  invalidCharacter,
  unclosedQuote,
  invalidEscape,
  emptyTerm,
  missingValue,
  unknownField,
  invalidState,
  invalidDate,
  unsupportedOperator,
  invalidExpression,
  nestingTooDeep,
}

/// Safe to display or log: no query or message content is included.
final class MailHeaderSearchException implements Exception {
  const MailHeaderSearchException(this.code, this.offset);

  final MailHeaderSearchError code;

  /// Zero-based UTF-16 code-unit offset into the original query.
  final int offset;

  @override
  String toString() =>
      'MailHeaderSearchException(${code.name}, offset=$offset)';
}

enum _TextField { any, subject, sender, to, cc }

enum _DateRelation { before, after, on }

/// Normalize each inspected field at most once while matching one candidate.
final class _SearchDocumentView {
  _SearchDocumentView(this.source);

  final MailHeaderSearchDocument source;
  late final String subject = source.subject.toLowerCase();
  late final String sender = source.sender.toLowerCase();
  late final String to = source.to.toLowerCase();
  late final String cc = source.cc.toLowerCase();
  late final int? day = _localDay();

  int? _localDay() {
    final date = source.date?.toLocal();
    return date == null
        ? null
        : date.year * 10000 + date.month * 100 + date.day;
  }
}

sealed class _HeaderSearchTerm {
  const _HeaderSearchTerm();

  /// Null preserves an observation that is unavailable to the loaded row.
  bool? matches(_SearchDocumentView document);
}

final class _TextTerm extends _HeaderSearchTerm {
  const _TextTerm(this.field, this.value);

  final _TextField field;
  final String value;

  @override
  bool matches(_SearchDocumentView document) => switch (field) {
    _TextField.any =>
      document.subject.contains(value) || document.sender.contains(value),
    _TextField.subject => document.subject.contains(value),
    _TextField.sender => document.sender.contains(value),
    _TextField.to => document.to.contains(value),
    _TextField.cc => document.cc.contains(value),
  };
}

final class _FlagTerm extends _HeaderSearchTerm {
  const _FlagTerm({required this.read, required this.value});

  final bool read;
  final bool value;

  @override
  bool? matches(_SearchDocumentView document) {
    final observed = read ? document.source.isRead : document.source.isFlagged;
    return observed == null ? null : observed == value;
  }
}

final class _DateTerm extends _HeaderSearchTerm {
  const _DateTerm(this.relation, this.day);

  final _DateRelation relation;
  final int day;

  @override
  bool? matches(_SearchDocumentView document) {
    final observed = document.day;
    if (observed == null) return null;
    return switch (relation) {
      _DateRelation.before => observed < day,
      _DateRelation.after => observed > day,
      _DateRelation.on => observed == day,
    };
  }
}

final class _NotTerm extends _HeaderSearchTerm {
  const _NotTerm(this.operand);

  final _HeaderSearchTerm operand;

  @override
  bool? matches(_SearchDocumentView document) {
    final observed = operand.matches(document);
    return observed == null ? null : !observed;
  }
}

final class _BooleanTerm extends _HeaderSearchTerm {
  const _BooleanTerm(this.left, this.right, {required this.isAnd});

  final _HeaderSearchTerm left;
  final _HeaderSearchTerm right;
  final bool isAnd;

  @override
  bool? matches(_SearchDocumentView document) {
    final first = left.matches(document);
    if (isAnd && first == false) return false;
    if (!isAnd && first == true) return true;
    final second = right.matches(document);
    if (isAnd && second == false) return false;
    if (!isAnd && second == true) return true;
    if (first == null || second == null) return null;
    return isAnd;
  }
}

final class _HeaderSearchParser {
  _HeaderSearchParser(this.input);

  final String input;
  int offset = 0;
  int _termCount = 0;
  int _operatorCount = 0;

  MailHeaderSearchQuery parse() {
    _skipWhitespace();
    if (offset == input.length) return MailHeaderSearchQuery._(null, 0);
    final expression = _or(0);
    _skipWhitespace();
    if (offset != input.length) _invalidExpression();
    return MailHeaderSearchQuery._(expression, _termCount);
  }

  _HeaderSearchTerm _or(int depth) {
    var expression = _and(depth);
    while (_operatorAt('OR')) {
      _consumeOperator(2);
      expression = _BooleanTerm(expression, _and(depth), isAnd: false);
    }
    return expression;
  }

  _HeaderSearchTerm _and(int depth) {
    var expression = _unary(depth);
    while (offset < input.length) {
      final spaced = _skipWhitespace();
      if (offset == input.length || input.codeUnitAt(offset) == 0x29) break;
      if (!spaced) {
        throw MailHeaderSearchException(
          MailHeaderSearchError.invalidCharacter,
          offset,
        );
      }
      if (_operatorAt('OR')) break;
      if (_operatorAt('AND')) _consumeOperator(3);
      expression = _BooleanTerm(expression, _unary(depth), isAnd: true);
    }
    return expression;
  }

  _HeaderSearchTerm _unary(int depth) {
    _skipWhitespace();
    var negated = false;
    // Parse unary chains iteratively so their length cannot grow the call stack.
    while (offset < input.length) {
      if (_operatorAt('NOT')) {
        _consumeOperator(3);
      } else if (input.codeUnitAt(offset) == 0x2d) {
        _consumeOperator(1);
      } else {
        break;
      }
      negated = !negated;
      _skipWhitespace();
    }

    if (offset == input.length ||
        input.codeUnitAt(offset) == 0x29 ||
        _operatorAt('AND') ||
        _operatorAt('OR')) {
      _invalidExpression();
    }

    final _HeaderSearchTerm expression;
    if (input.codeUnitAt(offset) == 0x28) {
      if (depth == MailHeaderSearchQuery.maxNestingDepth) {
        throw MailHeaderSearchException(
          MailHeaderSearchError.nestingTooDeep,
          offset,
        );
      }
      offset++;
      expression = _or(depth + 1);
      if (offset == input.length || input.codeUnitAt(offset) != 0x29) {
        _invalidExpression();
      }
      offset++;
    } else {
      if (_termCount == MailHeaderSearchQuery.maxTerms) {
        throw MailHeaderSearchException(
          MailHeaderSearchError.tooManyTerms,
          offset,
        );
      }
      expression = _term();
      _termCount++;
    }
    return negated ? _NotTerm(expression) : expression;
  }

  bool _operatorAt(String word) {
    if (!input.startsWith(word, offset)) return false;
    final end = offset + word.length;
    return end == input.length ||
        _whitespace(input.codeUnitAt(end)) ||
        input.codeUnitAt(end) == 0x28 ||
        input.codeUnitAt(end) == 0x29;
  }

  void _consumeOperator(int length) {
    if (_operatorCount == MailHeaderSearchQuery.maxOperators) {
      _invalidExpression();
    }
    _operatorCount++;
    offset += length;
  }

  bool _skipWhitespace() {
    final start = offset;
    while (offset < input.length && _whitespace(input.codeUnitAt(offset))) {
      offset++;
    }
    return offset != start;
  }

  Never _invalidExpression() => throw MailHeaderSearchException(
    MailHeaderSearchError.invalidExpression,
    offset,
  );

  _HeaderSearchTerm _term() {
    final start = offset;
    if (input.codeUnitAt(offset) == 0x22) {
      return _TextTerm(_TextField.any, _quoted().toLowerCase());
    }
    final word = _bare(stopAtColon: true);
    if (offset == input.length || input.codeUnitAt(offset) != 0x3a) {
      return _TextTerm(_TextField.any, word.toLowerCase());
    }

    final field = word.toLowerCase();
    if (!const {
      'from',
      'subject',
      'to',
      'cc',
      'is',
      'before',
      'after',
      'on',
    }.contains(field)) {
      throw MailHeaderSearchException(
        MailHeaderSearchError.unknownField,
        start,
      );
    }
    offset++;
    final valueStart = offset;
    if (offset == input.length ||
        _whitespace(input.codeUnitAt(offset)) ||
        input.codeUnitAt(offset) == 0x28 ||
        input.codeUnitAt(offset) == 0x29) {
      throw MailHeaderSearchException(
        MailHeaderSearchError.missingValue,
        offset,
      );
    }
    final value = input.codeUnitAt(offset) == 0x22
        ? _quoted()
        : _bare(stopAtColon: false);
    final normalized = value.toLowerCase();
    return switch (field) {
      'from' => _TextTerm(_TextField.sender, normalized),
      'subject' => _TextTerm(_TextField.subject, normalized),
      'to' => _TextTerm(_TextField.to, normalized),
      'cc' => _TextTerm(_TextField.cc, normalized),
      'is' => switch (normalized) {
        'read' => const _FlagTerm(read: true, value: true),
        'unread' => const _FlagTerm(read: true, value: false),
        'flagged' => const _FlagTerm(read: false, value: true),
        'unflagged' => const _FlagTerm(read: false, value: false),
        _ => throw MailHeaderSearchException(
          MailHeaderSearchError.invalidState,
          valueStart,
        ),
      },
      'before' => _DateTerm(_DateRelation.before, _day(value, valueStart)),
      'after' => _DateTerm(_DateRelation.after, _day(value, valueStart)),
      'on' => _DateTerm(_DateRelation.on, _day(value, valueStart)),
      _ => throw StateError('Validated header-search field was not handled.'),
    };
  }

  String _bare({required bool stopAtColon}) {
    final start = offset;
    while (offset < input.length) {
      final unit = input.codeUnitAt(offset);
      if (_whitespace(unit) ||
          unit == 0x28 ||
          unit == 0x29 ||
          stopAtColon && unit == 0x3a) {
        break;
      }
      if (_control(unit) || unit == 0x22) {
        throw MailHeaderSearchException(
          MailHeaderSearchError.invalidCharacter,
          offset,
        );
      }
      if (unit == 0x5c) {
        throw MailHeaderSearchException(
          MailHeaderSearchError.invalidEscape,
          offset,
        );
      }
      if (unit == 0x5b ||
          unit == 0x5d ||
          unit == 0x2a ||
          unit == 0x3f ||
          unit == 0x7c ||
          unit == 0x26) {
        throw MailHeaderSearchException(
          MailHeaderSearchError.unsupportedOperator,
          offset,
        );
      }
      offset++;
    }
    if (offset == start) {
      throw MailHeaderSearchException(MailHeaderSearchError.emptyTerm, start);
    }
    return input.substring(start, offset);
  }

  String _quoted() {
    final start = offset++;
    final value = StringBuffer();
    while (offset < input.length) {
      final unit = input.codeUnitAt(offset++);
      if (unit == 0x22) {
        final text = value.toString();
        if (text.trim().isEmpty) {
          throw MailHeaderSearchException(
            MailHeaderSearchError.emptyTerm,
            start,
          );
        }
        return text;
      }
      if (_control(unit)) {
        throw MailHeaderSearchException(
          MailHeaderSearchError.invalidCharacter,
          offset - 1,
        );
      }
      if (unit == 0x5c) {
        if (offset == input.length) {
          throw MailHeaderSearchException(
            MailHeaderSearchError.invalidEscape,
            offset - 1,
          );
        }
        final escaped = input.codeUnitAt(offset++);
        if (escaped != 0x22 && escaped != 0x5c) {
          throw MailHeaderSearchException(
            MailHeaderSearchError.invalidEscape,
            offset - 2,
          );
        }
        value.writeCharCode(escaped);
      } else {
        value.writeCharCode(unit);
      }
    }
    throw MailHeaderSearchException(MailHeaderSearchError.unclosedQuote, start);
  }

  int _day(String value, int valueStart) {
    int invalid() => throw MailHeaderSearchException(
      MailHeaderSearchError.invalidDate,
      valueStart,
    );

    if (value.length != 10 ||
        value.codeUnitAt(4) != 0x2d ||
        value.codeUnitAt(7) != 0x2d) {
      return invalid();
    }
    var digits = 0;
    for (var index = 0; index < value.length; index++) {
      if (index == 4 || index == 7) continue;
      final unit = value.codeUnitAt(index);
      if (unit < 0x30 || unit > 0x39) return invalid();
      digits = digits * 10 + unit - 0x30;
    }
    final year = digits ~/ 10000;
    final month = digits ~/ 100 % 100;
    final day = digits % 100;
    if (year < 1 || month < 1 || month > 12 || day < 1 || day > 31) {
      return invalid();
    }
    final checked = DateTime.utc(year, month, day);
    if (checked.year != year || checked.month != month || checked.day != day) {
      return invalid();
    }
    return digits;
  }
}

bool _control(int unit) => unit < 0x20 || unit >= 0x7f && unit <= 0x9f;

bool _whitespace(int unit) =>
    unit == 0x20 ||
    unit == 0x09 ||
    unit == 0x0a ||
    unit == 0x0d ||
    unit == 0xa0 ||
    unit == 0x1680 ||
    unit >= 0x2000 && unit <= 0x200a ||
    unit == 0x2028 ||
    unit == 0x2029 ||
    unit == 0x202f ||
    unit == 0x205f ||
    unit == 0x3000;

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
/// Whitespace joins terms with AND. Bare text and quoted phrases match
/// case-insensitive substrings of the subject or sender. The fields `from`,
/// `subject`, `to` and `cc` restrict that match to one header group. Field names
/// are case-insensitive and require an adjacent value, for example
/// `from:alice subject:"quarterly report"`.
///
/// `is:read`, `is:unread`, `is:flagged` and `is:unflagged` require an observed
/// flag value. `before:YYYY-MM-DD` and `after:YYYY-MM-DD` are exclusive calendar
/// day bounds; `on:YYYY-MM-DD` requires the same local calendar day. Missing
/// flags and dates do not match these predicates.
///
/// Quoted values support only escaped quotes and backslashes. Operators,
/// negation, groups and wildcards are deliberately unsupported; quote them to
/// search for their literal text. Uppercase AND/OR/NOT are reserved when used
/// as standalone bare terms. No provider, repository or body is consulted.
final class MailHeaderSearchQuery {
  MailHeaderSearchQuery._(List<_HeaderSearchTerm> terms)
    : _terms = List.unmodifiable(terms);

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

  final List<_HeaderSearchTerm> _terms;

  int get termCount => _terms.length;
  bool get isEmpty => _terms.isEmpty;

  /// Every term must match. An empty query matches every supplied document.
  bool matches(MailHeaderSearchDocument document) {
    if (_terms.isEmpty) return true;
    final view = _SearchDocumentView(document);
    return _terms.every((term) => term.matches(view));
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

  bool matches(_SearchDocumentView document);
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
  bool matches(_SearchDocumentView document) =>
      (read ? document.source.isRead : document.source.isFlagged) == value;
}

final class _DateTerm extends _HeaderSearchTerm {
  const _DateTerm(this.relation, this.day);

  final _DateRelation relation;
  final int day;

  @override
  bool matches(_SearchDocumentView document) {
    final observed = document.day;
    if (observed == null) return false;
    return switch (relation) {
      _DateRelation.before => observed < day,
      _DateRelation.after => observed > day,
      _DateRelation.on => observed == day,
    };
  }
}

final class _HeaderSearchParser {
  _HeaderSearchParser(this.input);

  final String input;
  int offset = 0;

  MailHeaderSearchQuery parse() {
    final terms = <_HeaderSearchTerm>[];
    while (offset < input.length) {
      if (_whitespace(input.codeUnitAt(offset))) {
        offset++;
        continue;
      }
      if (terms.length == MailHeaderSearchQuery.maxTerms) {
        throw MailHeaderSearchException(
          MailHeaderSearchError.tooManyTerms,
          offset,
        );
      }
      terms.add(_term());
      if (offset < input.length && !_whitespace(input.codeUnitAt(offset))) {
        throw MailHeaderSearchException(
          MailHeaderSearchError.invalidCharacter,
          offset,
        );
      }
    }
    return MailHeaderSearchQuery._(terms);
  }

  _HeaderSearchTerm _term() {
    final start = offset;
    if (input.codeUnitAt(offset) == 0x22) {
      return _TextTerm(_TextField.any, _quoted().toLowerCase());
    }
    if (input.codeUnitAt(offset) == 0x2d) {
      throw MailHeaderSearchException(
        MailHeaderSearchError.unsupportedOperator,
        offset,
      );
    }
    final word = _bare(stopAtColon: true);
    if (offset == input.length || input.codeUnitAt(offset) != 0x3a) {
      if (word == 'AND' || word == 'OR' || word == 'NOT') {
        throw MailHeaderSearchException(
          MailHeaderSearchError.unsupportedOperator,
          start,
        );
      }
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
    if (offset == input.length || _whitespace(input.codeUnitAt(offset))) {
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
      if (_whitespace(unit) || stopAtColon && unit == 0x3a) break;
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
      if (unit == 0x28 ||
          unit == 0x29 ||
          unit == 0x5b ||
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

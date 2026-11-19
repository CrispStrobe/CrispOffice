import 'dart:convert';

import 'office_macro_language.dart';
import 'office_macro_model.dart';
import 'office_operations.dart';

/// A source diagnostic from the explicitly invoked Excel VBA subset compiler.
/// Line and column are one-based UTF-16 positions in the supplied source.
class OfficeVbaCompileException extends OfficeMacroException {
  const OfficeVbaCompileException(
    super.code,
    super.message, {
    required this.moduleName,
    required this.entryPoint,
    required this.line,
    required this.column,
  });

  final String moduleName;
  final String entryPoint;
  final int line;
  final int column;

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    ...super.toJson(),
    'moduleName': moduleName,
    'entryPoint': entryPoint,
    'line': line,
    'column': column,
  };
}

/// Compiles a finite, document-independent Excel VBA subset to native calls.
///
/// This is not a general VBA interpreter. All source is parsed and checked,
/// including unused procedures and branches. Only the selected parameterless
/// Sub is evaluated. Expressions cannot read the document or invoke external
/// code; explicitly qualified writes retain the ordinary runtime policy and
/// transaction boundary. Compilation has separate syntax, work, string, range,
/// operation, and encoded-output limits, including for loops emitting no calls.
class OfficeVbaMacroLanguage implements OfficeMacroLanguage {
  const OfficeVbaMacroLanguage();

  @override
  String get id => 'vba-excel';

  @override
  OfficeMacro compile(OfficeMacroSource source) {
    final context = _Context(source);
    if (source.format != OfficeMacroFormat.xlsx) {
      context.fail(
        const _Token(_TokenKind.end, '', 1, 1),
        'vba_unsupported',
        'vba-excel only targets spreadsheet documents.',
      );
    }
    final module = _Parser(context, _Lexer(context).scan()).parse();
    final checked = _Checker(context, module)..check();
    return _Evaluator(context, module, checked).compile();
  }
}

const _maxTokens = 50000;
const _maxDepth = 64;
const _maxBlocks = 32;
const _maxStatements = 10000;
const _maxWork = 100000;
const _maxVariables = 256;
const _maxString = 32767;
const _maxSteps = 10000;
const _maxExactInteger = 9007199254740991;

class _Context {
  const _Context(this.source);
  final OfficeMacroSource source;

  Never fail(
    _Token token,
    String code,
    String message,
  ) => throw OfficeVbaCompileException(
    code,
    '${source.moduleName}.${source.entryPoint}:${token.line}:${token.column}: $message',
    moduleName: source.moduleName,
    entryPoint: source.entryPoint,
    line: token.line,
    column: token.column,
  );

  Never unsupported(_Token token, String message) =>
      fail(token, 'vba_unsupported', message);

  Never limit(_Token token, String message) =>
      fail(token, 'vba_limit_exceeded', message);

  Never type(_Token token, String message) =>
      fail(token, 'vba_type_error', message);
}

enum _TokenKind { identifier, number, string, symbol, separator, end }

class _Token {
  const _Token(this.kind, this.text, this.line, this.column);
  final _TokenKind kind;
  final String text;
  final int line;
  final int column;
  String get lower => text.toLowerCase();
}

bool _letter(int code) =>
    (code >= 65 && code <= 90) || (code >= 97 && code <= 122);
bool _digit(int code) => code >= 48 && code <= 57;
bool _horizontal(int code) => code == 32 || code == 9;

class _Lexer {
  _Lexer(this.context) : source = context.source.source;
  final _Context context;
  final String source;
  final List<_Token> tokens = <_Token>[];
  int offset = 0;
  int line = 1;
  int column = 1;
  bool statementStart = true;

  List<_Token> scan() {
    if (source.startsWith('\uFEFF')) offset++;
    while (offset < source.length) {
      final code = source.codeUnitAt(offset);
      if (_horizontal(code)) {
        _advance();
        continue;
      }
      if (code == 13 || code == 10) {
        final token = _Token(_TokenKind.separator, '\n', line, column);
        _newline();
        _add(token);
        statementStart = true;
        continue;
      }
      if (code == 39) {
        _comment();
        continue;
      }
      final start = offset;
      final startLine = line;
      final startColumn = column;
      _Token token(_TokenKind kind, String text) =>
          _Token(kind, text, startLine, startColumn);
      if (code == 95) {
        // VBA continuation is a space followed by underscore and a newline.
        if (offset == 0 ||
            !_horizontal(source.codeUnitAt(offset - 1)) ||
            statementStart) {
          context.fail(
            token(_TokenKind.symbol, '_'),
            'vba_syntax_error',
            'A continuation needs a preceding statement and whitespace.',
          );
        }
        _advance();
        while (offset < source.length &&
            _horizontal(source.codeUnitAt(offset))) {
          _advance();
        }
        if (offset == source.length ||
            (source.codeUnitAt(offset) != 13 &&
                source.codeUnitAt(offset) != 10)) {
          context.fail(
            token(_TokenKind.symbol, '_'),
            'vba_syntax_error',
            'A continuation must end at a newline.',
          );
        }
        _newline();
        if (offset == source.length) {
          context.fail(
            token(_TokenKind.symbol, '_'),
            'vba_syntax_error',
            'A continuation needs another source line.',
          );
        }
        continue;
      }
      if (code == 34) {
        _advance();
        final buffer = StringBuffer();
        var length = 0;
        var closed = false;
        while (offset < source.length) {
          final next = source.codeUnitAt(offset);
          if (next == 13 || next == 10) break;
          _advance();
          if (next == 34) {
            if (offset < source.length && source.codeUnitAt(offset) == 34) {
              _advance();
            } else {
              closed = true;
              break;
            }
          }
          if (++length > _maxString) {
            context.limit(
              token(_TokenKind.string, ''),
              'String literals exceed $_maxString code units.',
            );
          }
          buffer.writeCharCode(next);
        }
        if (!closed) {
          context.fail(
            token(_TokenKind.string, ''),
            'vba_syntax_error',
            'Unterminated string literal.',
          );
        }
        _add(token(_TokenKind.string, buffer.toString()));
        statementStart = false;
        continue;
      }
      if (_letter(code)) {
        _advance();
        while (offset < source.length) {
          final next = source.codeUnitAt(offset);
          if (!_letter(next) && !_digit(next) && next != 95) break;
          _advance();
        }
        final text = source.substring(start, offset);
        if (text.length > 128) {
          context.limit(
            token(_TokenKind.identifier, text),
            'Identifiers exceed 128 code units.',
          );
        }
        if (statementStart && text.toLowerCase() == 'rem') {
          _comment();
          continue;
        }
        _add(token(_TokenKind.identifier, text));
        statementStart = false;
        continue;
      }
      if (_digit(code) ||
          (code == 46 &&
              offset + 1 < source.length &&
              _digit(source.codeUnitAt(offset + 1)))) {
        while (offset < source.length && _digit(source.codeUnitAt(offset))) {
          _advance();
        }
        if (offset < source.length && source.codeUnitAt(offset) == 46) {
          _advance();
          while (offset < source.length && _digit(source.codeUnitAt(offset))) {
            _advance();
          }
        }
        if (offset < source.length &&
            (source.codeUnitAt(offset) == 69 ||
                source.codeUnitAt(offset) == 101)) {
          _advance();
          if (offset < source.length &&
              (source.codeUnitAt(offset) == 43 ||
                  source.codeUnitAt(offset) == 45)) {
            _advance();
          }
          final exponent = offset;
          while (offset < source.length && _digit(source.codeUnitAt(offset))) {
            _advance();
          }
          if (offset == exponent) {
            context.fail(
              token(_TokenKind.number, ''),
              'vba_syntax_error',
              'An exponent needs digits.',
            );
          }
        }
        _add(token(_TokenKind.number, source.substring(start, offset)));
        statementStart = false;
        continue;
      }
      if ('().,+-*/&=<>:'.contains(String.fromCharCode(code))) {
        _advance();
        if ((code == 60 || code == 62) && offset < source.length) {
          final next = source.codeUnitAt(offset);
          if (next == 61 || (code == 60 && next == 62)) _advance();
        }
        final text = source.substring(start, offset);
        _add(
          token(code == 58 ? _TokenKind.separator : _TokenKind.symbol, text),
        );
        statementStart = code == 58;
        continue;
      }
      context.unsupported(
        token(_TokenKind.symbol, String.fromCharCode(code)),
        'Unsupported character; VBA type suffixes, dates, and directives are not supported.',
      );
    }
    _add(_Token(_TokenKind.end, '', line, column));
    return tokens;
  }

  void _advance() {
    offset++;
    column++;
  }

  void _newline() {
    if (source.codeUnitAt(offset++) == 13 &&
        offset < source.length &&
        source.codeUnitAt(offset) == 10) {
      offset++;
    }
    line++;
    column = 1;
  }

  void _comment() {
    while (offset < source.length &&
        source.codeUnitAt(offset) != 13 &&
        source.codeUnitAt(offset) != 10) {
      _advance();
    }
  }

  void _add(_Token token) {
    if (tokens.length >= _maxTokens) {
      context.limit(token, 'Source exceeds $_maxTokens tokens.');
    }
    tokens.add(token);
  }
}

enum _Kind {
  number,
  string,
  boolean,
  variant,
  worksheet,
  range,
  workbook,
  font,
  interior,
}

enum _Declared { long, doubleType, string, boolean, variant, worksheet, range }

_Kind _kindOf(_Declared type) => switch (type) {
  _Declared.long || _Declared.doubleType => _Kind.number,
  _Declared.string => _Kind.string,
  _Declared.boolean => _Kind.boolean,
  _Declared.variant => _Kind.variant,
  _Declared.worksheet => _Kind.worksheet,
  _Declared.range => _Kind.range,
};

sealed class _Expr {
  const _Expr(this.token, this.depth);
  final _Token token;
  final int depth;
}

class _Literal extends _Expr {
  const _Literal(_Token token, this.value) : super(token, 1);
  final Object value;
}

class _Name extends _Expr {
  const _Name(_Token token) : super(token, 1);
}

class _WithValue extends _Expr {
  const _WithValue(_Token token) : super(token, 1);
}

class _Call extends _Expr {
  _Call(_Token token, this.arguments)
    : super(
        token,
        1 + arguments.fold<int>(0, (a, b) => a > b.depth ? a : b.depth),
      );
  final List<_Expr> arguments;
}

class _Member extends _Expr {
  _Member(_Token token, this.receiver, this.arguments)
    : super(
        token,
        1 +
            (arguments ?? const <_Expr>[]).fold<int>(
              receiver.depth,
              (a, b) => a > b.depth ? a : b.depth,
            ),
      );
  final _Expr receiver;
  final List<_Expr>? arguments;
}

class _Unary extends _Expr {
  _Unary(_Token token, this.operand) : super(token, operand.depth + 1);
  final _Expr operand;
}

class _Binary extends _Expr {
  _Binary(_Token token, this.left, this.right)
    : super(token, 1 + (left.depth > right.depth ? left.depth : right.depth));
  final _Expr left;
  final _Expr right;
}

sealed class _Statement {
  const _Statement(this.token);
  final _Token token;
}

class _Declaration extends _Statement {
  const _Declaration(super.token, this.type, this.isConst, this.initializer);
  final _Declared type;
  final bool isConst;
  final _Expr? initializer;
}

class _Assignment extends _Statement {
  const _Assignment(super.token, this.target, this.value, this.isSet);
  final _Expr target;
  final _Expr value;
  final bool isSet;
}

class _Clear extends _Statement {
  const _Clear(super.token, this.target);
  final _Member target;
}

class _For extends _Statement {
  const _For(
    super.token,
    this.counter,
    this.start,
    this.end,
    this.step,
    this.body,
  );
  final _Token counter;
  final _Expr start;
  final _Expr end;
  final _Expr step;
  final List<_Statement> body;
}

class _With extends _Statement {
  const _With(super.token, this.target, this.body);
  final _Expr target;
  final List<_Statement> body;
}

class _If extends _Statement {
  const _If(super.token, this.branches, this.otherwise);
  final List<(_Expr, List<_Statement>)> branches;
  final List<_Statement> otherwise;
}

class _Procedure {
  const _Procedure(this.name, this.body);
  final _Token name;
  final List<_Statement> body;
}

class _Module {
  const _Module(this.explicit, this.constants, this.procedures);
  final bool explicit;
  final List<_Declaration> constants;
  final Map<String, _Procedure> procedures;
}

class _Parser {
  _Parser(this.context, this.tokens);
  final _Context context;
  final List<_Token> tokens;
  int position = 0;
  int expressionDepth = 0;
  int statementCount = 0;
  _Token get current => tokens[position];
  bool _is(String text) =>
      (current.kind == _TokenKind.identifier ||
          current.kind == _TokenKind.symbol) &&
      current.lower == text;
  bool _atEnd(String second) =>
      _is('end') && tokens[position + 1].lower == second;

  _Module parse() {
    var explicit = false;
    var attribute = false;
    final constants = <_Declaration>[];
    final procedures = <String, _Procedure>{};
    _separators();
    while (current.kind != _TokenKind.end) {
      if (_take('option')) {
        if (procedures.isNotEmpty || explicit) {
          _syntax('Option Explicit must occur once before procedures.');
        }
        _expect('explicit');
        explicit = true;
        _endStatement();
      } else if (_take('attribute')) {
        if (procedures.isNotEmpty || attribute) {
          _syntax('Only one initial Attribute VB_Name is supported.');
        }
        _expect('vb_name');
        _expect('=');
        if (current.kind != _TokenKind.string) {
          _syntax('VB_Name needs a string literal.');
        }
        position++;
        attribute = true;
        _endStatement();
      } else if (_is('const')) {
        if (procedures.isNotEmpty) {
          _syntax('Module constants must precede procedures.');
        }
        constants.addAll(_declarations(true));
      } else {
        _take('public') || _take('private');
        if (!_take('sub')) {
          context.unsupported(
            current,
            'Only parameterless Sub procedures and module constants are supported.',
          );
        }
        final name = _identifier();
        if (_Checker._reserved.contains(name.lower)) {
          context.fail(
            name,
            'vba_name_error',
            'Reserved procedure name ${name.text}.',
          );
        }
        if (_take('(')) _expect(')');
        _endStatement();
        final body = _body(0, () => _atEnd('sub'));
        _expect('end');
        _expect('sub');
        _endStatement();
        if (procedures.containsKey(name.lower)) {
          _syntax('Duplicate procedure ${name.text}.', name);
        }
        procedures[name.lower] = _Procedure(name, body);
      }
      _separators();
    }
    if (!procedures.containsKey(context.source.entryPoint.toLowerCase())) {
      context.fail(
        current,
        'vba_entry_point',
        'No parameterless Sub named ${context.source.entryPoint}.',
      );
    }
    return _Module(explicit, constants, procedures);
  }

  List<_Statement> _body(int depth, bool Function() stop) {
    if (depth > _maxBlocks) {
      context.limit(current, 'Blocks exceed $_maxBlocks nesting levels.');
    }
    final result = <_Statement>[];
    _separators();
    while (!stop()) {
      if (current.kind == _TokenKind.end) _syntax('Unterminated block.');
      if (++statementCount > _maxStatements) {
        context.limit(current, 'Source exceeds $_maxStatements statements.');
      }
      if (_is('dim') || _is('const')) {
        result.addAll(_declarations(_is('const')));
      } else if (_is('for')) {
        final token = current;
        position++;
        final counter = _identifier();
        _expect('=');
        final start = _expression();
        _expect('to');
        final end = _expression();
        final step = _take('step') ? _expression() : _Literal(token, 1);
        _endStatement();
        final body = _body(depth + 1, () => _is('next'));
        _expect('next');
        if (current.kind == _TokenKind.identifier) {
          final ending = _identifier();
          if (ending.lower != counter.lower) {
            _syntax('Next counter does not match For ${counter.text}.', ending);
          }
        }
        _endStatement();
        result.add(_For(token, counter, start, end, step, body));
      } else if (_is('with')) {
        final token = current;
        position++;
        final target = _expression();
        _endStatement();
        final body = _body(depth + 1, () => _atEnd('with'));
        _expect('end');
        _expect('with');
        _endStatement();
        result.add(_With(token, target, body));
      } else if (_is('if')) {
        final token = current;
        position++;
        final branches = <(_Expr, List<_Statement>)>[];
        var condition = _expression();
        _expect('then');
        _blockIfNewline();
        List<_Statement> branch() => _body(
          depth + 1,
          () => _is('elseif') || _is('else') || _atEnd('if'),
        );
        branches.add((condition, branch()));
        while (_take('elseif')) {
          condition = _expression();
          _expect('then');
          _blockIfNewline();
          branches.add((condition, branch()));
        }
        var otherwise = <_Statement>[];
        if (_take('else')) {
          _endStatement();
          otherwise = _body(depth + 1, () => _atEnd('if'));
        }
        _expect('end');
        _expect('if');
        _endStatement();
        result.add(_If(token, branches, otherwise));
      } else {
        final token = current;
        final isSet = _take('set');
        if (!isSet) _take('let');
        final target = _postfix();
        if (_take('=')) {
          final value = _expression();
          _endStatement();
          result.add(_Assignment(token, target, value, isSet));
        } else if (!isSet &&
            target is _Member &&
            target.token.lower == 'clearcontents') {
          _endStatement();
          result.add(_Clear(token, target));
        } else {
          context.unsupported(
            token,
            'Only assignments, ClearContents, With, For, and block If statements are supported.',
          );
        }
      }
      _separators();
    }
    return result;
  }

  void _blockIfNewline() {
    if (current.kind != _TokenKind.separator || current.text != '\n') {
      context.unsupported(
        current,
        'Use a block If with Then at the end of its line.',
      );
    }
    _endStatement();
  }

  List<_Declaration> _declarations(bool isConst) {
    position++;
    final result = <_Declaration>[];
    do {
      final name = _identifier();
      var type = _Declared.variant;
      if (_take('as')) {
        final typeToken = _identifier();
        type = switch (typeToken.lower) {
          'long' => _Declared.long,
          'double' => _Declared.doubleType,
          'string' => _Declared.string,
          'boolean' => _Declared.boolean,
          'variant' => _Declared.variant,
          'worksheet' => _Declared.worksheet,
          'range' => _Declared.range,
          _ => context.unsupported(
            typeToken,
            'Supported declarations are Long, Double, String, Boolean, Variant, Worksheet, and Range.',
          ),
        };
      }
      _Expr? initializer;
      if (isConst) {
        _expect('=');
        initializer = _expression();
      }
      result.add(_Declaration(name, type, isConst, initializer));
      if (result.length > _maxVariables) {
        context.limit(name, 'Too many declarations.');
      }
    } while (_take(','));
    _endStatement();
    return result;
  }

  static const _precedence = <String, int>{
    'xor': 1,
    'or': 2,
    'and': 3,
    '=': 4,
    '<>': 4,
    '<': 4,
    '>': 4,
    '<=': 4,
    '>=': 4,
    '&': 5,
    '+': 6,
    '-': 6,
    '*': 7,
    '/': 7,
  };

  _Expr _expression([int minimum = 1]) {
    if (++expressionDepth > _maxDepth) {
      context.limit(current, 'Expressions exceed $_maxDepth nesting levels.');
    }
    _Expr left;
    if (_is('+') || _is('-') || _is('not')) {
      final token = current;
      position++;
      left = _bounded(_Unary(token, _expression(token.lower == 'not' ? 4 : 8)));
    } else {
      left = _postfix();
    }
    while (true) {
      final precedence =
          current.kind == _TokenKind.identifier ||
              current.kind == _TokenKind.symbol
          ? _precedence[current.lower]
          : null;
      if (precedence == null || precedence < minimum) break;
      final token = current;
      position++;
      left = _bounded(_Binary(token, left, _expression(precedence + 1)));
    }
    expressionDepth--;
    return left;
  }

  _Expr _postfix() {
    final token = current;
    _Expr result;
    if (_take('(')) {
      result = _expression();
      _expect(')');
    } else if (_take('.')) {
      final member = _identifier();
      result = _bounded(_Member(member, _WithValue(token), _arguments()));
    } else if (token.kind == _TokenKind.string) {
      position++;
      result = _Literal(token, token.text);
    } else if (token.kind == _TokenKind.number) {
      position++;
      final value = num.tryParse(token.text);
      if (value == null || !value.isFinite || value.abs() > _maxExactInteger) {
        context.limit(
          token,
          'Numeric literals must be finite with magnitude at most 2^53-1.',
        );
      }
      result = _Literal(token, value);
    } else if (token.kind == _TokenKind.identifier) {
      position++;
      if (token.lower == 'true' || token.lower == 'false') {
        result = _Literal(token, token.lower == 'true');
      } else {
        final arguments = _arguments();
        result = arguments == null
            ? _Name(token)
            : _bounded(_Call(token, arguments));
      }
    } else {
      _syntax('Expected a supported expression.');
    }
    while (_take('.')) {
      final member = _identifier();
      result = _bounded(_Member(member, result, _arguments()));
    }
    return result;
  }

  List<_Expr>? _arguments() {
    if (!_take('(')) return null;
    final result = <_Expr>[];
    if (!_is(')')) {
      do {
        if (result.length >= 3) {
          context.unsupported(
            current,
            'No supported call accepts more than three arguments.',
          );
        }
        result.add(_expression());
      } while (_take(','));
    }
    _expect(')');
    return result;
  }

  T _bounded<T extends _Expr>(T expression) {
    if (expression.depth > _maxDepth) {
      context.limit(
        expression.token,
        'Expressions exceed $_maxDepth syntax levels.',
      );
    }
    return expression;
  }

  _Token _identifier() {
    if (current.kind != _TokenKind.identifier) {
      _syntax('Expected an identifier.');
    }
    return tokens[position++];
  }

  bool _take(String text) {
    if (!_is(text)) return false;
    position++;
    return true;
  }

  void _expect(String text) {
    if (!_take(text)) _syntax('Expected "$text".');
  }

  void _endStatement() {
    if (current.kind == _TokenKind.end) return;
    if (current.kind != _TokenKind.separator) {
      _syntax('Unexpected token; the statement must end here.');
    }
    _separators();
  }

  void _separators() {
    while (current.kind == _TokenKind.separator) {
      position++;
    }
  }

  Never _syntax(String message, [_Token? token]) =>
      context.fail(token ?? current, 'vba_syntax_error', message);
}

class _Symbol {
  const _Symbol(this.type, this.isConst, this.token);
  final _Declared type;
  final bool isConst;
  final _Token token;
}

/// Static object-shape validation also visits branches that will not execute.
/// It admits no document getter or unknown callable into the evaluator.
class _Checker {
  _Checker(this.context, this.module);
  final _Context context;
  final _Module module;
  final Map<String, _Symbol> globals = <String, _Symbol>{};
  final Map<String, Map<String, _Symbol>> locals =
      <String, Map<String, _Symbol>>{};
  Map<String, _Symbol> symbols = <String, _Symbol>{};
  final List<_Kind> withKinds = <_Kind>[];
  final Set<String> counters = <String>{};
  static const _reserved = <String>{
    'sub',
    'end',
    'dim',
    'const',
    'as',
    'set',
    'let',
    'for',
    'to',
    'step',
    'next',
    'with',
    'if',
    'then',
    'else',
    'elseif',
    'true',
    'false',
    'not',
    'and',
    'or',
    'xor',
    'option',
    'explicit',
    'attribute',
    'public',
    'private',
    'thisworkbook',
    'worksheets',
    'range',
    'cells',
    'rgb',
    'empty',
    'null',
    'nothing',
    'application',
    'activesheet',
    'activeworkbook',
    'selection',
    'rem',
    'boolean',
    'double',
    'long',
    'string',
    'variant',
    'worksheet',
    'function',
    'call',
    'new',
    'on',
    'error',
    'resume',
    'exit',
    'while',
    'wend',
    'do',
    'loop',
    'select',
    'case',
    'until',
    'each',
    'in',
    'byref',
    'byval',
    'addressof',
    'alias',
    'any',
    'declare',
    'enum',
    'erase',
    'event',
    'friend',
    'implements',
    'lib',
    'me',
    'redim',
    'raiseevent',
    'static',
    'stop',
    'type',
    'withevents',
    'class',
  };

  void check() {
    symbols = globals;
    for (final declaration in module.constants) {
      _declare(declaration);
    }
    for (final procedure in module.procedures.values) {
      symbols = <String, _Symbol>{...globals};
      var executable = false;
      for (final statement in procedure.body) {
        if (statement is _Declaration) {
          if (executable) {
            context.unsupported(
              statement.token,
              'Declarations must precede executable statements in this subset.',
            );
          }
          _declare(statement);
        } else {
          executable = true;
        }
      }
      _implicit(procedure.body);
      _statements(procedure.body);
      locals[procedure.name.lower] = Map<String, _Symbol>.of(symbols);
    }
  }

  void _declare(_Declaration declaration) {
    final name = declaration.token.lower;
    if (_reserved.contains(name) || symbols.containsKey(name)) {
      context.fail(
        declaration.token,
        'vba_name_error',
        'Reserved or duplicate variable ${declaration.token.text}.',
      );
    }
    if (symbols.length >= _maxVariables) {
      context.limit(
        declaration.token,
        'A procedure may have at most $_maxVariables visible variables.',
      );
    }
    if (declaration.isConst) {
      if (declaration.type == _Declared.range ||
          declaration.type == _Declared.worksheet) {
        context.type(declaration.token, 'Constants must be scalar.');
      }
      final initializer = declaration.initializer!;
      _constant(initializer);
      _assignable(
        declaration.type,
        _expression(initializer),
        initializer.token,
      );
    }
    symbols[name] = _Symbol(
      declaration.type,
      declaration.isConst,
      declaration.token,
    );
  }

  void _constant(_Expr expression) {
    switch (expression) {
      case _Literal():
        break;
      case _Name():
        if (!(symbols[expression.token.lower]?.isConst ?? false)) {
          context.unsupported(
            expression.token,
            'Const expressions may only refer to previously declared constants.',
          );
        }
      case _Unary():
        _constant(expression.operand);
      case _Binary():
        _constant(expression.left);
        _constant(expression.right);
      default:
        context.unsupported(
          expression.token,
          'Const expressions cannot call functions or access objects.',
        );
    }
  }

  void _implicit(List<_Statement> statements) {
    for (final statement in statements) {
      _Token? variable;
      switch (statement) {
        case _Assignment(target: final _Name target):
          variable = target.token;
        case _For():
          variable = statement.counter;
          _implicit(statement.body);
        case _With():
          _implicit(statement.body);
        case _If():
          for (final branch in statement.branches) {
            _implicit(branch.$2);
          }
          _implicit(statement.otherwise);
        default:
          break;
      }
      if (variable != null && !symbols.containsKey(variable.lower)) {
        if (module.explicit || _reserved.contains(variable.lower)) {
          context.fail(
            variable,
            'vba_name_error',
            'Undeclared or reserved variable ${variable.text}.',
          );
        }
        if (symbols.length >= _maxVariables) {
          context.limit(variable, 'Too many variables.');
        }
        symbols[variable.lower] = _Symbol(_Declared.variant, false, variable);
      }
    }
  }

  void _statements(List<_Statement> statements, {bool nested = false}) {
    for (final statement in statements) {
      switch (statement) {
        case _Declaration():
          if (nested) {
            context.unsupported(
              statement.token,
              'Declarations inside control-flow blocks are unsupported.',
            );
          }
        case _Assignment():
          final valueKind = _expression(statement.value);
          if (statement.target case final _Name target) {
            final symbol = _symbol(target.token);
            if (symbol.isConst || counters.contains(target.token.lower)) {
              context.unsupported(
                target.token,
                'Constants and active For counters cannot be assigned.',
              );
            }
            final object =
                symbol.type == _Declared.worksheet ||
                symbol.type == _Declared.range;
            if (statement.isSet != object) {
              context.type(
                target.token,
                'Set is required only for declared Worksheet and Range variables.',
              );
            }
            _assignable(symbol.type, valueKind, statement.value.token);
          } else if (statement.target case final _Member target) {
            if (statement.isSet) {
              context.unsupported(
                target.token,
                'Set only supports declared object variables.',
              );
            }
            final expected = _writeKind(target);
            _compatible(expected, valueKind, statement.value.token);
          } else {
            context.unsupported(
              statement.target.token,
              'Unsupported assignment target.',
            );
          }
        case _Clear():
          _arguments(statement.target, 0, allowProperty: true);
          if (_expression(statement.target.receiver) != _Kind.range) {
            context.type(
              statement.token,
              'ClearContents requires an explicit Range.',
            );
          }
        case _For():
          final counter = _symbol(statement.counter);
          if (counter.isConst ||
              (counter.type != _Declared.long &&
                  counter.type != _Declared.variant)) {
            context.type(
              statement.counter,
              'For requires a mutable Long or Variant counter.',
            );
          }
          if (!counters.add(statement.counter.lower)) {
            context.unsupported(
              statement.counter,
              'Nested loops must use distinct counters.',
            );
          }
          for (final value in <_Expr>[
            statement.start,
            statement.end,
            statement.step,
          ]) {
            _compatible(_Kind.number, _expression(value), value.token);
          }
          _statements(statement.body, nested: true);
          counters.remove(statement.counter.lower);
        case _With():
          final kind = _expression(statement.target);
          if (kind != _Kind.worksheet && kind != _Kind.range) {
            context.type(
              statement.token,
              'With requires a Worksheet or Range.',
            );
          }
          withKinds.add(kind);
          _statements(statement.body, nested: true);
          withKinds.removeLast();
        case _If():
          for (final branch in statement.branches) {
            _compatible(_Kind.boolean, _expression(branch.$1), branch.$1.token);
            _statements(branch.$2, nested: true);
          }
          _statements(statement.otherwise, nested: true);
      }
    }
  }

  _Kind _writeKind(_Member target) {
    _arguments(target, 0, allowProperty: true);
    final receiver = _expression(target.receiver);
    final property = target.token.lower;
    if (receiver == _Kind.range) {
      if (property == 'value' || property == 'value2') return _Kind.variant;
      if (property == 'formula') return _Kind.string;
    } else if (receiver == _Kind.font) {
      if (property == 'bold') return _Kind.boolean;
      if (property == 'size' || property == 'color') return _Kind.number;
    } else if (receiver == _Kind.interior && property == 'color') {
      return _Kind.number;
    }
    context.unsupported(
      target.token,
      'Unsupported writable property ${target.token.text}.',
    );
  }

  _Kind _expression(_Expr expression) {
    switch (expression) {
      case _Literal():
        return expression.value is num
            ? _Kind.number
            : expression.value is bool
            ? _Kind.boolean
            : _Kind.string;
      case _Name():
        if (expression.token.lower == 'thisworkbook') return _Kind.workbook;
        return _kindOf(_symbol(expression.token).type);
      case _WithValue():
        if (withKinds.isEmpty) {
          context.unsupported(
            expression.token,
            'A leading dot requires an enclosing With block.',
          );
        }
        return withKinds.last;
      case _Call():
        if (expression.token.lower == 'worksheets') {
          _count(expression.token, expression.arguments, 1);
          final kind = _expression(expression.arguments.single);
          if (kind != _Kind.string &&
              kind != _Kind.number &&
              kind != _Kind.variant) {
            context.type(
              expression.token,
              'Worksheets needs a name or one-based index.',
            );
          }
          return _Kind.worksheet;
        }
        if (expression.token.lower == 'rgb') {
          _count(expression.token, expression.arguments, 3);
          for (final argument in expression.arguments) {
            _compatible(_Kind.number, _expression(argument), argument.token);
          }
          return _Kind.number;
        }
        context.unsupported(
          expression.token,
          'Only Worksheets and RGB function calls are supported.',
        );
      case _Member():
        final receiver = _expression(expression.receiver);
        final name = expression.token.lower;
        if (receiver == _Kind.workbook && name == 'worksheets') {
          final arguments = _arguments(expression, 1);
          final kind = _expression(arguments.single);
          if (kind != _Kind.string &&
              kind != _Kind.number &&
              kind != _Kind.variant) {
            context.type(
              expression.token,
              'Worksheets needs a name or one-based index.',
            );
          }
          return _Kind.worksheet;
        }
        if (receiver == _Kind.worksheet &&
            (name == 'range' || name == 'cells')) {
          final arguments = _arguments(expression, name == 'range' ? 1 : 2);
          for (final argument in arguments) {
            _compatible(
              name == 'range' ? _Kind.string : _Kind.number,
              _expression(argument),
              argument.token,
            );
          }
          return _Kind.range;
        }
        if (receiver == _Kind.range && (name == 'font' || name == 'interior')) {
          _arguments(expression, 0, allowProperty: true);
          return name == 'font' ? _Kind.font : _Kind.interior;
        }
        context.unsupported(
          expression.token,
          'Unsupported object member or document read: ${expression.token.text}.',
        );
      case _Unary():
        final expected = expression.token.lower == 'not'
            ? _Kind.boolean
            : _Kind.number;
        _compatible(
          expected,
          _expression(expression.operand),
          expression.operand.token,
        );
        return expected;
      case _Binary():
        final left = _expression(expression.left);
        final right = _expression(expression.right);
        final operator = expression.token.lower;
        if (operator == '&') {
          _scalar(left, expression.left.token);
          _scalar(right, expression.right.token);
          return _Kind.string;
        }
        if (const <String>{'and', 'or', 'xor'}.contains(operator)) {
          _compatible(_Kind.boolean, left, expression.left.token);
          _compatible(_Kind.boolean, right, expression.right.token);
          return _Kind.boolean;
        }
        if (const <String>{
          '=',
          '<>',
          '<',
          '>',
          '<=',
          '>=',
        }.contains(operator)) {
          _scalar(left, expression.left.token);
          _scalar(right, expression.right.token);
          if (left != right &&
              left != _Kind.variant &&
              right != _Kind.variant) {
            context.type(
              expression.token,
              'Comparisons require matching scalar types.',
            );
          }
          return _Kind.boolean;
        }
        _compatible(_Kind.number, left, expression.left.token);
        _compatible(_Kind.number, right, expression.right.token);
        return _Kind.number;
    }
  }

  _Symbol _symbol(_Token token) =>
      symbols[token.lower] ??
      context.fail(
        token,
        'vba_name_error',
        'Unknown name ${token.text}; active selections, default members, and undeclared reads are unsupported.',
      );

  List<_Expr> _arguments(
    _Member member,
    int count, {
    bool allowProperty = false,
  }) {
    final arguments = member.arguments;
    if (arguments == null && !(allowProperty && count == 0)) {
      context.type(member.token, '${member.token.text} needs arguments.');
    }
    // Property getter syntax must not accidentally become an invocation.
    if (allowProperty &&
        arguments != null &&
        member.token.lower != 'clearcontents') {
      context.unsupported(member.token, 'Property arguments are unsupported.');
    }
    _count(member.token, arguments ?? const <_Expr>[], count);
    return arguments ?? const <_Expr>[];
  }

  void _count(_Token token, List<_Expr> arguments, int count) {
    if (arguments.length != count) {
      context.type(token, '${token.text} requires $count argument(s).');
    }
  }

  void _assignable(_Declared type, _Kind value, _Token token) =>
      _compatible(_kindOf(type), value, token);

  void _compatible(_Kind expected, _Kind value, _Token token) {
    if (expected == _Kind.variant) {
      _scalar(value, token);
    } else if (expected != value && value != _Kind.variant) {
      context.type(
        token,
        'Implicit conversion from ${value.name} to ${expected.name} is unsupported.',
      );
    }
  }

  void _scalar(_Kind kind, _Token token) {
    if (kind != _Kind.string &&
        kind != _Kind.number &&
        kind != _Kind.boolean &&
        kind != _Kind.variant) {
      context.type(
        token,
        'A scalar value is required; object default members are unsupported.',
      );
    }
  }
}

class _Uninitialized {
  const _Uninitialized();
}

class _Workbook {
  const _Workbook();
}

class _Worksheet {
  const _Worksheet(this.selector);
  final Object selector;
}

class _Range {
  const _Range(
    this.sheet,
    this.minRow,
    this.minColumn,
    this.maxRow,
    this.maxColumn,
  );
  final _Worksheet sheet;
  final int minRow;
  final int minColumn;
  final int maxRow;
  final int maxColumn;
}

class _Font {
  const _Font(this.range);
  final _Range range;
}

class _Interior {
  const _Interior(this.range);
  final _Range range;
}

class _Evaluator {
  _Evaluator(this.context, this.module, this.checker);
  final _Context context;
  final _Module module;
  final _Checker checker;
  final List<OfficeMacroStep> steps = <OfficeMacroStep>[];
  final Map<String, Object> values = <String, Object>{};
  final List<Object> withValues = <Object>[];
  late final Map<String, _Symbol> symbols;
  int work = 0;
  int encodedBytes = 0;

  OfficeMacro compile() {
    final procedure =
        module.procedures[context.source.entryPoint.toLowerCase()]!;
    symbols = checker.locals[procedure.name.lower]!;
    final fullName = '${context.source.moduleName}.${procedure.name.text}';
    final name = fullName.length <= 128 ? fullName : procedure.name.text;
    encodedBytes = utf8
        .encode(
          jsonEncode(<String, Object?>{
            'version': 1,
            'name': name,
            'format': 'xlsx',
            'steps': <Object?>[],
          }),
        )
        .length;
    for (final entry in symbols.entries) {
      values[entry.key] = _default(entry.value.type);
    }
    for (final declaration in module.constants) {
      _initialize(declaration);
    }
    _execute(procedure.body);
    try {
      return OfficeMacro(
        name: name,
        format: OfficeMacroFormat.xlsx,
        steps: steps,
      );
    } on OfficeMacroException catch (error) {
      if (error.code == 'limit_exceeded') {
        context.limit(procedure.name, error.message);
      }
      rethrow;
    }
  }

  Object _default(_Declared type) => switch (type) {
    _Declared.long => 0,
    _Declared.doubleType => 0.0,
    _Declared.string => '',
    _Declared.boolean => false,
    _ => const _Uninitialized(),
  };

  void _initialize(_Declaration declaration) {
    if (declaration.initializer != null) {
      values[declaration.token.lower] = _convert(
        declaration.type,
        _evaluate(declaration.initializer!),
        declaration.token,
      );
    }
  }

  void _tick(_Token token) {
    if (++work > _maxWork) {
      context.limit(
        token,
        'Compilation exceeds $_maxWork evaluation/statement visits.',
      );
    }
  }

  void _execute(List<_Statement> statements) {
    for (final statement in statements) {
      _tick(statement.token);
      switch (statement) {
        case _Declaration():
          _initialize(statement);
        case _Assignment():
          final value = _evaluate(statement.value);
          if (statement.target case final _Name name) {
            values[name.token.lower] = _convert(
              symbols[name.token.lower]!.type,
              value,
              name.token,
            );
          } else {
            _write(statement.target as _Member, value);
          }
        case _Clear():
          final range = _evaluate(statement.target.receiver) as _Range;
          _emitRange(range, 'cellValue', <String, Object?>{
            'value': null,
          }, statement.token);
        case _With():
          final target = _evaluate(statement.target);
          withValues.add(target);
          _execute(statement.body);
          withValues.removeLast();
        case _If():
          var matched = false;
          for (final branch in statement.branches) {
            if (_boolean(_evaluate(branch.$1), branch.$1.token)) {
              _execute(branch.$2);
              matched = true;
              break;
            }
          }
          if (!matched) _execute(statement.otherwise);
        case _For():
          final start = _loopInteger(
            _evaluate(statement.start),
            statement.start.token,
          );
          final end = _loopInteger(
            _evaluate(statement.end),
            statement.end.token,
          );
          final step = _loopInteger(
            _evaluate(statement.step),
            statement.step.token,
          );
          if (step == 0) {
            context.unsupported(
              statement.step.token,
              'Step 0 is unsupported because it does not bound iteration.',
            );
          }
          final count = step > 0
              ? (start > end ? 0 : (end - start) ~/ step + 1)
              : (start < end ? 0 : (start - end) ~/ -step + 1);
          if (count > _maxWork - work) {
            context.limit(
              statement.token,
              'For loop exceeds the remaining compilation work budget.',
            );
          }
          final type = symbols[statement.counter.lower]!.type;
          var counter = start;
          values[statement.counter.lower] = _convert(
            type,
            counter,
            statement.counter,
          );
          for (var iteration = 0; iteration < count; iteration++) {
            _tick(statement.token);
            _execute(statement.body);
            counter += step;
            values[statement.counter.lower] = _convert(
              type,
              counter,
              statement.counter,
            );
          }
      }
    }
  }

  Object _evaluate(_Expr expression) {
    _tick(expression.token);
    switch (expression) {
      case _Literal():
        return expression.value;
      case _Name():
        if (expression.token.lower == 'thisworkbook') return const _Workbook();
        final value = values[expression.token.lower]!;
        if (value is _Uninitialized) {
          context.unsupported(
            expression.token,
            'Uninitialized Variant/objects (Empty or Nothing) are unsupported; assign before reading.',
          );
        }
        return value;
      case _WithValue():
        return withValues.last;
      case _Call():
        final arguments = <Object>[
          for (final argument in expression.arguments) _evaluate(argument),
        ];
        return expression.token.lower == 'worksheets'
            ? _sheet(arguments.single, expression.token)
            : _rgb(arguments, expression.token);
      case _Member():
        final receiver = _evaluate(expression.receiver);
        final arguments = <Object>[
          for (final argument in expression.arguments ?? const <_Expr>[])
            _evaluate(argument),
        ];
        if (receiver is _Workbook) {
          return _sheet(arguments.single, expression.token);
        }
        if (receiver is _Worksheet) {
          if (expression.token.lower == 'range') {
            return _range(
              receiver,
              _string(arguments.single, expression.token),
              expression.token,
            );
          }
          final row = _integer(arguments[0], expression.token);
          final column = _integer(arguments[1], expression.token);
          _coordinates(row, column, expression.token);
          return _Range(receiver, row, column, row, column);
        }
        final range = receiver as _Range;
        return expression.token.lower == 'font'
            ? _Font(range)
            : _Interior(range);
      case _Unary():
        final value = _evaluate(expression.operand);
        if (expression.token.lower == 'not') {
          return !_boolean(value, expression.token);
        }
        final number = _number(value, expression.token);
        return _finite(
          expression.token.lower == '-' ? -number : number,
          expression.token,
        );
      case _Binary():
        // VBA And/Or are eager, so both operands are evaluated.
        final left = _evaluate(expression.left);
        final right = _evaluate(expression.right);
        final operator = expression.token.lower;
        if (operator == '&') {
          final a = _scalarString(left, expression.token);
          final b = _scalarString(right, expression.token);
          if (a.length > _maxString - b.length) {
            context.limit(
              expression.token,
              'Concatenation exceeds $_maxString code units.',
            );
          }
          return a + b;
        }
        if (const <String>{'and', 'or', 'xor'}.contains(operator)) {
          final a = _boolean(left, expression.token);
          final b = _boolean(right, expression.token);
          return operator == 'and'
              ? a && b
              : operator == 'or'
              ? a || b
              : a != b;
        }
        if (const <String>{
          '=',
          '<>',
          '<',
          '>',
          '<=',
          '>=',
        }.contains(operator)) {
          final int comparison;
          if (left is num && right is num) {
            // Dart compareTo distinguishes signed zero; VBA numeric equality
            // and ordering do not distinguish -0.0 from 0.0.
            comparison = left == right ? 0 : left.compareTo(right);
          } else if (left is String && right is String) {
            comparison = left.compareTo(right);
          } else if (left is bool && right is bool) {
            // VBA True is -1 and False is 0 when ordering Booleans.
            comparison = (left ? -1 : 0).compareTo(right ? -1 : 0);
          } else {
            context.type(
              expression.token,
              'Comparisons require matching scalar types.',
            );
          }
          return switch (operator) {
            '=' => comparison == 0,
            '<>' => comparison != 0,
            '<' => comparison < 0,
            '>' => comparison > 0,
            '<=' => comparison <= 0,
            _ => comparison >= 0,
          };
        }
        // Use floating-point intermediates before checking the safe-integer
        // magnitude. Native Dart int multiplication can wrap before a later
        // range check; JS has no equivalent 64-bit integer arithmetic.
        final a = _number(left, expression.token).toDouble();
        final b = _number(right, expression.token).toDouble();
        if (operator == '/' && b == 0) {
          context.fail(
            expression.token,
            'vba_arithmetic_error',
            'Division by zero.',
          );
        }
        final result = _finite(switch (operator) {
          '+' => a + b,
          '-' => a - b,
          '*' => a * b,
          _ => a / b,
        }, expression.token);
        return result == result.truncateToDouble() ? result.toInt() : result;
    }
  }

  Object _convert(_Declared type, Object value, _Token token) {
    switch (type) {
      case _Declared.long:
        final number = _integer(value, token);
        if (number < -2147483648 || number > 2147483647) {
          context.type(
            token,
            'Long assignment overflows its signed 32-bit range.',
          );
        }
        return number;
      case _Declared.doubleType:
        return _number(value, token).toDouble();
      case _Declared.string:
        return _string(value, token);
      case _Declared.boolean:
        return _boolean(value, token);
      case _Declared.variant:
        if (value is! String && value is! num && value is! bool) {
          context.type(token, 'Variant bindings support scalar values only.');
        }
        return value is num ? _finite(value, token) : value;
      case _Declared.worksheet:
        if (value is! _Worksheet) {
          context.type(token, 'Set requires a Worksheet.');
        }
        return value;
      case _Declared.range:
        if (value is! _Range) context.type(token, 'Set requires a Range.');
        return value;
    }
  }

  num _finite(num value, _Token token) {
    if (!value.isFinite || value.abs() > _maxExactInteger) {
      context.limit(
        token,
        'Arithmetic exceeds finite, portable numeric bounds.',
      );
    }
    return value;
  }

  num _number(Object value, _Token token) {
    if (value is! num) {
      context.type(
        token,
        'A number is required; scalar coercions are unsupported.',
      );
    }
    return _finite(value, token);
  }

  int _integer(Object value, _Token token) {
    final number = _number(value, token);
    if (number.abs() > _maxExactInteger ||
        number != number.truncateToDouble()) {
      context.type(
        token,
        'An exact integer is required; rounding is unsupported.',
      );
    }
    return number.toInt();
  }

  int _loopInteger(Object value, _Token token) {
    final number = _integer(value, token);
    if (number < -2147483648 || number > 2147483647) {
      context.type(
        token,
        'For bounds and Step must be signed 32-bit integers.',
      );
    }
    return number;
  }

  String _string(Object value, _Token token) {
    if (value is! String) {
      context.type(
        token,
        'A string is required; scalar coercions are unsupported.',
      );
    }
    return value;
  }

  bool _boolean(Object value, _Token token) {
    if (value is! bool) {
      context.type(
        token,
        'A Boolean is required; numeric coercions and bitwise logic are unsupported.',
      );
    }
    return value;
  }

  String _scalarString(Object value, _Token token) {
    if (value is String) return value;
    if (value is bool) return value ? 'True' : 'False';
    if (value is num) {
      return value == value.truncateToDouble()
          ? value.toInt().toString()
          : value.toString();
    }
    context.type(token, 'Concatenation requires scalar operands.');
  }

  _Worksheet _sheet(Object value, _Token token) {
    if (value is String) {
      if (value.isEmpty || value.length > 31) {
        context.type(token, 'Worksheet names must contain 1..31 code units.');
      }
      return _Worksheet(value);
    }
    final index = _integer(value, token);
    if (index < 1 || index > 2147483647) {
      context.type(token, 'Worksheet indexes are one-based positive integers.');
    }
    return _Worksheet(index - 1);
  }

  int _rgb(List<Object> arguments, _Token token) {
    final components = <int>[];
    for (final argument in arguments) {
      final number = _integer(argument, token);
      if (number < 0) context.type(token, 'RGB components cannot be negative.');
      components.add(number > 255 ? 255 : number);
    }
    return components[0] + components[1] * 256 + components[2] * 65536;
  }

  void _coordinates(int row, int column, _Token token) {
    if (row < 1 || row > 1048576 || column < 1 || column > 16384) {
      context.type(token, 'Cell coordinates must be within A1:XFD1048576.');
    }
  }

  _Range _range(_Worksheet sheet, String address, _Token token) {
    if (address.length > 32) {
      context.unsupported(
        token,
        'Only bounded A1 cell or rectangular addresses are supported.',
      );
    }
    final match = RegExp(
      r'^\$?([A-Za-z]{1,3})\$?([1-9][0-9]{0,6})(?::\$?([A-Za-z]{1,3})\$?([1-9][0-9]{0,6}))?$',
    ).firstMatch(address);
    if (match == null) {
      context.unsupported(
        token,
        'Use A1 cells or rectangles; names, unions, whole rows/columns, and qualified strings are unsupported.',
      );
    }
    int column(String letters) {
      var result = 0;
      for (final code in letters.toUpperCase().codeUnits) {
        result = result * 26 + code - 64;
      }
      return result;
    }

    final row1 = int.parse(match.group(2)!);
    final col1 = column(match.group(1)!);
    final row2 = int.parse(match.group(4) ?? match.group(2)!);
    final col2 = column(match.group(3) ?? match.group(1)!);
    _coordinates(row1, col1, token);
    _coordinates(row2, col2, token);
    return _Range(
      sheet,
      row1 < row2 ? row1 : row2,
      col1 < col2 ? col1 : col2,
      row1 > row2 ? row1 : row2,
      col1 > col2 ? col1 : col2,
    );
  }

  void _write(_Member target, Object value) {
    final receiver = _evaluate(target.receiver);
    final property = target.token.lower;
    if (receiver is _Range) {
      if (property == 'formula') {
        final formula = _string(value, target.token);
        if (!formula.startsWith('=') || formula.length == 1) {
          context.unsupported(
            target.token,
            'Formula assignments require a nonempty formula beginning with =.',
          );
        }
        _emitRange(receiver, 'cellFormula', <String, Object?>{
          'formula': formula,
        }, target.token);
      } else {
        if (value is! String && value is! num && value is! bool) {
          context.type(
            target.token,
            'Value/Value2 supports scalar strings, numbers, and Booleans.',
          );
        }
        // Excel can reinterpret these as formulas. Do not silently preserve a
        // literal where native Excel would execute a formula.
        if (value is String && value.startsWith('=')) {
          context.unsupported(
            target.token,
            'Use Formula for strings beginning with =.',
          );
        }
        _emitRange(receiver, 'cellValue', <String, Object?>{
          'value': value,
        }, target.token);
      }
    } else if (receiver is _Font) {
      final String field;
      final Object normalized;
      if (property == 'bold') {
        field = 'bold';
        normalized = _boolean(value, target.token);
      } else if (property == 'size') {
        field = 'size';
        final size = _number(value, target.token);
        if (size < 1 || size > 409) {
          context.type(target.token, 'Font.Size must be in 1..409 points.');
        }
        normalized = size;
      } else {
        field = 'color';
        normalized = _color(value, target.token);
      }
      _emitRange(receiver.range, 'cellFormat', <String, Object?>{
        field: normalized,
      }, target.token);
    } else {
      _emitRange((receiver as _Interior).range, 'cellFormat', <String, Object?>{
        'fill': _color(value, target.token),
      }, target.token);
    }
  }

  String _color(Object value, _Token token) {
    final color = _integer(value, token);
    if (color < 0 || color > 0xFFFFFF) {
      context.unsupported(
        token,
        'Only explicit RGB colors are supported; system colors and palettes are unsupported.',
      );
    }
    String hex(int component) =>
        component.toRadixString(16).padLeft(2, '0').toUpperCase();
    return '${hex(color & 255)}${hex((color >> 8) & 255)}${hex((color >> 16) & 255)}';
  }

  void _emitRange(
    _Range range,
    String operation,
    Map<String, Object?> fields,
    _Token token,
  ) {
    final rows = range.maxRow - range.minRow + 1;
    final columns = range.maxColumn - range.minColumn + 1;
    final remaining = _maxSteps - steps.length;
    if (columns > remaining || rows > remaining ~/ columns) {
      context.limit(
        token,
        'Range expansion exceeds $_maxSteps emitted operations.',
      );
    }
    for (var row = range.minRow; row <= range.maxRow; row++) {
      for (var column = range.minColumn; column <= range.maxColumn; column++) {
        _tick(token);
        final arguments = <String, Object?>{
          'sheet': range.sheet.selector,
          'cell': '${_columnLetters(column)}$row',
          ...fields,
        };
        final json = <String, Object?>{
          'tool': 'xlsx.$operation',
          'arguments': arguments,
        };
        final bytes =
            utf8.encode(jsonEncode(json)).length + (steps.isEmpty ? 0 : 1);
        if (bytes > macroJsonByteLimit - encodedBytes) {
          context.limit(token, 'Compiled native JSON exceeds 1 MiB.');
        }
        encodedBytes += bytes;
        steps.add(
          OfficeMacroStep(tool: 'xlsx.$operation', arguments: arguments),
        );
      }
    }
  }

  String _columnLetters(int column) {
    var remaining = column;
    var result = '';
    while (remaining > 0) {
      remaining--;
      result = String.fromCharCode(65 + remaining % 26) + result;
      remaining ~/= 26;
    }
    return result;
  }
}

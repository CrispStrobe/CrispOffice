import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';

import 'package:quds_mail_core/quds_mail_core.dart';

/// Quoting is ambiguous between these formats; it is never auto-detected.
enum MailMboxDialect { mboxrd, mboxo }

/// One original MIME record, or a visible failure for that record's ordinal.
final class MailMboxEntry {
  const MailMboxEntry.message(this.ordinal, Uint8List value)
    : bytes = value,
      problem = null;

  const MailMboxEntry.failure(this.ordinal, MailProblem value)
    : bytes = null,
      problem = value;

  /// One-based record position. A terminal failure may identify the next record.
  final int ordinal;
  final Uint8List? bytes;
  final MailProblem? problem;
  bool get isSuccess => bytes != null;
}

/// Read bounded mboxrd or mboxo records with backpressure.
///
/// Envelope separators must have an ASCII `From sender Wdy Mon dd hh:mm:ss
/// [zone] yyyy` line (a trailing `remote from host` is accepted). LF and CRLF
/// are preserved in extracted messages. Envelope lines are removed; mboxrd
/// removes one `>` from `>+From ` lines, while mboxo removes one only from
/// `>From `. This preserves the chosen format's MIME octets, not the entire
/// original container. Ambiguous literal From_ lines cannot be recovered.
///
/// Empty input or a non-envelope preamble returns invalidInput. An oversized
/// message returns quotaExceeded, then scanning resumes at the next valid
/// separator without retaining the oversized content. The first record beyond
/// maxMessages returns quotaExceeded and closes the source. Content-Length
/// headers return unsupported and stop: mboxcl/mboxcl2 require different framing.
/// MIME interpretation and per-message diagnostics belong to [MailCodec].
///
/// At most one admitted message and a 1 KiB envelope candidate are buffered.
/// Copying a completed message temporarily requires a second message buffer.
/// Caller-supplied chunks are inspected without copying an entire input chunk.
/// Cancellation is checked during scanning and every 25 ms while awaiting a
/// source event. Source failures are redacted to storageFailure.
Stream<MailMboxEntry> readMailMbox(
  Stream<List<int>> input, {
  int maxMessageBytes = 32 * 1024 * 1024,
  int maxMessages = 100000,
  MailMboxDialect dialect = MailMboxDialect.mboxrd,
  MailCancellationToken? cancellation,
}) async* {
  if (maxMessageBytes < 1 ||
      maxMessageBytes > 1024 * 1024 * 1024 ||
      maxMessages < 1 ||
      maxMessages > 10000000) {
    yield const MailMboxEntry.failure(
      1,
      MailProblem(MailProblemCode.invalidInput),
    );
    return;
  }
  if (cancellation?.isCancelled ?? false) {
    yield const MailMboxEntry.failure(
      1,
      MailProblem(MailProblemCode.cancelled),
    );
    return;
  }
  final iterator = StreamIterator(input);
  final parser = _MboxParser(maxMessageBytes, maxMessages, dialect);
  var inputClosed = false;
  Future<void> closeInput() async {
    if (inputClosed) return;
    inputClosed = true;
    try {
      await iterator.cancel();
    } on Object {
      // Preserve the primary fixed result if cleanup itself fails. Never expose
      // a filesystem path or exception text through a late cleanup exception.
    }
  }

  var chunks = 0;
  try {
    while (!parser.done && await _nextMboxChunk(iterator, cancellation)) {
      if ((++chunks & 63) == 0) {
        await Future<void>.delayed(Duration.zero);
        cancellation?.throwIfCancelled();
      }
      final chunk = iterator.current;
      for (var offset = 0; offset < chunk.length && !parser.done; offset++) {
        if (offset != 0 && (offset & 65535) == 0) {
          await Future<void>.delayed(Duration.zero);
        }
        if ((offset & 1023) == 0) cancellation?.throwIfCancelled();
        parser.add(chunk[offset]);
        if (parser.done) await closeInput();
        while (parser.ready.isNotEmpty) {
          yield parser.ready.removeFirst();
          if (!parser.done) cancellation?.throwIfCancelled();
        }
      }
    }
    if (!parser.done) cancellation?.throwIfCancelled();
    if (!parser.done) parser.finish();
    await closeInput();
    while (parser.ready.isNotEmpty) {
      yield parser.ready.removeFirst();
    }
  } on MailCancelled {
    await closeInput();
    yield MailMboxEntry.failure(
      parser.failureOrdinal,
      const MailProblem(MailProblemCode.cancelled),
    );
  } on Object {
    await closeInput();
    yield MailMboxEntry.failure(
      parser.failureOrdinal,
      const MailProblem(MailProblemCode.storageFailure),
    );
  } finally {
    parser.clear();
    await closeInput();
  }
}

Future<bool> _nextMboxChunk(
  StreamIterator<List<int>> iterator,
  MailCancellationToken? cancellation,
) {
  cancellation?.throwIfCancelled();
  final read = iterator.moveNext();
  if (cancellation == null) return read;
  final result = Completer<bool>();
  // There is exactly one outstanding read. Its late completion/error is always
  // observed even when cancellation wins and the iterator is being closed.
  read.then(
    (value) {
      if (!result.isCompleted) result.complete(value);
    },
    onError: (Object error, StackTrace stack) {
      if (!result.isCompleted) result.completeError(error, stack);
    },
  );
  final timer = Timer.periodic(const Duration(milliseconds: 25), (_) {
    if (cancellation.isCancelled && !result.isCompleted) {
      result.completeError(
        MailCancelled(cancellation.reason ?? MailCancellationReason.user),
      );
    }
  });
  return result.future.whenComplete(timer.cancel);
}

enum _LineMode { start, envelope, quotes, quoteWord, data }

const _from = <int>[0x46, 0x72, 0x6f, 0x6d, 0x20];
const _maxEnvelopeBytes = 1024;

final _envelope = RegExp(
  r'^From [!-~]+ (?:Mon|Tue|Wed|Thu|Fri|Sat|Sun) '
  r'(?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec) '
  r'[ ]?(?:0?[1-9]|[12][0-9]|3[01]) '
  r'(?:[01][0-9]|2[0-3]):[0-5][0-9]:[0-5][0-9] '
  r'(?:(?:[A-Z]{1,5}|[+-][0-9]{4}) )?[0-9]{4}'
  r'(?: (?:[A-Z]{1,5}|[+-][0-9]{4}))?'
  r'(?: remote from [!-~]+)?\r?\n$',
);

final class _MboxParser {
  _MboxParser(this.maxMessageBytes, this.maxMessages, this.dialect);

  final int maxMessageBytes;
  final int maxMessages;
  final MailMboxDialect dialect;
  final Queue<MailMboxEntry> ready = Queue();
  _LineMode mode = _LineMode.start;
  final List<int> candidate = [];
  int quotes = 0;
  int ordinal = 0;
  bool done = false;
  _MboxBytes? content;
  bool inHeaders = true;
  final List<int> headerPrefix = [];

  int get failureOrdinal => ordinal == 0 ? 1 : ordinal;

  void add(int byte) {
    if (byte < 0 || byte > 255) {
      _fail(MailProblemCode.invalidInput);
      return;
    }
    switch (mode) {
      case _LineMode.start:
        if (byte == _from.first) {
          candidate.add(byte);
          mode = _LineMode.envelope;
        } else if (byte == 0x3e) {
          quotes = 1;
          mode = _LineMode.quotes;
        } else {
          mode = _LineMode.data;
          _append(byte);
          if (byte == 0x0a) _lineDone();
        }
      case _LineMode.envelope:
        candidate.add(byte);
        if ((candidate.length <= _from.length &&
                byte != _from[candidate.length - 1]) ||
            candidate.length > _maxEnvelopeBytes) {
          _flushCandidate();
          mode = _LineMode.data;
          if (byte == 0x0a) _lineDone();
        } else if (byte == 0x0a) {
          if (_envelope.hasMatch(String.fromCharCodes(candidate))) {
            _separator();
          } else {
            _flushCandidate();
          }
          _lineDone();
        }
      case _LineMode.quotes:
        if (byte == 0x3e) {
          quotes++;
        } else {
          candidate.add(byte);
          if (byte == _from.first) {
            mode = _LineMode.quoteWord;
          } else {
            _flushQuotes(false);
            mode = _LineMode.data;
            if (byte == 0x0a) _lineDone();
          }
        }
      case _LineMode.quoteWord:
        candidate.add(byte);
        if (byte != _from[candidate.length - 1]) {
          _flushQuotes(false);
          mode = _LineMode.data;
          if (byte == 0x0a) _lineDone();
        } else if (candidate.length == _from.length) {
          _flushQuotes(true);
          mode = _LineMode.data;
        }
      case _LineMode.data:
        _append(byte);
        if (byte == 0x0a) _lineDone();
    }
  }

  void _separator() {
    if (content != null) _finishMessage();
    ordinal++;
    if (ordinal > maxMessages) {
      _fail(MailProblemCode.quotaExceeded);
      return;
    }
    content = _MboxBytes(maxMessageBytes);
    inHeaders = true;
    headerPrefix.clear();
  }

  void _append(int byte) {
    if (done) return;
    final target = content;
    if (target == null) {
      _fail(MailProblemCode.invalidInput);
      return;
    }
    if (inHeaders) {
      if (byte == 0x0a) {
        if (headerPrefix.isEmpty ||
            (headerPrefix.length == 1 && headerPrefix.single == 0x0d)) {
          inHeaders = false;
        }
        headerPrefix.clear();
      } else if (headerPrefix.length < 16) {
        headerPrefix.add(byte);
        if (headerPrefix.length == 15 &&
            String.fromCharCodes(headerPrefix).toLowerCase() ==
                'content-length:') {
          _fail(MailProblemCode.unsupported);
          return;
        }
      }
    }
    target.add(byte);
  }

  void _flushCandidate() {
    for (final byte in candidate) {
      _append(byte);
      if (done) break;
    }
    candidate.clear();
  }

  void _flushQuotes(bool fromLine) {
    final remove =
        fromLine && (dialect == MailMboxDialect.mboxrd || quotes == 1);
    final count = quotes - (remove ? 1 : 0);
    // Once the message exceeds its budget, additional repeated bytes need not
    // be materialized. Framing still scans every incoming byte.
    final remaining = content == null
        ? 1
        : maxMessageBytes - content!.length + 1;
    final work = count < remaining ? count : remaining;
    for (var index = 0; index < work && !done; index++) {
      _append(0x3e);
    }
    quotes = 0;
    _flushCandidate();
  }

  void _lineDone() {
    mode = _LineMode.start;
    candidate.clear();
    quotes = 0;
  }

  void _finishMessage() {
    final target = content!;
    if (target.overflow) {
      ready.add(
        MailMboxEntry.failure(
          ordinal,
          const MailProblem(MailProblemCode.quotaExceeded),
        ),
      );
    } else if (target.length == 0) {
      ready.add(
        MailMboxEntry.failure(
          ordinal,
          const MailProblem(MailProblemCode.invalidInput),
        ),
      );
    } else {
      ready.add(MailMboxEntry.message(ordinal, target.take()));
    }
    target.clear();
    content = null;
  }

  void finish() {
    switch (mode) {
      case _LineMode.envelope:
        _flushCandidate();
      case _LineMode.quotes || _LineMode.quoteWord:
        _flushQuotes(false);
      case _LineMode.start || _LineMode.data:
        break;
    }
    if (done) return;
    if (content == null) {
      _fail(MailProblemCode.invalidInput);
    } else {
      _finishMessage();
      done = true;
    }
  }

  void _fail(MailProblemCode code) {
    if (done) return;
    ready.add(MailMboxEntry.failure(failureOrdinal, MailProblem(code)));
    done = true;
    content?.clear();
  }

  void clear() {
    content?.clear();
    ready.clear();
    candidate.clear();
    headerPrefix.clear();
  }
}

/// Fixed-size slabs avoid a `List<int>` allocation per input byte or large line.
final class _MboxBytes {
  _MboxBytes(this.limit);
  final int limit;
  final List<Uint8List> slabs = [];
  int length = 0;
  int tailLength = 0;
  bool overflow = false;

  void add(int byte) {
    if (overflow) return;
    if (length == limit) {
      clear();
      overflow = true;
      length = limit + 1;
      return;
    }
    if (slabs.isEmpty || tailLength == slabs.last.length) {
      final remaining = limit - length;
      slabs.add(Uint8List(remaining < 65536 ? remaining : 65536));
      tailLength = 0;
    }
    slabs.last[tailLength++] = byte;
    length++;
  }

  Uint8List take() {
    final result = Uint8List(length);
    var offset = 0;
    for (var index = 0; index < slabs.length; index++) {
      final count = index == slabs.length - 1
          ? tailLength
          : slabs[index].length;
      result.setRange(offset, offset + count, slabs[index]);
      offset += count;
    }
    return result;
  }

  void clear() {
    slabs.clear();
    length = 0;
    tailLength = 0;
  }
}

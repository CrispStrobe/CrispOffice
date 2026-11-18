import 'bytes.dart';
import 'message.dart';

/// Limits apply before allocation and cumulatively during decode/traversal.
/// A MIME codec must call [validate] before using caller-supplied limits.
final class MailReadBudget {
  const MailReadBudget({
    this.maxRawBytes = 32 * 1024 * 1024,
    this.maxDecodedBytes = 32 * 1024 * 1024,
    this.maxBodyBytes = 8 * 1024 * 1024,
    this.maxAttachmentBytes = 16 * 1024 * 1024,
    this.maxAttachments = 128,
    this.maxParts = 512,
    this.maxNestingDepth = 20,
    this.maxHeaderBytes = 256 * 1024,
    this.maxHeaderFieldBytes = 64 * 1024,
    this.maxHtmlNodes = 20000,
    this.maxHtmlDepth = 64,
    this.maxRenderTextBytes = 8 * 1024 * 1024,
    this.maxImagePixels = 16 * 1024 * 1024,
  });

  const MailReadBudget.preview({
    this.maxRawBytes = 20 * 1024 * 1024,
    this.maxDecodedBytes = 32 * 1024 * 1024,
    this.maxBodyBytes = 8 * 1024 * 1024,
    this.maxAttachmentBytes = 16 * 1024 * 1024,
    this.maxAttachments = 128,
    this.maxParts = 512,
    this.maxNestingDepth = 20,
    this.maxHeaderBytes = 256 * 1024,
    this.maxHeaderFieldBytes = 64 * 1024,
    this.maxHtmlNodes = 20000,
    this.maxHtmlDepth = 64,
    this.maxRenderTextBytes = 8 * 1024 * 1024,
    this.maxImagePixels = 16 * 1024 * 1024,
  });

  final int maxRawBytes;
  final int maxDecodedBytes;
  final int maxBodyBytes;
  final int maxAttachmentBytes;
  final int maxAttachments;
  final int maxParts;
  final int maxNestingDepth;
  final int maxHeaderBytes;
  final int maxHeaderFieldBytes;
  final int maxHtmlNodes;
  final int maxHtmlDepth;
  final int maxRenderTextBytes;
  final int maxImagePixels;

  void validate() {
    final limits = <int>[
      maxRawBytes,
      maxDecodedBytes,
      maxBodyBytes,
      maxAttachmentBytes,
      maxAttachments,
      maxParts,
      maxNestingDepth,
      maxHeaderBytes,
      maxHeaderFieldBytes,
      maxHtmlNodes,
      maxHtmlDepth,
      maxRenderTextBytes,
      maxImagePixels,
    ];
    if (limits.any((value) => value < 1)) {
      throw ArgumentError('Mail read budgets must be positive.');
    }
  }
}

enum MailParseStatus {
  complete,
  partial,
  rejected,
  unsupported,
  failed,
  cancelled,
}

enum MailDiagnosticSeverity { information, warning, error }

enum MailDiagnosticCode {
  rawLimit,
  decodedLimit,
  bodyLimit,
  attachmentLimit,
  attachmentCountLimit,
  partCountLimit,
  nestingLimit,
  headerLimit,
  headerFieldLimit,
  renderLimit,
  imageLimit,
  malformedHeader,
  malformedMime,
  malformedEncoding,
  unsupportedCharset,
  unsupportedTransferEncoding,
  invalidDate,
  truncatedMessage,
  invalidAddress,
  cancelled,
  internalFailure,
}

/// Structured diagnostics must never contain a message's source or credentials.
/// [message] is a fixed, content-redacted explanation supplied by the producer.
final class MailDiagnostic {
  const MailDiagnostic({
    required this.code,
    required this.message,
    this.severity = MailDiagnosticSeverity.warning,
    this.partPath,
    this.observed,
    this.limit,
  });

  final MailDiagnosticCode code;
  final String message;
  final MailDiagnosticSeverity severity;
  final String? partPath;
  final int? observed;
  final int? limit;
}

/// A limit rejection is never a truncated success. The host may retain original
/// bytes separately when copying them here would itself exceed the raw budget.
final class MailParseResult {
  MailParseResult({
    required this.status,
    this.message,
    MailBytes? original,
    List<MailDiagnostic> diagnostics = const [],
  }) : original = original ?? message?.raw,
       diagnostics = List.unmodifiable(diagnostics) {
    if ((status == MailParseStatus.complete ||
            status == MailParseStatus.partial) &&
        message == null) {
      throw ArgumentError(
        'Complete and partial parse results require a message.',
      );
    }
    if (status == MailParseStatus.complete &&
        diagnostics.any(
          (diagnostic) => diagnostic.severity == MailDiagnosticSeverity.error,
        )) {
      throw ArgumentError(
        'A complete result cannot contain error diagnostics.',
      );
    }
  }

  final MailParseStatus status;
  final MailMessage? message;
  final MailBytes? original;
  final List<MailDiagnostic> diagnostics;
  bool get hasMessage => message != null;
}

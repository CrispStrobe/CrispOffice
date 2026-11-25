/// Fixed ceilings for a single remote iCalendar task resource.
///
/// Callers cannot enlarge these limits. HTTP transports must independently
/// bound response bytes before decoding a String. The size limits here count
/// UTF-16 code units, not network bytes.
abstract final class CalDavCodecLimits {
  static const maxResourceCodeUnits = 2 * 1024 * 1024;
  static const maxPhysicalLines = 16384;
  static const maxUnfoldedLineCodeUnits = 256 * 1024;
  static const maxComponentDepth = 16;
}

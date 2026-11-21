import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

import 'studio_settings_backend_web.dart'
    if (dart.library.io) 'studio_settings_backend_io.dart'
    as platform;
import 'studio_shortcuts.dart';
import 'studio_strings.dart';
import 'studio_web_data_store.dart';

/// Where one settings document lives. Implementations replace the whole
/// document atomically: a reader sees either the previous or the new text,
/// never a partial write.
abstract interface class StudioSettingsBackend {
  /// The stored document, or null when there is none (or storage is
  /// unavailable). Never throws for a missing document.
  Future<String?> read();

  /// Replaces the stored document atomically.
  Future<void> write(String contents);

  /// Keeps an unreadable document aside (best effort) before it is replaced,
  /// so a corrupt file can still be inspected. Never throws.
  Future<void> quarantine(String contents);

  /// Where the document lives, for diagnostics.
  String get location;
}

/// The platform's settings document named [name]:
/// `<private app data directory>/settings/<name>.json` on native platforms
/// (the app's data container: Application Support on macOS/iOS, the
/// internal files directory on Android, %APPDATA% on Windows, XDG data on
/// Linux) and the browser's Cache Storage (the [StudioWebDataStore] layer
/// the verified proofing downloads use) on the web. Under `flutter test`
/// nothing on disk is read or written: the document lives in memory.
StudioSettingsBackend createDefaultStudioSettingsBackend({
  String name = 'studio-settings',
}) => platform.createDefaultStudioSettingsBackend(name);

/// In-memory backend (tests and hosts without storage).
final class MemoryStudioSettingsBackend implements StudioSettingsBackend {
  MemoryStudioSettingsBackend([this.contents]);
  String? contents;
  String? quarantined;
  int writes = 0;

  @override
  Future<String?> read() async => contents;

  @override
  Future<void> write(String contents) async {
    writes++;
    this.contents = contents;
  }

  @override
  Future<void> quarantine(String contents) async => quarantined = contents;

  @override
  String get location => 'memory';
}

/// Browser backend over [StudioWebDataStore] (Cache Storage). One `put`
/// replaces the stored response as a whole, so writes are atomic.
final class WebDataStoreStudioSettingsBackend implements StudioSettingsBackend {
  WebDataStoreStudioSettingsBackend(this.store, {required this.key});

  final StudioWebDataStore store;
  final String key;

  @override
  Future<String?> read() async {
    final bytes = await store.read(key);
    // Invalid UTF-8 becomes U+FFFD and then fails validation as corrupt.
    return bytes == null ? null : utf8.decode(bytes, allowMalformed: true);
  }

  @override
  Future<void> write(String contents) async {
    if (!await store.write(key, Uint8List.fromList(utf8.encode(contents)))) {
      throw StateError('The browser refused to store the settings.');
    }
  }

  @override
  Future<void> quarantine(String contents) async {
    try {
      await store.write(
        '$key.corrupt',
        Uint8List.fromList(utf8.encode(contents)),
      );
    } on Object {
      // Best effort only.
    }
  }

  @override
  String get location => 'browser storage ($key)';
}

/// One setting's type, default and validation. Invalid stored values are
/// replaced by the default; they never fail loading.
sealed class StudioSettingSpec {
  const StudioSettingSpec();
  Object get fallback;

  /// The validated value, or null when [value] is not acceptable.
  Object? accept(Object? value);
}

final class _Flag extends StudioSettingSpec {
  const _Flag(this.fallback);
  @override
  final bool fallback;
  @override
  Object? accept(Object? value) => value is bool ? value : null;
}

final class _Choice extends StudioSettingSpec {
  const _Choice(this.allowed, this.fallback);
  final List<String> allowed;
  @override
  final String fallback;
  @override
  Object? accept(Object? value) =>
      value is String && allowed.contains(value) ? value : null;
}

/// A whole number in [min]..[max] (for example milliseconds).
final class _Integer extends StudioSettingSpec {
  const _Integer(this.min, this.max, this.fallback);
  final int min;
  final int max;
  @override
  final int fallback;
  @override
  Object? accept(Object? value) {
    if (value is! num || !value.isFinite || value != value.roundToDouble()) {
      return null;
    }
    final whole = value.toInt();
    return whole < min || whole > max ? null : whole;
  }
}

/// Personal dictionary words by proofing language (`de-DE`: [...]).
final class _Words extends StudioSettingSpec {
  const _Words();
  static const maxLanguages = 32;
  static const maxWords = 10000;
  static const maxLength = 100;
  static final _language = RegExp(r'^[A-Za-z]{2,3}(-[A-Za-z0-9]{1,8})*$');

  @override
  Map<String, List<String>> get fallback => const <String, List<String>>{};

  @override
  Object? accept(Object? value) {
    if (value is! Map) return null;
    final out = <String, List<String>>{};
    for (final entry in value.entries.take(maxLanguages)) {
      final language = entry.key;
      final words = entry.value;
      if (language is! String || !_language.hasMatch(language)) continue;
      if (words is! List) continue;
      final kept = <String>{
        for (final word in words.take(maxWords))
          if (word is String &&
              word.trim().isNotEmpty &&
              word.length <= maxLength)
            word.trim(),
      }.toList()..sort();
      if (kept.isNotEmpty) out[language] = kept;
    }
    return out;
  }
}

/// Explicit shortcut overrides by action id. Missing actions use the catalog
/// default, so a new release can add defaults without rewriting old settings.
final class _ShortcutMap extends StudioSettingSpec {
  const _ShortcutMap();
  static const maxEntries = 256;

  @override
  Map<String, String> get fallback => const <String, String>{};

  @override
  Object? accept(Object? value) {
    if (value is! Map) return null;
    final out = <String, String>{};
    for (final entry in value.entries.take(maxEntries)) {
      final key = entry.key;
      final raw = entry.value;
      if (key is! String || key.length > 64 || raw is! String) continue;
      if (StudioShortcutBinding.tryParse(raw) == null) continue;
      out[key] = raw;
    }
    return out;
  }
}

/// Setting keys. Names are stable storage identifiers, never UI text.
abstract final class StudioSettingKeys {
  static const language = 'ui.language';
  static const look = 'ui.look';
  static const lengthUnit = 'ui.lengthUnit';
  static const shortcuts = 'ui.shortcuts';

  static const wordRulers = 'view.wordRulers';
  static const sheetGridlines = 'view.sheetGridlines';
  static const sheetHeaders = 'view.sheetHeaders';
  static const slideHandles = 'view.slideHandles';
  static const showNotes = 'view.showNotes';
  static const showComments = 'view.showComments';
  static const showOutline = 'view.showOutline';
  static const showAnimationPane = 'view.showAnimationPane';
  static const showSheetNavigation = 'view.showSheetNavigation';
  static const showPasteOptions = 'view.showPasteOptions';

  static const pdfNightMode = 'pdf.nightMode';
  static const pdfSwipeHorizontal = 'pdf.swipeHorizontal';
  static const pdfPageSnap = 'pdf.pageSnap';
  static const pdfPageFling = 'pdf.pageFling';
  static const pdfEnableSwipe = 'pdf.enableSwipe';
  static const pdfShowScroll = 'pdf.showScroll';
  static const pdfPreventLinks = 'pdf.preventLinks';
  static const pdfFitPolicy = 'pdf.fitPolicy';

  static const checkAsYouType = 'proofing.checkAsYouType';
  static const checkingMode = 'proofing.checkingMode';
  static const checkSpellingWhileTyping = 'proofing.checkSpellingWhileTyping';
  static const checkGrammarWhileTyping = 'proofing.checkGrammarWhileTyping';
  static const pauseMilliseconds = 'proofing.pauseMilliseconds';
  static const backgroundCheck = 'proofing.backgroundCheck';
  static const hideTypingErrors = 'proofing.hideTypingErrors';
  static const detectLanguage = 'proofing.detectLanguage';
  static const arabicContext = 'proofing.arabicContextReading';
  static const personalWords = 'proofing.personalWords';
}

/// The Studio's persisted settings: an immutable, validated snapshot.
///
/// Only preferences are stored; never credentials, tokens or document text
/// (mail passwords stay in the platform keychain). Values written by a newer
/// app that this version does not know are carried along unchanged.
@immutable
final class StudioSettings {
  const StudioSettings._(this._values, this.unknown);

  /// The defaults: what a fresh install shows.
  factory StudioSettings.defaults() => StudioSettings._({
    for (final entry in specs.entries) entry.key: entry.value.fallback,
  }, const <String, Object?>{});

  /// The schema of version [StudioSettingsStore.version].
  static final Map<String, StudioSettingSpec> specs =
      <String, StudioSettingSpec>{
        StudioSettingKeys.language: _Choice([
          for (final value in StudioLanguage.values) value.name,
        ], StudioLanguage.en.name),
        StudioSettingKeys.look: const _Choice([
          'light',
          'dark',
          'highContrast',
        ], 'light'),
        StudioSettingKeys.lengthUnit: _Choice([
          for (final value in OfficeLengthUnit.values) value.name,
        ], OfficeLengthUnit.millimeters.name),
        StudioSettingKeys.shortcuts: const _ShortcutMap(),
        StudioSettingKeys.wordRulers: const _Flag(true),
        StudioSettingKeys.sheetGridlines: const _Flag(true),
        StudioSettingKeys.sheetHeaders: const _Flag(true),
        StudioSettingKeys.slideHandles: const _Flag(true),
        StudioSettingKeys.showNotes: const _Flag(false),
        StudioSettingKeys.showComments: const _Flag(false),
        StudioSettingKeys.showOutline: const _Flag(false),
        StudioSettingKeys.showAnimationPane: const _Flag(true),
        StudioSettingKeys.showSheetNavigation: const _Flag(true),
        StudioSettingKeys.showPasteOptions: const _Flag(false),
        StudioSettingKeys.pdfNightMode: const _Flag(false),
        StudioSettingKeys.pdfSwipeHorizontal: const _Flag(false),
        StudioSettingKeys.pdfPageSnap: const _Flag(true),
        StudioSettingKeys.pdfPageFling: const _Flag(true),
        StudioSettingKeys.pdfEnableSwipe: const _Flag(true),
        StudioSettingKeys.pdfShowScroll: const _Flag(true),
        StudioSettingKeys.pdfPreventLinks: const _Flag(false),
        StudioSettingKeys.pdfFitPolicy: _Choice([
          for (final value in PdfFitPolicy.values) value.name,
        ], PdfFitPolicy.width.name),
        StudioSettingKeys.checkAsYouType: const _Flag(true),
        StudioSettingKeys.checkingMode: _Choice([
          for (final value in WordProofingMode.values) value.name,
        ], const WordProofingSchedule().mode.name),
        StudioSettingKeys.checkSpellingWhileTyping: _Flag(
          const WordProofingSchedule().checkSpelling,
        ),
        StudioSettingKeys.checkGrammarWhileTyping: _Flag(
          const WordProofingSchedule().checkGrammar,
        ),
        StudioSettingKeys.pauseMilliseconds: _Integer(
          WordProofingSchedule.minPause.inMilliseconds,
          WordProofingSchedule.maxPause.inMilliseconds,
          const WordProofingSchedule().pause.inMilliseconds,
        ),
        StudioSettingKeys.backgroundCheck: _Flag(
          const WordProofingSchedule().backgroundCheck,
        ),
        StudioSettingKeys.hideTypingErrors: _Flag(
          const WordProofingSchedule().hideTypingErrors,
        ),
        StudioSettingKeys.detectLanguage: const _Flag(true),
        StudioSettingKeys.arabicContext: const _Flag(true),
        StudioSettingKeys.personalWords: const _Words(),
      };

  final Map<String, Object> _values;

  /// Entries this version does not know (from a newer app), kept verbatim.
  final Map<String, Object?> unknown;

  bool flag(String key) => _values[key]! as bool;
  int integer(String key) => _values[key]! as int;

  /// The stored as-you-type proofing schedule.
  WordProofingSchedule get proofingSchedule => WordProofingSchedule(
    mode: choiceOf(
      StudioSettingKeys.checkingMode,
      WordProofingMode.values,
      WordProofingMode.whileTyping,
    ),
    checkSpelling: flag(StudioSettingKeys.checkSpellingWhileTyping),
    checkGrammar: flag(StudioSettingKeys.checkGrammarWhileTyping),
    pause: Duration(milliseconds: integer(StudioSettingKeys.pauseMilliseconds)),
    backgroundCheck: flag(StudioSettingKeys.backgroundCheck),
    hideTypingErrors: flag(StudioSettingKeys.hideTypingErrors),
  );

  /// The settings entries of [schedule] (the idle time is not a setting).
  static Map<String, Object> proofingScheduleJson(
    WordProofingSchedule schedule,
  ) => <String, Object>{
    StudioSettingKeys.checkingMode: schedule.mode.name,
    StudioSettingKeys.checkSpellingWhileTyping: schedule.checkSpelling,
    StudioSettingKeys.checkGrammarWhileTyping: schedule.checkGrammar,
    StudioSettingKeys.pauseMilliseconds: schedule.pause.inMilliseconds.clamp(
      WordProofingSchedule.minPause.inMilliseconds,
      WordProofingSchedule.maxPause.inMilliseconds,
    ),
    StudioSettingKeys.backgroundCheck: schedule.backgroundCheck,
    StudioSettingKeys.hideTypingErrors: schedule.hideTypingErrors,
  };
  String choice(String key) => _values[key]! as String;

  /// The enum value named by [key], or [fallback] for a name [values] lacks.
  T choiceOf<T extends Enum>(String key, List<T> values, T fallback) {
    final name = choice(key);
    for (final value in values) {
      if (value.name == name) return value;
    }
    return fallback;
  }

  Map<String, List<String>> get personalWords =>
      _values[StudioSettingKeys.personalWords]! as Map<String, List<String>>;

  Map<String, String> get shortcuts =>
      _values[StudioSettingKeys.shortcuts]! as Map<String, String>;

  /// A copy with [changes] applied; invalid values are rejected.
  StudioSettings copyWith(Map<String, Object?> changes) {
    final next = Map<String, Object>.of(_values);
    for (final entry in changes.entries) {
      final spec = specs[entry.key];
      if (spec == null) throw ArgumentError.value(entry.key, 'key');
      final value = spec.accept(entry.value);
      if (value == null) throw ArgumentError.value(entry.value, entry.key);
      next[entry.key] = value;
    }
    return StudioSettings._(next, unknown);
  }

  /// Reads the `settings` object of a current-version document. Each value
  /// is validated on its own; an invalid one falls back to its default and
  /// is listed in [repaired].
  static StudioSettings fromSettingsJson(
    Map<Object?, Object?> json, {
    List<String>? repaired,
  }) {
    final values = <String, Object>{};
    for (final entry in specs.entries) {
      final spec = entry.value;
      final stored = json[entry.key];
      final accepted = stored == null ? null : spec.accept(stored);
      if (stored != null && accepted == null) repaired?.add(entry.key);
      values[entry.key] = accepted ?? spec.fallback;
    }
    final unknown = <String, Object?>{
      for (final entry in json.entries)
        if (entry.key is String && !specs.containsKey(entry.key))
          entry.key! as String: entry.value,
    };
    return StudioSettings._(values, unknown);
  }

  Map<String, Object?> toSettingsJson() => <String, Object?>{
    ...unknown,
    for (final key in specs.keys) key: _values[key],
  };

  @override
  bool operator ==(Object other) =>
      other is StudioSettings &&
      jsonEncode(toSettingsJson()) == jsonEncode(other.toSettingsJson());

  @override
  int get hashCode => jsonEncode(toSettingsJson()).hashCode;
}

/// What [StudioSettingsStore.load] found.
enum StudioSettingsSource {
  /// Nothing stored yet: defaults.
  none,

  /// A current-version document.
  stored,

  /// An older document, upgraded (and rewritten on the next save).
  migrated,

  /// A document from a newer app: read best effort, never overwritten.
  newer,

  /// An unreadable document: defaults; it was set aside.
  corrupt,

  /// Storage failed: defaults.
  unavailable,
}

/// Loads and saves [StudioSettings] as one versioned JSON document:
///
/// ```json
/// {"format": "crispoffice-studio-settings", "version": 1,
///  "settings": {"ui.language": "de", "view.wordRulers": false, ...}}
/// ```
///
/// Loading never throws: a missing, corrupt or partly invalid document
/// yields defaults for whatever cannot be used. Saves are serialized and
/// coalesced (the latest snapshot wins) and each one replaces the document
/// atomically through the [backend].
class StudioSettingsStore {
  StudioSettingsStore({StudioSettingsBackend? backend})
    : backend = backend ?? createDefaultStudioSettingsBackend();

  static const format = 'crispoffice-studio-settings';

  /// The current schema version.
  static const version = 1;

  /// Documents larger than this are treated as corrupt.
  static const maxBytes = 1 << 20;

  final StudioSettingsBackend backend;

  StudioSettingsSource _source = StudioSettingsSource.none;
  StudioSettingsSource get source => _source;

  /// Keys whose stored values were invalid and replaced by defaults.
  List<String> get repaired => List.unmodifiable(_repaired);
  final _repaired = <String>[];

  /// The last save failure, if any (the settings stay in memory).
  Object? get saveError => _saveError;
  Object? _saveError;

  /// True after a newer app's document was loaded: saving would lose its
  /// data, so this version leaves it alone.
  bool get readOnly => _source == StudioSettingsSource.newer;

  Future<void> _writes = Future<void>.value();
  StudioSettings? _pending;

  /// Upgrades an older document's `settings` map to the current version.
  /// Version 0 is an unversioned document: a flat map of setting keys (for
  /// example one written by hand) without the `format`/`version` envelope.
  /// Later schema changes add a step here (rename or convert keys) and bump
  /// [version]; every step must accept anything and never throw.
  static Map<Object?, Object?> migrate(
    Map<Object?, Object?> settings,
    int from,
  ) {
    var current = Map<Object?, Object?>.of(settings);
    for (var v = from; v < version; v++) {
      current = switch (v) {
        // 0 -> 1: the flat map's keys are already version 1 keys; drop the
        // envelope fields a hand-written document might carry.
        0 =>
          current..removeWhere((key, _) => key == 'format' || key == 'version'),
        _ => current,
      };
    }
    return current;
  }

  Future<StudioSettings> load() async {
    _repaired.clear();
    final String? text;
    try {
      text = await backend.read();
    } on Object {
      _source = StudioSettingsSource.unavailable;
      return StudioSettings.defaults();
    }
    if (text == null) {
      _source = StudioSettingsSource.none;
      return StudioSettings.defaults();
    }
    try {
      if (text.length > maxBytes) throw const FormatException('too large');
      final Object? decoded = jsonDecode(text);
      if (decoded is! Map) throw const FormatException('not an object');
      final Object? stored = decoded['version'];
      if (stored == null && !decoded.containsKey('settings')) {
        _source = StudioSettingsSource.migrated;
        return StudioSettings.fromSettingsJson(
          migrate(decoded, 0),
          repaired: _repaired,
        );
      }
      if (decoded['format'] != format ||
          stored is! int ||
          stored < 1 ||
          decoded['settings'] is! Map) {
        throw const FormatException('not a settings document');
      }
      final settings = decoded['settings'] as Map;
      if (stored > version) {
        _source = StudioSettingsSource.newer;
        return StudioSettings.fromSettingsJson(settings, repaired: _repaired);
      }
      _source = stored < version
          ? StudioSettingsSource.migrated
          : StudioSettingsSource.stored;
      return StudioSettings.fromSettingsJson(
        stored < version ? migrate(settings, stored) : settings,
        repaired: _repaired,
      );
    } on Object {
      _source = StudioSettingsSource.corrupt;
      await backend.quarantine(text);
      return StudioSettings.defaults();
    }
  }

  static String encode(StudioSettings settings) =>
      const JsonEncoder.withIndent('  ').convert(<String, Object?>{
        'format': format,
        'version': version,
        'settings': settings.toSettingsJson(),
      });

  /// Saves [settings] after earlier saves; while one is running only the
  /// latest requested snapshot is written next. Failures are kept in
  /// [saveError], never thrown. A snapshot beyond the load size limit is
  /// rejected before writing, leaving the last readable document intact.
  Future<void> save(StudioSettings settings) {
    if (readOnly) return _writes;
    final queued = _pending != null;
    _pending = settings;
    if (queued) return _writes;
    return _writes = _writes.then((_) async {
      final next = _pending;
      _pending = null;
      if (next == null) return;
      try {
        final contents = encode(next);
        if (contents.length > maxBytes) {
          throw const FormatException(
            'Settings document exceeds the supported size limit.',
          );
        }
        await backend.write(contents);
        _saveError = null;
        if (_source != StudioSettingsSource.newer) {
          _source = StudioSettingsSource.stored;
        }
      } on Object catch (error) {
        _saveError = error;
      }
    });
  }

  /// Completes after every requested save finished.
  Future<void> flush() => _writes;
}

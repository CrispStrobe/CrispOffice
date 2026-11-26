import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// A user-visible Studio command and its optional default shortcut.
///
/// Settings store only the actions a user changed. Unknown action ids are
/// retained in the settings document but ignored by this catalog, which keeps
/// newer settings readable by older builds.
final class StudioShortcutAction {
  const StudioShortcutAction({
    required this.id,
    required this.label,
    this.key,
    this.shift = false,
    this.alt = false,
    this.primary = true,
    this.macKey,
    this.macShift,
    this.macControl = false,
  });

  final String id;
  final String label;
  final LogicalKeyboardKey? key;
  final bool shift;
  final bool alt;
  final bool primary;
  final LogicalKeyboardKey? macKey;
  final bool? macShift;
  final bool macControl;

  StudioShortcutBinding? defaultBinding({required bool mac}) {
    final trigger = mac ? macKey ?? key : key;
    if (trigger == null) return null;
    return StudioShortcutBinding(
      keyId: trigger.keyId,
      meta: primary && mac && !macControl,
      control: primary && (!mac || macControl),
      shift: mac ? macShift ?? shift : shift,
      alt: alt,
    );
  }
}

/// A persistable key combination. Key ids are Flutter's stable logical ids.
final class StudioShortcutBinding {
  const StudioShortcutBinding({
    required this.keyId,
    this.control = false,
    this.shift = false,
    this.alt = false,
    this.meta = false,
  });

  final int keyId;
  final bool control;
  final bool shift;
  final bool alt;
  final bool meta;

  SingleActivator get activator => SingleActivator(
    _key,
    control: control,
    shift: shift,
    alt: alt,
    meta: meta,
  );

  LogicalKeyboardKey get _key =>
      LogicalKeyboardKey.findKeyByKeyId(keyId) ?? LogicalKeyboardKey.keyA;

  String get label {
    final parts = <String>[
      if (control) 'Ctrl',
      if (alt) 'Alt',
      if (shift) 'Shift',
      if (meta) '⌘',
      _key.keyLabel,
    ];
    return parts.join('+');
  }

  String encode() {
    final parts = <String>[
      if (control) 'ctrl',
      if (alt) 'alt',
      if (shift) 'shift',
      if (meta) 'meta',
      '$keyId',
    ];
    return parts.join('+');
  }

  static StudioShortcutBinding? tryParse(String value) {
    final parts = value.split('+');
    var control = false, shift = false, alt = false, meta = false;
    for (final part in parts.take(parts.length - 1)) {
      switch (part) {
        case 'ctrl':
          control = true;
        case 'shift':
          shift = true;
        case 'alt':
          alt = true;
        case 'meta':
          meta = true;
        default:
          return null;
      }
    }
    final keyId = int.tryParse(parts.last);
    final key = keyId == null ? null : LogicalKeyboardKey.findKeyByKeyId(keyId);
    // SingleActivator rejects modifier keys as triggers, including the
    // platform-independent synonyms. Validate persisted input first.
    if (key == null ||
        _modifierKeys.contains(key) ||
        !(control || shift || alt || meta) &&
            (key.keyId < LogicalKeyboardKey.f1.keyId ||
                key.keyId > LogicalKeyboardKey.f24.keyId)) {
      return null;
    }
    return StudioShortcutBinding(
      keyId: keyId!,
      control: control,
      shift: shift,
      alt: alt,
      meta: meta,
    );
  }

  static const _modifierKeys = <LogicalKeyboardKey>[
    LogicalKeyboardKey.control,
    LogicalKeyboardKey.controlLeft,
    LogicalKeyboardKey.controlRight,
    LogicalKeyboardKey.shift,
    LogicalKeyboardKey.shiftLeft,
    LogicalKeyboardKey.shiftRight,
    LogicalKeyboardKey.alt,
    LogicalKeyboardKey.altLeft,
    LogicalKeyboardKey.altRight,
    LogicalKeyboardKey.meta,
    LogicalKeyboardKey.metaLeft,
    LogicalKeyboardKey.metaRight,
  ];
}

/// Configurable Studio shortcuts. The list is deliberately focused on commands the
/// editor implements; a configured key never silently creates a new command.
abstract final class StudioShortcutCatalog {
  static const List<StudioShortcutAction> actions = <StudioShortcutAction>[
    StudioShortcutAction(
      id: 'file.new',
      label: 'New document',
      key: LogicalKeyboardKey.keyN,
    ),
    StudioShortcutAction(
      id: 'file.open',
      label: 'Open…',
      key: LogicalKeyboardKey.keyO,
    ),
    StudioShortcutAction(
      id: 'file.save',
      label: 'Save',
      key: LogicalKeyboardKey.keyS,
    ),
    StudioShortcutAction(
      id: 'file.saveAs',
      label: 'Save As…',
      key: LogicalKeyboardKey.keyS,
      shift: true,
    ),
    StudioShortcutAction(
      id: 'file.print',
      label: 'Print…',
      key: LogicalKeyboardKey.keyP,
    ),
    StudioShortcutAction(
      id: 'file.exportPdf',
      label: 'Export PDF…',
      key: LogicalKeyboardKey.keyP,
      shift: true,
    ),
    StudioShortcutAction(
      id: 'file.close',
      label: 'Close file',
      key: LogicalKeyboardKey.keyW,
    ),
    StudioShortcutAction(
      id: 'edit.undo',
      label: 'Undo',
      key: LogicalKeyboardKey.keyZ,
    ),
    StudioShortcutAction(
      id: 'edit.redo',
      label: 'Redo',
      key: LogicalKeyboardKey.keyY,
      macKey: LogicalKeyboardKey.keyZ,
      macShift: true,
    ),
    StudioShortcutAction(
      id: 'edit.cut',
      label: 'Cut',
      key: LogicalKeyboardKey.keyX,
    ),
    StudioShortcutAction(
      id: 'edit.copy',
      label: 'Copy',
      key: LogicalKeyboardKey.keyC,
    ),
    StudioShortcutAction(
      id: 'edit.paste',
      label: 'Paste',
      key: LogicalKeyboardKey.keyV,
    ),
    StudioShortcutAction(
      id: 'edit.pastePlain',
      label: 'Paste as Plain Text',
      key: LogicalKeyboardKey.keyV,
      shift: true,
    ),
    StudioShortcutAction(
      id: 'edit.selectAll',
      label: 'Select all',
      key: LogicalKeyboardKey.keyA,
    ),
    StudioShortcutAction(
      id: 'format.bold',
      label: 'Bold',
      key: LogicalKeyboardKey.keyB,
    ),
    StudioShortcutAction(
      id: 'format.italic',
      label: 'Italic',
      key: LogicalKeyboardKey.keyI,
    ),
    StudioShortcutAction(
      id: 'format.underline',
      label: 'Underline',
      key: LogicalKeyboardKey.keyU,
    ),
    StudioShortcutAction(
      id: 'format.superscript',
      label: 'Superscript',
      key: LogicalKeyboardKey.equal,
      shift: true,
    ),
    StudioShortcutAction(
      id: 'format.subscript',
      label: 'Subscript',
      key: LogicalKeyboardKey.minus,
      shift: true,
    ),
    StudioShortcutAction(
      id: 'format.alignLeft',
      label: 'Align left',
      key: LogicalKeyboardKey.keyL,
    ),
    StudioShortcutAction(
      id: 'format.center',
      label: 'Center',
      key: LogicalKeyboardKey.keyE,
    ),
    StudioShortcutAction(
      id: 'format.alignRight',
      label: 'Align right',
      key: LogicalKeyboardKey.keyR,
    ),
    StudioShortcutAction(
      id: 'format.justify',
      label: 'Justify',
      key: LogicalKeyboardKey.keyJ,
    ),
    StudioShortcutAction(
      id: 'format.bullets',
      label: 'Bulleted list',
      key: LogicalKeyboardKey.keyL,
      shift: true,
    ),
    StudioShortcutAction(
      id: 'format.normalStyle',
      label: 'Normal paragraph style',
      key: LogicalKeyboardKey.keyN,
      shift: true,
    ),
    StudioShortcutAction(id: 'format.numbering', label: 'Numbered list'),
    StudioShortcutAction(
      id: 'format.indent',
      label: 'Increase indent',
      key: LogicalKeyboardKey.keyM,
    ),
    StudioShortcutAction(
      id: 'format.outdent',
      label: 'Decrease indent',
      key: LogicalKeyboardKey.keyM,
      shift: true,
    ),
    StudioShortcutAction(
      id: 'format.growFont',
      label: 'Grow font',
      key: LogicalKeyboardKey.bracketRight,
    ),
    StudioShortcutAction(
      id: 'format.shrinkFont',
      label: 'Shrink font',
      key: LogicalKeyboardKey.bracketLeft,
    ),
    StudioShortcutAction(
      id: 'format.singleSpacing',
      label: 'Single line spacing',
      key: LogicalKeyboardKey.digit1,
    ),
    StudioShortcutAction(
      id: 'format.doubleSpacing',
      label: 'Double line spacing',
      key: LogicalKeyboardKey.digit2,
    ),
    StudioShortcutAction(
      id: 'format.oneAndHalfSpacing',
      label: '1.5 line spacing',
      key: LogicalKeyboardKey.digit5,
    ),
    StudioShortcutAction(
      id: 'insert.pageBreak',
      label: 'Page break',
      key: LogicalKeyboardKey.enter,
    ),
    StudioShortcutAction(
      id: 'insert.comment',
      label: 'New comment',
      key: LogicalKeyboardKey.keyM,
      macKey: LogicalKeyboardKey.keyA,
      alt: true,
    ),
    StudioShortcutAction(
      id: 'review.trackChanges',
      label: 'Track changes',
      key: LogicalKeyboardKey.keyE,
      shift: true,
    ),
    StudioShortcutAction(
      id: 'review.spelling',
      label: 'Spelling',
      key: LogicalKeyboardKey.f7,
      primary: false,
    ),
    StudioShortcutAction(
      id: 'review.thesaurus',
      label: 'Thesaurus',
      key: LogicalKeyboardKey.f7,
      shift: true,
      primary: false,
    ),
    StudioShortcutAction(
      id: 'navigate.find',
      label: 'Find',
      key: LogicalKeyboardKey.keyF,
    ),
    StudioShortcutAction(
      id: 'navigate.replace',
      label: 'Replace',
      key: LogicalKeyboardKey.keyH,
      macControl: true,
    ),
    StudioShortcutAction(
      id: 'view.zoomIn',
      label: 'Zoom in',
      key: LogicalKeyboardKey.equal,
    ),
    StudioShortcutAction(
      id: 'view.zoomOut',
      label: 'Zoom out',
      key: LogicalKeyboardKey.minus,
    ),
    StudioShortcutAction(
      id: 'view.zoomReset',
      label: 'Reset zoom',
      key: LogicalKeyboardKey.digit0,
    ),
  ];

  static Map<String, StudioShortcutBinding> resolve(
    Map<String, String> overrides, {
    required bool mac,
  }) {
    final result = <String, StudioShortcutBinding>{};
    for (final action in actions) {
      final stored = overrides[action.id];
      final binding =
          (stored == null ? null : StudioShortcutBinding.tryParse(stored)) ??
          action.defaultBinding(mac: mac);
      if (binding != null) result[action.id] = binding;
    }
    return result;
  }

  /// The same winners used by [mergeBindings], for native menu equivalents.
  static Map<String, StudioShortcutBinding> menuBindings(
    Map<String, String> overrides, {
    required bool mac,
  }) {
    final settings = resolve(overrides, mac: mac);
    final byKey = <String, String>{};
    for (final explicit in [false, true]) {
      for (final entry in settings.entries) {
        final overridden =
            StudioShortcutBinding.tryParse(overrides[entry.key] ?? '') != null;
        if (overridden == explicit) byKey[entry.value.encode()] = entry.key;
      }
    }
    return {for (final id in byKey.values) id: settings[id]!};
  }

  /// Replaces catalog defaults by key combination, not activator identity.
  ///
  /// [SingleActivator] does not have value equality, and [CallbackShortcuts]
  /// invokes every matching entry. Keep one callback per trigger/modifier
  /// combination so duplicate defaults cannot execute a command twice.
  /// Explicit overrides win over defaults; ties within either group use the
  /// later catalog action. Unrelated base bindings are retained.
  static Map<ShortcutActivator, VoidCallback> mergeBindings(
    Map<ShortcutActivator, VoidCallback> base, {
    required Map<String, String> overrides,
    required Map<String, VoidCallback> callbacks,
    required bool mac,
  }) {
    final merged = <Object, MapEntry<ShortcutActivator, VoidCallback>>{
      for (final entry in base.entries) _bindingKey(entry.key): entry,
    };
    final active = actions.where((action) => callbacks.containsKey(action.id));
    for (final action in active) {
      for (final platform in [false, true]) {
        final binding = action.defaultBinding(mac: platform);
        if (binding != null) merged.remove(_bindingKey(binding.activator));
      }
    }

    final explicit = <MapEntry<ShortcutActivator, VoidCallback>>[];
    for (final action in active) {
      final stored = overrides[action.id];
      final override = stored == null
          ? null
          : StudioShortcutBinding.tryParse(stored);
      final binding = override ?? action.defaultBinding(mac: mac);
      if (binding == null) continue;
      final entry = MapEntry<ShortcutActivator, VoidCallback>(
        binding.activator,
        callbacks[action.id]!,
      );
      if (override == null) {
        merged[_bindingKey(entry.key)] = entry;
      } else {
        explicit.add(entry);
      }
    }
    for (final entry in explicit) {
      merged[_bindingKey(entry.key)] = entry;
    }
    return <ShortcutActivator, VoidCallback>{
      for (final entry in merged.values) entry.key: entry.value,
    };
  }

  static Object _bindingKey(ShortcutActivator activator) =>
      activator is SingleActivator
      ? (
          activator.trigger.keyId,
          activator.control,
          activator.shift,
          activator.alt,
          activator.meta,
        )
      : activator;
}

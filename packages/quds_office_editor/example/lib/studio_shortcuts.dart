import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// A user-visible Word/Writer command and its default shortcut.
///
/// Settings store only the actions a user changed. Unknown action ids are
/// retained in the settings document but ignored by this catalog, which keeps
/// newer settings readable by older builds.
final class StudioShortcutAction {
  const StudioShortcutAction({
    required this.id,
    required this.label,
    required this.key,
    this.shift = false,
    this.alt = false,
    this.primary = true,
  });

  final String id;
  final String label;
  final LogicalKeyboardKey key;
  final bool shift;
  final bool alt;
  final bool primary;

  StudioShortcutBinding defaultBinding({required bool mac}) =>
      StudioShortcutBinding(
        keyId: key.keyId,
        meta: primary && mac,
        control: primary && !mac,
        shift: shift,
        alt: alt,
      );
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
    if (key == null ||
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
}

/// Word and Writer shortcuts. The list is deliberately focused on commands the
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
      id: 'file.close',
      label: 'Close window',
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
      key: LogicalKeyboardKey.keyZ,
      shift: true,
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
      key: LogicalKeyboardKey.equal,
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
      id: 'format.numbering',
      label: 'Numbered list',
      key: LogicalKeyboardKey.keyN,
      shift: true,
    ),
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
      result[action.id] =
          (stored == null ? null : StudioShortcutBinding.tryParse(stored)) ??
          action.defaultBinding(mac: mac);
    }
    return result;
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
      merged.remove(_bindingKey(action.defaultBinding(mac: true).activator));
      merged.remove(_bindingKey(action.defaultBinding(mac: false).activator));
    }

    final explicit = <MapEntry<ShortcutActivator, VoidCallback>>[];
    for (final action in active) {
      final stored = overrides[action.id];
      final override = stored == null
          ? null
          : StudioShortcutBinding.tryParse(stored);
      final entry = MapEntry<ShortcutActivator, VoidCallback>(
        (override ?? action.defaultBinding(mac: mac)).activator,
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

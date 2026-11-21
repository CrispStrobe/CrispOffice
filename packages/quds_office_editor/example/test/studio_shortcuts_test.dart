import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_studio/studio_shortcuts.dart';

Future<void> _mountBindings(
  WidgetTester tester,
  Map<ShortcutActivator, VoidCallback> bindings,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: CallbackShortcuts(
        bindings: bindings,
        child: const Focus(autofocus: true, child: SizedBox.expand()),
      ),
    ),
  );
  await tester.pump();
}

Future<void> _press(
  WidgetTester tester,
  LogicalKeyboardKey key, {
  bool control = false,
  bool shift = false,
  bool alt = false,
  bool meta = false,
}) async {
  final modifiers = <LogicalKeyboardKey>[
    if (control) LogicalKeyboardKey.controlLeft,
    if (shift) LogicalKeyboardKey.shiftLeft,
    if (alt) LogicalKeyboardKey.altLeft,
    if (meta) LogicalKeyboardKey.metaLeft,
  ];
  for (final modifier in modifiers) {
    await tester.sendKeyDownEvent(modifier);
  }
  try {
    await tester.sendKeyEvent(key);
  } finally {
    for (final modifier in modifiers.reversed) {
      await tester.sendKeyUpEvent(modifier);
    }
  }
  await tester.pump();
}

void main() {
  test('shortcut bindings round-trip and reject incomplete values', () {
    const binding = StudioShortcutBinding(
      keyId: 98,
      meta: true,
      shift: true,
      alt: true,
    );
    final parsed = StudioShortcutBinding.tryParse(binding.encode());
    expect(parsed, isNotNull);
    expect(parsed!.encode(), binding.encode());
    expect(StudioShortcutBinding.tryParse('meta+KeyZ'), isNull);
    expect(StudioShortcutBinding.tryParse('meta+999999'), isNull);
  });

  test(
    'bare function keys round-trip while ordinary letters need modifiers',
    () {
      for (final key in [
        LogicalKeyboardKey.f1,
        LogicalKeyboardKey.f7,
        LogicalKeyboardKey.f24,
      ]) {
        final binding = StudioShortcutBinding(keyId: key.keyId);
        expect(
          StudioShortcutBinding.tryParse(binding.encode())!.encode(),
          binding.encode(),
        );
      }
      expect(
        StudioShortcutBinding.tryParse('${LogicalKeyboardKey.keyF.keyId}'),
        isNull,
      );
      expect(StudioShortcutBinding.tryParse(''), isNull);
    },
  );

  test('catalog defaults use Command on macOS and Ctrl elsewhere', () {
    final mac = StudioShortcutCatalog.resolve(const {}, mac: true);
    final other = StudioShortcutCatalog.resolve(const {}, mac: false);
    expect(mac['format.bold']!.meta, isTrue);
    expect(mac['format.bold']!.control, isFalse);
    expect(other['format.bold']!.control, isTrue);
    expect(mac['review.spelling']!.meta, isFalse);
    expect(mac['review.spelling']!.keyId, LogicalKeyboardKey.f7.keyId);
  });

  test('explicit overrides replace defaults', () {
    final bindings = StudioShortcutCatalog.resolve(<String, String>{
      'format.bold': 'ctrl+alt+${LogicalKeyboardKey.digit1.keyId}',
    }, mac: true);
    expect(bindings['format.bold']!.control, isTrue);
    expect(bindings['format.bold']!.alt, isTrue);
    expect(bindings['format.bold']!.meta, isFalse);
  });

  for (final mac in [false, true]) {
    testWidgets('default bold and undo dispatch once (mac: $mac)', (
      tester,
    ) async {
      final calls = <String>[];
      void bold() => calls.add('bold');
      void undo() => calls.add('undo');
      await _mountBindings(
        tester,
        StudioShortcutCatalog.mergeBindings(
          <ShortcutActivator, VoidCallback>{
            const SingleActivator(LogicalKeyboardKey.keyB, control: true): bold,
            const SingleActivator(LogicalKeyboardKey.keyB, meta: true): bold,
            const SingleActivator(LogicalKeyboardKey.keyZ, control: true): undo,
            const SingleActivator(LogicalKeyboardKey.keyZ, meta: true): undo,
            const SingleActivator(
              LogicalKeyboardKey.keyB,
              control: true,
              alt: true,
            ): () =>
                calls.add('alt'),
            const SingleActivator(
              LogicalKeyboardKey.keyB,
              control: true,
              shift: true,
            ): () =>
                calls.add('shift'),
          },
          overrides: const {},
          callbacks: {'format.bold': bold, 'edit.undo': undo},
          mac: mac,
        ),
      );
      await _press(tester, LogicalKeyboardKey.keyB, control: !mac, meta: mac);
      await _press(tester, LogicalKeyboardKey.keyZ, control: !mac, meta: mac);
      expect(calls, ['bold', 'undo']);
      await _press(tester, LogicalKeyboardKey.keyB, control: mac, meta: !mac);
      expect(calls, ['bold', 'undo']);
      await _press(tester, LogicalKeyboardKey.keyB, control: true, alt: true);
      await _press(tester, LogicalKeyboardKey.keyB, control: true, shift: true);
      expect(calls, ['bold', 'undo', 'alt', 'shift']);
    });
  }

  testWidgets(
    'remapping disables both old defaults and invokes the new key once',
    (tester) async {
      final calls = <String>[];
      void bold() => calls.add('bold');
      await _mountBindings(
        tester,
        StudioShortcutCatalog.mergeBindings(
          <ShortcutActivator, VoidCallback>{
            const SingleActivator(LogicalKeyboardKey.keyB, control: true): bold,
            const SingleActivator(LogicalKeyboardKey.keyB, meta: true): bold,
            const SingleActivator(
              LogicalKeyboardKey.digit1,
              control: true,
            ): () =>
                calls.add('unrelated'),
          },
          overrides: {
            'format.bold': 'ctrl+alt+${LogicalKeyboardKey.digit1.keyId}',
          },
          callbacks: {'format.bold': bold},
          mac: false,
        ),
      );
      await _press(tester, LogicalKeyboardKey.keyB, control: true);
      await _press(tester, LogicalKeyboardKey.keyB, meta: true);
      expect(calls, isEmpty);
      await _press(tester, LogicalKeyboardKey.digit1, control: true, alt: true);
      expect(calls, ['bold']);
      await _press(tester, LogicalKeyboardKey.digit1, control: true);
      expect(calls, ['bold', 'unrelated']);
    },
  );

  testWidgets('an explicit override wins over a later action default', (
    tester,
  ) async {
    final calls = <String>[];
    await _mountBindings(
      tester,
      StudioShortcutCatalog.mergeBindings(
        <ShortcutActivator, VoidCallback>{
          const SingleActivator(LogicalKeyboardKey.keyI, control: true): () =>
              calls.add('old italic'),
          const SingleActivator(LogicalKeyboardKey.keyP, control: true): () =>
              calls.add('print'),
        },
        overrides: {'format.bold': 'ctrl+${LogicalKeyboardKey.keyI.keyId}'},
        callbacks: {
          'format.bold': () => calls.add('bold'),
          'format.italic': () => calls.add('italic'),
        },
        mac: false,
      ),
    );
    await _press(tester, LogicalKeyboardKey.keyI, control: true);
    await _press(tester, LogicalKeyboardKey.keyB, control: true);
    expect(calls, ['bold']);
    await _press(tester, LogicalKeyboardKey.keyP, control: true);
    expect(calls, ['bold', 'print']);
  });

  testWidgets('default collision retains zoom and preserves its keypad alias', (
    tester,
  ) async {
    final calls = <String>[];
    void zoom() => calls.add('zoom');
    await _mountBindings(
      tester,
      StudioShortcutCatalog.mergeBindings(
        <ShortcutActivator, VoidCallback>{
          const SingleActivator(LogicalKeyboardKey.equal, control: true): zoom,
          const SingleActivator(LogicalKeyboardKey.numpadAdd, control: true):
              zoom,
        },
        overrides: const {},
        callbacks: {
          'format.subscript': () => calls.add('subscript'),
          'view.zoomIn': zoom,
        },
        mac: false,
      ),
    );
    await _press(tester, LogicalKeyboardKey.equal, control: true);
    expect(calls, ['zoom']);
    await _press(tester, LogicalKeyboardKey.numpadAdd, control: true);
    expect(calls, ['zoom', 'zoom']);
  });

  testWidgets('colliding explicit overrides follow catalog order', (
    tester,
  ) async {
    final calls = <String>[];
    await _mountBindings(
      tester,
      StudioShortcutCatalog.mergeBindings(
        const <ShortcutActivator, VoidCallback>{},
        // Deliberately reverse the storage order relative to the catalog.
        overrides: {
          'format.italic': 'ctrl+${LogicalKeyboardKey.keyK.keyId}',
          'format.bold': 'ctrl+${LogicalKeyboardKey.keyK.keyId}',
        },
        callbacks: {
          'format.bold': () => calls.add('bold'),
          'format.italic': () => calls.add('italic'),
        },
        mac: false,
      ),
    );
    await _press(tester, LogicalKeyboardKey.keyK, control: true);
    expect(calls, ['italic']);
  });
}

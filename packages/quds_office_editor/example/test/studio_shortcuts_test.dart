import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_studio/studio_shortcuts.dart';

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
    final bindings = StudioShortcutCatalog.resolve(
      <String, String>{
        'format.bold': 'ctrl+alt+${LogicalKeyboardKey.digit1.keyId}',
      },
      mac: true,
    );
    expect(bindings['format.bold']!.control, isTrue);
    expect(bindings['format.bold']!.alt, isTrue);
    expect(bindings['format.bold']!.meta, isFalse);
  });
}

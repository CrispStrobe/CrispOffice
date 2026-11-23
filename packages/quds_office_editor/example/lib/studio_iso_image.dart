import 'dart:convert';
import 'dart:typed_data';

/// One bounded ISO 9660 directory entry.
final class StudioIsoEntry {
  const StudioIsoEntry({
    required this.name,
    required this.path,
    required this.isDirectory,
    required this.extent,
    required this.size,
  });

  final String name;
  final String path;
  final bool isDirectory;
  final int extent;
  final int size;
}

/// Minimal read-only ISO 9660 image browser. It supports the primary volume
/// descriptor and 8.3 directory names, which covers `.iso`/`.cdr` images such
/// as macOS/Windows backups. It never mounts, executes or writes the image.
final class StudioIsoImage {
  StudioIsoImage._(this.bytes, this.label, this.entries);

  static const int sectorSize = 2048;
  static const int maxEntries = 20000;
  static const int maxDepth = 32;

  final Uint8List bytes;
  final String label;
  final List<StudioIsoEntry> entries;

  static bool isIso(Uint8List bytes) =>
      bytes.length >= 17 * sectorSize &&
      String.fromCharCodes(
            bytes.sublist(16 * sectorSize + 1, 16 * sectorSize + 6),
          ) ==
          'CD001';

  static StudioIsoImage parse(Uint8List bytes) {
    if (!isIso(bytes)) throw const FormatException('Not an ISO 9660 image.');
    StudioIsoEntry? root;
    String label = 'ISO image';
    for (var sector = 16; sector < 16 + 64; sector++) {
      final at = sector * sectorSize;
      if (at + sectorSize > bytes.length) break;
      final type = bytes[at];
      if (type == 255) break;
      if (type != 1) continue;
      if (String.fromCharCodes(bytes.sublist(at + 1, at + 6)) != 'CD001') {
        continue;
      }
      final nameBytes = bytes.sublist(at + 40, at + 72);
      label = ascii
          .decode(nameBytes, allowInvalid: true)
          .replaceAll('\x00', '')
          .trim();
      root = _entry(bytes, at + 156);
      break;
    }
    if (root == null) {
      throw const FormatException('ISO root directory missing.');
    }
    final rootDirectory = StudioIsoEntry(
      name: '',
      path: '',
      isDirectory: true,
      extent: root.extent,
      size: root.size,
    );
    final entries = <StudioIsoEntry>[];
    final seen = <String>{};
    void walk(StudioIsoEntry directory, int depth) {
      if (depth > maxDepth || entries.length >= maxEntries) return;
      final Uint8List data;
      try {
        data = _slice(bytes, directory.extent, directory.size);
      } on FormatException {
        return;
      }
      var at = 0;
      while (at < data.length && entries.length < maxEntries) {
        if (data[at] == 0) {
          at = ((at ~/ sectorSize) + 1) * sectorSize;
          continue;
        }
        final length = data[at];
        if (length < 34 || at + length > data.length) break;
        final entry = _entry(data, at, directory.path);
        if (entry.name != '.' &&
            entry.name != '..' &&
            entry.name != '\x00' &&
            entry.name != '\x01' &&
            seen.add(entry.path)) {
          entries.add(entry);
          if (entry.isDirectory) walk(entry, depth + 1);
        }
        at += length;
      }
    }

    walk(rootDirectory, 0);
    return StudioIsoImage._(
      Uint8List.fromList(bytes).asUnmodifiableView(),
      label.isEmpty ? 'ISO image' : label,
      List.unmodifiable(entries),
    );
  }

  List<StudioIsoEntry> children(String path) => [
    for (final entry in entries)
      if (_parent(entry.path) == path) entry,
  ];

  Uint8List read(StudioIsoEntry entry) {
    if (entry.isDirectory) throw const FormatException('Not a file.');
    return Uint8List.fromList(_slice(bytes, entry.extent, entry.size));
  }

  static String _parent(String path) {
    final slash = path.lastIndexOf('/');
    return slash < 0 ? '' : path.substring(0, slash);
  }

  static StudioIsoEntry _entry(Uint8List data, int at, [String? parent]) {
    final extent = _le32(data, at + 2);
    final size = _le32(data, at + 10);
    final flags = data[at + 25];
    final nameLength = data[at + 32];
    var name = ascii.decode(
      data.sublist(at + 33, at + 33 + nameLength),
      allowInvalid: true,
    );
    final semicolon = name.indexOf(';');
    if (semicolon >= 0) name = name.substring(0, semicolon);
    if (name.endsWith('.')) name = name.substring(0, name.length - 1);
    if (name.isEmpty) name = '.';
    final path = parent == null || parent.isEmpty ? name : '$parent/$name';
    return StudioIsoEntry(
      name: name,
      path: path,
      isDirectory: flags & 2 != 0,
      extent: extent,
      size: size,
    );
  }

  static int _le32(Uint8List data, int at) =>
      data[at] | data[at + 1] << 8 | data[at + 2] << 16 | data[at + 3] << 24;

  static Uint8List _slice(Uint8List data, int extent, int size) {
    final start = extent * sectorSize;
    if (start < 0 || size < 0 || start + size > data.length) {
      throw const FormatException('ISO entry exceeds the image.');
    }
    return Uint8List.sublistView(data, start, start + size);
  }
}

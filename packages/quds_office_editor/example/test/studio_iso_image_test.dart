import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_studio/studio_files.dart';
import 'package:quds_office_studio/studio_iso_image.dart';

Uint8List _iso() {
  final bytes = Uint8List(22 * StudioIsoImage.sectorSize);
  final pvd = 16 * StudioIsoImage.sectorSize;
  bytes[pvd] = 1;
  bytes.setRange(pvd + 1, pvd + 6, 'CD001'.codeUnits);
  bytes[pvd + 6] = 1;
  bytes.setRange(pvd + 40, pvd + 47, 'TESTISO'.codeUnits);
  void le32(int at, int value) {
    bytes[at] = value & 0xff;
    bytes[at + 1] = value >> 8 & 0xff;
    bytes[at + 2] = value >> 16 & 0xff;
    bytes[at + 3] = value >> 24 & 0xff;
  }

  void record(int at, String name, int extent, int size, {int flags = 0}) {
    final length = 33 + name.length;
    bytes[at] = length.isEven ? length : length + 1;
    le32(at + 2, extent);
    le32(at + 10, size);
    bytes[at + 25] = flags;
    bytes[at + 32] = name.length;
    bytes.setRange(at + 33, at + 33 + name.length, name.codeUnits);
  }

  record(pvd + 156, '\x00', 20, StudioIsoImage.sectorSize, flags: 2);
  final root = 20 * StudioIsoImage.sectorSize;
  record(root, '\x00', 20, StudioIsoImage.sectorSize, flags: 2);
  record(root + 34, '\x01', 20, StudioIsoImage.sectorSize, flags: 2);
  final fileAt = root + 68;
  record(fileAt, 'FILE.TXT;1', 21, 5);
  bytes.setRange(
    21 * StudioIsoImage.sectorSize,
    21 * StudioIsoImage.sectorSize + 5,
    'hello'.codeUnits,
  );
  return bytes;
}

void main() {
  test('recognizes ISO 9660 and lists/extracts bounded entries', () {
    final bytes = _iso();
    expect(StudioIsoImage.isIso(bytes), isTrue);
    final image = StudioIsoImage.parse(bytes);
    expect(image.label, 'TESTISO');
    expect(image.entries.single.name, 'FILE.TXT');
    expect(image.read(image.entries.single), 'hello'.codeUnits);
    expect(image.children(''), hasLength(1));
  });

  test('ISO and CDR images are offered by the picker', () {
    expect(StudioFiles.extensions, contains('iso'));
    expect(StudioFiles.extensions, contains('cdr'));
  });
}

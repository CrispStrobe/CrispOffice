import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_studio/studio_native_paths.dart';

void main() {
  test('Android files directory comes from process name and user id', () {
    expect(
      androidFilesDirectory(
        cmdline: 'com.quds.quds_office_studio\u0000',
        status: 'Name:\tquds\nUid:\t10123\t10123\t10123\t10123\n',
      ),
      '/data/user/0/com.quds.quds_office_studio/files',
    );
    // Secondary user 10, private worker process suffix ignored.
    expect(
      androidFilesDirectory(
        cmdline: 'com.example.app:worker\u0000',
        status: 'Uid:\t1010123\t1010123\t1010123\t1010123\n',
      ),
      '/data/user/10/com.example.app/files',
    );
  });

  test('unparseable process information yields no directory', () {
    expect(
      androidFilesDirectory(cmdline: '/system/bin/sh', status: ''),
      isNull,
    );
    expect(
      androidFilesDirectory(cmdline: '../evil\u0000', status: 'Uid:\t1\n'),
      isNull,
    );
  });
}

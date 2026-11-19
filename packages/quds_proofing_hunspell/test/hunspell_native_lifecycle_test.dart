@TestOn('vm')
library;

import 'dart:ffi';
import 'dart:io';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:quds_proofing_hunspell/quds_proofing_hunspell.dart';
import 'package:test/test.dart';

OfficeProofingRequest _request(String text) => OfficeProofingRequest(
  documentId: 'lifecycle',
  blockId: 'paragraph',
  revision: 1,
  text: text,
  language: 'ar',
);

void main() {
  final path = Platform.environment['QUDS_HUNSPELL_LIFECYCLE_LIBRARY'];
  final skip = path == null
      ? 'Build test/support/hunspell_lifecycle_shim.cpp and set '
            'QUDS_HUNSPELL_LIFECYCLE_LIBRARY.'
      : false;

  group('native dictionary lifecycle', () {
    late int Function() live;
    late int Function() opened;
    late int Function() closed;
    late Directory files;
    setUpAll(() {
      files = Directory.systemTemp.createTempSync('hunspell-lifecycle-');
      File('${files.path}/test.aff').writeAsStringSync('SET UTF-8\n');
      File('${files.path}/test.dic').writeAsStringSync('1\nهذا\n');
      final library = DynamicLibrary.open(path!);
      live = library.lookupFunction<Int32 Function(), int Function()>(
        'quds_hunspell_test_live_handles',
      );
      opened = library.lookupFunction<Int32 Function(), int Function()>(
        'quds_hunspell_test_opened_handles',
      );
      closed = library.lookupFunction<Int32 Function(), int Function()>(
        'quds_hunspell_test_closed_handles',
      );
    });
    tearDownAll(() => files.deleteSync(recursive: true));

    HunspellProofingProvider provider({
      Duration timeout = const Duration(seconds: 2),
    }) => HunspellProofingProvider(
      bundle: ayaspellArabic,
      dictionary: HunspellDictionaryFiles(
        affPath: '${files.path}/test.aff',
        dicPath: '${files.path}/test.dic',
      ),
      nativeLibraryPath: path,
      timeout: timeout,
    );

    test('disposal frees an opened dictionary before returning', () async {
      expect(live(), 0);
      final before = closed();
      final instance = provider();
      addTearDown(instance.dispose);
      final result = await instance.check(_request('هذا'));
      expect(result.status, OfficeProofingStatus.success);
      expect(live(), 1);
      await instance.dispose();
      expect(live(), 0, reason: 'The C ABI dictionary must be closed.');
      expect(closed(), before + 1);
    });

    test('concurrent disposal closes exactly once for every waiter', () async {
      expect(live(), 0);
      final before = closed();
      final instance = provider();
      await instance.check(_request('هذا'));
      final first = instance.dispose();
      final second = instance.dispose();
      await second;
      expect(live(), 0);
      await first;
      await instance.dispose();
      expect(closed(), before + 1);
    });

    test(
      'disposal during startup completes without opening a handle',
      () async {
        expect(live(), 0);
        final before = opened();
        final instance = provider();
        final pending = instance.check(_request('هذا'));
        await instance.dispose().timeout(const Duration(seconds: 3));
        final result = await pending.timeout(const Duration(seconds: 3));
        expect(result.status, OfficeProofingStatus.unavailable);
        expect(live(), 0);
        expect(opened(), before);
      },
    );

    test('timeout disposal waits for pending native work to close', () async {
      expect(live(), 0);
      final instance = provider(timeout: const Duration(milliseconds: 100));
      final ready = await instance.check(_request('هذا'));
      expect(ready.status, OfficeProofingStatus.success);
      final result = await instance.check(_request('تعليق'));
      expect(result.status, OfficeProofingStatus.failed);
      expect(result.message, contains('timed out'));
      await instance.dispose();
      expect(live(), 0);
      expect(
        (await instance.check(_request('هذا'))).status,
        OfficeProofingStatus.unavailable,
      );
    });
  }, skip: skip);
}

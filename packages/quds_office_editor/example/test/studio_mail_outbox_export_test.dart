import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_office_studio/studio_mail_outbox_export_native.dart';

void main() {
  late Directory directory;
  setUp(
    () async =>
        directory = await Directory.systemTemp.createTemp('outbox-export-'),
  );
  tearDown(() async => directory.delete(recursive: true));

  test(
    'exact EML and private JSON exports preserve bytes without changing existing files',
    () async {
      for (final name in ['message.eml', 'recipients.json']) {
        final file = File('${directory.path}/$name');
        final original = MailBytes(
          Uint8List.fromList([0, 10, 13, 127, 128, 255]),
        );
        final cancellation = MailCancellationSource();
        final result = await exportStudioMailOutboxFileTo(
          name,
          original,
          cancellation: cancellation.token,
          isCurrent: () => true,
          choosePath: (suggested) async {
            expect(suggested, name);
            return file.path;
          },
        );
        expect(
          result,
          isA<MailSuccess<bool>>().having(
            (value) => value.value,
            'saved',
            true,
          ),
        );
        expect(await file.readAsBytes(), original.bytes);
        final rejected = await exportStudioMailOutboxFileTo(
          name,
          MailBytes(Uint8List.fromList([1, 2, 3])),
          cancellation: cancellation.token,
          isCurrent: () => true,
          choosePath: (_) async => file.path,
        );
        expect(rejected, isA<MailFailure<bool>>());
        expect(await file.readAsBytes(), original.bytes);
      }
      expect(await directory.list().length, 2);
    },
  );

  test('cancelled picker and a retired session create no file', () async {
    final file = File('${directory.path}/message.eml');
    final original = MailBytes(Uint8List.fromList([1, 2, 3]));
    final cancellation = MailCancellationSource();
    final cancelled = await exportStudioMailOutboxFileTo(
      'message.eml',
      original,
      cancellation: cancellation.token,
      isCurrent: () => true,
      choosePath: (_) async => null,
    );
    expect(
      cancelled,
      isA<MailSuccess<bool>>().having((value) => value.value, 'saved', false),
    );
    var current = true;
    final retired = await exportStudioMailOutboxFileTo(
      'message.eml',
      original,
      cancellation: cancellation.token,
      isCurrent: () => current,
      choosePath: (_) async {
        current = false;
        return file.path;
      },
    );
    expect(
      retired,
      isA<MailFailure<bool>>().having(
        (value) => value.problem.code,
        'reason',
        MailProblemCode.cancelled,
      ),
    );
    expect(await directory.list().isEmpty, true);
  });

  test('disposal during picker and destination symlinks are refused', () async {
    final file = File('${directory.path}/message.eml');
    final original = MailBytes(Uint8List.fromList([1, 2, 3]));
    final cancellation = MailCancellationSource();
    final disposed = await exportStudioMailOutboxFileTo(
      'message.eml',
      original,
      cancellation: cancellation.token,
      isCurrent: () => true,
      choosePath: (_) async {
        cancellation.cancel(MailCancellationReason.disposed);
        return file.path;
      },
    );
    expect(disposed, isA<MailFailure<bool>>());
    expect(await directory.list().isEmpty, true);
    final target = File('${directory.path}/original.eml');
    await target.writeAsBytes([7, 8, 9]);
    await Link(file.path).create(target.path);
    final result = await exportStudioMailOutboxFileTo(
      'message.eml',
      original,
      cancellation: MailCancellationSource().token,
      isCurrent: () => true,
      choosePath: (_) async => file.path,
    );
    expect(result, isA<MailFailure<bool>>());
    expect(await target.readAsBytes(), [7, 8, 9]);
    expect(await Link(file.path).target(), target.path);
    expect(await directory.list().length, 2);
  });
}

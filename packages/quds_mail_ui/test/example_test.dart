import 'package:flutter_test/flutter_test.dart';
import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_mime/quds_mail_mime.dart';
import 'package:quds_mail_ui/quds_mail_ui.dart';

import 'package:quds_mail_reader_example/main.dart' show exampleMessage;

void main() {
  test(
    'actual example MIME bytes provide the displayed body, CID and exact attachment',
    () {
      final raw = exampleMessage();
      final controller = MailReaderController.fromBytes(
        raw,
        codec: const QudsMimeCodec(),
      );
      final result = controller.result;
      expect(result.status, MailParseStatus.complete);
      expect(result.original!.bytes, raw);
      expect(result.message!.envelope.subject, 'Offline reader — قارئ البريد');
      expect(controller.decodedText, contains('Meeting agenda'));
      expect(controller.presentation.blockedResourceCount, greaterThan(0));
      expect(controller.presentation.images, hasLength(1));
      final attachment = result.message!.attachments.firstWhere(
        (a) => a.displayName == 'original.bin',
      );
      expect(attachment.content.bytes, [0, 1, 0, 255]);
      controller.search('original.bin');
      expect(controller.searchMatches, hasLength(1));
      controller.dispose();
    },
  );
}

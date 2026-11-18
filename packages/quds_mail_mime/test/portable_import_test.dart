import 'package:enough_mail/mime_core.dart' as mime;
import 'package:quds_mail_mime/quds_mail_mime.dart';
import 'package:test/test.dart';

import 'fixtures/messages.dart';

void main() {
  test('both supported public MIME imports work without native libraries', () {
    final upstream = mime.MimeMessage.parseFromText(simpleMessage);
    final projected = const QudsMimeCodec().parse(eml(simpleMessage));
    expect(upstream.decodeSubject(), projected.message!.envelope.subject);
    expect(projected.original!.copyBytes(), eml(simpleMessage));
  });
}

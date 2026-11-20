import 'package:quds_mail_core/quds_mail_core.dart';

export 'studio_mail_outbox_export_stub.dart'
    if (dart.library.io) 'studio_mail_outbox_export_native.dart';

typedef StudioMailOutboxExporter =
    Future<MailResult<bool>> Function(
      String suggestedName,
      MailBytes bytes, {
      required MailCancellationToken cancellation,
      required bool Function() isCurrent,
    });

import 'dart:convert';

import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_store/quds_mail_store.dart';
import 'package:test/test.dart';

void main() {
  for (final itemCount in [0, 1, 3]) {
    for (final unicode in [false, true]) {
      test(
        'manifest byte boundary: $itemCount originals, Unicode: $unicode',
        () {
          final plan = MailArchiveExportPlan(
            profile: MailProfileId(
              unicode ? 'ملف "محلي"' : 'profile',
              hostId: unicode ? 'hôte\\local' : 'host',
            ),
            createdAt: DateTime.utc(2026, 11, 19),
            items: [
              for (var index = 0; index < itemCount; index++)
                MailArchiveExportItem(
                  id: index.toRadixString(16).padLeft(64, '0'),
                  byteLength: index + 1,
                  origins: [
                    for (var origin = 0; origin <= index; origin++)
                      MailArchiveOrigin(
                        source: unicode ? 'café "محلي"' : 'local',
                        folder: unicode ? '/رسائل/café' : '/Inbox',
                        sourceMessageId: 'source:$origin',
                      ),
                  ],
                ),
            ],
          );
          final encoded = encodeMailArchiveExportManifest(
            plan,
            const MailArchiveExportLimits(),
          );
          final byteLength = utf8.encode(encoded).length;
          final exact = MailArchiveExportLimits(maxManifestBytes: byteLength);

          expect(encodeMailArchiveExportManifest(plan, exact), encoded);
          final decoded = decodeMailArchiveExportManifest(encoded, exact);
          expect(decoded.profile, plan.profile);
          expect(decoded.items, hasLength(itemCount));
          expect(encodeMailArchiveExportManifest(decoded, exact), encoded);

          final tooSmall = MailArchiveExportLimits(
            maxManifestBytes: byteLength - 1,
          );
          final quotaExceeded = throwsA(
            isA<MailStoreStorageException>().having(
              (error) => error.code,
              'code',
              MailProblemCode.quotaExceeded,
            ),
          );
          expect(
            () => encodeMailArchiveExportManifest(plan, tooSmall),
            quotaExceeded,
          );
          expect(
            () => decodeMailArchiveExportManifest(encoded, tooSmall),
            quotaExceeded,
          );
        },
      );
    }
  }
}

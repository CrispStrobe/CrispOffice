@TestOn('vm')
library;

import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_store/quds_mail_store.dart';
import 'package:test/test.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  for (final field in ['id', 'name', 'query', 'account']) {
    test('probe $field malformed UTF-16', () async {
      final broken = 'prefix\uD800suffix';
      final candidate = MailSavedHeaderSearch(
        id: field == 'id' ? broken : 'view',
        name: field == 'name' ? broken : 'Unicode probe',
        query: field == 'query' ? broken : '',
        accountIds: [field == 'account' ? broken : 'account'],
      );
      final opened = await SqliteMailRepository.open(
        executor: NativeDatabase.memory(),
        profile: MailProfileId('unicode-probe', hostId: 'fixture'),
      );
      final store = (opened as MailSuccess<SqliteMailRepository>).value;
      try {
        final saved = await store.saveSavedHeaderSearch(candidate);
        final listed = await store.listSavedHeaderSearches();
        final record = listed is MailSuccess<List<MailSavedHeaderSearch>>
            ? listed.value.singleOrNull
            : null;
        String? stored = switch (field) {
          'id' => record?.id,
          'name' => record?.name,
          'query' => record?.query,
          _ => record?.accountIds.single,
        };
        print(jsonEncode({
          'field': field,
          'modelValid': candidate.isValid,
          'saveSuccess': saved is MailSuccess<MailSavedHeaderSearch>,
          'listSuccess': listed is MailSuccess<List<MailSavedHeaderSearch>>,
          'originalUnits': broken.codeUnits,
          'loadedUnits': stored?.codeUnits,
          'same': stored == broken,
        }));
      } finally {
        await store.close();
      }
    });
  }
}

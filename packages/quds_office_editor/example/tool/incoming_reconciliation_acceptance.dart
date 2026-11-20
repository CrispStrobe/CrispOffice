// Run from the example workspace after `flutter pub get --enforce-lockfile`.
// Each original test file gets its own Flutter tester process. Keeping the
// groups sequential bounds compiler memory and preserves file-local test state.
import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> arguments) async {
  if (arguments.contains('--help')) {
    stdout.writeln(
      'dart tool/incoming_reconciliation_acceptance.dart\n'
      'Runs the incoming Mail, credential, Downloads and reader regression files '
      'through the standard Flutter test CLI. Set FLUTTER_BIN to select Flutter.',
    );
    return;
  }
  if (arguments.isNotEmpty) {
    stderr.writeln('Only --help is supported.');
    exitCode = 64;
    return;
  }
  final example = File.fromUri(Platform.script).parent.parent;
  final mailUi = Directory.fromUri(
    example.parent.parent.uri.resolve('quds_mail_ui/'),
  );
  final batches = <({String name, Directory directory, List<String> tests})>[
    (
      name: 'Credential selection',
      directory: example,
      tests: [
        'studio_credential_selection_test.dart',
        'studio_credential_selection_race_test.dart',
      ],
    ),
    (
      name: 'Mail account catalog',
      directory: example,
      tests: [
        'studio_mail_credentials_test.dart',
        'studio_mail_accounts_test.dart',
        'studio_mail_account_catalog_test.dart',
      ],
    ),
    (
      name: 'Selected credential stores',
      directory: example,
      tests: [
        'studio_mail_account_stores_test.dart',
        'studio_mail_selected_store_integration_test.dart',
      ],
    ),
    (name: 'Native Mail', directory: example, tests: ['studio_mail_test.dart']),
    (
      name: 'EWS and reply',
      directory: example,
      tests: ['studio_mail_ews_test.dart', 'studio_mail_reply_test.dart'],
    ),
    (
      name: 'Cloud Mail and forwarding',
      directory: example,
      tests: ['studio_mail_cloud_test.dart', 'studio_mail_forward_test.dart'],
    ),
    (
      name: 'Downloads and theme',
      directory: example,
      tests: [
        'studio_layout_theme_test.dart',
        'studio_downloads_capture_test.dart',
        'studio_downloads_layout_test.dart',
        'studio_downloads_manager_test.dart',
      ],
    ),
    (
      name: 'Mail reader',
      directory: mailUi,
      tests: ['body_presentation_test.dart', 'reader_theme_scroll_test.dart'],
    ),
  ];
  final flutter = Platform.environment['FLUTTER_BIN'] ?? 'flutter';
  for (final batch in batches) {
    stderr.writeln(
      'Running ${batch.name} (${batch.tests.length} original files)',
    );
    final process = await Process.start(
      flutter,
      [
        'test',
        '--no-pub',
        '--reporter=json',
        '--concurrency=1',
        for (final test in batch.tests) 'test/$test',
      ],
      workingDirectory: batch.directory.path,
      runInShell: Platform.isWindows,
    );
    var terminalEvents = 0;
    var terminalSuccess = false;
    final outputDone = process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .forEach((line) {
          stdout.writeln(line);
          try {
            final event = jsonDecode(line);
            if (event is Map<String, dynamic> && event['type'] == 'done') {
              terminalEvents++;
              terminalSuccess = event['success'] == true;
            }
          } on FormatException {
            // Flutter can print asset and native-hook progress before JSON.
          }
        });
    final errorsDone = stderr.addStream(process.stderr);
    final result = await process.exitCode;
    await Future.wait([outputDone, errorsDone]);
    if (result != 0 || terminalEvents != 1 || !terminalSuccess) {
      stderr.writeln(
        '${batch.name} did not complete successfully: exit $result, '
        '$terminalEvents terminal events, success=$terminalSuccess.',
      );
      exitCode = result == 0 ? 1 : result;
      return;
    }
  }
  stderr.writeln('All incoming regression groups completed successfully.');
}

import 'package:enough_mail/enough_mail.dart' as mail;
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_studio/studio_mail_folders.dart';
import 'package:quds_office_studio/studio_mail_polling.dart';
import 'package:shared_preferences/shared_preferences.dart';

mail.Mailbox _folder(String path, [mail.MailboxFlag? role]) => mail.Mailbox(
  encodedName: path.split('.').last,
  encodedPath: path,
  pathSeparator: '.',
  flags: [if (role != null) role],
);

void main() {
  test('system folders lead the tree and IMAP descendants stay grouped', () {
    final folders = [
      _folder('inbox.Tech'),
      _folder('Archive.2024'),
      _folder('a normal folder'),
      _folder('Archive', mail.MailboxFlag.archive),
      _folder('Sent'),
      _folder('inbox'),
      _folder('inbox.Deals'),
      _folder('Provider.Sent items', mail.MailboxFlag.sent),
      _folder('Drafts', mail.MailboxFlag.drafts),
    ];
    expect(studioMailSentMailbox(folders)?.path, 'Provider.Sent items');
    final rows = studioMailFolderRows(folders, expandedPaths: {'inbox'});
    expect(rows.map((row) => (row.box.path, row.depth)), [
      ('inbox', 0),
      ('inbox.Deals', 1),
      ('inbox.Tech', 1),
      ('Provider.Sent items', 0),
      ('Drafts', 0),
      ('Archive', 0),
      ('a normal folder', 0),
      ('Sent', 0),
    ]);
    expect(
      studioMailFolderRows(
        folders,
      ).any((row) => row.box.path == 'Archive.2024' && row.depth == 1),
      isTrue,
    );
  });

  test('preferences are scoped to the connected account', () async {
    SharedPreferences.setMockInitialValues({});
    await StudioMailPollPreferences.save('account-a', 0);
    await StudioMailPollPreferences.save('account-b', 15);
    await StudioMailPollPreferences.saveSnapshotDays('account-a', 7);
    expect(await StudioMailPollPreferences.load('account-a'), 0);
    expect(await StudioMailPollPreferences.load('account-b'), 15);
    expect(await StudioMailPollPreferences.load('account-c'), 5);
    expect(await StudioMailPollPreferences.loadSnapshotDays('account-a'), 7);
    expect(await StudioMailPollPreferences.loadSnapshotDays('account-b'), 0);
  });
}

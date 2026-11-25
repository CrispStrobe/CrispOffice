import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'studio_strings.dart';

abstract final class StudioMailPollPreferences {
  static const minutes = [0, 1, 2, 5, 10, 15, 30, 60];
  static const defaultMinutes = 5;

  static String _key(String account) => 'crispoffice.mail.pollMinutes.$account';

  static const snapshotDays = [0, 7, 30, 90];

  static String _retentionKey(String account) =>
      'crispoffice.mail.snapshotDays.$account';

  static Future<int> loadSnapshotDays(String account) async {
    final days = (await SharedPreferences.getInstance()).getInt(
      _retentionKey(account),
    );
    return snapshotDays.contains(days) ? days! : 0;
  }

  static Future<void> saveSnapshotDays(String account, int days) async {
    if (!snapshotDays.contains(days)) throw ArgumentError.value(days);
    if (!await (await SharedPreferences.getInstance()).setInt(
      _retentionKey(account),
      days,
    )) {
      throw StateError('Could not save cache retention.');
    }
  }

  static Future<int> load(String account) async {
    final value = (await SharedPreferences.getInstance()).getInt(_key(account));
    return minutes.contains(value) ? value! : defaultMinutes;
  }

  static Future<void> save(String account, int value) async {
    if (!minutes.contains(value)) throw ArgumentError.value(value);
    if (!await (await SharedPreferences.getInstance()).setInt(
      _key(account),
      value,
    )) {
      throw StateError('Could not save poll interval.');
    }
  }
}

String studioMailPollFailure(Object error, {String? code}) =>
    code ?? error.runtimeType.toString();

Future<void> showStudioMailPolling(
  BuildContext context, {
  required StudioStrings strings,
  required String label,
  required int interval,
  required int snapshotDays,
  required ValueNotifier<List<String>> activity,
  required Future<void> Function(int) save,
  required Future<void> Function(int) saveSnapshotDays,
  required Future<void> Function() poll,
}) async {
  String text(String en, String de, String ar) => switch (strings.language) {
    StudioLanguage.en => en,
    StudioLanguage.de => de,
    StudioLanguage.ar => ar,
  };
  var selected = interval;
  var retention = snapshotDays;
  var failed = false;
  var saving = false;
  final runNow = await showDialog<bool>(
    context: context,
    builder: (_) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text(
          text(
            'Mail account settings',
            'E-Mail-Kontoeinstellungen',
            'إعدادات حساب البريد',
          ),
        ),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            padding: const EdgeInsetsDirectional.only(end: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(label, textDirection: TextDirection.ltr),
                const SizedBox(height: 16),
                DropdownButtonFormField<int>(
                  key: ValueKey(('poll-interval', selected)),
                  initialValue: selected,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: text(
                      'Check Inbox for new mail',
                      'Posteingang abrufen',
                      'التحقق من الوارد',
                    ),
                  ),
                  items: [
                    for (final minutes in StudioMailPollPreferences.minutes)
                      DropdownMenuItem(
                        value: minutes,
                        child: Text(
                          minutes == 0
                              ? text('Manually', 'Manuell', 'يدويًا')
                              : text(
                                  'Every $minutes min',
                                  'Alle $minutes Min.',
                                  'كل $minutes دقيقة',
                                ),
                        ),
                      ),
                  ],
                  onChanged: saving
                      ? null
                      : (value) async {
                          if (value == null || value == selected) return;
                          final previous = selected;
                          setState(() {
                            selected = value;
                            saving = true;
                            failed = false;
                          });
                          try {
                            await save(value);
                          } on Object {
                            selected = previous;
                            failed = true;
                          } finally {
                            if (context.mounted) setState(() => saving = false);
                          }
                        },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  key: ValueKey(('snapshot-retention', retention)),
                  initialValue: retention,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: text(
                      'Keep offline folder snapshots',
                      'Offline-Ordneransichten behalten',
                      'الاحتفاظ بلقطات المجلدات دون اتصال',
                    ),
                  ),
                  items: [
                    for (final days in StudioMailPollPreferences.snapshotDays)
                      DropdownMenuItem(
                        value: days,
                        child: Text(
                          days == 0
                              ? text(
                                  'No expiry',
                                  'Ohne Ablaufdatum',
                                  'بدون انتهاء',
                                )
                              : text('$days days', '$days Tage', '$days يومًا'),
                        ),
                      ),
                  ],
                  onChanged: saving
                      ? null
                      : (value) async {
                          if (value == null || value == retention) return;
                          final previous = retention;
                          setState(() {
                            retention = value;
                            saving = true;
                            failed = false;
                          });
                          try {
                            await saveSnapshotDays(value);
                          } on Object {
                            retention = previous;
                            failed = true;
                          } finally {
                            if (context.mounted) setState(() => saving = false);
                          }
                        },
                ),
                if (failed)
                  Text(
                    text(
                      'Could not save the account setting.',
                      'Die Kontoeinstellung konnte nicht gespeichert werden.',
                      'تعذر حفظ الفاصل الزمني.',
                    ),
                  ),
                const SizedBox(height: 12),
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: Text(
                    text('IMAP activity', 'IMAP-Aktivität', 'نشاط IMAP'),
                  ),
                  children: [
                    ValueListenableBuilder(
                      valueListenable: activity,
                      builder: (context, entries, _) => Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (entries.isEmpty)
                            Text(
                              text(
                                'No activity for this account in this session.',
                                'Keine Aktivität für dieses Konto in dieser Sitzung.',
                                'لا يوجد نشاط لهذا الحساب في هذه الجلسة.',
                              ),
                            )
                          else ...[
                            Align(
                              alignment: AlignmentDirectional.centerStart,
                              child: TextButton.icon(
                                onPressed: () => Clipboard.setData(
                                  ClipboardData(text: entries.join('\n')),
                                ),
                                icon: const Icon(Icons.copy_outlined),
                                label: Text(
                                  text(
                                    'Copy log',
                                    'Protokoll kopieren',
                                    'نسخ السجل',
                                  ),
                                ),
                              ),
                            ),
                            SelectableText(
                              entries.reversed.join('\n'),
                              textDirection: TextDirection.ltr,
                              style: const TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(strings.close),
          ),
          FilledButton(
            onPressed: saving ? null : () => Navigator.pop(context, true),
            child: Text(text('Check now', 'Jetzt abrufen', 'تحقق الآن')),
          ),
        ],
      ),
    ),
  );
  if (runNow == true) await poll();
}

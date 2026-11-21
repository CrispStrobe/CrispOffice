import 'package:intl/intl.dart';

import 'studio_mail_reader_labels.dart';
import 'studio_strings.dart';

extension StudioMailScheduleStrings on StudioStrings {
  String _scheduleText(String en, String de, String ar) => switch (language) {
    StudioLanguage.en => en,
    StudioLanguage.de => de,
    StudioLanguage.ar => ar,
  };

  String get mailSendLater =>
      _scheduleText('Send later', 'Später senden', 'إرسال لاحقًا');
  String get mailSendWithUndo => _scheduleText(
    'Send with 10-second undo',
    'Mit 10 Sekunden Rücknahme senden',
    'إرسال مع مهلة تراجع 10 ثوانٍ',
  );
  String get mailScheduleExplanation => _scheduleText(
    'The message sends once at the selected time while this Outbox stays open and the app is active. Closing, switching accounts or leaving the app pauses sending. Reopen Outbox and choose Resume to continue. The saved time is a fixed instant, even if your time zone changes.',
    'Die Nachricht wird einmal zur gewählten Zeit gesendet, solange dieser Postausgang geöffnet und die App aktiv bleibt. Schließen, Kontowechsel oder Verlassen der App pausiert das Senden. Öffnen Sie den Postausgang und wählen Sie Fortsetzen. Der gespeicherte Zeitpunkt bleibt bei einem Zeitzonenwechsel gleich.',
    'تُرسل الرسالة مرة واحدة في الوقت المحدد ما دام صندوق الصادر هذا مفتوحًا والتطبيق نشطًا. يؤدي الإغلاق أو تبديل الحسابات أو مغادرة التطبيق إلى إيقاف الإرسال مؤقتًا. أعد فتح صندوق الصادر واختر استئناف للمتابعة. يبقى الموعد المحفوظ لحظة ثابتة حتى إذا تغيرت منطقتك الزمنية.',
  );
  String get mailScheduleUndoExplanation => _scheduleText(
    'Sending starts after 10 seconds. Choose Undo before then to keep the message in Outbox without sending it. Closing Outbox pauses sending; it does not discard the message.',
    'Das Senden beginnt nach 10 Sekunden. Wählen Sie vorher Rückgängig, um die Nachricht ungesendet im Postausgang zu behalten. Das Schließen pausiert das Senden und behält die Nachricht.',
    'يبدأ الإرسال بعد 10 ثوانٍ. اختر تراجع قبل ذلك لإبقاء الرسالة في صندوق الصادر دون إرسالها. يؤدي إغلاق صندوق الصادر إلى إيقاف الإرسال مؤقتًا دون حذف الرسالة.',
  );
  String get mailScheduleResume => _scheduleText(
    'Resume scheduled send',
    'Geplantes Senden fortsetzen',
    'استئناف الإرسال المجدول',
  );
  String get mailSchedulePaused => _scheduleText(
    'Paused — resume to send at the saved time, or now if overdue.',
    'Pausiert — fortsetzen, um zum gespeicherten Zeitpunkt oder bei Fälligkeit jetzt zu senden.',
    'متوقف مؤقتًا — استأنف للإرسال في الموعد المحفوظ، أو الآن إذا مضى الموعد.',
  );
  String get mailScheduleActive => _scheduleText(
    'Scheduled sending is active while this Outbox stays open.',
    'Geplantes Senden ist aktiv, solange dieser Postausgang geöffnet bleibt.',
    'الإرسال المجدول نشط ما دام صندوق الصادر هذا مفتوحًا.',
  );
  String get mailSchedulePause => _scheduleText(
    'Pause sending',
    'Senden pausieren',
    'إيقاف الإرسال مؤقتًا',
  );
  String get mailScheduleUndo => _scheduleText(
    'Undo / remove schedule',
    'Rückgängig / Zeitplan entfernen',
    'تراجع / إزالة الموعد',
  );
  String get mailScheduleDate => _scheduleText('Date', 'Datum', 'التاريخ');
  String get mailScheduleTime => _scheduleText('Time', 'Uhrzeit', 'الوقت');
  String get mailScheduleTomorrow => _scheduleText(
    'Tomorrow at 09:00',
    'Morgen um 09:00',
    'غدًا الساعة 09:00',
  );
  String get mailScheduleInOneHour =>
      _scheduleText('In one hour', 'In einer Stunde', 'بعد ساعة');
  String get mailScheduleConfirm =>
      _scheduleText('Schedule send', 'Senden planen', 'جدولة الإرسال');
  String get mailScheduleChooseFuture => _scheduleText(
    'Choose a valid future date and time.',
    'Wählen Sie ein gültiges Datum mit Uhrzeit in der Zukunft.',
    'اختر تاريخًا ووقتًا صالحين في المستقبل.',
  );
  String get mailScheduleSendNowExplanation => _scheduleText(
    'Remove the saved schedule and send this message now?',
    'Den gespeicherten Zeitplan entfernen und diese Nachricht jetzt senden?',
    'إزالة الموعد المحفوظ وإرسال هذه الرسالة الآن؟',
  );

  String mailScheduleAt(DateTime date) {
    final local = date.toLocal();
    final formatted = DateFormat.yMMMd(
      studioIntlLocale(language),
    ).add_Hms().format(local);
    final offset = local.timeZoneOffset.inMinutes;
    final sign = offset < 0 ? '−' : '+';
    final hours = (offset.abs() ~/ 60).toString().padLeft(2, '0');
    final minutes = (offset.abs() % 60).toString().padLeft(2, '0');
    final value = '$formatted (UTC$sign$hours:$minutes)';
    return _scheduleText(
      'Scheduled: $value',
      'Geplant: $value',
      'الموعد: $value',
    );
  }

  String mailScheduleCountdown(Duration remaining) {
    final seconds = (remaining.inMilliseconds + 999) ~/ 1000;
    return _scheduleText(
      'Sending in $seconds s',
      'Senden in $seconds s',
      'الإرسال خلال $seconds ث',
    );
  }
}

import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_store/quds_mail_store.dart';

import 'studio_strings.dart';

extension StudioMailJournalStrings on StudioStrings {
  String _text(String en, String de, String ar) => switch (language) {
    StudioLanguage.en => en,
    StudioLanguage.de => de,
    StudioLanguage.ar => ar,
  };

  String get mailActivity =>
      _text('Mail activity', 'Mail-Aktivitäten', 'نشاط البريد');
  String get mailActivityScope => _text(
    'Read and flag changes saved on this device. Interrupted changes are never sent again automatically.',
    'Auf diesem Gerät gespeicherte Lese- und Kennzeichnungsänderungen. Unterbrochene Änderungen werden nie automatisch erneut gesendet.',
    'تغييرات القراءة والعلامات المحفوظة على هذا الجهاز. لا تُرسل التغييرات المتوقفة مرة أخرى تلقائيًا.',
  );
  String get mailActivityEmpty => _text(
    'No saved mail activity yet.',
    'Noch keine gespeicherten Mail-Aktivitäten.',
    'لا يوجد نشاط بريد محفوظ بعد.',
  );
  String get mailActivityFailed => _text(
    'Mail activity could not be read. Close this view and try again.',
    'Mail-Aktivitäten konnten nicht gelesen werden. Schließen Sie diese Ansicht und versuchen Sie es erneut.',
    'تعذرت قراءة نشاط البريد. أغلق هذا العرض وحاول مرة أخرى.',
  );
  String get mailActivityInterrupted => _text(
    'Interrupted. Refresh the folder to check its current state. No remaining changes were replayed.',
    'Unterbrochen. Aktualisieren Sie den Ordner, um den aktuellen Status zu prüfen. Ausstehende Änderungen wurden nicht erneut ausgeführt.',
    'توقف الإجراء. حدّث المجلد للتحقق من حالته الحالية. لم تُنفذ التغييرات المتبقية مرة أخرى.',
  );
  String get mailActivityRunning => _text(
    'Still in progress. A pending server reply is not a confirmed change.',
    'Noch in Bearbeitung. Eine ausstehende Serverantwort ist keine bestätigte Änderung.',
    'ما زال الإجراء قيد التنفيذ. انتظار رد الخادم لا يعني تأكيد التغيير.',
  );
  String get mailActivityMore =>
      _text('Older activity', 'Ältere Aktivitäten', 'نشاط أقدم');
  String get mailActivityBack =>
      _text('All activity', 'Alle Aktivitäten', 'كل النشاط');
  String get mailActivityClear => _text(
    'Clear completed receipts',
    'Abgeschlossene Belege löschen',
    'مسح سجلات الإجراءات المكتملة',
  );
  String get mailActivityClearQuestion => _text(
    'Clear completed receipts on this device? Changes still in progress or with uncertain outcomes are kept. Mail on the server is unchanged.',
    'Abgeschlossene Belege auf diesem Gerät löschen? Laufende Änderungen und ungewisse Ergebnisse bleiben erhalten. Servernachrichten bleiben unverändert.',
    'هل تريد مسح سجلات الإجراءات المكتملة على هذا الجهاز؟ تُحفظ التغييرات الجارية أو ذات النتائج غير المؤكدة، ولا يتغير البريد على الخادم.',
  );
  String get mailActivityPersistenceFailed => _text(
    'The local receipt could not be saved reliably. Further changes stopped. Refresh the folder and check Mail activity before another change.',
    'Der lokale Beleg konnte nicht zuverlässig gespeichert werden. Weitere Änderungen wurden gestoppt. Aktualisieren Sie den Ordner und prüfen Sie die Mail-Aktivitäten vor einer weiteren Änderung.',
    'تعذر حفظ السجل المحلي بشكل موثوق. توقفت التغييرات التالية. حدّث المجلد وتحقق من نشاط البريد قبل إجراء تغيير آخر.',
  );
  String mailActivityAction(MailBulkFlagAction action) => switch (action) {
    MailBulkFlagAction.markRead => _text(
      'Mark read',
      'Als gelesen markieren',
      'تحديد كمقروءة',
    ),
    MailBulkFlagAction.markUnread => _text(
      'Mark unread',
      'Als ungelesen markieren',
      'تحديد كغير مقروءة',
    ),
    MailBulkFlagAction.flag => _text(
      'Flag messages',
      'Kennzeichnen',
      'تعليم الرسائل',
    ),
    MailBulkFlagAction.unflag => _text(
      'Unflag messages',
      'Kennzeichnung entfernen',
      'إزالة تعليم الرسائل',
    ),
  };
  String mailActivityCounts(MailStoredFlagBatchSummary batch) => _text(
    '${batch.confirmedCount} confirmed · ${batch.failedCount} failed · ${batch.uncertainCount} uncertain · ${batch.unattemptedCount} not attempted',
    '${batch.confirmedCount} bestätigt · ${batch.failedCount} fehlgeschlagen · ${batch.uncertainCount} ungewiss · ${batch.unattemptedCount} nicht versucht',
    '${batch.confirmedCount} مؤكدة · ${batch.failedCount} فشلت · ${batch.uncertainCount} غير مؤكدة · ${batch.unattemptedCount} لم تُحاول',
  );
}

import 'package:quds_mail_store/quds_mail_store.dart';

import 'studio_mail_archive_strings.dart';
import 'studio_strings.dart';

extension StudioMailArchiveRestoreStrings on StudioStrings {
  String _restoreText(String en, String de, String ar) => switch (language) {
    StudioLanguage.en => en,
    StudioLanguage.de => de,
    StudioLanguage.ar => ar,
  };

  String get archiveRestoreExport => _restoreText(
    'Restore exported archive',
    'Exportiertes Archiv wiederherstellen',
    'استعادة أرشيف مُصدَّر',
  );

  String get archiveRestoreStart => _restoreText(
    'Restore messages',
    'Nachrichten wiederherstellen',
    'استعادة الرسائل',
  );

  String archiveRestoreSelection(
    int messages,
    int origins,
    int bytes,
  ) => _restoreText(
    'Restore $messages original messages ($bytes bytes) and $origins recorded source and folder entries into this local archive.',
    '$messages Originalnachrichten ($bytes Bytes) und $origins gespeicherte Quellen- und Ordnerangaben in dieses lokale Archiv übernehmen.',
    'استعد $messages رسالة أصلية ($bytes بايت) و$origins من سجلات المصادر والمجلدات إلى هذا الأرشيف المحلي.',
  );

  String archiveRestoreSourceProfile(String host, String profile) =>
      _restoreText(
        'Exported from: $host / $profile',
        'Exportiert aus: $host / $profile',
        'صُدِّر من: $host / $profile',
      );

  String archiveRestoreCreatedAt(String date) => _restoreText(
    'Export created: $date',
    'Export erstellt: $date',
    'تاريخ إنشاء التصدير: $date',
  );

  String get archiveRestoreTrust => _restoreText(
    'Source and folder labels come from this unsigned export. Restore exports you trust. Each original is checked against its recorded size and SHA-256 before it is saved.',
    'Quellen- und Ordnerangaben stammen aus diesem unsignierten Export. Nur vertrauenswürdige Exporte wiederherstellen. Jedes Original wird vor dem Speichern anhand der gespeicherten Größe und SHA-256-Prüfsumme geprüft.',
    'تأتي تسميات المصادر والمجلدات من هذا التصدير غير الموقَّع. استعد التصديرات التي تثق بها. تُفحص كل رسالة أصلية وفق حجمها وبصمة SHA-256 المسجَّلين قبل حفظها.',
  );

  String get archiveRestoreHelp => _restoreText(
    'Existing originals are deduplicated and missing source entries are added. Rerun after an interruption to finish. New messages receive the current archive date. Accounts and saved searches are outside this export.',
    'Vorhandene Originale werden dedupliziert und fehlende Quellenangaben ergänzt. Nach einer Unterbrechung erneut starten. Neue Nachrichten erhalten das aktuelle Archivierungsdatum. Konten und gespeicherte Suchen sind nicht Teil dieses Exports.',
    'تُزال ازدواجية الرسائل الأصلية الموجودة وتُضاف سجلات المصادر الناقصة. أعد التشغيل بعد الانقطاع لإكمال الاستعادة. تحصل الرسائل الجديدة على تاريخ الأرشفة الحالي. لا يتضمن هذا التصدير الحسابات وعمليات البحث المحفوظة.',
  );

  String archiveRestoreCounts(
    int saved,
    int duplicates,
    int failed,
    int planned,
    int originsAdded,
    int bytes,
    int warnings,
  ) => _restoreText(
    '$saved saved · $duplicates already archived · $failed failed · $planned planned\n$originsAdded source entries added · $bytes verified bytes · $warnings indexing warnings',
    '$saved gespeichert · $duplicates bereits archiviert · $failed fehlgeschlagen · $planned geplant\n$originsAdded Quellenangaben ergänzt · $bytes geprüfte Bytes · $warnings Indizierungswarnungen',
    '$saved محفوظة · $duplicates مؤرشفة سابقًا · $failed تعذرت · $planned مقررة\n$originsAdded سجلات مصادر مضافة · $bytes بايت تم التحقق منها · $warnings تحذيرات فهرسة',
  );

  String archiveRestoreSummary(MailArchiveRestoreReport report) {
    final status = switch (report.status) {
      MailArchiveRestoreStatus.completed => MailArchiveRunStatus.completed,
      MailArchiveRestoreStatus.partial => MailArchiveRunStatus.partial,
      MailArchiveRestoreStatus.cancelled => MailArchiveRunStatus.cancelled,
      MailArchiveRestoreStatus.failed => MailArchiveRunStatus.failed,
    };
    return '${archiveRunStatusLabel(status)}. ${archiveRestoreCounts(report.saved, report.duplicates, report.failed, report.planned, report.originsAdded, report.bytes, report.indexWarnings)}';
  }

  String get archiveRestoreFailures => _restoreText(
    'Restore failures',
    'Fehler bei der Wiederherstellung',
    'أخطاء الاستعادة',
  );

  String archiveRestoreItem(int ordinal) => _restoreText(
    'Export item $ordinal',
    'Exporteintrag $ordinal',
    'عنصر التصدير $ordinal',
  );
}

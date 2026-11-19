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

  String get archiveRestoreResumeStart => _restoreText(
    'Resume restore',
    'Wiederherstellung fortsetzen',
    'متابعة الاستعادة',
  );

  String get archiveRestoreResume => _restoreText(
    'Resume unfinished work',
    'Unvollständige Arbeit fortsetzen',
    'متابعة العمل غير المكتمل',
  );

  String get archiveRestoreResumeHelp => _restoreText(
    'Previously committed messages and source entries are checked in this archive. Their export files are not read again. Clear this option to verify every source file again.',
    'Bereits gespeicherte Nachrichten und Quellenangaben werden in diesem Archiv geprüft. Ihre Exportdateien werden nicht erneut gelesen. Diese Option deaktivieren, um alle Quelldateien erneut zu prüfen.',
    'تُفحص الرسائل وسجلات المصادر المحفوظة سابقًا في هذا الأرشيف. لا تُقرأ ملفات تصديرها مرة أخرى. ألغِ هذا الخيار للتحقق من جميع الملفات المصدر مجددًا.',
  );

  String archiveRestoreExportId(String value) => _restoreText(
    'Export ID: \u2066$value\u2069',
    'Export-ID: \u2066$value\u2069',
    'معرّف التصدير: \u2066$value\u2069',
  );

  String archiveRestoreRecorded(
    int completed,
    int planned,
    int bytes,
  ) => _restoreText(
    '$completed of $planned messages recorded as committed ($bytes bytes).',
    '$completed von $planned Nachrichten als gespeichert erfasst ($bytes Bytes).',
    'سُجّل حفظ $completed من $planned رسالة ($bytes بايت).',
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
    'Existing originals are deduplicated and missing source entries are added. Progress is saved with each message so you can resume after restarting. New messages receive the current archive date. Accounts and saved searches are outside this export.',
    'Vorhandene Originale werden dedupliziert und fehlende Quellenangaben ergänzt. Der Fortschritt wird mit jeder Nachricht gespeichert und bleibt nach einem Neustart erhalten. Neue Nachrichten erhalten das aktuelle Archivierungsdatum. Konten und gespeicherte Suchen sind nicht Teil dieses Exports.',
    'تُزال ازدواجية الرسائل الأصلية الموجودة وتُضاف سجلات المصادر الناقصة. يُحفظ التقدم مع كل رسالة لتتمكن من المتابعة بعد إعادة التشغيل. تحصل الرسائل الجديدة على تاريخ الأرشفة الحالي. لا يتضمن هذا التصدير الحسابات وعمليات البحث المحفوظة.',
  );

  String archiveRestoreCounts(
    int saved,
    int duplicates,
    int failed,
    int planned,
    int originsAdded,
    int bytes,
    int warnings, {
    int resumed = 0,
    int resumedBytes = 0,
    int resumedIndexWarnings = 0,
  }) {
    final current = _restoreText(
      '$saved saved · $duplicates already archived · $failed failed · $planned planned\n$originsAdded source entries added · $bytes source bytes verified · $warnings indexing warnings',
      '$saved gespeichert · $duplicates bereits archiviert · $failed fehlgeschlagen · $planned geplant\n$originsAdded Quellenangaben ergänzt · $bytes geprüfte Quellbytes · $warnings Indizierungswarnungen',
      '$saved محفوظة · $duplicates مؤرشفة سابقًا · $failed تعذرت · $planned مقررة\n$originsAdded سجلات مصادر مضافة · $bytes بايت مصدر تم التحقق منها · $warnings تحذيرات فهرسة',
    );
    if (resumed == 0) return current;
    final previous = _restoreText(
      '$resumed previously committed · $resumedBytes archive bytes rechecked · $resumedIndexWarnings earlier indexing warnings',
      '$resumed zuvor gespeichert · $resumedBytes Archivbytes erneut geprüft · $resumedIndexWarnings frühere Indizierungswarnungen',
      '$resumed محفوظة سابقًا · $resumedBytes بايت أرشيف أُعيد فحصها · $resumedIndexWarnings تحذيرات فهرسة سابقة',
    );
    return '$current\n$previous';
  }

  String archiveRestoreSummary(MailArchiveRestoreReport report) {
    final status = switch (report.status) {
      MailArchiveRestoreStatus.completed => MailArchiveRunStatus.completed,
      MailArchiveRestoreStatus.partial => MailArchiveRunStatus.partial,
      MailArchiveRestoreStatus.cancelled => MailArchiveRunStatus.cancelled,
      MailArchiveRestoreStatus.failed => MailArchiveRunStatus.failed,
    };
    return '${archiveRunStatusLabel(status)}. ${archiveRestoreCounts(report.saved, report.duplicates, report.failed, report.planned, report.originsAdded, report.bytes, report.indexWarnings, resumed: report.resumed, resumedBytes: report.resumedBytes, resumedIndexWarnings: report.resumedIndexWarnings)}';
  }

  String get archiveRestoreProgress => _restoreText(
    'Restore progress',
    'Wiederherstellungsfortschritt',
    'تقدم الاستعادة',
  );

  String get archiveRestoreProgressHelp => _restoreText(
    'Saved progress lets you resume an export after restarting. Match its export ID with the restore preview. Forget progress you no longer need to free space for other restores.',
    'Gespeicherter Fortschritt ermöglicht das Fortsetzen nach einem Neustart. Die Export-ID steht auch in der Wiederherstellungsvorschau. Nicht mehr benötigten Fortschritt entfernen, um Platz für weitere Wiederherstellungen freizugeben.',
    'يتيح التقدم المحفوظ متابعة التصدير بعد إعادة التشغيل. طابق معرّف التصدير مع معاينة الاستعادة. احذف التقدم الذي لم تعد تحتاج إليه لإتاحة مساحة لاستعادات أخرى.',
  );

  String get archiveRestoreProgressEmpty => _restoreText(
    'No saved restore progress.',
    'Kein Wiederherstellungsfortschritt gespeichert.',
    'لا يوجد تقدم استعادة محفوظ.',
  );

  String get archiveRestoreForget =>
      _restoreText('Forget progress', 'Fortschritt entfernen', 'حذف التقدم');

  String archiveRestoreForgetConfirmation(String value) => _restoreText(
    'Forget saved progress for export \u2066$value\u2069? Archived messages and source files are kept. A future restore will verify every source file again.',
    'Gespeicherten Fortschritt für Export \u2066$value\u2069 entfernen? Archivierte Nachrichten und Quelldateien bleiben erhalten. Bei einer späteren Wiederherstellung wird jede Quelldatei erneut geprüft.',
    'هل تريد حذف التقدم المحفوظ للتصدير \u2066$value\u2069؟ تبقى الرسائل المؤرشفة والملفات المصدر محفوظة. ستفحص الاستعادة اللاحقة جميع الملفات المصدر مجددًا.',
  );

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

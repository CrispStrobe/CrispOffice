import 'studio_strings.dart';

extension StudioMailDraftsStrings on StudioStrings {
  String _draftsText(String en, String de, String ar) => switch (language) {
    StudioLanguage.en => en,
    StudioLanguage.de => de,
    StudioLanguage.ar => ar,
  };

  String get mailDrafts => _draftsText('Drafts', 'Entwürfe', 'المسودات');
  String get mailNewDraft =>
      _draftsText('New draft', 'Neuer Entwurf', 'مسودة جديدة');
  String get mailDraftListExplanation => _draftsText(
    'Drafts are saved locally for this account. Start a new message or resume a saved draft. Opening a draft never sends it.',
    'Entwürfe werden lokal für dieses Konto gespeichert. Beginnen Sie eine neue Nachricht oder setzen Sie einen gespeicherten Entwurf fort. Das Öffnen versendet keine Nachricht.',
    'تُحفظ المسودات محليًا لهذا الحساب. ابدأ رسالة جديدة أو استأنف مسودة محفوظة. فتح المسودة لا يرسلها.',
  );
  String get mailDraftListEmpty => _draftsText(
    'No saved drafts on this page.',
    'Keine gespeicherten Entwürfe auf dieser Seite.',
    'لا توجد مسودات محفوظة في هذه الصفحة.',
  );
  String get mailDraftListFailed => _draftsText(
    'Could not update local drafts. Refresh and try again. Existing drafts are retained; up to 100 active drafts can be created per account.',
    'Lokale Entwürfe konnten nicht aktualisiert werden. Aktualisieren Sie die Liste und versuchen Sie es erneut. Vorhandene Entwürfe bleiben erhalten; pro Konto können bis zu 100 aktive Entwürfe angelegt werden.',
    'تعذر تحديث المسودات المحلية. حدّث القائمة وحاول مجددًا. تُحفظ المسودات الموجودة؛ يمكن إنشاء ما يصل إلى 100 مسودة نشطة لكل حساب.',
  );
  String get mailDraftNoSubject =>
      _draftsText('(No subject)', '(Kein Betreff)', '(بلا موضوع)');
  String get mailDraftNoRecipients => _draftsText(
    'No recipients yet',
    'Noch keine Empfänger',
    'لا يوجد مستلمون بعد',
  );
  String get mailDraftUncertain => _draftsText(
    'Check earlier delivery before sending',
    'Vor dem Senden frühere Zustellung prüfen',
    'تحقق من التسليم السابق قبل الإرسال',
  );
  String get mailDraftDelete =>
      _draftsText('Delete draft', 'Entwurf löschen', 'حذف المسودة');
  String get mailDraftDeleteExplanation => _draftsText(
    'Delete this local draft and its saved attachments? Other drafts and server messages are kept.',
    'Diesen lokalen Entwurf und seine gespeicherten Anhänge löschen? Andere Entwürfe und Nachrichten auf dem Server bleiben erhalten.',
    'حذف هذه المسودة المحلية ومرفقاتها المحفوظة؟ تبقى المسودات الأخرى ورسائل الخادم محفوظة.',
  );
  String get mailDraftDeleteUncertainExplanation => _draftsText(
    'An earlier send may have been accepted. Deleting this draft does not recall that message or resolve its delivery status.',
    'Ein früherer Sendeversuch wurde möglicherweise angenommen. Das Löschen des Entwurfs ruft diese Nachricht nicht zurück und klärt ihren Zustellstatus nicht.',
    'ربما قُبلت محاولة إرسال سابقة. حذف المسودة لا يستدعي تلك الرسالة ولا يحسم حالة تسليمها.',
  );
  String get mailDraftPrevious =>
      _draftsText('Previous page', 'Vorherige Seite', 'الصفحة السابقة');
  String get mailDraftNext =>
      _draftsText('Next page', 'Nächste Seite', 'الصفحة التالية');
  String get mailDraftResume =>
      _draftsText('Resume draft', 'Entwurf fortsetzen', 'استئناف المسودة');
  String get mailLocalDrafts =>
      _draftsText('Local drafts', 'Lokale Entwürfe', 'المسودات المحلية');
  String get mailLocalDraftsExplanation => _draftsText(
    'Edit drafts for this saved account without connecting. Connect to your mailbox when you are ready to send.',
    'Bearbeiten Sie Entwürfe für dieses gespeicherte Konto ohne Verbindung. Verbinden Sie das Postfach, wenn Sie senden möchten.',
    'حرّر مسودات هذا الحساب المحفوظ دون اتصال. اتصل بصندوق البريد عندما تكون مستعدًا للإرسال.',
  );
  String get mailDraftConnectToSend => _draftsText(
    'Sending is unavailable in this view. You can save this draft locally.',
    'Senden ist in dieser Ansicht nicht verfügbar. Sie können diesen Entwurf lokal speichern.',
    'الإرسال غير متاح في هذه الواجهة. يمكنك حفظ هذه المسودة محليًا.',
  );
  String get mailDraftCloseFailed => _draftsText(
    'Could not finish closing local drafts. Please try again before opening this account.',
    'Lokale Entwürfe konnten nicht vollständig geschlossen werden. Versuchen Sie es erneut, bevor Sie dieses Konto öffnen.',
    'تعذر إكمال إغلاق المسودات المحلية. حاول مجددًا قبل فتح هذا الحساب.',
  );
  String mailDraftAttachmentCount(int count) =>
      _draftsText('Attachments: $count', 'Anhänge: $count', 'المرفقات: $count');
}

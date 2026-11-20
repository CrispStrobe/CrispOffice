import 'studio_strings.dart';

extension StudioMailLocalAccountsStrings on StudioStrings {
  String _text(String en, String de, String ar) => switch (language) {
    StudioLanguage.en => en,
    StudioLanguage.de => de,
    StudioLanguage.ar => ar,
  };

  String get mailLocalAccounts => _text(
    'Drafts for connected accounts',
    'Entwürfe bereits verbundener Konten',
    'مسودات الحسابات المتصلة سابقًا',
  );
  String get mailLocalAccountsHelp => _text(
    'Choose an account you connected successfully to edit its local drafts offline. Account addresses and server settings are saved on this device; passwords and sign-in tokens are not saved here. Reconnect through the matching provider to send.',
    'Wählen Sie ein zuvor erfolgreich verbundenes Konto, um lokale Entwürfe offline zu bearbeiten. Adressen und Servereinstellungen werden auf diesem Gerät gespeichert; Passwörter und Anmeldetoken werden hier nicht gespeichert. Verbinden Sie sich zum Senden erneut über den passenden Anbieter.',
    'اختر حسابًا اتصلت به بنجاح لتحرير مسوداته المحلية دون اتصال. تُحفظ العناوين وإعدادات الخادم على هذا الجهاز، ولا تُحفظ هنا كلمات المرور أو رموز تسجيل الدخول. أعد الاتصال عبر المزوّد المناسب للإرسال.',
  );
  String get mailLocalAccountsEmpty => _text(
    'No connected accounts are listed yet. Connect once to add an account. Older accounts need one successful reconnect.',
    'Noch keine verbundenen Konten erfasst. Verbinden Sie ein Konto einmal erfolgreich. Ältere Konten müssen einmal erneut verbunden werden.',
    'لا توجد حسابات مسجلة بعد. اتصل مرة واحدة لإضافة حساب. تحتاج الحسابات القديمة إلى إعادة اتصال ناجحة واحدة.',
  );
  String get mailLocalAccountsFailed => _text(
    'Could not read or update the local account list. Refresh and try again. Existing drafts are retained.',
    'Die lokale Kontenliste konnte nicht gelesen oder aktualisiert werden. Aktualisieren Sie die Liste und versuchen Sie es erneut. Vorhandene Entwürfe bleiben erhalten.',
    'تعذرت قراءة قائمة الحسابات المحلية أو تحديثها. حدّث القائمة وحاول مجددًا. تبقى المسودات الموجودة محفوظة.',
  );
  String get mailLocalAccountsSaveFailed => _text(
    'Connected, but this account could not be added to the offline draft list. The list holds up to 100 accounts; remove an old entry or reconnect to try again. Your mailbox and saved drafts remain available.',
    'Verbunden, aber dieses Konto konnte nicht zur Offline-Entwurfsliste hinzugefügt werden. Die Liste fasst bis zu 100 Konten; entfernen Sie einen alten Eintrag oder verbinden Sie sich erneut. Postfach und gespeicherte Entwürfe bleiben verfügbar.',
    'تم الاتصال، لكن تعذرت إضافة الحساب إلى قائمة المسودات دون اتصال. تتسع القائمة لـ100 حساب؛ أزل إدخالًا قديمًا أو أعد الاتصال للمحاولة مجددًا. يبقى صندوق البريد والمسودات المحفوظة متاحة.',
  );
  String get mailLocalAccountRemove =>
      _text('Remove from list', 'Aus Liste entfernen', 'إزالة من القائمة');
  String get mailLocalAccountRemoveHelp => _text(
    'Remove only this offline account shortcut? Local drafts, Outbox messages, saved credentials and server mail are kept. A successful reconnect adds the shortcut again.',
    'Nur diesen Offline-Kontoeintrag entfernen? Lokale Entwürfe, Postausgang, gespeicherte Zugangsdaten und Servernachrichten bleiben erhalten. Eine erfolgreiche erneute Verbindung fügt den Eintrag wieder hinzu.',
    'إزالة اختصار الحساب دون اتصال فقط؟ تبقى المسودات المحلية ورسائل الصادر وبيانات الاعتماد المحفوظة ورسائل الخادم. تعيد إعادة الاتصال الناجحة إضافة الاختصار.',
  );
}

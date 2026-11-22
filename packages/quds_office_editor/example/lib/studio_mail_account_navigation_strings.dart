import 'studio_strings.dart';

extension StudioMailAccountNavigationStrings on StudioStrings {
  String _text(String en, String de, String ar) => switch (language) {
    StudioLanguage.en => en,
    StudioLanguage.de => de,
    StudioLanguage.ar => ar,
  };

  String get mailAccountNavigationTitle =>
      _text('Choose an account', 'Konto auswählen', 'اختيار حساب');
  String get mailAccountNavigationHelp => _text(
    'Choose an account you have connected before. Review its sign-in settings before connecting.',
    'Wählen Sie ein zuvor verbundenes Konto. Prüfen Sie vor dem Verbinden dessen Anmeldeeinstellungen.',
    'اختر حسابًا اتصلت به سابقًا. راجع إعدادات تسجيل الدخول قبل الاتصال.',
  );
  String get mailAccountNavigationCurrent =>
      _text('Current account', 'Aktuelles Konto', 'الحساب الحالي');
  String get mailAccountNavigationContinue => _text(
    'Continue to sign in',
    'Weiter zur Anmeldung',
    'المتابعة لتسجيل الدخول',
  );
  String get mailAccountNavigationRefresh =>
      _text('Refresh accounts', 'Konten aktualisieren', 'تحديث الحسابات');
  String get mailAccountNavigationEmpty => _text(
    'No saved accounts are available. Connect an account first.',
    'Keine gespeicherten Konten verfügbar. Verbinden Sie zuerst ein Konto.',
    'لا توجد حسابات محفوظة. اتصل بحساب أولًا.',
  );
  String get mailAccountNavigationFailed => _text(
    'Could not read the saved accounts. Refresh and try again.',
    'Die gespeicherten Konten konnten nicht gelesen werden. Aktualisieren Sie die Liste und versuchen Sie es erneut.',
    'تعذرت قراءة الحسابات المحفوظة. حدّث القائمة وحاول مجددًا.',
  );
  String get mailAccountNavigationChanged => _text(
    'The selected account changed or was removed. Refresh the list before continuing.',
    'Das ausgewählte Konto wurde geändert oder entfernt. Aktualisieren Sie die Liste, bevor Sie fortfahren.',
    'تغير الحساب المحدد أو أُزيل. حدّث القائمة قبل المتابعة.',
  );
  String get mailAccountNavigationIdentityMismatch => _text(
    'These settings do not match the selected account. Select the intended account again before connecting.',
    'Diese Einstellungen stimmen nicht mit dem ausgewählten Konto überein. Wählen Sie das gewünschte Konto vor dem Verbinden erneut aus.',
    'لا تتطابق هذه الإعدادات مع الحساب المحدد. اختر الحساب المقصود مجددًا قبل الاتصال.',
  );
  String get mailAccountNavigationReconnectHelp => _text(
    'Sign in to the selected account to open its connected mailbox.',
    'Melden Sie sich beim ausgewählten Konto an, um dessen verbundenes Postfach zu öffnen.',
    'سجّل الدخول إلى الحساب المحدد لفتح صندوق بريده المتصل.',
  );
  String get mailAccountNavigationRouteUnavailable => _text(
    'Choose a matching saved sign-in, or enter this account’s server settings to continue.',
    'Wählen Sie passende gespeicherte Anmeldedaten oder geben Sie die Servereinstellungen dieses Kontos ein, um fortzufahren.',
    'اختر بيانات تسجيل دخول محفوظة مطابقة، أو أدخل إعدادات خادم هذا الحساب للمتابعة.',
  );
  String get mailAccountNavigationReleaseFailed => _text(
    'The previous account could not finish closing. Try again before opening another account.',
    'Das vorherige Konto konnte nicht vollständig geschlossen werden. Versuchen Sie es erneut, bevor Sie ein anderes Konto öffnen.',
    'تعذر إكمال إغلاق الحساب السابق. حاول مجددًا قبل فتح حساب آخر.',
  );
  String get mailAccountNavigationRelease => _text(
    'Retry closing account',
    'Schließen des Kontos erneut versuchen',
    'إعادة محاولة إغلاق الحساب',
  );
  String get mailAccountNavigationReleaseHelp => _text(
    'The previous account could not finish closing. Retry before connecting another account.',
    'Das vorherige Konto konnte nicht vollständig geschlossen werden. Versuchen Sie es erneut, bevor Sie ein anderes Konto verbinden.',
    'تعذر إكمال إغلاق الحساب السابق. أعد المحاولة قبل الاتصال بحساب آخر.',
  );
}

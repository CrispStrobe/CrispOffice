import 'credentials/biometric_secret_store.dart';
import 'studio_strings.dart';

/// Touch ID unlock of the encrypted credential vault.
extension StudioCredentialBiometricStrings on StudioStrings {
  String _text(String en, String de, String ar) => switch (language) {
    StudioLanguage.en => en,
    StudioLanguage.de => de,
    StudioLanguage.ar => ar,
  };

  /// Shown by macOS in the system Touch ID sheet.
  String get vaultTouchIdReason => _text(
    'unlock your saved CrispOffice accounts',
    'gespeicherte CrispOffice-Konten entsperren',
    'فتح حسابات CrispOffice المحفوظة',
  );
  String get vaultTouchIdUsePassword => _text(
    'Use master password',
    'Master-Passwort verwenden',
    'استخدام كلمة المرور الرئيسية',
  );
  String get vaultTouchIdOptIn => _text(
    'Unlock with Touch ID next time',
    'Nächstes Mal mit Touch ID entsperren',
    'الفتح باستخدام Touch ID في المرة القادمة',
  );
  String get vaultTouchIdToggle => _text(
    'Unlock with Touch ID',
    'Mit Touch ID entsperren',
    'الفتح باستخدام Touch ID',
  );
  String get vaultTouchIdUnlockButton =>
      _text('Use Touch ID', 'Touch ID verwenden', 'استخدام Touch ID');
  String get vaultTouchIdHelp => _text(
    'macOS keeps the vault key in this Mac’s keychain and releases it only after Touch ID. The master password still works and is not stored.',
    'macOS bewahrt den Tresorschlüssel im Schlüsselbund dieses Macs auf und gibt ihn nur nach Touch ID frei. Das Master-Passwort funktioniert weiterhin und wird nicht gespeichert.',
    'يحتفظ macOS بمفتاح الخزنة في سلسلة مفاتيح هذا الـMac ولا يسلّمه إلا بعد Touch ID. تظل كلمة المرور الرئيسية صالحة ولا تُخزَّن.',
  );
  String get vaultTouchIdEnableAfterUnlock => _text(
    'Touch ID is turned on after the vault is unlocked with its master password.',
    'Touch ID wird eingeschaltet, nachdem der Tresor mit dem Master-Passwort entsperrt wurde.',
    'يُفعَّل Touch ID بعد فتح الخزنة بكلمة مرورها الرئيسية.',
  );
  String get vaultTouchIdInvalidated => _text(
    'Touch ID unlock was turned off because the fingerprints on this Mac or the vault changed. Turn it on again if you like.',
    'Die Entsperrung mit Touch ID wurde ausgeschaltet, weil sich die Fingerabdrücke auf diesem Mac oder der Tresor geändert haben. Sie kann wieder eingeschaltet werden.',
    'أُوقف الفتح باستخدام Touch ID لأن البصمات على هذا الـMac أو الخزنة قد تغيّرت. يمكنك تفعيله من جديد.',
  );
  String get vaultTouchIdEnableFailed => _text(
    'The vault is unlocked, but Touch ID could not be turned on. The master password still works.',
    'Der Tresor ist entsperrt, aber Touch ID konnte nicht eingeschaltet werden. Das Master-Passwort funktioniert weiterhin.',
    'فُتحت الخزنة، لكن تعذّر تفعيل Touch ID. تظل كلمة المرور الرئيسية صالحة.',
  );
  String get vaultTouchIdDisableFailed => _text(
    'Touch ID unlock could not be turned off. Try again.',
    'Die Entsperrung mit Touch ID konnte nicht ausgeschaltet werden. Erneut versuchen.',
    'تعذّر إيقاف الفتح باستخدام Touch ID. حاول مجددًا.',
  );
  String get vaultTouchIdFailed => _text(
    'Touch ID did not unlock the vault. Enter the master password.',
    'Touch ID hat den Tresor nicht entsperrt. Master-Passwort eingeben.',
    'لم يفتح Touch ID الخزنة. أدخل كلمة المرور الرئيسية.',
  );

  /// Why the option is hidden or disabled, or null when it can be used.
  String? vaultTouchIdUnavailable(
    BiometricUnlockAvailability availability,
  ) => switch (availability) {
    BiometricUnlockAvailability.available => null,
    BiometricUnlockAvailability.unsupportedPlatform => null,
    BiometricUnlockAvailability.noHardware => _text(
      'Touch ID is not available on this Mac right now.',
      'Touch ID ist auf diesem Mac derzeit nicht verfügbar.',
      'Touch ID غير متاح على هذا الـMac حاليًا.',
    ),
    BiometricUnlockAvailability.notEnrolled => _text(
      'Add a fingerprint in System Settings › Touch ID & Password to unlock with Touch ID.',
      'Fingerabdruck unter Systemeinstellungen › Touch ID & Passwort hinzufügen, um mit Touch ID zu entsperren.',
      'أضف بصمة في إعدادات النظام › Touch ID وكلمة السر للفتح باستخدام Touch ID.',
    ),
    BiometricUnlockAvailability.lockedOut => _text(
      'Touch ID is locked after too many attempts. Unlock your Mac with its password, then try again.',
      'Touch ID ist nach zu vielen Versuchen gesperrt. Mac mit seinem Passwort entsperren und erneut versuchen.',
      'Touch ID مقفل بعد محاولات كثيرة. افتح الـMac بكلمة مروره ثم حاول مجددًا.',
    ),
    BiometricUnlockAvailability.keychainUnavailable => _text(
      'This CrispOffice build is not signed for the protected keychain, so Touch ID unlock is unavailable. Signed releases support it.',
      'Dieser CrispOffice-Build ist nicht für den geschützten Schlüsselbund signiert, daher ist die Entsperrung mit Touch ID nicht verfügbar. Signierte Versionen unterstützen sie.',
      'نسخة CrispOffice هذه غير موقّعة لسلسلة المفاتيح المحمية، لذا لا يتوفر الفتح باستخدام Touch ID. تدعمه النسخ الموقّعة.',
    ),
    BiometricUnlockAvailability.error => _text(
      'Touch ID unlock is unavailable right now.',
      'Die Entsperrung mit Touch ID ist derzeit nicht verfügbar.',
      'الفتح باستخدام Touch ID غير متاح حاليًا.',
    ),
  };
}

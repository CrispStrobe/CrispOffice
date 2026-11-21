# CrispOffice credential adapters

Ported from CrispStrobe/CrispCloud commit 4ee4eef5 (2026-11-20): OS storage,
custom macOS keychain adapter, transactional file vault and shared AES-256-GCM /
PBKDF2-HMAC-SHA256 codec. Local imports and the custom keychain namespace are
adapted for this independent host. The native vault uses the existing pure Dart
provider; browser storage and legacy plaintext migration are excluded. Secrets
are never stored in preferences. Explicit store failures never redirect writes.

Touch ID unlock of the encrypted vault (`biometric_secret_store.dart`,
`macos/Runner/BiometricVaultKeychain.swift`) stores the derived vault key, not
the master password, in a data protection keychain item protected by
`.biometryCurrentSet`; the OS enforces biometry when the item is read. Only a
non-secret on/off flag lives in preferences.

Enrolment requires the selected, unlocked vault and is fenced when the storage
selection changes. The disabled state is saved before writing or removing a
protected key; failed removal stays visible and can be retried. Startup also
cleans disabled enrolments whose key survived an earlier failure. Biometric
failures leave the master-password fallback and dialog controls usable.

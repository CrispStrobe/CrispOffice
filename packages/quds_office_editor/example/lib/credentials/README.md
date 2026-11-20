# CrispOffice credential adapters

Ported from CrispStrobe/CrispCloud commit 4ee4eef5 (2026-11-20): OS storage,
custom macOS keychain adapter, transactional file vault and shared AES-256-GCM /
PBKDF2-HMAC-SHA256 codec. Local imports and the custom keychain namespace are
adapted for this independent host. The native vault uses the existing pure Dart
provider; browser storage and legacy plaintext migration are excluded. Secrets
are never stored in preferences. Explicit store failures never redirect writes.

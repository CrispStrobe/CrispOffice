import 'package:quds_office_studio/credentials/secure_storage_service.dart';
import 'package:quds_office_studio/studio_mail_credentials.dart';

/// Keeps the real account catalog behind a per-fixture memory backend.
/// Widget tests never await platform preference I/O or access an OS keychain.
StudioMailCredentialStore memoryStudioMailCredentialStore() {
  final storage = InMemorySecureStorage();
  return StudioMailCredentialStore(backend: () async => storage);
}

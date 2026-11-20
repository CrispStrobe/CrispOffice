import 'package:quds_office_studio/studio_mail_credentials.dart';

/// Isolates account-free host tests from platform credentials and preferences.
final class SessionMailCredentials implements StudioMailCredentialStore {
  @override
  Future<StudioMailCredentials?> load() async => null;
  @override
  Future<bool> save(StudioMailCredentials credentials) async => true;
  @override
  Future<bool> clear() async => true;
}

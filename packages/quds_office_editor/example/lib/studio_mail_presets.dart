import 'package:enough_mail/enough_mail.dart' as mail;

import 'studio_mail_compose.dart';

/// Provider-published settings. Presets never discover endpoints or downgrade
/// TLS. A primary account login can differ from the message's From address.
enum StudioMailImapPreset {
  yahoo('Yahoo Mail', 'imap.mail.yahoo.com', 'smtp.mail.yahoo.com'),
  icloud('iCloud Mail', 'imap.mail.me.com', 'smtp.mail.me.com'),
  fastmail('Fastmail', 'imap.fastmail.com', 'smtp.fastmail.com');

  const StudioMailImapPreset(this.label, this.imapHost, this.smtpHost);

  final String label;
  final String imapHost;
  final String smtpHost;
  int get smtpPort => this == icloud ? 587 : 465;
  mail.SocketType get smtpSocketType =>
      this == icloud ? mail.SocketType.starttls : mail.SocketType.ssl;
}

mail.MailAccount createStudioMailPresetAccount({
  required StudioMailImapPreset preset,
  required String email,
  required String password,
  String primaryLogin = '',
  bool icloudFullAddressLogin = false,
}) {
  final login = primaryLogin.trim().isEmpty ? email : primaryLogin.trim();
  if (!StudioMailDraft.isSupportedAddress(email) ||
      !StudioMailDraft.isSupportedAddress(login) ||
      password.isEmpty ||
      password.length > 64 * 1024 ||
      password.contains(RegExp(r'[\x00-\x1f\x7f]'))) {
    throw const FormatException('Invalid secure mail account settings.');
  }
  // Apple documents a local-part login for IMAP and a full address for SMTP.
  final incomingLogin =
      preset == StudioMailImapPreset.icloud && !icloudFullAddressLogin
      ? login.substring(0, login.indexOf('@'))
      : login;
  return mail.MailAccount.fromManualSettingsWithAuth(
    name: email,
    email: email,
    incomingHost: preset.imapHost,
    outgoingHost: preset.smtpHost,
    auth: mail.PlainAuthentication(incomingLogin, password),
    outgoingAuth: mail.PlainAuthentication(login, password),
    incomingPort: 993,
    outgoingPort: preset.smtpPort,
    incomingSocketType: mail.SocketType.ssl,
    outgoingSocketType: preset.smtpSocketType,
  );
}

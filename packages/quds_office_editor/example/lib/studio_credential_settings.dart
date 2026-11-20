import 'dart:io';
import 'package:flutter/material.dart';
import 'studio_credential_storage.dart';
import 'credentials/secure_storage_macos_keychain.dart';

Future<bool> showStudioCredentialSettings(BuildContext context) async {
  final manager = StudioCredentialStorage.instance;
  await manager.loadSelection();
  if (!context.mounted) return false;
  return await showDialog<bool>(
        context: context,
        builder: (_) => const _CredentialSettings(),
      ) ??
      false;
}

class _CredentialSettings extends StatefulWidget {
  const _CredentialSettings();
  @override
  State<_CredentialSettings> createState() => _CredentialSettingsState();
}

class _CredentialSettingsState extends State<_CredentialSettings> {
  final manager = StudioCredentialStorage.instance;
  late StudioCredentialMode mode = manager.mode;
  late final path = TextEditingController(text: manager.customPath);
  final password = TextEditingController();
  final confirmation = TextEditingController();
  bool existing = true, busy = false;
  String? error;
  @override
  void initState() {
    super.initState();
    _inspect();
  }

  Future<void> _inspect() async {
    try {
      final has = await manager.vaultExists();
      if (mounted) setState(() => existing = has);
    } catch (_) {
      if (mounted)
        setState(() => error = 'The existing vault could not be inspected.');
    }
  }

  @override
  void dispose() {
    path.dispose();
    password.dispose();
    confirmation.dispose();
    super.dispose();
  }

  Future<void> _apply() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      if (mode == StudioCredentialMode.encryptedVault) {
        if (!existing && password.text != confirmation.text)
          throw StateError('Passwords do not match.');
        await manager.unlockVault(password.text, create: !existing);
      }
      await manager.select(mode, path: path.text.trim());
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted)
        setState(
          () => error =
              'Could not open the selected credential store. Check its access or password and try again.',
        );
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Credential storage'),
    content: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 520),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Choose where CrispOffice remembers accounts. Changing stores does not move or delete accounts in another store.',
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<StudioCredentialMode>(
              initialValue: mode,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Credential store'),
              items: [
                for (final m in StudioCredentialMode.values)
                  if (m != StudioCredentialMode.customKeychain ||
                      Platform.isMacOS)
                    DropdownMenuItem(
                      value: m,
                      child: Text(switch (m) {
                        StudioCredentialMode.system =>
                          'System credential store',
                        StudioCredentialMode.customKeychain =>
                          'Custom macOS keychain',
                        StudioCredentialMode.encryptedVault =>
                          'Encrypted credential vault',
                        StudioCredentialMode.session => 'This session only',
                      }),
                    ),
              ],
              onChanged: busy
                  ? null
                  : (m) {
                      if (m != null) setState(() => mode = m);
                    },
            ),
            if (mode == StudioCredentialMode.customKeychain) ...[
              const SizedBox(height: 12),
              TextField(
                controller: path,
                decoration: const InputDecoration(labelText: 'Keychain file'),
              ),
              TextButton.icon(
                onPressed: busy
                    ? null
                    : () async {
                        final selected =
                            await MacOsCustomKeychainStorage.chooseKeychain(
                              initialPath: path.text,
                            );
                        if (mounted && selected != null)
                          setState(() => path.text = selected);
                      },
                icon: const Icon(Icons.folder_open),
                label: const Text('Browse…'),
              ),
            ],
            if (mode == StudioCredentialMode.encryptedVault) ...[
              const SizedBox(height: 12),
              Text(
                existing
                    ? 'Unlock the existing vault.'
                    : 'Create a new encrypted vault. Keep its master password safe.',
              ),
              TextField(
                controller: password,
                obscureText: true,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Master password'),
              ),
              if (!existing)
                TextField(
                  controller: confirmation,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Confirm master password',
                  ),
                ),
            ],
            if (mode == StudioCredentialMode.session)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: Text(
                  'Accounts and passwords will be forgotten when CrispOffice quits.',
                ),
              ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: busy ? null : () => Navigator.pop(context, false),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: busy ? null : _apply,
        child: Text(busy ? 'Opening…' : 'Use this store'),
      ),
    ],
  );
}

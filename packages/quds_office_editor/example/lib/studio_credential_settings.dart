import 'dart:io';
import 'package:flutter/material.dart';
import 'studio_credential_storage.dart';
import 'credentials/secure_storage_macos_keychain.dart';

Future<bool> showStudioCredentialSettings(
  BuildContext context, {
  StudioCredentialStorage? manager,
}) async {
  final selectedManager = manager ?? StudioCredentialStorage.instance;
  await selectedManager.loadSelection();
  if (!context.mounted) return false;
  return await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _CredentialSettings(manager: selectedManager),
      ) ??
      false;
}

class _CredentialSettings extends StatefulWidget {
  const _CredentialSettings({required this.manager});
  final StudioCredentialStorage manager;

  @override
  State<_CredentialSettings> createState() => _CredentialSettingsState();
}

class _CredentialSettingsState extends State<_CredentialSettings> {
  late final manager = widget.manager;
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
      if (mounted) {
        setState(() => error = 'The existing vault could not be inspected.');
      }
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
    if (busy) return;
    final selectedMode = mode;
    final selectedPath = path.text.trim();
    final selectedPassword = password.text;
    final selectedConfirmation = confirmation.text;
    final createVault = !existing;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      if (selectedMode == StudioCredentialMode.encryptedVault) {
        if (createVault && selectedPassword != selectedConfirmation) {
          throw StateError('Passwords do not match.');
        }
        await manager.unlockVault(selectedPassword, create: createVault);
      }
      await manager.select(selectedMode, path: selectedPath);
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) {
        setState(
          () => error =
              'Could not open the selected credential store. Check its access or password and try again.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope<bool>(
    canPop: !busy,
    child: AlertDialog(
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
                decoration: const InputDecoration(
                  labelText: 'Credential store',
                ),
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
                  enabled: !busy,
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
                          if (mounted && selected != null) {
                            setState(() => path.text = selected);
                          }
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
                  enabled: !busy,
                  obscureText: true,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Master password',
                  ),
                ),
                if (!existing)
                  TextField(
                    controller: confirmation,
                    enabled: !busy,
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
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
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
    ),
  );
}

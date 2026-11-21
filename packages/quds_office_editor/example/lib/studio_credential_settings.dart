import 'dart:io';
import 'package:flutter/material.dart';
import 'studio_credential_biometric_strings.dart';
import 'studio_credential_storage.dart';
import 'studio_strings.dart';
import 'credentials/biometric_secret_store.dart';
import 'credentials/secure_storage_macos_keychain.dart';

Future<bool> showStudioCredentialSettings(
  BuildContext context, {
  StudioCredentialStorage? manager,
  StudioStrings strings = const StudioStrings(StudioLanguage.en),
}) async {
  final selectedManager = manager ?? StudioCredentialStorage.instance;
  await selectedManager.loadSelection();
  if (!context.mounted) return false;
  return await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) =>
            _CredentialSettings(manager: selectedManager, strings: strings),
      ) ??
      false;
}

class _CredentialSettings extends StatefulWidget {
  const _CredentialSettings({required this.manager, required this.strings});
  final StudioCredentialStorage manager;
  final StudioStrings strings;

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
  // Touch ID unlock of the vault: what the OS offers, what is stored, and
  // what the user asked for (applied after the next password unlock).
  BiometricUnlockAvailability touchIdAvailability =
      BiometricUnlockAvailability.unsupportedPlatform;
  bool touchIdEnabled = false, touchIdWanted = false;
  String? touchIdNotice;
  late final strings = widget.strings;
  @override
  void initState() {
    super.initState();
    _inspect();
    _inspectTouchId();
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

  Future<void> _inspectTouchId() async {
    final availability = await manager.biometricAvailability();
    var enabled = false;
    try {
      enabled = await manager.biometricUnlockEnabled();
    } on Object {
      // Preferences unavailable: present the option as off.
    }
    if (!mounted) return;
    setState(() {
      touchIdAvailability = availability;
      touchIdEnabled = touchIdWanted = enabled;
      if (manager.biometricCleanupPending) {
        touchIdNotice = strings.vaultTouchIdCleanupPending;
      } else if (manager.biometricReenrolmentSuggested) {
        touchIdNotice = strings.vaultTouchIdInvalidated;
      }
    });
  }

  bool get _touchIdUsable =>
      touchIdAvailability == BiometricUnlockAvailability.available;

  Future<void> _setTouchId(bool value) async {
    if (value) {
      // Storing the key needs the vault unlocked with its master password;
      // that happens in _apply.
      setState(() => touchIdWanted = true);
      return;
    }
    if (!touchIdEnabled && !manager.biometricCleanupPending) {
      setState(() => touchIdWanted = false);
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await manager.disableBiometricUnlock();
      if (mounted) {
        setState(() {
          touchIdEnabled = touchIdWanted = false;
          touchIdNotice = null;
        });
      }
    } on Object {
      if (mounted) setState(() => error = strings.vaultTouchIdDisableFailed);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _unlockWithTouchId() async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final result = await manager.unlockVaultWithBiometrics(
        reason: strings.vaultTouchIdReason,
        fallbackTitle: strings.vaultTouchIdUsePassword,
      );
      if (result == StudioVaultBiometricUnlock.unlocked) {
        await manager.select(StudioCredentialMode.encryptedVault);
        if (mounted) Navigator.pop(context, true);
        return;
      }
      if (!mounted) return;
      setState(() {
        if (result == StudioVaultBiometricUnlock.invalidated) {
          touchIdEnabled = touchIdWanted = false;
          touchIdNotice = strings.vaultTouchIdInvalidated;
        } else if (result != StudioVaultBiometricUnlock.cancelled) {
          touchIdNotice = strings.vaultTouchIdFailed;
        }
      });
    } on Object {
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
      if (selectedMode == StudioCredentialMode.encryptedVault &&
          touchIdWanted &&
          _touchIdUsable &&
          (createVault || !touchIdEnabled)) {
        try {
          await manager.enableBiometricUnlock();
        } on Object {
          // The vault is open and selected; only the convenience failed.
          if (mounted) {
            ScaffoldMessenger.maybeOf(context)?.showSnackBar(
              SnackBar(
                content: Text(
                  manager.biometricCleanupPending
                      ? strings.vaultTouchIdCleanupPending
                      : strings.vaultTouchIdEnableFailed,
                ),
              ),
            );
          }
        }
      }
      if (mounted &&
          selectedMode != StudioCredentialMode.encryptedVault &&
          manager.biometricCleanupPending) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(content: Text(strings.vaultTouchIdCleanupPending)),
        );
      }
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

  List<Widget> _touchIdControls(BuildContext context) {
    // Hidden where the platform has no biometric vault unlock at all.
    if (touchIdAvailability ==
        BiometricUnlockAvailability.unsupportedPlatform) {
      return const [];
    }
    final unavailable = strings.vaultTouchIdUnavailable(touchIdAvailability);
    return [
      const SizedBox(height: 12),
      SwitchListTile(
        key: const ValueKey('studio-credential-touchid-toggle'),
        contentPadding: EdgeInsets.zero,
        title: Text(strings.vaultTouchIdToggle),
        subtitle: Text(
          unavailable ??
              (touchIdWanted && !touchIdEnabled
                  ? strings.vaultTouchIdEnableAfterUnlock
                  : strings.vaultTouchIdHelp),
        ),
        value: touchIdWanted,
        // Turning it off is always possible; turning it on needs biometry.
        onChanged:
            busy ||
                manager.biometricCleanupPending ||
                (!_touchIdUsable && !touchIdWanted)
            ? null
            : _setTouchId,
      ),
      if (touchIdNotice != null)
        Text(
          touchIdNotice!,
          key: const ValueKey('studio-credential-touchid-notice'),
        ),
      if (manager.biometricCleanupPending)
        TextButton(
          key: const ValueKey('studio-credential-touchid-cleanup'),
          onPressed: busy ? null : () => _setTouchId(false),
          child: Text(strings.vaultTouchIdRetryCleanup),
        ),
      if (existing && touchIdEnabled && _touchIdUsable)
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton.icon(
            key: const ValueKey('studio-credential-touchid-unlock'),
            onPressed: busy ? null : _unlockWithTouchId,
            icon: const Icon(Icons.fingerprint),
            label: Text(strings.vaultTouchIdUnlockButton),
          ),
        ),
    ];
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
                ..._touchIdControls(context),
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

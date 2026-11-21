import 'package:flutter/material.dart';

import 'credentials/biometric_secret_store.dart';
import 'studio_credential_biometric_strings.dart';
import 'studio_credential_storage.dart';
import 'studio_strings.dart';

enum StudioVaultUnlockOutcome {
  cancelled,
  unlocked,

  /// Unlocked with the master password, but the requested Touch ID
  /// enrolment failed. The vault is usable.
  unlockedTouchIdNotEnabled,
}

/// Opens the selected encrypted credential vault: Touch ID first when it is
/// turned on and usable, otherwise (or after cancel, failure or an
/// invalidated key) the master-password dialog, which offers Touch ID for the
/// next time. Never changes the store selection.
Future<StudioVaultUnlockOutcome> unlockStudioCredentialVault(
  BuildContext context, {
  required StudioCredentialStorage manager,
  required StudioStrings strings,
}) async {
  var biometric = StudioVaultBiometricUnlock.failed;
  try {
    biometric = await manager.unlockVaultWithBiometrics(
      reason: strings.vaultTouchIdReason,
      fallbackTitle: strings.vaultTouchIdUsePassword,
    );
  } on Object {
    // A failed preference/backend read must still offer the master password.
  }
  if (biometric == StudioVaultBiometricUnlock.unlocked) {
    return StudioVaultUnlockOutcome.unlocked;
  }
  var availability = BiometricUnlockAvailability.error;
  var enabled = false;
  try {
    availability = await manager.biometricAvailability();
    enabled = await manager.biometricUnlockEnabled();
  } on Object {
    availability = BiometricUnlockAvailability.error;
  }
  if (!context.mounted) return StudioVaultUnlockOutcome.cancelled;
  final usable = availability == BiometricUnlockAvailability.available;
  return await showDialog<StudioVaultUnlockOutcome>(
        context: context,
        barrierDismissible: false,
        builder: (_) => StudioVaultUnlockDialog(
          manager: manager,
          strings: strings,
          offerTouchId: usable && !enabled,
          retryTouchId: usable && enabled,
          notice: manager.biometricReenrolmentSuggested
              ? strings.vaultTouchIdInvalidated
              : biometric == StudioVaultBiometricUnlock.failed
              ? strings.vaultTouchIdFailed
              : null,
        ),
      ) ??
      StudioVaultUnlockOutcome.cancelled;
}

class StudioVaultUnlockDialog extends StatefulWidget {
  const StudioVaultUnlockDialog({
    super.key,
    required this.manager,
    required this.strings,
    this.offerTouchId = false,
    this.retryTouchId = false,
    this.notice,
  });

  final StudioCredentialStorage manager;
  final StudioStrings strings;

  /// Show the "Unlock with Touch ID next time" opt-in.
  final bool offerTouchId;

  /// Show a button that tries Touch ID again.
  final bool retryTouchId;
  final String? notice;

  @override
  State<StudioVaultUnlockDialog> createState() =>
      _StudioVaultUnlockDialogState();
}

class _StudioVaultUnlockDialogState extends State<StudioVaultUnlockDialog> {
  final _password = TextEditingController();
  bool _busy = false;
  bool _enableTouchId = false;
  late bool _offerTouchId = widget.offerTouchId;
  late bool _retryTouchId = widget.retryTouchId;
  late String? _notice = widget.notice;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _unlock() async {
    if (_busy) return;
    final password = _password.text;
    if (password.isEmpty) {
      setState(() => _error = 'Enter the master password.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.manager.unlockVault(password, create: false);
    } on Object {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = 'Incorrect master password or damaged vault.';
        });
      }
      return;
    }
    var outcome = StudioVaultUnlockOutcome.unlocked;
    if (_offerTouchId && _enableTouchId) {
      try {
        await widget.manager.enableBiometricUnlock();
      } on Object {
        outcome = StudioVaultUnlockOutcome.unlockedTouchIdNotEnabled;
      }
    }
    if (mounted) Navigator.of(context).pop(outcome);
  }

  Future<void> _useTouchId() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await widget.manager.unlockVaultWithBiometrics(
        reason: widget.strings.vaultTouchIdReason,
        fallbackTitle: widget.strings.vaultTouchIdUsePassword,
      );
      if (!mounted) return;
      if (result == StudioVaultBiometricUnlock.unlocked) {
        Navigator.of(context).pop(StudioVaultUnlockOutcome.unlocked);
        return;
      }
      setState(() {
        if (result == StudioVaultBiometricUnlock.invalidated) {
          _retryTouchId = false;
          _offerTouchId = true;
          _notice = widget.strings.vaultTouchIdInvalidated;
        } else if (result != StudioVaultBiometricUnlock.cancelled) {
          _notice = widget.strings.vaultTouchIdFailed;
        }
      });
    } on Object {
      if (mounted) {
        setState(() => _notice = widget.strings.vaultTouchIdFailed);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope<StudioVaultUnlockOutcome>(
    canPop: !_busy,
    child: AlertDialog(
      title: const Text('Unlock saved accounts'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Saved mail accounts use the encrypted credential vault. '
                'Enter its master password. Wrong passwords or damaged vaults '
                'leave the saved accounts untouched.',
              ),
              if (_notice != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    _notice!,
                    key: const ValueKey('studio-vault-touchid-notice'),
                  ),
                ),
              const SizedBox(height: 12),
              TextField(
                key: const ValueKey('studio-mail-vault-password'),
                controller: _password,
                obscureText: true,
                autofocus: true,
                enabled: !_busy,
                onSubmitted: (_) => _unlock(),
                decoration: const InputDecoration(labelText: 'Master password'),
              ),
              if (_offerTouchId)
                CheckboxListTile(
                  key: const ValueKey('studio-vault-touchid-optin'),
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: _enableTouchId,
                  onChanged: _busy
                      ? null
                      : (value) => setState(() => _enableTouchId = value!),
                  title: Text(widget.strings.vaultTouchIdOptIn),
                  subtitle: Text(widget.strings.vaultTouchIdHelp),
                ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    _error!,
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
          onPressed: _busy
              ? null
              : () => Navigator.of(
                  context,
                ).pop(StudioVaultUnlockOutcome.cancelled),
          child: const Text('Cancel'),
        ),
        if (_retryTouchId)
          TextButton.icon(
            key: const ValueKey('studio-vault-touchid-retry'),
            onPressed: _busy ? null : _useTouchId,
            icon: const Icon(Icons.fingerprint),
            label: Text(widget.strings.vaultTouchIdUnlockButton),
          ),
        FilledButton(
          key: const ValueKey('studio-mail-vault-unlock'),
          onPressed: _busy ? null : _unlock,
          child: Text(_busy ? 'Unlocking…' : 'Unlock'),
        ),
      ],
    ),
  );
}

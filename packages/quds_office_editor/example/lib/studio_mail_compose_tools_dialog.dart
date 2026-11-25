import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:quds_mail_core/quds_mail_core.dart';

import 'studio_mail_compose_tools_strings.dart';
import 'studio_mail_identity_templates.dart';
import 'studio_strings.dart';

/// Edits one account's writing tools locally, then saves the entire revision.
///
/// A failed save may have committed. The dialog retains the edits for copying
/// but requires closing and reopening through the host's loader before another
/// write. No mail provider or send callback is involved.
class StudioMailComposeToolsDialog extends StatefulWidget {
  const StudioMailComposeToolsDialog({
    super.key,
    required this.strings,
    required this.initialSettings,
    required this.onSave,
    required this.isCurrent,
  });

  final StudioStrings strings;
  final MailComposeSettings initialSettings;
  final Future<MailComposeSettings> Function(MailComposeSettings) onSave;
  final bool Function() isCurrent;

  @override
  State<StudioMailComposeToolsDialog> createState() =>
      _StudioMailComposeToolsDialogState();
}

class _StudioMailComposeToolsDialogState
    extends State<StudioMailComposeToolsDialog> {
  late final MailComposeSettings _base;
  late final TextEditingController _signature;
  final _quickName = TextEditingController();
  final _quickText = TextEditingController();
  final _quickNameFocus = FocusNode();
  final _quickTextFocus = FocusNode();
  late List<MailQuickText> _quickTexts;
  late List<MailSenderIdentity> _senderIdentities;
  late List<MailMessageTemplate> _templates;
  String? _defaultSenderIdentityId;
  late bool _signatureForNew;
  late bool _signatureForReplies;
  bool _saving = false;
  bool _requiresReload = false;
  bool _editing = false;
  String? _editingId;
  String? _error;
  String? _editError;

  bool get _current =>
      mounted &&
      widget.isCurrent() &&
      widget.initialSettings.account == _base.account &&
      widget.initialSettings.revision == _base.revision;

  bool get _canEdit => _current && !_saving && !_requiresReload;

  MailComposeSettings get _settings => _base.copyWith(
    signature: _signature.text,
    signatureForNewMessages: _signatureForNew,
    signatureForReplies: _signatureForReplies,
    quickTexts: _quickTexts,
    senderIdentities: _senderIdentities,
    templates: _templates,
    defaultSenderIdentityId: _defaultSenderIdentityId,
    clearDefaultSenderIdentity: _defaultSenderIdentityId == null,
  );

  @override
  void initState() {
    super.initState();
    _base = widget.initialSettings;
    _signature = TextEditingController(text: _base.signature);
    _signatureForNew = _base.signatureForNewMessages;
    _signatureForReplies = _base.signatureForReplies;
    _quickTexts = [..._base.quickTexts];
    _senderIdentities = [..._base.senderIdentities];
    _templates = [..._base.templates];
    _defaultSenderIdentityId = _base.defaultSenderIdentityId;
  }

  @override
  void dispose() {
    _signature.dispose();
    _quickName.dispose();
    _quickText.dispose();
    _quickNameFocus.dispose();
    _quickTextFocus.dispose();
    super.dispose();
  }

  void _edit([MailQuickText? entry]) {
    if (!_canEdit || _editing) return;
    if (entry == null &&
        _quickTexts.length >= MailComposeSettings.maxQuickTexts) {
      return;
    }
    setState(() {
      _editing = true;
      _editingId = entry?.id;
      _quickName.text = entry?.name ?? '';
      _quickText.text = entry?.text ?? '';
      _editError = null;
      _error = null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _editing && _canEdit) _quickNameFocus.requestFocus();
    });
  }

  String _newId() {
    final random = Random.secure();
    while (true) {
      final id = List.generate(
        16,
        (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
      ).join();
      if (!_quickTexts.any((entry) => entry.id == id)) return id;
    }
  }

  void _applyText() {
    if (!_canEdit || !_editing) return;
    final entry = MailQuickText(
      id: _editingId ?? _newId(),
      name: _quickName.text.trim(),
      text: _quickText.text,
    );
    if (!entry.isValid) {
      setState(() => _editError = widget.strings.mailComposeQuickTextInvalid);
      return;
    }
    if (_quickTexts.any(
      (other) => other.id != _editingId && other.nameKey == entry.nameKey,
    )) {
      setState(() => _editError = widget.strings.mailComposeQuickTextDuplicate);
      return;
    }
    final updated = [
      for (final other in _quickTexts)
        if (other.id == _editingId) entry else other,
      if (_editingId == null) entry,
    ];
    if (!_settings.copyWith(quickTexts: updated).isValid) {
      setState(() => _editError = widget.strings.mailComposeToolsInvalid);
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _quickTexts = updated;
      _editing = false;
      _editingId = null;
      _editError = null;
      _error = null;
    });
  }

  void _cancelText() {
    if (!_canEdit) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _editing = false;
      _editingId = null;
      _editError = null;
    });
  }

  void _removeText(MailQuickText entry) {
    if (!_canEdit || _editing) return;
    setState(() {
      _quickTexts = [
        for (final other in _quickTexts)
          if (other.id != entry.id) other,
      ];
      _error = null;
    });
  }

  Future<void> _save() async {
    if (!_current) {
      if (mounted) {
        setState(() => _error = widget.strings.mailComposeToolsStale);
      }
      return;
    }
    if (!_canEdit || _editing) return;
    final settings = _settings;
    if (!settings.isValid) {
      setState(() => _error = widget.strings.mailComposeToolsInvalid);
      return;
    }
    final isCurrent = widget.isCurrent;
    final save = widget.onSave;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final persisted = await save(settings);
      if (!mounted) return;
      if (!_current || !isCurrent()) {
        setState(() {
          _requiresReload = true;
          _error = widget.strings.mailComposeToolsStale;
        });
        return;
      }
      if (!persisted.isValid ||
          persisted.account != _base.account ||
          persisted.revision != _base.revision + 1) {
        throw StateError('Unconfirmed writing-tools save.');
      }
      setState(() => _saving = false);
      Navigator.of(context).pop(persisted);
    } on Object {
      if (mounted) {
        setState(() {
          _requiresReload = true;
          _error = _current
              ? widget.strings.mailComposeToolsSaveUnconfirmed
              : widget.strings.mailComposeToolsStale;
        });
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _close() {
    if (!_saving) Navigator.of(context).pop();
  }

  Widget _notice(String message) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: Semantics(
      liveRegion: true,
      child: Text(
        message,
        style: TextStyle(color: Theme.of(context).colorScheme.error),
      ),
    ),
  );

  Widget _textEntry(MailQuickText entry) => Card(
    key: ValueKey('studio-mail-quick-text-${entry.id}'),
    margin: const EdgeInsets.only(top: 8),
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(entry.name, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 4),
          Text(entry.text, maxLines: 3, overflow: TextOverflow.ellipsis),
          Wrap(
            spacing: 8,
            children: [
              TextButton.icon(
                key: ValueKey('studio-mail-quick-text-edit-${entry.id}'),
                onPressed: _canEdit && !_editing ? () => _edit(entry) : null,
                icon: const Icon(Icons.edit_outlined),
                label: Text(widget.strings.mailComposeQuickTextEdit),
              ),
              TextButton.icon(
                key: ValueKey('studio-mail-quick-text-remove-${entry.id}'),
                onPressed: _canEdit && !_editing
                    ? () => _removeText(entry)
                    : null,
                icon: const Icon(Icons.delete_outline),
                label: Text(widget.strings.mailComposeQuickTextDelete),
              ),
            ],
          ),
        ],
      ),
    ),
  );

  Widget _textEditor() => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          key: const ValueKey('studio-mail-quick-text-name'),
          controller: _quickName,
          focusNode: _quickNameFocus,
          readOnly: !_canEdit,
          textInputAction: TextInputAction.next,
          inputFormatters: const [
            _CodeUnitLimitFormatter(MailQuickText.maxNameCodeUnits),
          ],
          decoration: InputDecoration(
            labelText: widget.strings.mailComposeQuickTextName,
            counterText:
                '${_quickName.text.length}/${MailQuickText.maxNameCodeUnits}',
          ),
          onChanged: (_) => setState(() => _editError = null),
          onSubmitted: (_) => _quickTextFocus.requestFocus(),
        ),
        const SizedBox(height: 8),
        TextField(
          key: const ValueKey('studio-mail-quick-text-body'),
          controller: _quickText,
          focusNode: _quickTextFocus,
          readOnly: !_canEdit,
          minLines: 3,
          maxLines: 8,
          inputFormatters: const [
            _CodeUnitLimitFormatter(MailQuickText.maxTextCodeUnits),
          ],
          decoration: InputDecoration(
            labelText: widget.strings.mailComposeQuickTextText,
            counterText:
                '${_quickText.text.length}/${MailQuickText.maxTextCodeUnits}',
          ),
          onChanged: (_) => setState(() => _editError = null),
        ),
        if (_editError case final error?) _notice(error),
        Wrap(
          spacing: 8,
          children: [
            TextButton(
              key: const ValueKey('studio-mail-quick-text-cancel'),
              onPressed: _canEdit ? _cancelText : null,
              child: Text(widget.strings.cancel),
            ),
            OutlinedButton(
              key: const ValueKey('studio-mail-quick-text-apply'),
              onPressed: _canEdit ? _applyText : null,
              child: Text(widget.strings.mailComposeQuickTextApply),
            ),
          ],
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving,
    child: AlertDialog(
      scrollable: true,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      title: Text(widget.strings.mailComposeTools),
      content: SizedBox(
        width: 600,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.strings.mailComposeToolsHelp),
            const SizedBox(height: 16),
            TextField(
              key: const ValueKey('studio-mail-compose-signature'),
              controller: _signature,
              readOnly: !_canEdit,
              minLines: 3,
              maxLines: 8,
              inputFormatters: const [
                _CodeUnitLimitFormatter(
                  MailComposeSettings.maxSignatureCodeUnits,
                ),
              ],
              decoration: InputDecoration(
                labelText: widget.strings.mailComposeSignature,
                counterText:
                    '${_signature.text.length}/'
                    '${MailComposeSettings.maxSignatureCodeUnits}',
              ),
              onChanged: (_) => setState(() => _error = null),
            ),
            SwitchListTile(
              key: const ValueKey('studio-mail-compose-signature-new'),
              contentPadding: EdgeInsets.zero,
              value: _signatureForNew,
              title: Text(widget.strings.mailComposeSignatureForNew),
              onChanged: _canEdit
                  ? (value) => setState(() => _signatureForNew = value)
                  : null,
            ),
            SwitchListTile(
              key: const ValueKey('studio-mail-compose-signature-replies'),
              contentPadding: EdgeInsets.zero,
              value: _signatureForReplies,
              title: Text(widget.strings.mailComposeSignatureForReplies),
              onChanged: _canEdit
                  ? (value) => setState(() => _signatureForReplies = value)
                  : null,
            ),
            const Divider(height: 24),
            Text(
              widget.strings.mailComposeQuickTexts,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(widget.strings.mailComposeQuickTextsHelp),
            if (_quickTexts.isEmpty && !_editing)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(widget.strings.mailComposeQuickTextsEmpty),
              ),
            for (final entry in _quickTexts) _textEntry(entry),
            if (_editing)
              _textEditor()
            else
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton.icon(
                  key: const ValueKey('studio-mail-quick-text-add'),
                  onPressed:
                      _canEdit &&
                          _quickTexts.length < MailComposeSettings.maxQuickTexts
                      ? _edit
                      : null,
                  icon: const Icon(Icons.add),
                  label: Text(widget.strings.mailComposeQuickTextAdd),
                ),
              ),
            const Divider(height: 24),
            StudioMailIdentityTemplates(
              strings: widget.strings,
              settings: _settings,
              enabled: _canEdit && !_editing,
              isCurrent: () => _canEdit && !_editing,
              onChanged: (settings) {
                if (!_canEdit || _editing) return;
                setState(() {
                  _senderIdentities = [...settings.senderIdentities];
                  _templates = [...settings.templates];
                  _defaultSenderIdentityId = settings.defaultSenderIdentityId;
                  _error = null;
                });
              },
            ),
            if (_saving)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: LinearProgressIndicator(
                  semanticsLabel: widget.strings.mailComposeToolsSaving,
                ),
              ),
            if (!_current)
              _notice(widget.strings.mailComposeToolsStale)
            else if (_error case final error?)
              _notice(error),
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const ValueKey('studio-mail-compose-tools-close'),
          onPressed: _saving ? null : _close,
          child: Text(widget.strings.close),
        ),
        FilledButton(
          key: const ValueKey('studio-mail-compose-tools-save'),
          onPressed: _canEdit && !_editing ? _save : null,
          child: Text(widget.strings.save),
        ),
      ],
    ),
  );
}

/// Storage bounds use UTF-16 code units rather than Flutter's grapheme count.
/// Rejecting an oversized edit preserves the prior text and never cuts a pair.
class _CodeUnitLimitFormatter extends TextInputFormatter {
  const _CodeUnitLimitFormatter(this.limit);

  final int limit;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) => newValue.text.length <= limit ? newValue : oldValue;
}

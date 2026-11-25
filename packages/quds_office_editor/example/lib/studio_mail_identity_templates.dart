import 'dart:math';

import 'package:flutter/material.dart';
import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

import 'studio_mail_compose_tools.dart';
import 'studio_mail_compose_tools_strings.dart';
import 'studio_mail_identity_strings.dart';
import 'studio_mail_rich_body.dart';
import 'studio_mail_rich_strings.dart';
import 'studio_mail_strings.dart';
import 'studio_strings.dart';

String _identityId() {
  final random = Random.secure();
  return List.generate(
    16,
    (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
}

/// Edits the identity/template portion of a pending account-settings revision.
/// The parent owns the one atomic save; these controls never access a provider.
class StudioMailIdentityTemplates extends StatefulWidget {
  const StudioMailIdentityTemplates({
    super.key,
    required this.strings,
    required this.settings,
    required this.isCurrent,
    required this.onChanged,
    this.enabled = true,
  });

  final StudioStrings strings;
  final MailComposeSettings settings;
  final bool Function() isCurrent;
  final ValueChanged<MailComposeSettings> onChanged;
  final bool enabled;

  @override
  State<StudioMailIdentityTemplates> createState() =>
      _StudioMailIdentityTemplatesState();
}

class _StudioMailIdentityTemplatesState
    extends State<StudioMailIdentityTemplates> {
  String? _error;
  bool get _canEdit => mounted && widget.enabled && widget.isCurrent();

  void _change(MailComposeSettings next) {
    if (!_canEdit) return;
    if (!next.isValid) {
      setState(() => _error = widget.strings.mailComposeToolsInvalid);
      return;
    }
    setState(() => _error = null);
    widget.onChanged(next);
  }

  Future<void> _editIdentity([MailSenderIdentity? identity]) async {
    if (!_canEdit) return;
    final settings = widget.settings;
    final result = await showDialog<MailSenderIdentity>(
      context: context,
      builder: (_) => Directionality(
        textDirection: widget.strings.language == StudioLanguage.ar
            ? TextDirection.rtl
            : TextDirection.ltr,
        child: _SenderDialog(
          strings: widget.strings,
          settings: settings,
          initial: identity,
          isCurrent: () =>
              _canEdit &&
              (settings.account == widget.settings.account &&
                  settings.revision == widget.settings.revision),
        ),
      ),
    );
    if (!_canEdit ||
        !(settings.account == widget.settings.account &&
            settings.revision == widget.settings.revision) ||
        result == null) {
      return;
    }
    _change(
      settings.copyWith(
        senderIdentities: [
          for (final item in settings.senderIdentities)
            if (item.id == result.id) result else item,
          if (identity == null) result,
        ],
      ),
    );
  }

  void _removeIdentity(MailSenderIdentity identity) {
    if (!_canEdit) return;
    final settings = widget.settings;
    if (settings.templates.any(
      (item) => item.senderIdentityId == identity.id,
    )) {
      setState(() => _error = widget.strings.mailSenderInUse);
      return;
    }
    _change(
      settings.copyWith(
        senderIdentities: [
          for (final item in settings.senderIdentities)
            if (item.id != identity.id) item,
        ],
        clearDefaultSenderIdentity:
            settings.defaultSenderIdentityId == identity.id,
      ),
    );
  }

  Future<void> _editTemplate([MailMessageTemplate? template]) async {
    if (!_canEdit) return;
    final settings = widget.settings;
    final result = await showStudioMailTemplateEditor(
      context,
      strings: widget.strings,
      settings: settings,
      initial: template,
      isCurrent: () =>
          _canEdit && identical(settings, widget.settings),
    );
    if (!_canEdit ||
        !identical(settings, widget.settings) ||
        result == null) {
      return;
    }
    _change(
      settings.copyWith(
        templates: [
          for (final item in settings.templates)
            if (item.id == result.id) result else item,
          if (template == null) result,
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final strings = widget.strings;
    final settings = widget.settings;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ExpansionTile(
          key: const ValueKey('studio-mail-sender-identities'),
          tilePadding: EdgeInsets.zero,
          title: Text(strings.mailSenderIdentities),
          children: [
            Text(strings.mailSenderHelp),
            DropdownButtonFormField<String>(
              key: ValueKey(
                'studio-mail-default-sender-${settings.defaultSenderIdentityId}',
              ),
              initialValue: settings.defaultSenderIdentityId ?? '',
              isExpanded: true,
              decoration: InputDecoration(labelText: strings.mailSenderDefault),
              items: [
                DropdownMenuItem(
                  value: '',
                  child: Text(strings.mailSenderPrimary),
                ),
                for (final identity in settings.senderIdentities)
                  DropdownMenuItem(
                    value: identity.id,
                    child: Text(identity.name),
                  ),
              ],
              onChanged: _canEdit
                  ? (value) => _change(
                      settings.copyWith(
                        defaultSenderIdentityId: value == '' ? null : value,
                        clearDefaultSenderIdentity: value == '',
                      ),
                    )
                  : null,
            ),
            for (final identity in settings.senderIdentities)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(identity.name),
                subtitle: Text(identity.address),
                trailing: Wrap(
                  children: [
                    IconButton(
                      key: ValueKey('studio-mail-identity-edit-${identity.id}'),
                      tooltip: strings.mailComposeQuickTextEdit,
                      onPressed: _canEdit
                          ? () => _editIdentity(identity)
                          : null,
                      icon: const Icon(Icons.edit_outlined),
                    ),
                    IconButton(
                      key: ValueKey(
                        'studio-mail-identity-remove-${identity.id}',
                      ),
                      tooltip: strings.mailComposeQuickTextDelete,
                      onPressed: _canEdit
                          ? () => _removeIdentity(identity)
                          : null,
                      icon: const Icon(Icons.delete_outline),
                    ),
                  ],
                ),
              ),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                key: const ValueKey('studio-mail-identity-add'),
                onPressed:
                    _canEdit &&
                        settings.senderIdentities.length <
                            MailComposeSettings.maxSenderIdentities
                    ? _editIdentity
                    : null,
                icon: const Icon(Icons.add),
                label: Text(strings.mailSenderIdentityAdd),
              ),
            ),
          ],
        ),
        ExpansionTile(
          key: const ValueKey('studio-mail-message-templates'),
          tilePadding: EdgeInsets.zero,
          title: Text(strings.mailMessageTemplates),
          children: [
            Text(strings.mailMessageTemplateHelp),
            for (final template in settings.templates)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(template.name),
                subtitle: Text(
                  template.subject,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: Wrap(
                  children: [
                    IconButton(
                      key: ValueKey('studio-mail-template-edit-${template.id}'),
                      tooltip: strings.mailComposeQuickTextEdit,
                      onPressed: _canEdit
                          ? () => _editTemplate(template)
                          : null,
                      icon: const Icon(Icons.edit_outlined),
                    ),
                    IconButton(
                      key: ValueKey(
                        'studio-mail-template-remove-${template.id}',
                      ),
                      tooltip: strings.mailComposeQuickTextDelete,
                      onPressed: _canEdit
                          ? () => _change(
                              settings.copyWith(
                                templates: [
                                  for (final item in settings.templates)
                                    if (item.id != template.id) item,
                                ],
                              ),
                            )
                          : null,
                      icon: const Icon(Icons.delete_outline),
                    ),
                  ],
                ),
              ),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                key: const ValueKey('studio-mail-template-add'),
                onPressed:
                    _canEdit &&
                        settings.templates.length <
                            MailComposeSettings.maxTemplates
                    ? _editTemplate
                    : null,
                icon: const Icon(Icons.add),
                label: Text(strings.mailMessageTemplateAdd),
              ),
            ),
          ],
        ),
        if (_error case final error?)
          Text(
            error,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
      ],
    );
  }
}

class _SenderDialog extends StatefulWidget {
  const _SenderDialog({
    required this.strings,
    required this.settings,
    required this.isCurrent,
    this.initial,
  });
  final StudioStrings strings;
  final MailComposeSettings settings;
  final bool Function() isCurrent;
  final MailSenderIdentity? initial;
  @override
  State<_SenderDialog> createState() => _SenderDialogState();
}

class _SenderDialogState extends State<_SenderDialog> {
  late final _name = TextEditingController(text: widget.initial?.name ?? '');
  late final _address = TextEditingController(
    text: widget.initial?.address ?? '',
  );
  late final _display = TextEditingController(
    text: widget.initial?.displayName ?? '',
  );
  late final _reply = TextEditingController(
    text: widget.initial?.replyTo ?? '',
  );
  bool _invalid = false;
  @override
  void dispose() {
    for (final controller in [_name, _address, _display, _reply]) {
      controller.dispose();
    }
    super.dispose();
  }

  void _apply() {
    if (!widget.isCurrent()) return;
    final item = MailSenderIdentity(
      id: widget.initial?.id ?? _identityId(),
      name: _name.text.trim(),
      address: _address.text.trim(),
      displayName: _display.text.trim(),
      replyTo: _reply.text.trim(),
    );
    final next = widget.settings.copyWith(
      senderIdentities: [
        for (final existing in widget.settings.senderIdentities)
          if (existing.id == item.id) item else existing,
        if (widget.initial == null) item,
      ],
    );
    if (!next.isValid) {
      setState(() => _invalid = true);
      return;
    }
    Navigator.of(context).pop(item);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    scrollable: true,
    title: Text(widget.strings.mailSenderIdentities),
    content: SizedBox(
      width: 520,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(widget.strings.mailSenderHelp),
          TextField(
            key: const ValueKey('studio-mail-identity-name'),
            controller: _name,
            maxLength: 80,
            decoration: InputDecoration(
              labelText: widget.strings.mailComposeQuickTextName,
            ),
          ),
          TextField(
            key: const ValueKey('studio-mail-identity-address'),
            controller: _address,
            keyboardType: TextInputType.emailAddress,
            maxLength: MailSenderIdentity.maxAddressCodeUnits,
            decoration: InputDecoration(
              labelText: widget.strings.mailSenderAddress,
            ),
          ),
          TextField(
            key: const ValueKey('studio-mail-identity-display'),
            controller: _display,
            maxLength: MailSenderIdentity.maxDisplayNameCodeUnits,
            decoration: InputDecoration(
              labelText: widget.strings.mailSenderDisplayName,
            ),
          ),
          TextField(
            key: const ValueKey('studio-mail-identity-reply-to'),
            controller: _reply,
            keyboardType: TextInputType.emailAddress,
            maxLength: MailSenderIdentity.maxAddressCodeUnits,
            decoration: InputDecoration(
              labelText: widget.strings.mailSenderReplyTo,
            ),
          ),
          if (_invalid)
            Text(
              widget.strings.mailSenderInvalid,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          if (!widget.isCurrent()) Text(widget.strings.mailComposeToolsStale),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(widget.strings.cancel),
      ),
      FilledButton(
        key: const ValueKey('studio-mail-identity-apply'),
        onPressed: widget.isCurrent() ? _apply : null,
        child: Text(widget.strings.mailComposeQuickTextApply),
      ),
    ],
  );
}

Future<MailMessageTemplate?> showStudioMailTemplateEditor(
  BuildContext context, {
  required StudioStrings strings,
  required MailComposeSettings settings,
  required bool Function() isCurrent,
  MailMessageTemplate? initial,
  bool createFromSnapshot = false,
}) => showDialog<MailMessageTemplate>(
  context: context,
  builder: (_) => Directionality(
    textDirection: strings.language == StudioLanguage.ar
        ? TextDirection.rtl
        : TextDirection.ltr,
    child: _TemplateDialog(
      strings: strings,
      settings: settings,
      isCurrent: isCurrent,
      initial: initial,
      createFromSnapshot: createFromSnapshot,
    ),
  ),
);

class _TemplateDialog extends StatefulWidget {
  const _TemplateDialog({
    required this.strings,
    required this.settings,
    required this.isCurrent,
    this.initial,
    required this.createFromSnapshot,
  });
  final StudioStrings strings;
  final MailComposeSettings settings;
  final bool Function() isCurrent;
  final MailMessageTemplate? initial;
  final bool createFromSnapshot;
  @override
  State<_TemplateDialog> createState() => _TemplateDialogState();
}

class _TemplateDialogState extends State<_TemplateDialog> {
  late final _name = TextEditingController(text: widget.initial?.name ?? '');
  late final _to = TextEditingController(text: widget.initial?.to ?? '');
  late final _cc = TextEditingController(text: widget.initial?.cc ?? '');
  late final _bcc = TextEditingController(text: widget.initial?.bcc ?? '');
  late final _subject = TextEditingController(
    text: widget.initial?.subject ?? '',
  );
  late final WordEditorController _body;
  late final bool _initialBodyConflict;
  late String? _sender = widget.initial?.senderIdentityId;
  bool _invalid = false;
  bool _bodyUnsupported = false;
  @override
  void initState() {
    super.initState();
    final richBody = widget.initial?.richBody;
    _initialBodyConflict =
        richBody != null &&
        richBody.plainText != studioMailComposeText(widget.initial!.body);
    final document = richBody == null || _initialBodyConflict
        ? WmlDocument.empty(text: widget.initial?.body ?? '')
        : studioMailDocumentFromRichBody(richBody);
    for (final section in document.sections) {
      section.pageSize = section.pageSize.copyWith(width: 360);
      section.margins = const WmlPageMargins(
        top: 12,
        bottom: 12,
        left: 12,
        right: 12,
        header: 0,
        footer: 0,
      );
    }
    _body = WordEditorController(
      document: document,
      config: OfficeSurfaceConfig(
        showRulers: false,
        textDirection: widget.strings.language == StudioLanguage.ar
            ? TextDirection.rtl
            : TextDirection.ltr,
        strings: switch (widget.strings.language) {
          StudioLanguage.en => OfficeStrings.english,
          StudioLanguage.de => OfficeStrings.german,
          StudioLanguage.ar => OfficeStrings.arabic,
        },
      ),
      proofingService: OfficeProofingService(providers: const []),
    );
    _body.proofing.enabled = false;
  }

  @override
  void dispose() {
    for (final controller in [_name, _to, _cc, _bcc, _subject]) {
      controller.dispose();
    }
    _body.dispose();
    super.dispose();
  }

  void _apply() {
    if (!mounted) return;
    if (!widget.isCurrent()) {
      // The owner can retire while the modal route is otherwise unchanged.
      // Refresh its feedback and controls when a retained callback is used.
      setState(() {});
      return;
    }
    if (_initialBodyConflict) return;
    _body.commitPendingEdits();
    final MailComposeBody? richBody;
    try {
      // Plain templates retain their existing text/structure limits. This
      // still checks unsupported Word content before taking a text snapshot.
      richBody = studioMailOptionalRichBodyFromDocument(_body.document);
    } on Object {
      setState(() {
        _bodyUnsupported = true;
        _invalid = false;
      });
      return;
    }
    final item = MailMessageTemplate(
      id: widget.initial != null && !widget.createFromSnapshot
          ? widget.initial!.id
          : _identityId(),
      name: _name.text.trim(),
      to: _to.text,
      cc: _cc.text,
      bcc: _bcc.text,
      subject: _subject.text,
      body:
          richBody?.plainText ??
          _body.document.paragraphs
              .map((paragraph) => paragraph.text)
              .join('\n'),
      richBody: richBody,
      senderIdentityId: _sender,
    );
    final next = widget.settings.copyWith(
      templates: [
        for (final existing in widget.settings.templates)
          if (existing.id == item.id) item else existing,
        if (widget.initial == null || widget.createFromSnapshot) item,
      ],
    );
    if (!next.isValid) {
      setState(() {
        _bodyUnsupported = false;
        _invalid = true;
      });
      return;
    }
    if (!widget.isCurrent()) {
      setState(() {});
      return;
    }
    Navigator.of(context).pop(item);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    scrollable: true,
    title: Text(widget.strings.mailMessageTemplates),
    content: SizedBox(
      width: 680,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.strings.mailMessageTemplateHelp),
          TextField(
            key: const ValueKey('studio-mail-template-name'),
            controller: _name,
            maxLength: 80,
            decoration: InputDecoration(
              labelText: widget.strings.mailComposeQuickTextName,
            ),
          ),
          DropdownButtonFormField<String>(
            key: const ValueKey('studio-mail-template-sender'),
            initialValue: _sender ?? '',
            isExpanded: true,
            decoration: InputDecoration(
              labelText: widget.strings.mailSenderAddress,
            ),
            items: [
              DropdownMenuItem(
                value: '',
                child: Text(widget.strings.mailSenderPrimary),
              ),
              for (final identity in widget.settings.senderIdentities)
                DropdownMenuItem(
                  value: identity.id,
                  child: Text(identity.name),
                ),
            ],
            onChanged: (value) =>
                setState(() => _sender = value == '' ? null : value),
          ),
          for (final field in [
            (key: 'to', controller: _to, label: widget.strings.to),
            (key: 'cc', controller: _cc, label: widget.strings.mailCc),
            (key: 'bcc', controller: _bcc, label: widget.strings.mailBcc),
          ])
            TextField(
              key: ValueKey('studio-mail-template-${field.key}'),
              controller: field.controller,
              maxLength: MailMessageTemplate.maxRecipientCodeUnits,
              decoration: InputDecoration(labelText: field.label),
            ),
          TextField(
            key: const ValueKey('studio-mail-template-subject'),
            controller: _subject,
            maxLength: MailMessageTemplate.maxSubjectCodeUnits,
            decoration: InputDecoration(labelText: widget.strings.subject),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 240,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final width = ((constraints.maxWidth - 142) / (96 / 72)).clamp(
                  48.0,
                  double.infinity,
                );
                var changed = false;
                for (final section in _body.document.sections) {
                  if (section.pageSize.width != width) {
                    section.pageSize = section.pageSize.copyWith(width: width);
                    changed = true;
                  }
                }
                if (changed) _body.relayout();
                return QudsWordEditor(
                  key: const ValueKey('studio-mail-template-body'),
                  controller: _body,
                );
              },
            ),
          ),
          if (_initialBodyConflict)
            Text(
              widget.strings.mailRichTemplateConflict,
              key: const ValueKey('studio-mail-template-rich-conflict'),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          if (_bodyUnsupported)
            Text(
              widget.strings.mailRichUnsupported,
              key: const ValueKey('studio-mail-template-rich-unsupported'),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          if (_invalid)
            Text(
              widget.strings.mailMessageTemplateInvalid,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          if (!widget.isCurrent()) Text(widget.strings.mailComposeToolsStale),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(widget.strings.cancel),
      ),
      FilledButton(
        key: const ValueKey('studio-mail-template-apply'),
        onPressed: widget.isCurrent() && !_initialBodyConflict ? _apply : null,
        child: Text(widget.strings.mailComposeQuickTextApply),
      ),
    ],
  );
}

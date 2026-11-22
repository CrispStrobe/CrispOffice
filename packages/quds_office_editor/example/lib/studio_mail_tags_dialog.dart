import 'package:flutter/material.dart';
import 'package:quds_mail_core/quds_mail_core.dart';

import 'studio_mail_tag_strings.dart';
import 'studio_strings.dart';

/// Returns the exact tag names chosen by the user, or null when cancelled.
Future<Set<String>?> showStudioMailTagsDialog(
  BuildContext context, {
  required StudioStrings strings,
  required List<MailTag> selected,
  required List<MailTag> known,
}) => showDialog<Set<String>>(
  context: context,
  builder: (_) =>
      _StudioMailTagsDialog(strings: strings, selected: selected, known: known),
);

class _StudioMailTagsDialog extends StatefulWidget {
  const _StudioMailTagsDialog({
    required this.strings,
    required this.selected,
    required this.known,
  });

  final StudioStrings strings;
  final List<MailTag> selected;
  final List<MailTag> known;

  @override
  State<_StudioMailTagsDialog> createState() => _StudioMailTagsDialogState();
}

class _StudioMailTagsDialogState extends State<_StudioMailTagsDialog> {
  late final Map<String, MailTag> _selected = {
    for (final tag in widget.selected) tag.key: tag,
  };
  final _name = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _add() {
    final values = _name.text
        .split(RegExp(r'[,;]'))
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty);
    final added = <MailTag>[];
    try {
      for (final value in values) {
        final tag = MailTag.parse(value);
        if (_selected.containsKey(tag.key)) continue;
        if (_selected.length >= MailTag.maxTagsPerMessage) {
          throw const FormatException('Too many tags.');
        }
        added.add(tag);
      }
    } on FormatException {
      setState(() => _error = widget.strings.mailTagInvalid);
      return;
    }
    if (added.isEmpty) return;
    setState(() {
      for (final tag in added) {
        _selected[tag.key] = tag;
      }
      _name.clear();
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final strings = widget.strings;
    final known = <MailTag>[...widget.known, ..._selected.values];
    final unique = <String, MailTag>{for (final tag in known) tag.key: tag};
    return AlertDialog(
      title: Text(strings.mailTags),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(strings.mailTagsHelp),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      key: const ValueKey('studio-mail-tag-name'),
                      controller: _name,
                      maxLength: MailTag.maxNameLength,
                      decoration: InputDecoration(
                        labelText: strings.mailTagName,
                        counterText: '',
                        errorText: _error,
                      ),
                      onSubmitted: (_) => _add(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    key: const ValueKey('studio-mail-tag-add'),
                    onPressed: _add,
                    child: Text(strings.mailTagAdd),
                  ),
                ],
              ),
              if (_selected.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(strings.mailTagSelected),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    for (final tag in _selected.values)
                      InputChip(
                        key: ValueKey('studio-mail-tag-selected-${tag.key}'),
                        label: Text(tag.name),
                        onDeleted: () =>
                            setState(() => _selected.remove(tag.key)),
                        deleteButtonTooltipMessage: strings.mailTagRemove,
                      ),
                  ],
                ),
              ],
              if (unique.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(strings.mailTagKnown),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    for (final tag in unique.values)
                      FilterChip(
                        key: ValueKey('studio-mail-tag-known-${tag.key}'),
                        label: Text(tag.name),
                        selected: _selected.containsKey(tag.key),
                        onSelected: (value) => setState(() {
                          if (value) {
                            _selected[tag.key] = tag;
                          } else {
                            _selected.remove(tag.key);
                          }
                        }),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
        ),
        FilledButton(
          key: const ValueKey('studio-mail-tag-save'),
          onPressed: () => Navigator.pop(
            context,
            _selected.values.map((tag) => tag.name).toSet(),
          ),
          child: Text(MaterialLocalizations.of(context).okButtonLabel),
        ),
      ],
    );
  }
}

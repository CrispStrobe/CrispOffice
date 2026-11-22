import 'dart:async';

import 'package:flutter/material.dart';
import 'package:quds_mail_core/quds_mail_core.dart';

import 'studio_mail_rule_strings.dart';
import 'studio_strings.dart';

typedef StudioMailRulePreview = Future<int> Function(MailRule rule);
typedef StudioMailRuleApply = Future<int> Function(List<MailRule> rules);
typedef StudioMailRuleSave = Future<void> Function(List<MailRule> rules);

Future<void> showStudioMailRulesDialog(
  BuildContext context, {
  required StudioStrings strings,
  required List<MailRule> rules,
  required StudioMailRulePreview preview,
  required StudioMailRuleApply apply,
  required StudioMailRuleSave save,
}) => showDialog<void>(
  context: context,
  builder: (_) => _StudioMailRulesDialog(
    strings: strings,
    initial: rules,
    preview: preview,
    apply: apply,
    save: save,
  ),
);

class _StudioMailRulesDialog extends StatefulWidget {
  const _StudioMailRulesDialog({
    required this.strings,
    required this.initial,
    required this.preview,
    required this.apply,
    required this.save,
  });

  final StudioStrings strings;
  final List<MailRule> initial;
  final StudioMailRulePreview preview;
  final StudioMailRuleApply apply;
  final StudioMailRuleSave save;

  @override
  State<_StudioMailRulesDialog> createState() => _StudioMailRulesDialogState();
}

class _StudioMailRulesDialogState extends State<_StudioMailRulesDialog> {
  late List<MailRule> _rules = MailRuleSet.parse(widget.initial).rules.toList();
  final Map<String, int> _counts = {};
  bool _busy = false;
  String? _status;
  bool _statusIsError = false;

  List<MailRule> _repositioned(List<MailRule> rules) => [
    for (var index = 0; index < rules.length; index++)
      rules[index].copyWith(position: index),
  ];

  Future<void> _persist(List<MailRule> next) async {
    final previous = _rules;
    setState(() {
      _rules = _repositioned(next);
      _counts.clear();
      _busy = true;
      _status = null;
    });
    try {
      await widget.save(_rules);
      if (mounted) setState(() => _busy = false);
    } on Object {
      if (!mounted) return;
      setState(() {
        _rules = previous;
        _busy = false;
        _status = widget.strings.mailRuleSaveFailed;
        _statusIsError = true;
      });
    }
  }

  Future<void> _add() async {
    if (_rules.length >= MailRule.maxRules) {
      setState(() {
        _status = widget.strings.mailRuleInvalid;
        _statusIsError = true;
      });
      return;
    }
    final rule = await showDialog<MailRule>(
      context: context,
      builder: (_) => _StudioMailRuleEditor(
        strings: widget.strings,
        ruleId: MailRule.newId(),
        position: _rules.length,
        isNew: true,
      ),
    );
    if (rule == null || !mounted) return;
    await _persist([..._rules, rule]);
  }

  Future<void> _edit(MailRule rule) async {
    final edited = await showDialog<MailRule>(
      context: context,
      builder: (_) => _StudioMailRuleEditor(
        strings: widget.strings,
        initial: rule,
        ruleId: rule.id,
        position: rule.position,
      ),
    );
    if (edited == null || !mounted) return;
    await _persist([
      for (final current in _rules) current.id == edited.id ? edited : current,
    ]);
  }

  Future<void> _delete(MailRule rule) async {
    await _persist([
      for (final current in _rules)
        if (current.id != rule.id) current,
    ]);
  }

  Future<void> _move(MailRule rule, int delta) async {
    final index = _rules.indexWhere((current) => current.id == rule.id);
    final target = index + delta;
    if (index < 0 || target < 0 || target >= _rules.length) return;
    final next = [..._rules];
    final removed = next.removeAt(index);
    next.insert(target, removed);
    await _persist(next);
  }

  Future<void> _toggle(MailRule rule, bool enabled) => _persist([
    for (final current in _rules)
      current.id == rule.id ? current.copyWith(enabled: enabled) : current,
  ]);

  Future<void> _preview() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _status = null;
      _statusIsError = false;
    });
    try {
      final counts = <String, int>{};
      for (final rule in _rules) {
        if (!rule.enabled) continue;
        counts[rule.id] = await widget.preview(rule);
      }
      if (!mounted) return;
      setState(() {
        _counts
          ..clear()
          ..addAll(counts);
        _busy = false;
      });
    } on Object {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _status = widget.strings.mailRuleOperationFailed;
        _statusIsError = true;
      });
    }
  }

  Future<void> _apply() async {
    if (_busy || _rules.every((rule) => !rule.enabled)) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        content: Text(widget.strings.mailRuleApplyConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
          ),
          FilledButton(
            key: const ValueKey('studio-mail-rule-apply-confirm'),
            onPressed: () => Navigator.pop(context, true),
            child: Text(widget.strings.mailRuleApply),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _busy = true;
      _status = null;
      _statusIsError = false;
    });
    try {
      final changed = await widget.apply(_rules);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _counts.clear();
        _status = changed == 0
            ? widget.strings.mailRuleNoChanges
            : widget.strings.mailRuleChanged(changed);
      });
    } on Object {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _status = widget.strings.mailRuleOperationFailed;
        _statusIsError = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = widget.strings;
    final theme = Theme.of(context);
    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.rule_outlined),
          const SizedBox(width: 8),
          Text(strings.mailRules),
          const Spacer(),
          IconButton(
            key: const ValueKey('studio-mail-rule-add'),
            tooltip: strings.mailRuleAdd,
            onPressed: _busy ? null : _add,
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      content: SizedBox(
        width: 660,
        height: 480,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(strings.mailRulesHelp),
            if (_status case final status?) ...[
              const SizedBox(height: 8),
              Text(
                status,
                key: const ValueKey('studio-mail-rule-status'),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: _statusIsError
                      ? theme.colorScheme.error
                      : theme.colorScheme.primary,
                ),
              ),
            ],
            const SizedBox(height: 8),
            Expanded(
              child: _rules.isEmpty
                  ? Center(
                      child: Text(
                        strings.mailRuleEmpty,
                        textAlign: TextAlign.center,
                      ),
                    )
                  : ListView.separated(
                      itemCount: _rules.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 6),
                      itemBuilder: (context, index) {
                        final rule = _rules[index];
                        final count = _counts[rule.id];
                        return Card(
                          margin: EdgeInsets.zero,
                          child: ListTile(
                            key: ValueKey('studio-mail-rule-${rule.id}'),
                            leading: Switch(
                              value: rule.enabled,
                              onChanged: _busy
                                  ? null
                                  : (value) => _toggle(rule, value),
                            ),
                            title: Text(rule.name),
                            subtitle: Text(
                              [
                                rule.query,
                                if (rule.addTags.isNotEmpty)
                                  '+ ${rule.addTags.join(', ')}',
                                if (rule.removeTags.isNotEmpty)
                                  '− ${rule.removeTags.join(', ')}',
                                if (count != null)
                                  strings.mailRuleMatches(count),
                              ].join('\n'),
                            ),
                            isThreeLine: true,
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  tooltip: strings.mailRuleMoveUp,
                                  onPressed: _busy || index == 0
                                      ? null
                                      : () => _move(rule, -1),
                                  icon: const Icon(
                                    Icons.arrow_upward,
                                    size: 18,
                                  ),
                                ),
                                IconButton(
                                  tooltip: strings.mailRuleMoveDown,
                                  onPressed: _busy || index == _rules.length - 1
                                      ? null
                                      : () => _move(rule, 1),
                                  icon: const Icon(
                                    Icons.arrow_downward,
                                    size: 18,
                                  ),
                                ),
                                IconButton(
                                  tooltip: strings.mailRuleEdit,
                                  onPressed: _busy ? null : () => _edit(rule),
                                  icon: const Icon(
                                    Icons.edit_outlined,
                                    size: 18,
                                  ),
                                ),
                                IconButton(
                                  tooltip: strings.mailRuleDelete,
                                  onPressed: _busy ? null : () => _delete(rule),
                                  icon: const Icon(
                                    Icons.delete_outline,
                                    size: 18,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: Text(MaterialLocalizations.of(context).closeButtonLabel),
        ),
        OutlinedButton.icon(
          key: const ValueKey('studio-mail-rule-preview'),
          onPressed: _busy ? null : _preview,
          icon: const Icon(Icons.visibility_outlined),
          label: Text(strings.mailRulePreview),
        ),
        FilledButton.icon(
          key: const ValueKey('studio-mail-rule-apply'),
          onPressed: _busy ? null : _apply,
          icon: const Icon(Icons.play_arrow),
          label: Text(strings.mailRuleApply),
        ),
      ],
    );
  }
}

class _StudioMailRuleEditor extends StatefulWidget {
  const _StudioMailRuleEditor({
    required this.strings,
    required this.ruleId,
    required this.position,
    this.initial,
    this.isNew = false,
  });

  final StudioStrings strings;
  final String ruleId;
  final int position;
  final MailRule? initial;
  final bool isNew;

  @override
  State<_StudioMailRuleEditor> createState() => _StudioMailRuleEditorState();
}

class _StudioMailRuleEditorState extends State<_StudioMailRuleEditor> {
  late final _name = TextEditingController(text: widget.initial?.name ?? '');
  late final _query = TextEditingController(text: widget.initial?.query ?? '');
  late final _add = TextEditingController(
    text: widget.initial?.addTags.join(', ') ?? '',
  );
  late final _remove = TextEditingController(
    text: widget.initial?.removeTags.join(', ') ?? '',
  );
  late bool _enabled = widget.initial?.enabled ?? true;
  String? _error;

  static Iterable<String> _split(String value) => value
      .split(RegExp(r'[,;]'))
      .map((tag) => tag.trim())
      .where((tag) => tag.isNotEmpty);

  @override
  void dispose() {
    _name.dispose();
    _query.dispose();
    _add.dispose();
    _remove.dispose();
    super.dispose();
  }

  void _save() {
    try {
      final rule = MailRule.parse(
        id: widget.ruleId,
        name: _name.text,
        query: _query.text,
        enabled: _enabled,
        position: widget.position,
        addTags: _split(_add.text),
        removeTags: _split(_remove.text),
      );
      Navigator.pop(context, rule);
    } on FormatException {
      setState(() => _error = widget.strings.mailRuleInvalid);
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = widget.strings;
    return AlertDialog(
      title: Text(widget.isNew ? strings.mailRuleAdd : strings.mailRuleEdit),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                key: const ValueKey('studio-mail-rule-name'),
                controller: _name,
                maxLength: MailRule.maxNameLength,
                decoration: InputDecoration(
                  labelText: strings.mailRuleName,
                  counterText: '',
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                key: const ValueKey('studio-mail-rule-query'),
                controller: _query,
                maxLength: MailRule.maxQueryLength,
                decoration: InputDecoration(
                  labelText: strings.mailRuleQuery,
                  helperText: strings.mailRuleQueryHelp,
                  counterText: '',
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                key: const ValueKey('studio-mail-rule-add-tags'),
                controller: _add,
                decoration: InputDecoration(
                  labelText: strings.mailRuleAddTags,
                  helperText: strings.mailRuleTagsHelp,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                key: const ValueKey('studio-mail-rule-remove-tags'),
                controller: _remove,
                decoration: InputDecoration(
                  labelText: strings.mailRuleRemoveTags,
                ),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  _enabled ? strings.mailRuleEnabled : strings.mailRuleDisabled,
                ),
                value: _enabled,
                onChanged: (value) => setState(() => _enabled = value),
              ),
              if (_error case final error?)
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(
                    error,
                    key: const ValueKey('studio-mail-rule-error'),
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
          onPressed: () => Navigator.pop(context),
          child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
        ),
        FilledButton(
          key: const ValueKey('studio-mail-rule-save'),
          onPressed: _save,
          child: Text(MaterialLocalizations.of(context).okButtonLabel),
        ),
      ],
    );
  }
}

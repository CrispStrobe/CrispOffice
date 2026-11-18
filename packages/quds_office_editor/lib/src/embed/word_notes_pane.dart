import 'package:flutter/material.dart';
import 'package:quds_office_engine/quds_office_engine.dart';

import 'office_controller.dart';
import 'office_theme.dart';
import 'word_review_dialog.dart';

/// Chrome pane listing footnotes, endnotes, and tracked revisions.
class WordNotesPane extends StatefulWidget {
  /// WordNotesPane API.
  const WordNotesPane({
    super.key,
    required this.controller,
    this.arabic = false,
  });

  /// controller API.
  final WordEditorController controller;

  /// arabic API.
  final bool arabic;

  @override
  State<WordNotesPane> createState() => _WordNotesPaneState();
}

class _WordNotesPaneState extends State<WordNotesPane> {
  final Map<WmlNote, TextEditingController> _noteEdits =
      <WmlNote, TextEditingController>{};
  final Map<WmlNote, FocusNode> _noteFocus = <WmlNote, FocusNode>{};
  bool _syncing = false;

  WordEditorController get _c => widget.controller;

  @override
  void initState() {
    super.initState();
    _c.addListener(_controllerChanged);
  }

  @override
  void didUpdateWidget(WordNotesPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, _c)) {
      oldWidget.controller.removeListener(_controllerChanged);
      oldWidget.controller.clearNoteEditingTarget(notify: false);
      _disposeEdits();
      _c.addListener(_controllerChanged);
    }
  }

  void _controllerChanged() {
    if (mounted && !_syncing) setState(() {});
  }

  @override
  void dispose() {
    _c.removeListener(_controllerChanged);
    if (_noteEdits.containsKey(_c.noteEditingTarget?.note)) {
      _c.clearNoteEditingTarget(notify: false);
    }
    _disposeEdits();
    super.dispose();
  }

  void _disposeEdits() {
    _syncing = true;
    for (final TextEditingController edit in _noteEdits.values) {
      edit.dispose();
    }
    for (final FocusNode focus in _noteFocus.values) {
      focus.dispose();
    }
    _noteEdits.clear();
    _noteFocus.clear();
    _syncing = false;
  }

  FocusNode _focusFor(WmlNote note) => _noteFocus.putIfAbsent(note, () {
    final FocusNode focus = FocusNode();
    focus.addListener(() {
      if (_syncing || _c.isDisposed) return;
      if (focus.hasFocus) {
        _publishSelection(note);
      } else {
        _c.commitNoteEdit(note);
      }
    });
    return focus;
  });

  void _publishSelection(WmlNote note) {
    final edit = _noteEdits[note];
    if (_syncing ||
        edit == null ||
        !(_noteFocus[note]?.hasFocus ?? false) ||
        edit.text != _c.noteEditText(note) ||
        !edit.selection.isValid) {
      return;
    }
    _c.setNoteEditingTarget(
      note,
      edit.selection,
      composing: edit.value.composing,
    );
  }

  /// One controller per note object. Native replacements and undo update this
  /// view even if it retained focus while a keyboard command was running.
  TextEditingController _editFor(WmlNote note) {
    final String current = _c.noteEditText(note);
    final TextEditingController edit = _noteEdits.putIfAbsent(note, () {
      final edit = TextEditingController(text: current);
      edit.addListener(() => _publishSelection(note));
      return edit;
    });
    final target = _c.noteEditingTarget;
    final selection = identical(target?.note, note)
        ? target!.selection
        : edit.selection;
    final safeSelection = selection.isValid
        ? selection.copyWith(
            baseOffset: selection.baseOffset.clamp(0, current.length),
            extentOffset: selection.extentOffset.clamp(0, current.length),
          )
        : TextSelection.collapsed(offset: current.length);
    if (edit.text != current || edit.selection != safeSelection) {
      _syncing = true;
      try {
        edit.value = TextEditingValue(
          text: current,
          selection: safeSelection,
          composing: edit.text == current
              ? edit.value.composing
              : TextRange.empty,
        );
      } finally {
        _syncing = false;
      }
    }
    return edit;
  }

  void _dropStale(List<WmlNote> notes) {
    _syncing = true;
    for (final WmlNote gone
        in _noteEdits.keys.where((WmlNote n) => !notes.contains(n)).toList()) {
      _noteEdits.remove(gone)?.dispose();
      _noteFocus.remove(gone)?.dispose();
    }
    _syncing = false;
  }

  @override
  Widget build(BuildContext context) {
    final OfficeTheme theme = _c.config.theme;
    final numbering = WordNoteNumbering(_c.document);
    final List<WmlNote> notes = numbering.notes;
    _dropStale(notes);
    final bool editable = _c.config.allowsMutation;
    return ColoredBox(
      color: theme.chromeFill,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                widget.arabic ? 'ملاحظات' : 'Notes',
                style: TextStyle(
                  color: theme.chromeText,
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
              if (editable) ...<Widget>[
                const SizedBox(height: 6),
                Wrap(
                  spacing: 12,
                  children: <Widget>[
                    GestureDetector(
                      key: const ValueKey<String>('notes-add-footnote'),
                      onTap: () => _c.insertFootnote(),
                      child: Text(
                        widget.arabic ? '+ حاشية سفلية' : '+ Footnote',
                        style: TextStyle(color: theme.focusRing, fontSize: 11),
                      ),
                    ),
                    GestureDetector(
                      key: const ValueKey<String>('notes-add-endnote'),
                      onTap: () => _c.insertFootnote(endnote: true),
                      child: Text(
                        widget.arabic ? '+ حاشية ختامية' : '+ Endnote',
                        style: TextStyle(color: theme.focusRing, fontSize: 11),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 8),
              if (notes.isEmpty)
                Text(
                  widget.arabic ? 'لا توجد حواشٍ' : 'No notes',
                  style: TextStyle(color: theme.headerText, fontSize: 11),
                )
              else
                ...notes.map((WmlNote note) {
                  final String label = numbering.labelFor(note);
                  final String mark = label.isEmpty
                      ? (widget.arabic ? 'مخصصة' : 'custom')
                      : (note.endnote ? 'E$label' : label);
                  // Widget identity follows the native link, not its changing
                  // visible number, so edits and focus survive renumbering.
                  final String identity = note.endnote
                      ? 'E${note.id}'
                      : '${note.id}';
                  final String title = numbering.hasExactLabel(note)
                      ? (widget.arabic ? 'حاشية $mark' : 'Note $mark')
                      : (widget.arabic
                            ? 'حاشية (معرّف المصدر $identity)'
                            : 'Note (source ID $identity)');
                  final TextEditingController edit = _editFor(note);
                  return Padding(
                    key: ValueKey<WmlNote>(note),
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        Row(
                          children: <Widget>[
                            Expanded(
                              child: GestureDetector(
                                onTap: () => _c.jumpToNote(note),
                                child: Text(
                                  title,
                                  style: TextStyle(
                                    color: theme.focusRing,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                            if (editable)
                              GestureDetector(
                                key: ValueKey<String>('notes-delete-$identity'),
                                onTap: () => _c.deleteNote(note),
                                child: Text(
                                  widget.arabic ? 'حذف' : 'Delete',
                                  style: TextStyle(
                                    color: theme.headerText,
                                    fontSize: 10,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        TextField(
                          key: ValueKey<String>('notes-edit-$identity'),
                          controller: edit,
                          focusNode: _focusFor(note),
                          minLines: 1,
                          maxLines: null,
                          keyboardType: TextInputType.multiline,
                          enabled: editable,
                          style: TextStyle(
                            color: theme.chromeText,
                            fontSize: 11,
                          ),
                          decoration: const InputDecoration(
                            isDense: true,
                            border: InputBorder.none,
                          ),
                          onChanged: (String value) {
                            _c.setNoteText(note, value);
                            _publishSelection(note);
                          },
                          onTapOutside: (_) => _focusFor(note).unfocus(),
                        ),
                      ],
                    ),
                  );
                }),
              const SizedBox(height: 12),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton(
                  key: const ValueKey<String>('notes-review-changes'),
                  onPressed: () => showWordReviewDialog(
                    context,
                    controller: _c,
                    arabic: widget.arabic,
                  ),
                  child: Text(
                    widget.arabic ? 'مراجعة التغييرات' : 'Review changes',
                  ),
                ),
              ),
              Text(
                widget.arabic ? 'التغييرات' : 'Revisions',
                style: TextStyle(
                  color: theme.chromeText,
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 8),
              if (_c.document.revisions.isEmpty)
                Text(
                  widget.arabic ? 'لا توجد تغييرات' : 'No revisions',
                  style: TextStyle(color: theme.headerText, fontSize: 11),
                )
              else
                ..._c.document.revisions.map((WmlRevision revision) {
                  final bool on = identical(revision, _c.selectedRevision);
                  final String kind = revision.kind == WmlRevisionKind.insert
                      ? (widget.arabic ? 'إدراج' : 'Insert')
                      : (widget.arabic ? 'حذف' : 'Delete');
                  return GestureDetector(
                    onTap: () => _c.selectRevision(revision),
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: ColoredBox(
                        color: on
                            ? theme.focusRing.withValues(alpha: 0.12)
                            : const Color(0x00000000),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 4,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: <Widget>[
                              Text(
                                '$kind · ${revision.author}',
                                style: TextStyle(
                                  color: theme.chromeText,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                revision.text,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: theme.headerText,
                                  fontSize: 11,
                                ),
                              ),
                              Row(
                                children: <Widget>[
                                  GestureDetector(
                                    onTap: editable && revision.conflict == null
                                        ? () => _c.acceptRevision(revision)
                                        : null,
                                    child: Text(
                                      widget.arabic ? 'قبول' : 'Accept',
                                      style: TextStyle(
                                        color: theme.focusRing,
                                        fontSize: 10,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  GestureDetector(
                                    onTap: editable && revision.conflict == null
                                        ? () => _c.rejectRevision(revision)
                                        : null,
                                    child: Text(
                                      widget.arabic ? 'رفض' : 'Reject',
                                      style: TextStyle(
                                        color: theme.focusRing,
                                        fontSize: 10,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                }),
            ],
          ),
        ),
      ),
    );
  }
}

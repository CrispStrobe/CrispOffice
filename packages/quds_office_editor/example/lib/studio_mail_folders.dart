import 'package:enough_mail/enough_mail.dart' as mail;

typedef StudioMailFolderRow = ({
  mail.Mailbox box,
  int depth,
  bool hasChildren,
  bool expanded,
});

mail.Mailbox? studioMailSentMailbox(List<mail.Mailbox> boxes) {
  final selectable = boxes.where(
    (box) =>
        !box.isNotSelectable &&
        !box.isVirtual &&
        !box.hasFlag(mail.MailboxFlag.nonExistent),
  );
  return selectable.where((box) => box.isSent).firstOrNull ??
      selectable
          .where(
            (box) =>
                !box.path.contains(box.pathSeparator) &&
                const {
                  'sent',
                  'sent items',
                  'sent messages',
                  'gesendet',
                }.contains(box.name.toLowerCase()),
          )
          .firstOrNull;
}

List<StudioMailFolderRow> studioMailFolderRows(
  List<mail.Mailbox> boxes, {
  Set<String>? expandedPaths,
}) {
  String key(String path, String separator) {
    final first = path.split(separator).first;
    return first.toLowerCase() == 'inbox'
        ? 'INBOX${path.substring(first.length)}'
        : path;
  }

  final byPath = {
    for (final box in boxes) key(box.path, box.pathSeparator): box,
  };
  final sent = studioMailSentMailbox(boxes);
  int rank(mail.Mailbox box) => switch (box) {
    _ when box.isInbox && key(box.path, box.pathSeparator) == 'INBOX' => 0,
    _ when box == sent => 1,
    _ when box.isDrafts => 2,
    _ when box.isJunk => 3,
    _ when box.isTrash => 4,
    _ when box.isArchive => 5,
    _ => 6,
  };

  final groups = <mail.Mailbox?, List<mail.Mailbox>>{};
  for (final box in byPath.values) {
    final separator = box.pathSeparator;
    var parentPath = box.path;
    mail.Mailbox? parent;
    while (separator.isNotEmpty && rank(box) == 6) {
      final last = parentPath.lastIndexOf(separator);
      if (last <= 0) break;
      parentPath = parentPath.substring(0, last);
      parent = byPath[key(parentPath, separator)];
      if (parent != null) break;
    }
    (groups[parent] ??= []).add(box);
  }

  final rows = <StudioMailFolderRow>[];
  void add(mail.Mailbox? parent, int depth) {
    final children = groups[parent];
    if (children == null) return;
    children.sort((a, b) {
      final order = rank(a).compareTo(rank(b));
      if (order != 0) return order;
      final name = a.name.toLowerCase().compareTo(b.name.toLowerCase());
      return name != 0 ? name : a.path.compareTo(b.path);
    });
    for (final box in children) {
      final hasChildren = groups.containsKey(box);
      final expanded =
          hasChildren &&
          (expandedPaths == null || expandedPaths.contains(box.path));
      rows.add((
        box: box,
        depth: depth,
        hasChildren: hasChildren,
        expanded: expanded,
      ));
      if (expanded) add(box, depth + 1);
    }
  }

  add(null, 0);
  return rows;
}

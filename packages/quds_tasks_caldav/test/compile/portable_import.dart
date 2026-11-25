import 'package:quds_tasks_caldav/quds_tasks_caldav.dart';
import 'package:quds_tasks_core/quds_tasks_core.dart';

void main() {
  const source =
      'BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:-//portable-test//EN\r\n'
      'BEGIN:VTODO\r\nUID:portable\r\nSUMMARY:Original\r\n'
      'DUE;VALUE=DATE:20261125\r\nX-KEEP:opaque-data\r\n'
      'END:VTODO\r\nEND:VCALENDAR\r\n';
  final document = CalDavTodoDocument.parse(source);
  if (document.encode() != source) {
    throw StateError('Portable VTODO no-op changed the source.');
  }
  final patched = document.apply(
    const TaskPatch(title: TaskFieldPatch.set('Portable ä 🗂️')),
  );
  final reparsed = CalDavTodoDocument.parse(patched.encode());
  if (reparsed.summary != 'Portable ä 🗂️' ||
      reparsed.toTaskFields().due != TaskDate(2026, 11, 25) ||
      !reparsed.encode().contains('X-KEEP:opaque-data\r\n') ||
      reparsed.uid != document.uid) {
    throw StateError('Portable VTODO patch round-trip failed.');
  }
  print('Portable VTODO preservation and date projection passed.');
}

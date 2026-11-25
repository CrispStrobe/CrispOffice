import 'package:quds_tasks_caldav/quds_tasks_caldav.dart';
import 'package:quds_tasks_core/quds_tasks_core.dart';
import 'package:test/test.dart';

String calendar(String properties) =>
    'BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:-//limits-test//EN\r\n'
    'BEGIN:VTODO\r\nUID:limits\r\n$properties'
    'END:VTODO\r\nEND:VCALENDAR\r\n';

String repeat(String value, int count) => List.filled(count, value).join();

void main() {
  test('resource size accepts the ceiling and rejects one more code unit', () {
    final available =
        CalDavCodecLimits.maxResourceCodeUnits - calendar('').length;
    const count = 9;
    final lines = <String>[];
    for (var i = 0; i < count; i++) {
      final length = available ~/ count + (i < available % count ? 1 : 0);
      lines.add('X-LARGE:${repeat('a', length - 10)}\r\n');
    }
    final source = calendar(lines.join());
    expect(source.length, CalDavCodecLimits.maxResourceCodeUnits);
    expect(CalDavTodoDocument.parse(source).encode(), source);
    expect(() => CalDavTodoDocument.parse('${source}x'), throwsFormatException);
  });

  test('physical-line budget is enforced before splitting', () {
    final fixed = calendar('').split('\n').length - 1;
    final body = repeat(
      'X-PADDING:1\r\n',
      CalDavCodecLimits.maxPhysicalLines - fixed,
    );
    final source = calendar(body);
    expect(CalDavTodoDocument.parse(source).uid, 'limits');
    expect(
      () => CalDavTodoDocument.parse(calendar('${body}X-ONE-MORE:1\r\n')),
      throwsFormatException,
    );
  });

  test('logical-line budget counts unfolded content as one line', () {
    final length =
        CalDavCodecLimits.maxUnfoldedLineCodeUnits - 'SUMMARY:'.length;
    final first = repeat('a', length ~/ 2);
    final second = repeat('b', length - first.length);
    final source = calendar('SUMMARY:$first\r\n $second\r\n');
    expect(CalDavTodoDocument.parse(source).summary!.length, length);
    expect(
      () => CalDavTodoDocument.parse(
        calendar('SUMMARY:$first\r\n ${second}x\r\n'),
      ),
      throwsFormatException,
    );
    expect(
      () => CalDavTodoDocument.parse(
        calendar(
          'X:${repeat('a', CalDavCodecLimits.maxUnfoldedLineCodeUnits)}\r\n',
        ),
      ),
      throwsFormatException,
    );
  });

  test(
    'component-depth budget is bounded while unknown components survive',
    () {
      String nested(int count) => calendar(
        '${repeat('BEGIN:X-NESTED\r\n', count)}'
        'X-KEEP:yes\r\n'
        '${repeat('END:X-NESTED\r\n', count)}',
      );
      final source = nested(CalDavCodecLimits.maxComponentDepth - 2);
      expect(CalDavTodoDocument.parse(source).encode(), source);
      expect(
        () => CalDavTodoDocument.parse(
          nested(CalDavCodecLimits.maxComponentDepth - 1),
        ),
        throwsFormatException,
      );
    },
  );

  test(
    'forbidden raw controls fail; tabs and legitimate folds are preserved',
    () {
      for (final control in [0, 1, 8, 11, 12, 14, 31, 127]) {
        expect(
          () => CalDavTodoDocument.parse(
            calendar('X-DATA:a${String.fromCharCode(control)}b\r\n'),
          ),
          throwsFormatException,
        );
      }
      final source = calendar('SUMMARY:with\ttab\r\n\tand fold\r\n');
      expect(CalDavTodoDocument.parse(source).summary, 'with\ttaband fold');
      expect(CalDavTodoDocument.parse(source).encode(), source);
    },
  );

  test('new task text cannot expand past the content-line ceiling', () {
    final document = CalDavTodoDocument.parse(calendar(''));
    expect(
      () => document.apply(
        TaskPatch(
          title: TaskFieldPatch.set(
            repeat('a', CalDavCodecLimits.maxUnfoldedLineCodeUnits + 1),
          ),
        ),
      ),
      throwsArgumentError,
    );
    expect(
      () => document.apply(
        TaskPatch(
          title: TaskFieldPatch.set(
            repeat(';', CalDavCodecLimits.maxUnfoldedLineCodeUnits ~/ 2),
          ),
        ),
      ),
      throwsFormatException,
    );
  });

  test('the public date serializer refuses property-token injection', () {
    final date = CalDavDateValue.parse('20261125', valueType: 'DATE');
    for (final name in [
      '',
      'DUE\r\nATTENDEE',
      'DUE:other',
      'DUE;VALUE=DATE',
      'DUE name',
    ]) {
      expect(() => date.contentLine(name), throwsArgumentError);
    }
    expect(date.contentLine('DUE'), 'DUE;VALUE=DATE:20261125');
  });
}

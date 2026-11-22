import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:test/test.dart';

MailRule _rule({
  String id = 'rule-1',
  String name = 'Work',
  String query = 'from:alice',
  int position = 0,
  bool enabled = true,
  List<String> add = const ['Work'],
  List<String> remove = const [],
}) => MailRule.parse(
  id: id,
  name: name,
  query: query,
  position: position,
  enabled: enabled,
  addTags: add,
  removeTags: remove,
);

void main() {
  group('mail rules', () {
    test('parse bounded identities, queries and tag actions', () {
      final rule = _rule(add: [' Work ', 'work'], remove: ['Travel']);
      expect(rule.addTags.map((tag) => tag.name), ['Work']);
      expect(rule.removeTags.single.name, 'Travel');
      expect(rule.compiledQuery.termCount, 1);
    });

    test('reject empty, invalid, overlapping and excessive rules', () {
      for (final build in <MailRule Function()>[
        () => _rule(id: 'bad id'),
        () => _rule(name: ' '),
        () => _rule(query: ' '),
        () => _rule(query: 'subject:'),
        () => _rule(add: ['One'], remove: ['one']),
        () => _rule(add: const []),
        () => _rule(add: [for (var i = 0; i < 9; i++) 'tag$i']),
        () => _rule(position: MailRule.maxRules),
      ]) {
        expect(build, throwsFormatException);
      }
    });

    test('matches only enabled rules and keeps order', () {
      final first = _rule(id: 'a', position: 1, add: ['Work']);
      final disabled = _rule(
        id: 'b',
        position: 0,
        enabled: false,
        add: ['Disabled'],
      );
      final set = MailRuleSet.parse([first, disabled]);
      const doc = MailHeaderSearchDocument(
        subject: 'Quarterly report',
        sender: 'Alice <alice@example.test>',
      );
      expect(set.matching(doc).map((rule) => rule.id), ['a']);
    });

    test('last ordered action wins and removals run after additions', () {
      final add = _rule(id: 'a', position: 0, add: ['Work', 'Receipts']);
      final remove = _rule(
        id: 'b',
        position: 1,
        add: ['Travel'],
        remove: ['work'],
      );
      final set = MailRuleSet.parse([remove, add]);
      final tags = set.applyTags(
        matchedRuleIds: {'a', 'b'},
        currentTags: ['Old'],
      );
      expect(tags.map((tag) => tag.name), ['Old', 'Receipts', 'Travel']);
    });

    test('rule set rejects duplicate identity and positions', () {
      expect(
        () => MailRuleSet.parse([
          _rule(id: 'same', position: 0),
          _rule(id: 'same', position: 1),
        ]),
        throwsFormatException,
      );
      expect(
        () => MailRuleSet.parse([
          _rule(id: 'a', position: 0),
          _rule(id: 'b', position: 0),
        ]),
        throwsFormatException,
      );
      expect(
        () => MailRuleSet.parse([
          for (var i = 0; i < MailRule.maxRules + 1; i++)
            _rule(id: 'rule-$i', position: i),
        ]),
        throwsFormatException,
      );
    });

    test('generated IDs satisfy the published shape', () {
      final id = MailRule.newId(DateTime.utc(2026, 11, 22));
      expect(MailRule.idPattern.hasMatch(id), isTrue);
      expect(id, isNot(MailRule.newId(DateTime.utc(2026, 11, 23))));
    });
  });
}

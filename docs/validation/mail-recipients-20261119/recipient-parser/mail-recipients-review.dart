import 'dart:convert';
import 'dart:io';

import 'quds_office_suite/packages/quds_office_editor/example/lib/studio_mail_recipients.dart';

void main() {
  final checks = <Map<String, Object?>>[];
  void check(String name, bool passed) {
    checks.add({'name': name, 'passed': passed});
  }

  final grouped = StudioMailRecipients.tryParse(
    to: ' One@EXAMPLE.test ; Two@example.test ',
    cc: 'One@example.test, Copy@example.test',
    bcc: 'Copy@EXAMPLE.test; Hidden@example.test; one@example.test',
  );
  check('groups_parse', grouped != null);
  check('to_order_and_first_spelling', grouped!.to.join('|') == 'One@EXAMPLE.test|Two@example.test');
  check('cc_visible_precedence', grouped.cc.join('|') == 'Copy@example.test');
  check('bcc_preserves_distinct_local_case', grouped.bcc.join('|') == 'Hidden@example.test|one@example.test');
  check('explicit_envelope_order', grouped.envelope.join('|') == 'One@EXAMPLE.test|Two@example.test|Copy@example.test|Hidden@example.test|one@example.test');
  check('identity_key_only_folds_domain', StudioMailRecipients.identityKey('One@EXAMPLE.test') == 'One@example.test');

  for (final (name, list) in [
    ('to', grouped.to),
    ('cc', grouped.cc),
    ('bcc', grouped.bcc),
    ('envelope', grouped.envelope),
  ]) {
    var protected = false;
    try {
      list.add('injected@example.test');
    } on UnsupportedError {
      protected = true;
    }
    check('${name}_immutable', protected);
  }

  check('empty_envelope_rejected', StudioMailRecipients.tryParse(to: '', cc: ' ', bcc: '') == null);
  check('cc_only_accepted', StudioMailRecipients.tryParse(to: '', cc: 'c@example.test')?.envelope.single == 'c@example.test');
  check('bcc_only_accepted', StudioMailRecipients.tryParse(to: '', bcc: 'b@example.test')?.envelope.single == 'b@example.test');
  for (final (name, invalid) in [
    ('leading_separator', ',a@example.test'),
    ('trailing_separator', 'a@example.test;'),
    ('empty_member', 'a@example.test,,b@example.test'),
    ('display_name', 'Name <a@example.test>'),
    ('group_syntax', 'Team:a@example.test;'),
    ('quoted_local', '"a"@example.test'),
    ('whitespace_pair', 'a@example.test b@example.test'),
    ('tab', 'a@example.test\t'),
    ('lf', 'a@example.test\n'),
    ('crlf_injection', 'a@example.test\r\nBcc: attacker@example.test'),
    ('nul', 'a@example.test\u0000'),
    ('del', 'a@example.test\u007f'),
    ('non_ascii_space', 'a@example.test\u00a0'),
    ('unicode_local', 'مستخدم@example.test'),
    ('unicode_domain', 'a@例.test'),
    ('domain_literal', 'a@[127.0.0.1]'),
    ('domain_empty_label', 'a@example..test'),
    ('local_empty_atom', 'a..b@example.test'),
    ('domain_bad_hyphen', 'a@-example.test'),
    ('missing_local', '@example.test'),
    ('missing_domain', 'a@'),
  ]) {
    check('${name}_rejected_in_all_groups',
      StudioMailRecipients.tryParse(to: invalid) == null &&
      StudioMailRecipients.tryParse(to: 'valid@example.test', cc: invalid) == null &&
      StudioMailRecipients.tryParse(to: 'valid@example.test', bcc: invalid) == null);
  }

  final maxAddress = '${'l' * 64}@${'a' * 63}.${'b' * 63}.${'c' * 61}';
  check('254_octet_address_accepted', maxAddress.length == 254 && StudioMailRecipients.isSupportedAddress(maxAddress));
  check('255_octet_address_rejected', !StudioMailRecipients.isSupportedAddress('${maxAddress}c'));
  check('64_octet_local_accepted', StudioMailRecipients.isSupportedAddress('${'a' * 64}@example.test'));
  check('65_octet_local_rejected', !StudioMailRecipients.isSupportedAddress('${'a' * 65}@example.test'));
  check('63_octet_domain_label_accepted', StudioMailRecipients.isSupportedAddress('a@${'b' * 63}.test'));
  check('64_octet_domain_label_rejected', !StudioMailRecipients.isSupportedAddress('a@${'b' * 64}.test'));
  check('single_label_host_supported', StudioMailRecipients.isSupportedAddress('a@localhost'));
  check('100_entries_accepted', StudioMailRecipients.tryParse(to: List.generate(100, (i) => 'r$i@example.test').join(','))?.envelope.length == 100);
  check('101_entries_rejected', StudioMailRecipients.tryParse(to: List.generate(101, (i) => 'r$i@example.test').join(',')) == null);
  check('100_duplicates_accepted_once', StudioMailRecipients.tryParse(to: List.filled(100, 'a@example.test').join(','))?.envelope.length == 1);
  check('101_duplicates_rejected_before_dedup', StudioMailRecipients.tryParse(to: List.filled(101, 'a@example.test').join(',')) == null);
  check('entry_limit_sums_across_groups', StudioMailRecipients.tryParse(to: List.generate(99, (i) => 'r$i@example.test').join(','), cc: 'c@example.test', bcc: 'b@example.test') == null);
  const address = 'a@example.test';
  final padded = '${' ' * (StudioMailRecipients.maxInputLength - address.length)}$address';
  check('exact_input_character_bound_accepted', StudioMailRecipients.tryParse(to: padded)?.envelope.single == address);
  check('input_bound_sums_all_groups', StudioMailRecipients.tryParse(to: padded, cc: ' ') == null);
  final longest100 = List.generate(100, (i) => '${i.toString().padLeft(64, 'a')}@${'a' * 63}.${'b' * 63}.${'c' * 61}').join(', ');
  check('100_max_length_addresses_fit_input_bound', StudioMailRecipients.tryParse(to: longest100)?.envelope.length == 100);

  final failures = checks.where((check) => check['passed'] != true).toList();
  stdout.writeln(const JsonEncoder.withIndent('  ').convert({
    'runtime': Platform.version,
    'source': 'packages/quds_office_editor/example/lib/studio_mail_recipients.dart',
    'checks': checks,
    'passed': checks.length - failures.length,
    'failed': failures.length,
    'qualification': 'Direct imported production recipient helper only; no Flutter, MIME, provider, widget, or live-service acceptance.',
  }));
  if (failures.isNotEmpty) exitCode = 1;
}

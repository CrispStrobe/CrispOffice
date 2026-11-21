import 'dart:convert';
import 'package:quds_mail_core/quds_mail_core.dart';
String _defaultSearchError(MailHeaderSearchError error) => switch (error) {
  MailHeaderSearchError.queryTooLong => 'The search is too long.',
  MailHeaderSearchError.tooManyTerms => 'Use fewer search terms.',
  MailHeaderSearchError.invalidCharacter =>
    'The search contains an unsupported character.',
  MailHeaderSearchError.unclosedQuote => 'Close the quoted search phrase.',
  MailHeaderSearchError.invalidEscape =>
    'Inside quotes, only a quote or backslash can be escaped.',
  MailHeaderSearchError.emptyTerm => 'Enter text inside the quoted phrase.',
  MailHeaderSearchError.missingValue => 'Enter a value after the search field.',
  MailHeaderSearchError.unknownField => 'This search field is not supported.',
  MailHeaderSearchError.invalidState =>
    'Use is:read, is:unread, is:flagged or is:unflagged.',
  MailHeaderSearchError.invalidDate => 'Enter a valid date as YYYY-MM-DD.',
  MailHeaderSearchError.unsupportedOperator =>
    'Wildcards, brackets and symbolic operators are not supported.',
  MailHeaderSearchError.invalidExpression =>
    'Complete each AND, OR or NOT expression and balance parentheses. '
    'Use at most 32 explicit operators.',
  MailHeaderSearchError.nestingTooDeep =>
    'Use no more than 8 nested groups.',
};
final _searchExampleLine = RegExp(
  r'^\s*(?:[-(]\s*|NOT\b\s*)*(?:from|subject|to|cc|is|before|after|on):',
  caseSensitive: false,
);
enum Language { en, de, ar }
enum TextDirection { ltr, rtl }
TextDirection? sourceDirection(String line) => _searchExampleLine.hasMatch(line)
                          ? TextDirection.ltr
                          : null;
class Strings {
  const Strings(this.language);
  final Language language;
  String _text(String en, String de, String ar) => switch(language) {
    Language.en => en, Language.de => de, Language.ar => ar,
  };
  String _mailHeaderSearchError(MailHeaderSearchError error) => switch (error) {
    MailHeaderSearchError.queryTooLong => _text(
      'Search is limited to 1,024 characters.',
      'Die Suche ist auf 1.024 Zeichen begrenzt.',
      'البحث محدود بـ1024 حرفًا.',
    ),
    MailHeaderSearchError.tooManyTerms => _text(
      'Use no more than 32 search terms.',
      'Verwenden Sie höchstens 32 Suchbegriffe.',
      'استخدم 32 عبارة بحث كحد أقصى.',
    ),
    MailHeaderSearchError.invalidCharacter => _text(
      'Remove unsupported characters and separate search terms with spaces.',
      'Entfernen Sie nicht unterstützte Zeichen und trennen Sie Suchbegriffe durch Leerzeichen.',
      'أزل المحارف غير المدعومة وافصل عبارات البحث بمسافات.',
    ),
    MailHeaderSearchError.unclosedQuote => _text(
      'Close the double-quoted phrase.',
      'Schließen Sie die doppelten Anführungszeichen.',
      'أغلق علامة الاقتباس المزدوجة للعبارة.',
    ),
    MailHeaderSearchError.invalidEscape => _text(
      'Inside quotes, a backslash can escape only a quote or another backslash.',
      'In Anführungszeichen darf ein Rückstrich nur ein Anführungszeichen oder einen weiteren Rückstrich schützen.',
      'داخل الاقتباس، يمكن للشرطة المائلة العكسية أن تسبق علامة اقتباس أو شرطة عكسية أخرى فقط.',
    ),
    MailHeaderSearchError.emptyTerm => _text(
      'Enter text inside the quoted phrase.',
      'Geben Sie Text zwischen den Anführungszeichen ein.',
      'أدخل نصًا داخل علامتي الاقتباس.',
    ),
    MailHeaderSearchError.missingValue => _text(
      'Enter a value after the search field.',
      'Geben Sie einen Wert nach dem Suchfeld ein.',
      'أدخل قيمة بعد حقل البحث.',
    ),
    MailHeaderSearchError.unknownField => _text(
      'Use from, subject, to, cc, before, after, on or is. See Search help.',
      'Verwenden Sie from, subject, to, cc, before, after, on oder is. Siehe Suchhilfe.',
      'استخدم from أو subject أو to أو cc أو before أو after أو on أو is. راجع مساعدة البحث.',
    ),
    MailHeaderSearchError.invalidState => _text(
      'Use is:read, is:unread, is:flagged or is:unflagged.',
      'Verwenden Sie is:read, is:unread, is:flagged oder is:unflagged.',
      'استخدم is:read أو is:unread أو is:flagged أو is:unflagged.',
    ),
    MailHeaderSearchError.invalidDate => _text(
      'Enter a valid calendar date as YYYY-MM-DD.',
      'Geben Sie ein gültiges Kalenderdatum als JJJJ-MM-TT ein.',
      'أدخل تاريخًا صحيحًا بالتنسيق YYYY-MM-DD.',
    ),
    MailHeaderSearchError.unsupportedOperator => _text(
      'Wildcards, brackets and symbolic operators are not supported. Use AND, OR, NOT and parentheses; quote literal text.',
      'Platzhalter, eckige Klammern und symbolische Operatoren werden nicht unterstützt. Verwenden Sie AND, OR, NOT und runde Klammern; setzen Sie wörtlichen Text in Anführungszeichen.',
      'لا تُدعم أحرف البدل أو الأقواس المربعة أو العوامل الرمزية. استخدم AND وOR وNOT والأقواس المستديرة؛ وضع النص الحرفي بين علامتي اقتباس.',
    ),
    MailHeaderSearchError.invalidExpression => _text(
      'Complete each AND, OR or NOT expression and balance parentheses. Use at most 32 explicit operators.',
      'Vervollständigen Sie jeden AND-, OR- oder NOT-Ausdruck und schließen Sie alle Klammern. Verwenden Sie höchstens 32 ausdrückliche Operatoren.',
      'أكمل كل تعبير AND أو OR أو NOT وأغلق جميع الأقواس. استخدم 32 عاملًا صريحًا كحد أقصى.',
    ),
    MailHeaderSearchError.nestingTooDeep => _text(
      'Use no more than 8 nested groups.',
      'Verwenden Sie höchstens 8 ineinander verschachtelte Gruppen.',
      'استخدم 8 مجموعات متداخلة كحد أقصى.',
    ),
  };
  String help() => _text(
      'Words match the subject or sender. Separate terms or use AND to '
          'require all. Use OR for alternatives, and NOT or a leading - '
          'to exclude matches. NOT applies before AND, then OR; parentheses '
          'group conditions. Use double quotes for a phrase or literal '
          'operator text.\n\n'
          '(from:alice OR from:bob) NOT subject:invoice\n'
          'from:alice -subject:"weekly digest"\n'
          'to:team@example.test cc:manager\n'
          'State choices: is:read, is:unread, is:flagged, is:unflagged\n'
          'after:2026-10-01 before:2026-11-01 on:2026-10-15\n\n'
          'Dates use the displayed local calendar day. Before and after '
          'exclude the named day; on includes it. Missing dates or flags '
          'remain unknown, including with NOT. Operator names stay in '
          'English; Boolean operators must be uppercase.\n\n'
          'Search covers only loaded headers in this folder. It does not '
          'search message bodies, Bcc or other folders, or download more '
          'mail. Use Archive search for collected message content. '
          'Limits: 1,024 characters, 32 terms, 32 explicit operators and '
          '8 nested groups. Wildcards are not supported.',
      'Wörter suchen im Betreff oder Absender. Leerzeichen oder AND '
          'verlangen alle Bedingungen. OR erlaubt Alternativen; NOT oder '
          'ein vorangestelltes - schließt Treffer aus. NOT gilt vor AND, '
          'danach OR; Klammern gruppieren Bedingungen. Doppelte '
          'Anführungszeichen suchen eine Wortgruppe oder wörtliche '
          'Operatornamen.\n\n'
          '(from:alice OR from:bob) NOT subject:invoice\n'
          'from:alice -subject:"weekly digest"\n'
          'to:team@example.test cc:manager\n'
          'Statusauswahl: is:read, is:unread, is:flagged, is:unflagged\n'
          'after:2026-10-01 before:2026-11-01 on:2026-10-15\n\n'
          'Datumsfilter verwenden den angezeigten lokalen Kalendertag. '
          'Before und after schließen den genannten Tag aus; on umfasst '
          'ihn. Fehlende Datums- oder Statuswerte bleiben unbekannt, auch '
          'mit NOT. Operatornamen bleiben Englisch; boolesche Operatoren '
          'müssen großgeschrieben werden.\n\n'
          'Durchsucht werden nur geladene Nachrichtenköpfe dieses Ordners. '
          'Nachrichtentext, Bcc und andere Ordner bleiben außerhalb der '
          'Suche; es werden keine weiteren Nachrichten geladen. Gesammelte '
          'Inhalte finden Sie mit der Archivsuche. Grenzen: 1.024 Zeichen, '
          '32 Begriffe, 32 ausdrückliche Operatoren und 8 verschachtelte '
          'Gruppen. Platzhalter werden nicht unterstützt.',
      'تطابق الكلمات الموضوع أو المرسل. تفصل المسافات أو AND بين الشروط '
          'المطلوب تطابقها جميعًا. استخدم OR للبدائل، وNOT أو - في البداية '
          'لاستبعاد التطابقات. تُطبّق NOT قبل AND ثم OR؛ وتجمع الأقواس '
          'الشروط. استخدم علامتي اقتباس مزدوجتين لعبارة أو لاسم عامل '
          'بحث حرفي.\n\n'
          '(from:alice OR from:bob) NOT subject:invoice\n'
          'from:alice -subject:"weekly digest"\n'
          'to:team@example.test cc:manager\n'
          'خيارات الحالة: is:read، is:unread، is:flagged، is:unflagged\n'
          'after:2026-10-01 before:2026-11-01 on:2026-10-15\n\n'
          'تستخدم التواريخ اليوم المحلي المعروض. يستثني before وafter '
          'اليوم المحدد، ويشمله on. تبقى التواريخ أو الحالات المفقودة '
          'غير معروفة حتى مع NOT. تبقى أسماء العوامل بالإنجليزية؛ '
          'وتُكتب العوامل المنطقية بأحرف كبيرة.\n\n'
          'يشمل البحث الترويسات المحمّلة في هذا المجلد فقط، ولا يبحث في '
          'متن الرسائل أو Bcc أو المجلدات الأخرى، ولا يحمّل بريدًا إضافيًا. '
          'استخدم بحث الأرشيف للمحتوى الذي جُمع. الحدود: 1024 حرفًا '
          'و32 عبارة و32 عاملًا صريحًا و8 مجموعات متداخلة. '
          'لا تُدعم أحرف البدل.',
    );
}
void main() {
  var labelChecks = 0;
  var directionChecks = 0;
  var exampleChecks = 0;
  for (final error in MailHeaderSearchError.values) {
    if (_defaultSearchError(error).isEmpty) throw StateError('Empty default $error');
    labelChecks++;
    for (final language in Language.values) {
      final text = Strings(language)._mailHeaderSearchError(error);
      if (text.isEmpty) throw StateError('Empty $language $error');
      labelChecks++;
      if (language != Language.en) {
        if (text == const Strings(Language.en)._mailHeaderSearchError(error)) {
          throw StateError('Untranslated $language $error');
        }
        labelChecks++;
      }
    }
  }
  for (final line in [
    '(from:alice OR from:bob) NOT subject:invoice',
    'NOT from:alice',
    'NOT(from:alice OR from:bob)',
    '-from:alice',
    '-(from:alice OR from:bob)',
    '(NOT from:alice)',
    '  (( - NOT subject:invoice))',
    'NOT NOT subject:invoice',
    '\u2003NOT - (is:read OR is:flagged)',
    'FROM:ALICE',
    'NOT from:alice OR to:team',
    'subject:"weekly digest"',
    'from:alice -subject:"weekly digest"',
    'to:team@example.test cc:manager',
    'after:2026-10-01 before:2026-11-01 on:2026-10-15',
  ]) {
    if (!_searchExampleLine.hasMatch(line)) throw StateError('Unrecognized example $line');
    directionChecks++;
    // Evaluate the exact production routing expression in an Arabic ambient.
    if ((sourceDirection(line) ?? TextDirection.rtl) != TextDirection.ltr) {
      throw StateError('Example did not override Arabic direction: $line');
    }
    directionChecks++;
    MailHeaderSearchQuery.parse(line);
    exampleChecks++;
  }
  for (final line in [
    'مثال بحث (from:alice)',
    'خيارات الحالة: is:read',
    'المرسل: أحمد',
    'State choices: is:read',
    'Statusauswahl: is:read',
    'NOTHING from:alice',
    'before 2026-10-01',
  ]) {
    if (_searchExampleLine.hasMatch(line)) throw StateError('Prose classified as example: $line');
    directionChecks++;
    if ((sourceDirection(line) ?? TextDirection.rtl) != TextDirection.rtl) {
      throw StateError('Arabic ambient direction was overridden for prose: $line');
    }
    directionChecks++;
  }
  var actualExamples = 0;
  for (final language in Language.values) {
    final help = Strings(language).help();
    if (!help.contains('(from:alice OR from:bob) NOT subject:invoice')) {
      throw StateError('Missing grouped example in $language');
    }
    exampleChecks++;
    for (final line in help.split('\n')) {
      if (!_searchExampleLine.hasMatch(line)) continue;
      MailHeaderSearchQuery.parse(line);
      exampleChecks++;
      if ((sourceDirection(line) ?? TextDirection.rtl) != TextDirection.ltr) {
        throw StateError('Authored example direction in $language');
      }
      directionChecks++;
      actualExamples++;
    }
  }
  if (actualExamples != 12) throw StateError('Expected 12 authored example lines, got $actualExamples');
  exampleChecks++;
  print(jsonEncode({'labelChecks':labelChecks,'directionChecks':directionChecks,'exampleChecks':exampleChecks,'authoredExamples':actualExamples,'errors':MailHeaderSearchError.values.length,'languages':Language.values.length}));
}

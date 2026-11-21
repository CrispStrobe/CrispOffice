import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_ui/quds_mail_ui.dart';

import 'studio_mail_strings.dart';
import 'studio_strings.dart';

/// Provider-independent mailbox navigation copy, with explicit loaded scope.
extension StudioMailWorkspaceStrings on StudioStrings {
  String _text(String en, String de, String ar) => switch (language) {
    StudioLanguage.en => en,
    StudioLanguage.de => de,
    StudioLanguage.ar => ar,
  };

  MailMessageListStrings get mailMessageListStrings => MailMessageListStrings(
    searchLoaded: _text(
      'Search mail',
      'E-Mails durchsuchen',
      'البحث في البريد',
    ),
    unread: _text('Unread', 'Ungelesen', 'غير مقروءة'),
    flagged: _text('Flagged', 'Gekennzeichnet', 'المعلّمة'),
    noMessages: noMessages,
    noMatches: _text(
      'No loaded messages match these filters.',
      'Keine geladene Nachricht entspricht diesen Filtern.',
      'لا توجد رسائل محمّلة تطابق هذه المرشحات.',
    ),
    loadMore: ewsLoadMore,
    loading: _text('Loading…', 'Wird geladen…', 'جارٍ التحميل…'),
    loadedScope: _text(
      'Search, filters and sorting apply only to loaded headers in this folder.',
      'Suche, Filter und Sortierung gelten nur für geladene Nachrichtenköpfe dieses Ordners.',
      'ينطبق البحث والترشيح والترتيب على الترويسات المحمّلة في هذا المجلد فقط.',
    ),
    count: (shown, loaded) => _text(
      '$shown shown · $loaded loaded',
      '$shown angezeigt · $loaded geladen',
      '$shown معروضة · $loaded محمّلة',
    ),
    clearSearch: _text('Clear search', 'Suche löschen', 'مسح البحث'),
    searchHelp: _text('Search help', 'Suchhilfe', 'مساعدة البحث'),
    searchHelpTitle: _text(
      'Search mail',
      'E-Mails durchsuchen',
      'البحث في البريد',
    ),
    searchHelpText: _text(
      'Words match the subject or sender. Separate terms with spaces to '
          'require every match; use double quotes for an exact phrase. '
          'Use uppercase AND, OR and NOT, or a leading minus for NOT. '
          'Parentheses group terms; NOT applies first, then AND, then OR. '
          'Use spaces between adjacent terms and groups.\n\n'
          'from:alice subject:"quarterly report"\n'
          'from:alice OR (subject:report AND NOT is:read)\n'
          'to:team@example.test cc:manager\n'
          'State choices: is:read, is:unread, is:flagged, is:unflagged\n'
          'after:2026-10-01 before:2026-11-01 on:2026-10-15\n\n'
          'Dates use the displayed local calendar day. Before and after exclude '
          'the named day; on includes that day. A missing date or flag does '
          'not match its filter, even when negated. '
          'Operator names stay in English.\n\n'
          'Search covers only loaded headers in this folder. It does not search '
          'message bodies, Bcc or other folders, or download more mail. '
          'Use Archive search for collected message content. '
          'Up to 1,024 characters, 32 terms, 32 operators and eight nested '
          'groups. Wildcards, square brackets, && and || are not supported.',
      'Wörter suchen im Betreff oder Absender. Durch Leerzeichen getrennte '
          'Begriffe müssen alle zutreffen; doppelte Anführungszeichen suchen '
          'eine genaue Wortgruppe. Verwenden Sie AND, OR und NOT in '
          'Großbuchstaben oder ein vorangestelltes Minus für NOT. Klammern '
          'gruppieren Begriffe; NOT gilt vor AND und AND vor OR. Trennen Sie '
          'benachbarte Begriffe und Gruppen durch Leerzeichen.\n\n'
          'from:alice subject:"quarterly report"\n'
          'from:alice OR (subject:report AND NOT is:read)\n'
          'to:team@example.test cc:manager\n'
          'Statusauswahl: is:read, is:unread, is:flagged, is:unflagged\n'
          'after:2026-10-01 before:2026-11-01 on:2026-10-15\n\n'
          'Datumsfilter verwenden den angezeigten lokalen Kalendertag. Before '
          'und after schließen den genannten Tag aus; on umfasst diesen Tag. '
          'Fehlende Datums- oder Statuswerte erfüllen ihren Filter auch '
          'bei NOT nicht. '
          'Die Operatornamen bleiben Englisch.\n\n'
          'Durchsucht werden nur geladene Nachrichtenköpfe dieses Ordners. '
          'Nachrichtentext, Bcc und andere Ordner bleiben außerhalb der Suche; '
          'es werden keine weiteren Nachrichten geladen. Gesammelte Inhalte '
          'finden Sie mit der Archivsuche. Höchstens 1.024 Zeichen, 32 '
          'Begriffe, 32 Operatoren und acht verschachtelte Gruppen. '
          'Platzhalter, eckige Klammern, && und || werden nicht unterstützt.',
      'تطابق الكلمات الموضوع أو المرسل. افصل العبارات بمسافات لاشتراط '
          'تطابقها جميعًا؛ استخدم علامتي اقتباس مزدوجتين لعبارة مطابقة حرفيًا. '
          'استخدم AND وOR وNOT بأحرف كبيرة، أو علامة ناقص قبل العبارة للنفي. '
          'تجمع الأقواس العبارات؛ تُطبّق NOT أولًا، ثم AND، ثم OR. '
          'افصل العبارات والمجموعات المتجاورة بمسافات.\n\n'
          'from:alice subject:"quarterly report"\n'
          'from:alice OR (subject:report AND NOT is:read)\n'
          'to:team@example.test cc:manager\n'
          'خيارات الحالة: is:read، is:unread، is:flagged، is:unflagged\n'
          'after:2026-10-01 before:2026-11-01 on:2026-10-15\n\n'
          'تستخدم التواريخ اليوم المحلي المعروض. يستثني before وafter اليوم '
          'المحدد، ويشمله on. لا تطابق التواريخ أو الحالات المفقودة '
          'مرشحاتها، حتى عند نفيها باستخدام NOT. تبقى أسماء عوامل البحث '
          'بالإنجليزية.\n\n'
          'يشمل البحث الترويسات المحمّلة في هذا المجلد فقط، ولا يبحث في متن '
          'الرسائل أو Bcc أو المجلدات الأخرى، ولا يحمّل بريدًا إضافيًا. '
          'استخدم بحث الأرشيف للمحتوى الذي جُمع. الحد الأقصى 1024 حرفًا '
          'و32 عبارة و32 عاملًا وثمانية مستويات من الأقواس المتداخلة. '
          'لا تُدعم أحرف البدل أو الأقواس المربعة أو && أو ||.',
    ),
    close: _text('Close', 'Schließen', 'إغلاق'),
    sort: _text(
      'Sort loaded messages',
      'Geladene Nachrichten sortieren',
      'ترتيب الرسائل المحمّلة',
    ),
    providerOrder: _text('Folder order', 'Ordnerreihenfolge', 'ترتيب المجلد'),
    newestFirst: _text('Newest first', 'Neueste zuerst', 'الأحدث أولًا'),
    oldestFirst: _text('Oldest first', 'Älteste zuerst', 'الأقدم أولًا'),
    senderAscending: _text('Sender A–Z', 'Absender A–Z', 'المرسل أ–ي'),
    subjectAscending: _text('Subject A–Z', 'Betreff A–Z', 'الموضوع أ–ي'),
    searchError: _mailHeaderSearchError,
    selectMessage: _text(
      'Select message',
      'Nachricht auswählen',
      'تحديد الرسالة',
    ),
    selectShown: _text(
      'Select shown',
      'Angezeigte auswählen',
      'تحديد المعروضة',
    ),
    clearSelection: _text(
      'Clear selection',
      'Auswahl aufheben',
      'إلغاء التحديد',
    ),
    selectedCount: (count) =>
        _text('$count selected', '$count ausgewählt', '$count محددة'),
    bulkActions: _text(
      'Actions for selected messages',
      'Aktionen für ausgewählte Nachrichten',
      'إجراءات الرسائل المحددة',
    ),
    markRead: markRead,
    markUnread: ewsMarkUnread,
    flag: _text('Flag', 'Kennzeichnen', 'وضع علامة'),
    unflag: _text('Remove flag', 'Kennzeichnung entfernen', 'إزالة العلامة'),
    stopBulk: _text(
      'Stop after current message',
      'Nach aktueller Nachricht stoppen',
      'التوقف بعد الرسالة الحالية',
    ),
    bulkWorking: _text(
      'Applying changes…',
      'Änderungen werden angewendet…',
      'جارٍ تطبيق التغييرات…',
    ),
  );

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
      'Use AND, OR or NOT. Wildcards, square brackets, && and || are not supported; quote literal text.',
      'Verwenden Sie AND, OR oder NOT. Platzhalter, eckige Klammern, && und || werden nicht unterstützt; setzen Sie wörtlichen Text in Anführungszeichen.',
      'استخدم AND أو OR أو NOT. لا تُدعم أحرف البدل أو الأقواس المربعة أو && أو ||؛ ضع النص الحرفي بين علامتي اقتباس.',
    ),
    MailHeaderSearchError.invalidExpression => _text(
      'Check the search terms, operators and parentheses; use at most 32 operators.',
      'Prüfen Sie Suchbegriffe, Operatoren und Klammern; verwenden Sie höchstens 32 Operatoren.',
      'تحقق من عبارات البحث والعوامل والأقواس؛ استخدم 32 عاملًا كحد أقصى.',
    ),
    MailHeaderSearchError.nestingTooDeep => _text(
      'Use no more than eight nested groups of parentheses.',
      'Verwenden Sie höchstens acht ineinander verschachtelte Klammergruppen.',
      'استخدم ثمانية مستويات من الأقواس المتداخلة كحد أقصى.',
    ),
  };

  String get mailWorkspaceLimit => _text(
    '1,000 messages loaded. This view has reached its limit; older messages may remain on the server.',
    '1.000 Nachrichten geladen. Diese Ansicht hat ihre Grenze erreicht; ältere Nachrichten können auf dem Server verbleiben.',
    'حُمّلت 1000 رسالة. بلغت هذه القائمة حدّها؛ قد تبقى رسائل أقدم على الخادم.',
  );

  String get mailWorkspaceRefreshRequired => _text(
    'The mailbox changed or a change could not be confirmed. Refresh before continuing.',
    'Das Postfach wurde geändert oder eine Änderung konnte nicht bestätigt werden. Vor dem Fortfahren aktualisieren.',
    'تغيّر صندوق البريد أو تعذر تأكيد التغيير. حدّث القائمة قبل المتابعة.',
  );

  String get mailWorkspaceActionConfirmed => _text(
    'The server confirmed the change.',
    'Der Server hat die Änderung bestätigt.',
    'أكد الخادم التغيير.',
  );

  String mailBulkSummary(MailBulkFlagReport report) => _text(
    '${report.confirmedCount} confirmed · ${report.failedCount} failed · '
        '${report.uncertainCount} uncertain · ${report.unattemptedCount} not attempted',
    '${report.confirmedCount} bestätigt · ${report.failedCount} fehlgeschlagen · '
        '${report.uncertainCount} ungewiss · ${report.unattemptedCount} nicht versucht',
    '${report.confirmedCount} مؤكدة · ${report.failedCount} فاشلة · '
        '${report.uncertainCount} غير مؤكدة · ${report.unattemptedCount} لم تُحاول',
  );
}

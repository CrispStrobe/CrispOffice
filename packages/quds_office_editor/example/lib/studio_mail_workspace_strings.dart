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
    groupConversations: _text('Conversations', 'Unterhaltungen', 'المحادثات'),
    conversationCount: (count) => _text(
      '$count loaded messages in conversation',
      '$count geladene Nachrichten in einer Unterhaltung',
      '$count رسالة محمّلة في المحادثة',
    ),
    collapseConversation: _text(
      'Collapse conversation',
      'Unterhaltung einklappen',
      'طيّ المحادثة',
    ),
    expandConversation: _text(
      'Expand conversation',
      'Unterhaltung ausklappen',
      'توسيع المحادثة',
    ),
    conversationSummary: (loaded, unread, flagged) => _text(
      '$loaded loaded · $unread unread · $flagged flagged',
      '$loaded geladen · $unread ungelesen · $flagged gekennzeichnet',
      '$loaded محمّلة · $unread غير مقروءة · $flagged معلّمة',
    ),
    conversationUnknown: (unknownRead, unknownFlagged) => _text(
      'Read state unknown: $unknownRead · Flag state unknown: $unknownFlagged',
      'Lesestatus unbekannt: $unknownRead · Kennzeichnungsstatus unbekannt: $unknownFlagged',
      'حالة القراءة غير معروفة: $unknownRead · حالة العلامة غير معروفة: $unknownFlagged',
    ),
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
    selectionHelp: _text(
      'Selection help',
      'Hilfe zur Auswahl',
      'مساعدة التحديد',
    ),
    selectionHelpTitle: _text(
      'Select messages',
      'Nachrichten auswählen',
      'تحديد الرسائل',
    ),
    selectionHelpText: _text(
      'Arrow keys and Home/End move the list cursor without opening mail. '
          'Space toggles its checkbox. Hold Shift with Up/Down or Home/End '
          'to extend or shrink a checked range. Shift+Space or Shift+click '
          'on a row or checkbox selects a range from the anchor. '
          'Separately checked messages stay selected when a range shrinks. '
          'Ctrl/Cmd+A selects shown rows; Escape clears the selection.\n\n'
          'Search, sorting, conversation folding and refreshed rows reset '
          'the range anchor. Only shown rows are included; filtered or '
          'collapsed messages are excluded. Choose an action from '
          'Actions for selected messages to apply changes.',
      'Pfeiltasten und Pos1/Ende bewegen den Listencursor, ohne E-Mails zu '
          'öffnen. Die Leertaste schaltet das Kontrollkästchen um. '
          'Umschalt+Auf/Ab oder Umschalt+Pos1/Ende erweitert oder verkleinert '
          'den ausgewählten Bereich. Umschalt+Leertaste oder ein Klick auf '
          'eine Zeile oder ein Kontrollkästchen mit gedrückter Umschalttaste '
          'wählt den Bereich ab dem Anker aus. Separat ausgewählte '
          'Nachrichten bleiben beim Verkleinern ausgewählt. Strg/Cmd+A '
          'wählt angezeigte Zeilen; Escape hebt die Auswahl auf.\n\n'
          'Suche, Sortierung, das Ein- und Ausklappen von Unterhaltungen '
          'sowie aktualisierte Zeilen setzen den Bereichsanker zurück. '
          'Nur angezeigte Zeilen werden einbezogen; ausgefilterte oder '
          'eingeklappte Nachrichten bleiben ausgeschlossen. Wählen Sie '
          'unter Aktionen für ausgewählte Nachrichten die gewünschte Aktion.',
      'تنقل مفاتيح الأسهم وHome/End مؤشر القائمة دون فتح البريد. يبدّل '
          'مفتاح المسافة تحديد الرسالة. اضغط Shift مع أعلى/أسفل أو '
          'Home/End لتوسيع نطاق التحديد أو تقليصه. يحدد Shift+المسافة '
          'أو النقر مع Shift على صف أو مربع تحديد النطاق من نقطة البداية. '
          'تبقى الرسائل المحددة منفردة محددة عند تقليص النطاق. '
          'يحدد Ctrl/Cmd+A الصفوف المعروضة؛ ويلغي Escape التحديد.\n\n'
          'يعيد البحث والترتيب وطي المحادثات أو توسيعها وتحديث الصفوف '
          'تعيين نقطة بداية النطاق. يشمل التحديد الصفوف المعروضة فقط؛ '
          'ولا يشمل الرسائل المخفية بالترشيح أو الطي. اختر إجراءً من '
          'إجراءات الرسائل المحددة لتطبيق التغييرات.',
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

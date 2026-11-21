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
      'Words match the subject or sender. All terms must match; use double '
          'quotes for an exact phrase.\n\n'
          'from:alice subject:"quarterly report"\n'
          'to:team@example.test cc:manager\n'
          'State choices: is:read, is:unread, is:flagged, is:unflagged\n'
          'after:2026-10-01 before:2026-11-01 on:2026-10-15\n\n'
          'Dates use the displayed local calendar day. Before and after exclude '
          'the named day; on includes that day. Unknown dates or flags do not '
          'match those filters. Operator names stay in English.\n\n'
          'Search covers only loaded headers in this folder. It does not search '
          'message bodies, Bcc or other folders, or download more mail. '
          'Use Archive search for collected message content. '
          'Up to 1,024 characters and 32 terms; Boolean operators, negation '
          'and wildcards are not supported.',
      'Wörter suchen im Betreff oder Absender. Alle Begriffe müssen zutreffen; '
          'doppelte Anführungszeichen suchen eine genaue Wortgruppe.\n\n'
          'from:alice subject:"quarterly report"\n'
          'to:team@example.test cc:manager\n'
          'Statusauswahl: is:read, is:unread, is:flagged, is:unflagged\n'
          'after:2026-10-01 before:2026-11-01 on:2026-10-15\n\n'
          'Datumsfilter verwenden den angezeigten lokalen Kalendertag. Before '
          'und after schließen den genannten Tag aus; on umfasst diesen Tag. '
          'Unbekannte Datums- oder Statuswerte erfüllen diese Filter nicht. '
          'Die Operatornamen bleiben Englisch.\n\n'
          'Durchsucht werden nur geladene Nachrichtenköpfe dieses Ordners. '
          'Nachrichtentext, Bcc und andere Ordner bleiben außerhalb der Suche; '
          'es werden keine weiteren Nachrichten geladen. Gesammelte Inhalte '
          'finden Sie mit der Archivsuche. Höchstens 1.024 Zeichen und 32 '
          'Begriffe; boolesche Operatoren, Verneinung und Platzhalter werden '
          'nicht unterstützt.',
      'تطابق الكلمات الموضوع أو المرسل. يجب أن تتطابق جميع العبارات؛ '
          'استخدم علامتي اقتباس مزدوجتين لعبارة مطابقة حرفيًا.\n\n'
          'from:alice subject:"quarterly report"\n'
          'to:team@example.test cc:manager\n'
          'خيارات الحالة: is:read، is:unread، is:flagged، is:unflagged\n'
          'after:2026-10-01 before:2026-11-01 on:2026-10-15\n\n'
          'تستخدم التواريخ اليوم المحلي المعروض. يستثني before وafter اليوم '
          'المحدد، ويشمله on. لا تطابق التواريخ أو الحالات غير المعروفة هذه '
          'المرشحات. تبقى أسماء عوامل البحث بالإنجليزية.\n\n'
          'يشمل البحث الترويسات المحمّلة في هذا المجلد فقط، ولا يبحث في متن '
          'الرسائل أو Bcc أو المجلدات الأخرى، ولا يحمّل بريدًا إضافيًا. '
          'استخدم بحث الأرشيف للمحتوى الذي جُمع. الحد الأقصى 1024 حرفًا '
          'و32 عبارة؛ لا تُدعم العوامل المنطقية أو النفي أو أحرف البدل.',
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
      'Combine terms with spaces. Boolean operators, negation and wildcards are not supported; quote literal text.',
      'Trennen Sie Begriffe durch Leerzeichen. Boolesche Operatoren, Verneinung und Platzhalter werden nicht unterstützt; setzen Sie wörtlichen Text in Anführungszeichen.',
      'افصل العبارات بمسافات. لا تُدعم العوامل المنطقية أو النفي أو أحرف البدل؛ ضع النص الحرفي بين علامتي اقتباس.',
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

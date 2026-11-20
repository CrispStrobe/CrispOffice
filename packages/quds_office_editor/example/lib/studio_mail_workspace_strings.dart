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
    searchLoaded: ewsSearchLoaded,
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
      'Search and filters apply to loaded messages.',
      'Suche und Filter gelten für geladene Nachrichten.',
      'ينطبق البحث والترشيح على الرسائل المحمّلة.',
    ),
    count: (shown, loaded) => _text(
      '$shown shown · $loaded loaded',
      '$shown angezeigt · $loaded geladen',
      '$shown معروضة · $loaded محمّلة',
    ),
  );

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
}

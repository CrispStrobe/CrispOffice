import 'studio_strings.dart';

extension StudioMailRuleStrings on StudioStrings {
  String _t(String en, String de, String ar) => switch (language) {
    StudioLanguage.en => en,
    StudioLanguage.de => de,
    StudioLanguage.ar => ar,
  };

  String get mailRules => _t('Rules', 'Regeln', 'القواعد');
  String get mailRulesHelp => _t(
    'Rules run in order over saved mail and only add or remove local tags. They never move mail, change read state, contact the server or write provider keywords.',
    'Regeln laufen der Reihe nach über gespeicherte E-Mails und fügen nur lokale Tags hinzu oder entfernen sie. Sie verschieben keine E-Mails, ändern keinen Lesestatus, kontaktieren keinen Server und schreiben keine Anbieter-Schlüsselwörter.',
    'تعمل القواعد بالترتيب على البريد المحفوظ وتضيف الوسوم المحلية أو تزيلها فقط. لا تنقل البريد ولا تغيّر حالة القراءة ولا تتصل بالخادم ولا تكتب كلمات مفتاحية لدى المزود.',
  );
  String get mailRuleAdd => _t('Add rule', 'Regel hinzufügen', 'إضافة قاعدة');
  String get mailRuleEdit =>
      _t('Edit rule', 'Regel bearbeiten', 'تعديل القاعدة');
  String get mailRuleName => _t('Rule name', 'Regelname', 'اسم القاعدة');
  String get mailRuleQuery => _t(
    'Match saved mail',
    'Gespeicherte E-Mails treffen',
    'مطابقة البريد المحفوظ',
  );
  String get mailRuleQueryHelp => _t(
    'Uses the same search grammar as saved mail. Example: from:shop subject:invoice',
    'Verwendet dieselbe Suchsyntax wie gespeicherte E-Mails. Beispiel: from:shop subject:invoice',
    'يستخدم صيغة البحث نفسها للبريد المحفوظ. مثال: from:shop subject:invoice',
  );
  String get mailRuleAddTags =>
      _t('Add local tags', 'Lokale Tags hinzufügen', 'إضافة وسوم محلية');
  String get mailRuleRemoveTags =>
      _t('Remove local tags', 'Lokale Tags entfernen', 'إزالة وسوم محلية');
  String get mailRuleTagsHelp => _t(
    'Separate tag names with commas. Leave one side empty when unused.',
    'Trennen Sie Tag-Namen durch Kommas. Lassen Sie eine Seite leer, wenn sie nicht verwendet wird.',
    'افصل أسماء الوسوم بفواصل. اترك أحد الجانبين فارغًا عند عدم استخدامه.',
  );
  String get mailRuleEnabled => _t('Enabled', 'Aktiviert', 'مفعّلة');
  String get mailRuleDisabled => _t('Disabled', 'Deaktiviert', 'معطّلة');
  String get mailRuleInvalid => _t(
    'Check the name, search expression and tags. A rule needs at least one action and cannot add and remove the same tag.',
    'Prüfen Sie Name, Suchausdruck und Tags. Eine Regel braucht mindestens eine Aktion und kann denselben Tag nicht hinzufügen und entfernen.',
    'تحقق من الاسم وتعبير البحث والوسوم. تحتاج القاعدة إلى إجراء واحد على الأقل ولا يمكنها إضافة وسم وإزالته معًا.',
  );
  String get mailRulePreview => _t('Preview', 'Vorschau', 'معاينة');
  String get mailRuleApply => _t('Apply now', 'Jetzt anwenden', 'تطبيق الآن');
  String get mailRuleApplyConfirm => _t(
    'Apply all enabled rules to saved mail now? Only local tags change, and the update is all-or-nothing.',
    'Alle aktivierten Regeln jetzt auf gespeicherte E-Mails anwenden? Nur lokale Tags ändern sich, und die Aktualisierung ist alles-oder-nichts.',
    'تطبيق كل القواعد المفعّلة على البريد المحفوظ الآن؟ تتغير الوسوم المحلية فقط، والتحديث إمّا كامل أو لا شيء.',
  );
  String mailRuleMatches(int count) => _t(
    '$count saved matches',
    '$count gespeicherte Treffer',
    '$count نتيجة محفوظة',
  );
  String mailRuleChanged(int count) => _t(
    'Updated $count messages.',
    '$count Nachrichten aktualisiert.',
    'تم تحديث $count رسالة.',
  );
  String get mailRuleNoChanges => _t(
    'No local tags needed changing.',
    'Keine lokalen Tags mussten geändert werden.',
    'لم تكن هناك حاجة لتغيير وسوم محلية.',
  );
  String get mailRuleSaveFailed => _t(
    'Rules could not be saved. Previous rules were restored.',
    'Regeln konnten nicht gespeichert werden. Die bisherigen Regeln wurden wiederhergestellt.',
    'تعذر حفظ القواعد. تمت استعادة القواعد السابقة.',
  );
  String get mailRuleLoadFailed => _t(
    'Rules could not be loaded.',
    'Regeln konnten nicht geladen werden.',
    'تعذر تحميل القواعد.',
  );
  String get mailRuleOperationFailed => _t(
    'The rule operation failed. No tag change was applied unless the message says otherwise.',
    'Der Regelvorgang ist fehlgeschlagen. Es wurde keine Tag-Änderung angewendet, sofern nicht anders angegeben.',
    'فشلت عملية القاعدة. لم يتم تطبيق تغيير وسم ما لم تُذكر خلاف ذلك.',
  );
  String get mailRuleMoveUp => _t('Move up', 'Nach oben', 'نقل لأعلى');
  String get mailRuleMoveDown => _t('Move down', 'Nach unten', 'نقل لأسفل');
  String get mailRuleDelete =>
      _t('Delete rule', 'Regel löschen', 'حذف القاعدة');
  String get mailRuleEmpty => _t(
    'No rules yet. Add a rule to tag saved mail automatically.',
    'Noch keine Regeln. Fügen Sie eine Regel hinzu, um gespeicherte E-Mails automatisch zu taggen.',
    'لا توجد قواعد بعد. أضف قاعدة لوسم البريد المحفوظ تلقائيًا.',
  );
}

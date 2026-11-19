/// CLD3's 109 output labels, in model order.
const cld3Labels = <String>[
  'eo', 'co', 'eu', 'ta', 'de', 'mt', 'ps', 'te', 'su', 'uz', 'zh-Latn', //
  'ne', 'nl', 'sw', 'sq', 'hmn', 'ja', 'no', 'mn', 'so', 'ko', 'kk', 'sl',
  'ig', 'mr', 'th', 'zu', 'ml', 'hr', 'bs', 'lo', 'sd', 'cy', 'hy', 'uk',
  'pt', 'lv', 'iw', 'cs', 'vi', 'jv', 'be', 'km', 'mk', 'tr', 'fy', 'am',
  'zh', 'da', 'sv', 'fi', 'ht', 'af', 'la', 'id', 'fil', 'sm', 'ca', 'el',
  'ka', 'sr', 'it', 'sk', 'ru', 'ru-Latn', 'bg', 'ny', 'fa', 'haw', 'gl',
  'et', 'ms', 'gd', 'bg-Latn', 'ha', 'is', 'ur', 'mi', 'hi', 'bn',
  'hi-Latn', 'fr', 'yi', 'hu', 'xh', 'my', 'tg', 'ro', 'ar', 'lb',
  'el-Latn', 'st', 'ceb', 'kn', 'az', 'si', 'ky', 'mg', 'en', 'gu', 'es',
  'pl', 'ja-Latn', 'ga', 'lt', 'sn', 'yo', 'pa', 'ku',
];

/// The BCP-47 tag for a CLD3 label. CLD3 keeps a few legacy or
/// non-canonical codes: `iw` (Hebrew, now `he`), `jw` (Javanese in older
/// releases, now `jv`) and `in`/`ji` (old Indonesian/Yiddish codes).
/// Romanized variants (`zh-Latn`, `ru-Latn`, `bg-Latn`, `el-Latn`,
/// `hi-Latn`, `ja-Latn`) stay distinct tags with a script subtag. `no`
/// (Norwegian macrolanguage), `fil`, `haw`, `hmn` and `ceb` are already
/// valid BCP-47 tags and pass through unchanged.
String cld3LabelToLanguage(String label) => switch (label) {
  'iw' => 'he',
  'jw' => 'jv',
  'in' => 'id',
  'ji' => 'yi',
  _ => label,
};

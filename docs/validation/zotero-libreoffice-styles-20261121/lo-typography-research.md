# LibreOffice ODT paragraph typography: bounded import research

Read-only review performed on 2026-11-21. No production files were changed by this review.

## Source identity and conclusion

The source below was fetched from LibreOffice/core at exact commit
`2c87e51eeaa2b413ff4ae097b2705eea1995d8e5`, matching the retained
LibreOfficeDev 26.8 converter build recorded for `native-prose.odt`.

`style:punctuation-wrap="hanging"` and `style:line-break="strict"` cannot be
treated as inert merely because the document contains no Han characters or
because the options appear in an Asian Typography dialog. Their implementation
depends on the effective line-breaking locale. Chinese and Korean hanging
character tables include ASCII punctuation. A conservative content-and-language
guard can establish that these settings do not affect the retained fixture's
current text. This is not an implementation of general CJK typography.

`style:text-autospace="ideograph-alpha"` is separately gated to an Asian/non-Asian
script boundary in Writer. Latin/Arabic transitions alone do not activate it.

## Verified implementation conditions

| Property | ODF import mapping | Runtime behavior |
| --- | --- | --- |
| `punctuation-wrap="hanging"` | Enables `ParaIsHangingPunctuation`. | The CJK break iterator checks its locale-specific hanging-character set. The generic Unicode break iterator ignores this user option. |
| `line-break="strict"` | Enables `ParaIsForbiddenRules`. | The CJK break iterator applies forbidden-line-start/end character rules. The generic Unicode break iterator ignores this user option. |
| `text-autospace="ideograph-alpha"` | Enables `ParaIsCharacterDistance`. | Writer inserts script spacing only across a script change where at least one side is classified `ASIAN`; its current implementation excludes transitions touching Hangul. |

Chinese (`zh_CN`, `zh_TW`) and Korean (`ko_KR`) hanging-character sets are
`!,.:;?、。！，．：；？`. Japanese (`ja_JP`) uses `、。，．`.
Therefore ASCII commas and periods can hang when the CJK iterator is selected.
Writer deliberately looks backward across punctuation at script boundaries to
choose the preceding substantive character's language. The break-iterator
dispatcher selects a service by locale and falls back to the Unicode service.

## Retained fixture inspection

Inspected `/workspace/scratch/d565978da184/lo-fixture/native-prose.odt` without
modification. Its visible text is two paragraphs:

- `Research bold and italic prose.`
- `Second paragraph العربية 😀.`

The used default paragraph text properties specify normal language `en-US`,
complex-script language `hi-IN`, and Asian language `zh-CN`. The Asian language
is a separate unused slot for this text. Used `Standard`/automatic character
styles do not change those language slots. The Latin, Arabic and U+1F600 emoji
content does not contain LibreOffice Asian-script-class characters.

Accordingly, the three properties are inert for the fixture's **current**
content under those resolved languages. This is an inference from the inspected
file and the exact implementation, not a fresh rendered LibreOffice A/B test.

## Conservative importer guard

For a paragraph containing an otherwise-unrepresented active setting, accept
its inert interpretation only after materializing all visible text and resolving
the language cascade:

1. Reject Asian-class text, including relevant historical CJK/fullwidth blocks
   and the Han, Hiragana, Katakana, Hangul, Bopomofo, Yi, Tangut and Khitan scripts.
   Scan Unicode code points, including supplementary planes.
2. For hanging punctuation and strict line breaking, additionally reject
   effective normal or complex-script languages selecting `zh`, `ja` or `ko`.
   Checking the dormant Asian language slot would unnecessarily reject this
   fixture, but conservative rejection of an unused complex CJK slot is safe.
3. Resolve parent/default and inline-language overrides before the check. An
   unresolved ambient/system locale is not proof of a non-CJK locale. An
   explicit conservative refusal is appropriate when this cannot be established.
4. Explicit simple/normal/none settings should retain their own semantics;
   blanket refusal merely because an inactive CJK-related property exists is
   unnecessary.

The guard qualifies current imported content only. Preserving these typography
settings for later insertion or Zotero refresh into CJK text needs native model,
serialization and layout support, or a clearly documented restricted contract.

### Script-classifier cautions

LibreOffice does not use a Han-only test or a pure Unicode Script property.
`i18nutil::GetScriptClass` first applies historical Unicode-block assignments,
then falls back to UAX #24 script classification. In particular, fullwidth
Latin letters and digits and CJK punctuation can be `ASIAN` despite their
Unicode Script being Latin or Common. A conservative superset is safe; an
underapproximation is not. U+1F600 is Common/WEAK and does not itself activate
Asian spacing. Broader rejection of uncertain supplementary blocks is safer
than silently accepting an unrecognized future Asian script.

## Exact primary sources

All links below use the pinned source commit, not a moving branch.

- [ODF paragraph-property mappings: txtprmap.cxx](https://github.com/LibreOffice/core/blob/2c87e51eeaa2b413ff4ae097b2705eea1995d8e5/xmloff/source/text/txtprmap.cxx), lines 456–458. Blob `751b22971af612a29b07fd1a0dc2ef6b028d323b`.
- [ODF token-to-boolean handlers: txtprhdl.cxx](https://github.com/LibreOffice/core/blob/2c87e51eeaa2b413ff4ae097b2705eea1995d8e5/xmloff/source/text/txtprhdl.cxx), lines 1369–1379. Blob `c411fa5be5e33bc0c19f6403e15dcf8ee3cb09fe`.
- [Writer language selection and hanging eligibility: guess.cxx](https://github.com/LibreOffice/core/blob/2c87e51eeaa2b413ff4ae097b2705eea1995d8e5/sw/source/core/text/guess.cxx), lines 668–740. Blob `30ae99df68abfd3120bdd2994e7dd1ec60a08a69`.
- [CJK line-breaking and locale hanging tables: breakiterator_cjk.cxx](https://github.com/LibreOffice/core/blob/2c87e51eeaa2b413ff4ae097b2705eea1995d8e5/i18npool/source/breakiterator/breakiterator_cjk.cxx), lines 50–217. Blob `230f8869976a4eb3271e0a1214c66ad19bbffe1b`.
- [Generic Unicode line breaker: breakiterator_unicode.cxx](https://github.com/LibreOffice/core/blob/2c87e51eeaa2b413ff4ae097b2705eea1995d8e5/i18npool/source/breakiterator/breakiterator_unicode.cxx), `getLineBreak`, lines 474 onward. Its user-options parameter is unused. Blob `cb885bd34a967d4313c4cd4a29caefba6cb568b5`.
- [Locale service dispatch: breakiteratorImpl.cxx](https://github.com/LibreOffice/core/blob/2c87e51eeaa2b413ff4ae097b2705eea1995d8e5/i18npool/source/breakiterator/breakiteratorImpl.cxx), lines 263–267 and 480–561. Blob `aa5e35c837b1c4d017a79057e76112281a1cc6cb`.
- [Writer script-spacing conditions: itrform2.cxx](https://github.com/LibreOffice/core/blob/2c87e51eeaa2b413ff4ae097b2705eea1995d8e5/sw/source/core/text/itrform2.cxx), lines 481–516, 519–575 and 703–720. Blob `8ed468b3d8f2458134b7304e346bb2d9f6798b83`.
- [Historical script classification: scriptclass.cxx](https://github.com/LibreOffice/core/blob/2c87e51eeaa2b413ff4ae097b2705eea1995d8e5/i18nutil/source/utility/scriptclass.cxx), lines 42–140. Blob `843f654ac7d0bbed61a4d60290af3273281350a8`.
- [UAX #24 script-to-class mapping: unicode.cxx](https://github.com/LibreOffice/core/blob/2c87e51eeaa2b413ff4ae097b2705eea1995d8e5/i18nutil/source/utility/unicode.cxx), lines 230–397. Blob `c57903673b2fb1e39372da39752e9ce18cee7207`.
- Locale data: [ja_JP.xml](https://github.com/LibreOffice/core/blob/2c87e51eeaa2b413ff4ae097b2705eea1995d8e5/i18npool/source/localedata/data/ja_JP.xml), blob `81aa087668eadb6044721d90af87b15140146864`; [zh_CN.xml](https://github.com/LibreOffice/core/blob/2c87e51eeaa2b413ff4ae097b2705eea1995d8e5/i18npool/source/localedata/data/zh_CN.xml), blob `589509452c0ec33d3a157c21f1f5246010f5cac8`; [zh_TW.xml](https://github.com/LibreOffice/core/blob/2c87e51eeaa2b413ff4ae097b2705eea1995d8e5/i18npool/source/localedata/data/zh_TW.xml), blob `88fe72944b2112d738150332540eb9af4519cd29`; [ko_KR.xml](https://github.com/LibreOffice/core/blob/2c87e51eeaa2b413ff4ae097b2705eea1995d8e5/i18npool/source/localedata/data/ko_KR.xml), blob `a3df743e0c571f8991b006937f0fec142a71349d`.

The [official Asian Typography help](https://help.libreoffice.org/latest/en-GB/text/shared/01/05020700.html?DbPAR=SHARED)
explains the user controls, but does not specify the complete character sets or
locale dispatch. The source inspection above supplies that distinction.

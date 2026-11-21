# CrispOffice — Mac App Store submission package

App Store Connect app id 6837406661, bundle id `com.crispstrobe.crispoffice`,
category Productivity. Draft prepared 20 November 2026 from the code on
`main`; items marked **owner** need a decision or information only the owner
has. Paste-ready text is in the code blocks.

## 1. Availability and China compliance

- **Recommendation: exclude China mainland** (Pricing and Availability).
  Apple requires an ICP filing number for apps distributed there; none exists.
- Compliance answers (valid either way):
  - *Does your app include features that require a security assessment in
    China mainland?* **No.** No end-to-end encrypted instant messaging; mail is
    standard IMAP/SMTP/EWS/Graph/Gmail API traffic over TLS to the user's own
    providers. No AI-generated content.
  - *Does your app offer AIGC services in China mainland?* **No.** The app
    contains no generative model, chatbot, image/video/voice generation. Its
    local language models (Hunspell, Harper, spaCy, language identification,
    Arabic morphology) only analyse text for spelling and grammar checking.

## 2. Listing text (English, primary)

Name (30): `CrispOffice`

Subtitle (30):
```
Documents, mail and proofing
```

Promotional text (170):
```
Write, check and send in one app: Word, Excel and PowerPoint documents, a mail client, and offline spelling and grammar checking for English, German and Arabic.
```

Description (4000):
```
CrispOffice is an office suite for the Mac that keeps your work on your computer.

DOCUMENTS
• Open, edit and save Word (.docx, legacy .doc), Excel (.xlsx) and PowerPoint (.pptx) files.
• Faithful page layout with headers, footers, footnotes, tables, lists, sections and comments.
• Right-to-left text and mixed Arabic/Latin documents.
• Citations and bibliographies from your Zotero library.
• Run VBA-style macros on documents.

PROOFING, OFFLINE
• Spelling for many languages using Hunspell dictionaries you choose in the Downloads manager.
• English grammar and style checking.
• German grammar: agreement, case after prepositions and verb position.
• Arabic: hamza and ta marbuta spelling, verb mood and number–gender agreement, with context-aware word analysis.
• Automatic language detection per paragraph.
• All checking runs on your Mac. Your text is never sent to a server.

MAIL
• Connect your existing accounts (IMAP/SMTP, Microsoft 365, Exchange, Gmail).
• Read, write, reply and forward with attachments; work offline with a local outbox.
• Passwords are kept in the macOS keychain.

PRIVACY
CrispOffice has no tracking, no analytics and no account with us. Language packs are downloaded only when you choose them; mail goes directly between your Mac and your mail provider.
```

Keywords (100, comma-separated, no spaces):
```
word,docx,excel,xlsx,powerpoint,pptx,spell checker,grammar,arabic,german,mail,email,office,zotero
```
(Check the length in App Store Connect; drop `zotero` first if over 100.)

What's New (first version): `First release.`

## 3. Listing text (German, optional localization)

Subtitle: `Dokumente, Mail und Korrektur`

Promotional text:
```
Schreiben, prüfen und senden in einer App: Word-, Excel- und PowerPoint-Dokumente, ein Mailprogramm und Rechtschreib- und Grammatikprüfung offline für Deutsch, Englisch und Arabisch.
```

Description: translate section 2 when the English text is approved (**owner**:
include German and Arabic localizations?).

## 4. URLs and contact

- Support URL: `https://www.crispstro.be/en/apps/crispoffice/` (app page with
  a Support section: e-mail, GitHub issues, privacy link; German page
  `/de/apps/crispoffice/`).
- Marketing URL (optional): the same app page.
- Privacy Policy URL: `https://www.crispstro.be/en/crispoffice-privacy/`
  (German: `https://www.crispstro.be/de/crispoffice-datenschutz/`). The app's
  About dialog links it (guideline 5.1.1), alongside the provider and contact
  details that every CrispStrobe app shows there.
- Copyright: **owner** (e.g. `2026 Christian Ströbele`).
- Review contact name, phone and email: entered in App Store Connect only.

## 5. App Privacy ("nutrition label")

Answer **"No, we do not collect data from this app."** Basis in the code:

- No analytics, crash reporting, advertising or tracking SDK in the app or its
  packages (no Firebase, Sentry, Crashlytics or similar).
- No developer server. Network destinations are the user's own mail providers
  (including Microsoft Graph and the Gmail API when the user adds such
  accounts), Hugging Face for language packs the user chooses to download,
  and Zotero when the user connects it.
- Mail data, documents and credentials stay on the device; credentials are in
  the keychain or an AES-256-GCM vault in the app container.

Apple counts data as "collected" only when it leaves the device to the
developer or to third-party partners integrated in the app. Downloads from a
public file host and traffic to the user's own providers do not count.
Revisit this section whenever telemetry, sync or a relay is added.

## 6. Privacy policy (draft, host publicly)

```
CrispOffice Privacy Policy

CrispOffice does not collect, store or share personal data. There is no user account, analytics, advertising or tracking.

Documents you open stay on your Mac. Spelling and grammar checking runs entirely on your Mac.

When you add a mail account, CrispOffice connects directly from your Mac to that mail provider. Your mail, addresses and attachments are stored only on your Mac and with your provider. Passwords and tokens are stored in the macOS keychain or in encrypted form in the app's container.

When you choose to download a dictionary or language model, CrispOffice fetches it from a public file host (Hugging Face). That host receives the request as for any download; CrispOffice sends no personal data with it.

If you connect Zotero, CrispOffice reads your library through Zotero to insert citations.

You can remove all local data by deleting the app and its container (~/Library/Containers/com.crispstrobe.crispoffice).

Contact: <support address>
```

## 7. Age rating (as submitted 20 November 2026)

Step 1, in-app controls and capabilities:

| Question | Answer | Basis |
|---|---|---|
| Parental Controls | No | none in the app |
| Age Assurance | No | none in the app |
| Unrestricted Web Access | No | links open in the user's browser; HTML mail is converted to static styled text (`quds_mail_ui` reader presentation), nothing loads remotely |
| User-Generated Content | No | nothing users create is distributed through the app |
| Social Media | No | no feed or publishing |
| Social Media Disabled for Users Under 13 | No | not applicable |
| Messaging and Chat | **Yes** | the mail client lets users write to other people |
| Shared Location | No | |
| Advertising | No | |

Content steps: **None / No** throughout (profanity, horror, alcohol/drugs,
dating, violence, sexual content, gambling, contests, medical). User documents
and mail are not app content.

Result: **4+** calculated; age category **Not Applicable** (not Made for Kids),
no override, no age suitability URL.

## 8. Export compliance (encryption)

The app uses only standard cryptography:

- TLS for all network traffic (Dart's built-in TLS, not only Apple's APIs).
- AES-256-GCM with PBKDF2-HMAC-SHA256 (pointycastle) to protect stored
  credentials locally.
- NTLM/HMAC for Exchange authentication.
- No proprietary algorithms, no end-to-end messaging encryption, no S/MIME or
  OpenPGP yet.

App Store Connect answers:

1. *Type of encryption:* **Standard encryption algorithms instead of, or in
   addition to, using or accessing the encryption within Apple's operating
   system.**
2. The follow-up asks about distribution in France. Standard-algorithm,
   mass-market software normally needs no French declaration, but App Store
   Connect may still request documentation. **Owner**: answer as presented;
   if it asks for a document, stop and decide whether to exclude France or
   file it.

Once the determination is accepted, set `ITSAppUsesNonExemptEncryption` in
`Runner/Info.plist` to match, so later uploads skip the question. Re-check
when S/MIME or OpenPGP is added.

## 9. Notes for the reviewer

```
CrispOffice is an offline office suite (documents, mail, proofing). No account is needed.

To try proofing: open the Downloads manager (toolbar), install "English (US)" spelling and the English grammar pack, then type in a new document; misspellings are underlined after a short pause.

Mail requires the reviewer's own IMAP/SMTP account; the app works fully without one.

Entitlements: network.client for mail and pack downloads; network.server only for the OAuth sign-in redirect listener bound to 127.0.0.1 on a random port (Microsoft 365 and Gmail accounts); user-selected read-write and app-scoped bookmarks to reopen documents the user picked.
```
(`network.server`: the only listener in the code is the OAuth loopback in
`quds_mail_transport` `cloud/native/authorization.dart`.)

## 10. Screenshots

Mac App Store: 1 to 10 screenshots, 16:10, one of 1280×800, 1440×900,
2560×1600 or 2880×1800. Planned set, rendered on GitHub Actions (no GUI
automation on a personal machine), 2880×1800:

1. Word document with mixed English/Arabic text and proofing underlines.
2. German grammar suggestion popover ("Die Katzen auf dem Sofa schläft").
3. Excel workbook.
4. PowerPoint slide editing.
5. Mail reader with a message and attachment.
6. Downloads manager with language packs.

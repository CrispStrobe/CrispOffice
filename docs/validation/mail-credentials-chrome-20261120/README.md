# Mail credentials, chrome and reader continuation

The reported save warning was reproducible from the running local build's
signature: it was ad hoc, without a team or application identity, while the
original Mail store unconditionally used the Data Protection keychain. The
standalone host now uses CrispCloud's pre-read capability detection and its
explicit OS/custom-keychain/encrypted-vault/session store design. Failed selected
stores never redirect credential writes elsewhere. Secret values never enter
preferences, source control or diagnostics.

Mail's Credential storage dialog selects the backend; a vault must be created or
unlocked explicitly. Keychain Browse grants scoped access to the selected file.
The native scoped adapter and transactional AES-256-GCM/PBKDF2 vault were ported
from CrispCloud 4ee4eef5; provenance and adaptations are recorded alongside them.
The local build wrapper signs with a persistent development identity and stable
team/bundle requirement, including Debug's companion dylibs and entitlements.
Existing native proofing libraries, notices and spaCy code qualification remain
part of the build.

The account repository stores independently keyed accounts in its selected
secure backend. Setup offers saved-account selection and Add account. Forget
removes the active account while preserving others. Version-one records in the
selected store are retained until a verified version-two write succeeds. The
foreground IMAP/SMTP session still connects one account at a time; simultaneous
multi-account background synchronization is outside this continuation. A failed
save leaves the working connection available and offers Retry saving account.
Selecting another store does not automatically migrate existing accounts.

Mail is pushed as a workspace route with the existing shared title bar, native
traffic-light spacing, selected Mail switcher, and return routes to the other
four modes. Its File/Mail/View menus expose Mail actions, store selection and
saved messages. The account and settings GlobalKeys remain exclusive to the
underlying workspace. The hidden document retains its state.

The reader uses explicit surface/text/link/error color pairs, and its bounded
scroll viewport is a repaint boundary. Scrolling tests preserve the existing
reader render object and offset. This narrows repaint propagation; the reported
physical-device flicker still requires live acceptance before claiming it is
fully resolved.

Validation so far:

- 97 account/setup/storage/theme tests passed, including real encrypted-vault
  round trips, wrong-password byte preservation, independent accounts and failed
  writes. Later Retry UI changes receive a final host regression pass.
- 18 reader/controller tests passed, including light/dark contrast greater than
  4.5:1, bounded reader repaint isolation and synthetic pointer-wheel scrolling.
- Three credential-selection tests passed: session records never enter
  preferences, failed custom selection preserves the previous store, and the
  local file-keychain probe verifies read-back then deletes its own sentinel.
- The shared-chrome Mac widget test passed after allowing the actual route
  transition to finish. Mail is selected, traffic-light spacing is present, no
  duplicate GlobalKeys occur and closing returns to the Word editor.
- The native scoped keychain suite passed on temporary keychains: creation,
  namespace, collision/update behavior, missing/locked paths, bookmark recovery
  and unchanged user default/search-list settings.
- Targeted Dart analysis reports no errors or warnings (style infos in ported
  sources are retained separately). Shell syntax checks pass.

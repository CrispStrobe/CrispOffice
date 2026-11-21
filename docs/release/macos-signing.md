# macOS signing and release (CrispOffice)

How the Studio macOS app (`packages/quds_office_editor/example`, Dart package
`quds_office_studio`, product and bundle `CrispOffice.app`, bundle id
`com.crispstrobe.crispoffice`) is signed for the Mac App Store and
for direct download, and how the spaCy grammar qualification survives
re-signing. Private values (team, key and certificate identifiers, keychain
passwords, contact data) are deliberately not recorded here; they live in the
maintainer's private release notes and in repository secrets referenced by
name below.

## Build modes

`packages/quds_office_editor/example/tool/build_macos_app.sh [--sign MODE]
[--rebuild-spacy] [flutter build arguments]`

| Mode | Identity | Output | Bundle id |
|------|----------|--------|-----------|
| `adhoc` (default) | ad hoc (`-`) | `build/macos/Build/Products/Release/CrispOffice.app` | `com.crispstrobe.crispoffice` |
| `appstore` | Apple Distribution + Mac Installer Distribution | `build/macos/signed/CrispOffice.app` and `CrispOffice-<version>-<build>.pkg` | `com.crispstrobe.crispoffice` |
| `developer-id` | Developer ID Application | notarized, stapled `build/macos/signed/CrispOffice.app` and `CrispOffice-<version>-<build>-macos.zip` | `com.crispstrobe.crispoffice` |

Every mode builds the same native libraries and installs the same pinned
spaCy library. Signed modes copy the built app to `QUDS_SIGN_OUTPUT`
(default `build/macos/signed`), name it `CrispOffice.app` (or
`QUDS_APP_NAME`), set the bundle id (`QUDS_BUNDLE_ID`, same default as the
Xcode project),
embed the provisioning profile and sign inside out: each dylib, each
framework, then the app with `Release.entitlements` plus
`com.apple.application-identifier`, `com.apple.developer.team-identifier` and
`keychain-access-groups` (`TEAM_ID.<bundle id>`) taken from the profile.
Hardened runtime and secure timestamps are on in both
signed modes; App Sandbox stays on in every mode.

### Keychain access group (Touch ID vault unlock)

Touch ID unlock of the encrypted credential vault keeps the vault key in the
data protection keychain, which needs a team-signed, profile-backed build. The
keychain group is therefore added only by the signed modes above (Mac App
Store and Developer ID profiles authorize `keychain-access-groups: TEAM_ID.*`).
It is deliberately not in `Runner/*.entitlements`:

- Xcode refuses to build the default ad hoc ("Sign to Run Locally")
  configuration with it ("Runner has entitlements that require signing with a
  development certificate"), which would break every `flutter build macos`;
- macOS kills an app that claims a keychain group without an embedded
  provisioning profile (measured on macOS 26 for ad hoc and for Apple
  Development signatures), so `build_macos_local.sh` and the ad hoc CI
  workflow must not add it either.

Ad hoc and profile-less builds get errSecMissingEntitlement (-34018) from the
data protection keychain; the app detects this with a write probe and hides
Touch ID unlock with an explanation. To try Touch ID from Xcode, select a
development team for the Runner target and add the Keychain Sharing
capability locally (Xcode then provisions a development profile); do not
commit that change.

Pass `--build-name X.Y.Z --build-number N` through to Flutter for releases. App
Store Connect rejects a repeated `CFBundleVersion` and a repeated
`CFBundleShortVersionString` after a version has been released.

### Environment

| Variable | Modes | Meaning |
|----------|-------|---------|
| `QUDS_PROVISIONING_PROFILE` | signed | Path to the Mac App Store profile (appstore) or Developer ID profile (developer-id) for the bundle id. Required: the data-protection keychain used for mail credentials needs the application identifier, which only a profile authorizes. The script checks that the profile names this bundle id and includes the signing certificate. |
| `QUDS_SIGN_IDENTITY` | signed | SHA-1 or full name of the code-signing identity. Default: the single valid `Apple Distribution: …` / `Developer ID Application: …` identity on the keychain search list (the script fails when there are several). |
| `QUDS_INSTALLER_IDENTITY` | appstore | SHA-1 or full name of the installer identity (`3rd Party Mac Developer Installer: …` / `Mac Installer Distribution: …`). Set it when several are listed; a stale one in the login keychain is a common cause of ambiguity. |
| `QUDS_SIGN_KEYCHAIN` | signed | Limit identity lookup to this keychain (it must also be on the user search list; `codesign` searches only there). |
| `QUDS_BUNDLE_ID` | signed | Default `com.crispstrobe.crispoffice` (the Xcode project's id; override only for a differently registered id). |
| `QUDS_APP_NAME` | signed | Default `CrispOffice` (name of the signed `.app` and its archives). |
| `QUDS_SIGN_OUTPUT` | signed | Output directory. |
| `QUDS_NOTARY_KEY`, `QUDS_NOTARY_KEY_ID`, `QUDS_NOTARY_ISSUER` | developer-id | App Store Connect API key file (`.p8`), key id and issuer id for `notarytool`. |
| `QUDS_NOTARIZE=0` | developer-id | Sign only; skip notarization and stapling. |

## spaCy qualification across signatures

The manual German grammar provider is qualified for one exact build of
`libcrispembed-spacy.dylib` (macOS arm64, ad hoc signed, SHA-256
`ccc96620…1b40f`, Hub revision `2aa70083…`). A release signature rewrites the
end of the file, so the file digest necessarily changes. The scheme keeps the
qualification bound to the code that was qualified, not to a signature:

1. **Code identity.** `machOCodeSha256` (`quds_proofing_spacy`,
   `lib/src/macho_code_identity.dart`) is SHA-256 over the file prefix up to
   the code signature (`LC_CODE_SIGNATURE.dataoff`) with exactly three fields
   zeroed: the signature's `datasize` and the `__LINKEDIT` `vmsize` and
   `filesize`. Everything dyld maps, binds or executes is covered. A file is
   rejected (no code identity) unless it is a thin 64-bit Mach-O with one
   signature that ends the file and one `__LINKEDIT` that ends with it, so
   nothing can hide behind the mask. Measured: the ad hoc qualified file, an
   Apple Distribution copy and a Developer ID copy (with secure timestamp) all
   give `f2022b1c…07efeb`; changing one code byte changes it.
2. **Apple's tool agrees.** `codesign --remove-signature` of the qualified file
   and of every re-signed copy yields identical bytes (with Xcode 26: 2,300,136
   bytes, SHA-256 `f62d2a0c…886ed2`). Older codesign does not normalize: on
   the Xcode 16 CI runner neither ad hoc re-signing nor
   `--remove-signature` reproduces these bytes, while the code digest is
   unchanged. That is why the code digest, not a file digest, is the identity.
3. **Build-time proof.** `build_macos_app.sh` checks the code digest of the
   pinned input before signing (after verifying its SHA-256 and length) and of
   the signed output, and refuses to record the library as qualified
   otherwise. When the local codesign strips the pinned input to the
   reference above, it additionally requires the signed output to strip to
   the same bytes. Ad hoc builds do not re-sign the pinned library at all;
   they ship its exact qualified bytes. It writes `sha256` and `code_sha256` into
   `Contents/Resources/spacy-native.json`, which the app signature seals.
4. **Runtime proof.** For a host-bundled library the native backend reads the
   file once, verifies its SHA-256 and computes `machOCodeSha256` from the same
   bytes; the result travels in `SpacyBackendIdentity.codeSha256`. The grammar
   planner accepts an exact qualified library digest
   (`spacyGrammarNativeSha256s`) or a measured code digest in
   `spacyGrammarCodeSha256s`; it never reads `spacy-native.json`. Studio uses
   the recorded `code_sha256` only to display the qualification
   (`spacyQualificationForHostBundled`). Downloaded packages stay bound to
   their exact bytes; unknown code, a missing code digest, or a different
   capability profile is still refused.

With the hardened runtime, library validation additionally requires every
loaded library to carry the app's team signature, so the re-signed library is
also the only one the signed app can load.

The other bundled libraries (Hunspell, Arabic morphology, CLD3 language ID,
Harper) are built from source, checked against their build receipts before
installation and loaded by path; no runtime digest is pinned to their signed
bytes. The CLD3 model and other assets are data inside the sealed bundle and
are not changed by signing.

## Minimum macOS

CrispOffice requires macOS 13 (Ventura) or newer: `MACOSX_DEPLOYMENT_TARGET`
in the Runner project, the Podfile platform and therefore
`LSMinimumSystemVersion` are 13.0. The bundled spaCy library is built for
macOS 13; the other native libraries pin a lower target (10.15 requested,
11.0 effective on Apple silicon).

`build_macos_app.sh` checks every bundled library with `vtool -show-build`
and fails when a library's `minos` exceeds the app's `LSMinimumSystemVersion`.
A native build that does not pin its deployment target inherits the host
SDK's version (the Hunspell library built with Xcode 26 declared macOS 26 and
would not have loaded on any older system); the check prevents that from
shipping.

## Data location after the bundle id change

A sandboxed app's data lives in `~/Library/Containers/<bundle id>`. Every
build, ad hoc and release-signed, now uses `com.crispstrobe.crispoffice`;
builds made before the CrispOffice rename used `com.quds.qudsOfficeStudio`
and the product name `quds_office_studio.app`. The app is unreleased, so there
is no automatic migration: a new build starts with an empty container.
Spelling dictionaries, the Arabic morphology database and the spaCy model
files are verified downloads; install them again from the app (Review ›
Proofing › Dictionaries and language data, Review › Analysis setup). Saved
mail accounts are keychain items owned by the old app's identity and must be
entered again; the old items stay in the keychain until removed with Keychain
Access. Ribbon preferences, the local Mail archive and saved drafts also live
in the old container, but use two different support directories. Proofing and
ribbon preferences use `quds_office_studio`. Mail uses the platform support
directory, to which the pinned `path_provider_foundation` appends the bundle
id, followed by `quds_mail` (drafts) or `quds_mail_archive` (archive).

To keep existing test data, quit both apps and copy both support directories
once, before creating local Mail data in the new app (macOS may ask to allow
Terminal access to another app's data). If the new app already contains drafts
or an archive, preserve both copies before attempting a migration; these
commands are for an empty destination, not a database merge:

```bash
ditto "$HOME/Library/Containers/com.quds.qudsOfficeStudio/Data/Library/Application Support/quds_office_studio" "$HOME/Library/Containers/com.crispstrobe.crispoffice/Data/Library/Application Support/quds_office_studio"
ditto "$HOME/Library/Containers/com.quds.qudsOfficeStudio/Data/Library/Application Support/com.quds.qudsOfficeStudio" "$HOME/Library/Containers/com.crispstrobe.crispoffice/Data/Library/Application Support/com.crispstrobe.crispoffice"
```

Copy a source directory only if it exists. Copying `quds_office_studio` alone
does **not** migrate the Mail archive or draft database. Keep each complete
Mail directory together, including any SQLite sidecar files; reconnect with
the same provider/account identity to recover its draft. This does not move
keychain credentials or enable access to the old keychain identity.

The proofing data folder name inside the container (`quds_office_studio`) is
an internal identifier and is unchanged. Point `QUDS_STUDIO_DATA` of the gate
tests at `~/Library/Containers/com.crispstrobe.crispoffice/Data/Library/Application Support/quds_office_studio`
or at a scratch directory.

The same applies on the other platforms: iOS uses the bundle id
`com.crispstrobe.crispoffice` and Android the application id
`com.crispstrobe.crispoffice` (previously `com.quds.qudsOfficeStudio` and
`com.quds.quds_office_studio`), so they install as a new app beside an older
development build, with their own data and keychain/keystore entries.

## Mac App Store procedure

1. Prerequisites (one-time): the bundle id `com.crispstrobe.crispoffice` is
   registered and a Mac App Store provisioning profile exists for it, issued
   against the account's single shared Apple Distribution certificate (never
   create another one; the account caps certificates). The Apple Distribution
   and Mac Installer Distribution identities must be in a keychain on the
   search list.
2. Build: `QUDS_PROVISIONING_PROFILE=<profile> QUDS_INSTALLER_IDENTITY=<sha1>
   tool/build_macos_app.sh --sign appstore --build-name X.Y.Z --build-number N`.
3. Verify: the script runs `codesign --verify --deep --strict` and
   `pkgutil --check-signature`. Then, once the App Store Connect app record
   exists: `xcrun altool --validate-app -f <pkg> --type macos --apiKey <id>
   --apiIssuer <issuer>` (camelCase flags work on old and new Xcode; altool
   finds the `.p8` only as `AuthKey_<id>.p8` in `~/.appstoreconnect/private_keys`
   or `~/.private_keys`).
4. Upload (`altool --upload-package … --type macos --apple-id <numeric app
   id>`), TestFlight and review submission are deliberate human release
   decisions; nothing in this repository uploads automatically.

## Developer ID procedure

1. Prerequisites: the Developer ID Application identity (reuse the account's
   existing certificate and key; do not create a new certificate) in a
   keychain on the search list, a Developer ID (`MAC_APP_DIRECT`) provisioning
   profile for the bundle id, and an App Store Connect API key for notarytool.
2. Build: `QUDS_PROVISIONING_PROFILE=<profile> QUDS_NOTARY_KEY=<p8>
   QUDS_NOTARY_KEY_ID=<id> QUDS_NOTARY_ISSUER=<issuer>
   tool/build_macos_app.sh --sign developer-id --build-name X.Y.Z
   --build-number N`.
3. The script submits a zip with `notarytool submit --wait`, fails with the
   notary log on anything but `Accepted`, staples the ticket, runs
   `stapler validate` and `spctl --assess --type execute`, and zips the
   stapled app for distribution.

## Keychain notes

- A headless shell cannot answer keychain prompts. If `codesign` fails with
  `errSecInternalComponent`, the private key's access list needs a one-time
  human `security unlock-keychain` / `security set-key-partition-list` with the
  keychain password. Prefer a dedicated build keychain with a known password
  over the login keychain.
- An identity present in two keychains with the same name makes name-based
  `codesign -s` ambiguous; the script signs by SHA-1 and fails on ambiguous
  defaults instead of guessing.

## CI

`.github/workflows/macos-app-weekly.yml` builds the ad hoc app on a clean
macOS arm64 runner every Monday (and on manual dispatch), runs both bundle
gates against it with a scratch data directory, runs `dart analyze packages
apps` and uploads logs (not the app).

Manual dispatch with `sign=appstore` or `sign=developer-id` additionally runs
the `signed` job, which needs these repository secrets:

| Secret | Used for |
|--------|----------|
| `DIST_CERT_P12_BASE64`, `DIST_CERT_PASSWORD` | base64 `.p12` holding the Apple Distribution and Mac Installer Distribution identities (appstore) |
| `MAC_PROFILE_BASE64` | base64 Mac App Store provisioning profile (appstore) |
| `MACOS_DEVELOPER_ID_P12_BASE64`, `MACOS_DEVELOPER_ID_P12_PASSWORD` | base64 `.p12` with the Developer ID Application identity (developer-id) |
| `MACOS_DEVELOPER_ID_PROFILE_BASE64` | base64 Developer ID provisioning profile (developer-id) |
| `ASC_API_KEY_P8_BASE64`, `ASC_KEY_ID`, `ASC_ISSUER_ID` | App Store Connect API key for notarization (developer-id) |

The job imports them into a temporary keychain, builds with `--build-number`
set to the run number, verifies, uploads the `.pkg` or notarized zip as a
seven-day workflow artifact and deletes the keychain. It never uploads to App
Store Connect.

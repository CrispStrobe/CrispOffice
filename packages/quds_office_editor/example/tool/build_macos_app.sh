#!/usr/bin/env bash
# Build the Studio macOS release app with its native proofing libraries.
#
#   packages/quds_office_editor/example/tool/build_macos_app.sh
#
# 1. builds the pinned native libraries (Hunspell, Arabic morphology, CLD3
#    language ID, unless QUDS_SKIP_HARPER=1 Harper for English, and unless
#    QUDS_SKIP_SPACY=1 the CrispEmbed spaCy analysis runtime) with each
#    package's tool/build.py;
# 2. checks the bundled CLD3 model against its pin;
# 3. runs `flutter build macos --release`;
# 4. installs the receipt-verified libraries into Contents/Frameworks (where
#    the Studio hosts look for them) and their notices into Contents/Resources;
# 5. signs (each library and framework, then the app with
#    Release.entitlements), records the signed spaCy library's digest and its
#    signature-independent code digest in Contents/Resources/spacy-native.json
#    (sealed by the app signature) and verifies the signature, the
#    libraries' load commands and that each library opens from inside the
#    bundle.
#
# Signing modes (`--sign MODE`, default adhoc; release procedure and every
# variable: docs/release/macos-signing.md):
#
#   adhoc         ad hoc signature on the Flutter build product, as before.
#   appstore      Apple Distribution identity, hardened runtime, App Sandbox,
#                 application/team identifier from the Mac App Store profile
#                 (QUDS_PROVISIONING_PROFILE, embedded), bundle id
#                 QUDS_BUNDLE_ID (default com.crispstrobe.crispoffice), and a
#                 .pkg signed with the Mac Installer Distribution identity.
#                 Nothing is uploaded.
#   developer-id  Developer ID Application identity, hardened runtime,
#                 secure timestamp, the Developer ID profile, then (unless
#                 QUDS_NOTARIZE=0) notarytool submit --wait with an App Store
#                 Connect API key, stapler staple and a Gatekeeper check.
#
# Signed modes copy the app to $QUDS_SIGN_OUTPUT/CrispOffice.app (default
# build/macos/signed) and sign that copy. The Flutter product is already
# CrispOffice.app with bundle id com.crispstrobe.crispoffice; QUDS_APP_NAME
# and QUDS_BUNDLE_ID override them for the signed copy only.
#
# Release signing changes the spaCy library's file bytes, so its grammar
# qualification is carried by code identity rather than by file digest: the
# script requires the shipped library's machOCodeSha256 to equal
# SPACY_PIN_CODE_SHA256 before and after signing. Where the local codesign
# strips the pinned input to SPACY_PIN_UNSIGNED_SHA256 (Xcode 26), it also
# requires `codesign --remove-signature` of the signed library to equal that
# byte for byte; Xcode 16 does not normalize stripping, so there only the
# code digest applies. Ad hoc builds ship the pinned bytes unchanged. Studio
# re-measures the code digest from the bytes it loads.
#
# The spaCy library is not rebuilt by default: the script downloads the exact
# ad hoc signed bytes whose analysis and manual German grammar were qualified
# (quds_proofing_spacy `spacyGrammarMacosBundledSha256`) from an immutable
# Hugging Face revision and verifies their SHA-256 and length before
# installing them. `--rebuild-spacy` builds it from source with
# quds_proofing_spacy/tool/build.py instead; that build is reproducible, but a
# different toolchain yields different bytes, which Studio treats as an
# unqualified build (analysis only, no grammar suggestions).
#
# Flutter 3.47.8 or newer must be on PATH. Rust/Cargo is needed only for
# Harper, CMake and Git only for spaCy. Cargo's build directory defaults to
# $HOME/.cache/shared-cargo-target (override with CARGO_TARGET_DIR).
set -euo pipefail

# Cargo must not depend on temporary state: a CARGO_HOME (or ~/.cargo link)
# that is missing or lives under /tmp is replaced by a persistent cache for
# this build. Toolchains are not touched; an explicit CARGO_HOME outside
# /tmp is kept.
export CARGO_TARGET_DIR="${CARGO_TARGET_DIR:-$HOME/.cache/shared-cargo-target}"
cargo_home="${CARGO_HOME:-$HOME/.cargo}"
cargo_home_real="$(cd "$cargo_home" 2>/dev/null && pwd -P || true)"
case "$cargo_home_real" in
  ''|/tmp/*|/private/tmp/*|/var/folders/*|/private/var/folders/*)
    export CARGO_HOME="$HOME/.cache/quds-cargo-home"
    mkdir -p "$CARGO_HOME"
    ;;
esac

EXAMPLE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PACKAGES="$(cd "$EXAMPLE/../.." && pwd)"
JOBS="${QUDS_BUILD_JOBS:-4}"
BUILD_MODE="${QUDS_BUILD_MODE:-release}"
case "$BUILD_MODE" in
  debug) BUILD_CONFIGURATION=Debug ;;
  profile) BUILD_CONFIGURATION=Profile ;;
  release) BUILD_CONFIGURATION=Release ;;
  *) echo "QUDS_BUILD_MODE must be debug, profile or release" >&2; exit 64 ;;
esac
APP="$EXAMPLE/build/macos/Build/Products/$BUILD_CONFIGURATION/CrispOffice.app"
while IFS= read -r executable; do
  [[ "$executable" != "$APP/Contents/MacOS/CrispOffice" ]] || {
    echo "Preserve the running workspace; build from a separate checkout." >&2; exit 1;
  }
done < <(ps -axo comm=)

log() { printf '\n== %s\n' "$*"; }

# Qualified app-bundled spaCy library (see the header). Keep in sync with
# spacyGrammarMacosBundledSha256; a Studio test checks both pins.
SPACY_PIN_REPOSITORY=cstr/crispembed-spacy-de-core-news-sm-3.8.0
SPACY_PIN_REVISION=2aa70083055073adf8d2ffbb0ff203cc4fcafd7e
SPACY_PIN_SHA256=ccc96620e01164d18e8d2e46b9a383677e4430c8889833bedab5b56c16a1b40f
SPACY_PIN_BYTES=2322928
SPACY_PIN_PATH="app-bundled/macos-arm64/$SPACY_PIN_SHA256/libcrispembed-spacy.dylib"
# Signature-independent identity of the same qualified code (see the header);
# keep in sync with spacyGrammarMacosBundledCodeSha256 and (informational,
# Xcode 26 codesign) spacyGrammarMacosBundledUnsignedSha256.
SPACY_PIN_CODE_SHA256=f2022b1cf75d831cddbd047eec5f5ac759728fee169ed2b5b785ecda1a07efeb
SPACY_PIN_UNSIGNED_SHA256=f62d2a0cf457a0ac577f45eceba93d8d5f2f450d4fd5a191f0cec61d88886ed2

REBUILD_SPACY=0
SIGN_MODE=adhoc
FLUTTER_ARGS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --rebuild-spacy) REBUILD_SPACY=1 ;;
    --sign) SIGN_MODE="${2:-}"; shift ;;
    --sign=*) SIGN_MODE="${1#--sign=}" ;;
    *) FLUTTER_ARGS+=("$1") ;;
  esac
  shift
done
case "$SIGN_MODE" in
  adhoc|appstore|developer-id) ;;
  *) echo "--sign must be adhoc, appstore or developer-id" >&2; exit 64 ;;
esac

# Downloads the pinned library once into the build directory and verifies
# its digest and length; prints its path.
fetch_pinned_spacy() {
  local dir="$EXAMPLE/build/spacy-pinned/$SPACY_PIN_SHA256"
  local file="$dir/libcrispembed-spacy.dylib"
  if [[ ! -f "$file" ]] || [[ "$(shasum -a 256 "$file" | awk '{print $1}')" != "$SPACY_PIN_SHA256" ]]; then
    mkdir -p "$dir"
    curl -fsSL --retry 3 -o "$file.part" \
      "https://huggingface.co/$SPACY_PIN_REPOSITORY/resolve/$SPACY_PIN_REVISION/$SPACY_PIN_PATH"
    mv "$file.part" "$file"
  fi
  local digest size
  digest="$(shasum -a 256 "$file" | awk '{print $1}')"
  size="$(wc -c <"$file" | tr -d ' ')"
  if [[ "$digest" != "$SPACY_PIN_SHA256" || "$size" != "$SPACY_PIN_BYTES" ]]; then
    rm -f "$file"
    echo "pinned spaCy library failed verification ($digest, $size bytes)" >&2
    return 1
  fi
  printf '%s\n' "$file"
}

# SHA-256 of a Mach-O after `codesign --remove-signature` (on a copy).
unsigned_sha256() {
  local copy
  copy="$(mktemp -d)/$(basename "$1")"
  cp "$1" "$copy"
  codesign --remove-signature "$copy"
  shasum -a 256 "$copy" | awk '{print $1}'
  rm -rf "$(dirname "$copy")"
}

# machOCodeSha256 (quds_proofing_spacy), the digest Studio measures at load.
code_sha256() {
  (cd "$PACKAGES/quds_proofing_spacy" && dart run tool/macho_code_digest.dart "$1")
}

# Prints the SHA-1 of the one valid identity whose name starts with $2
# (alternatives separated by |; policy $1: codesigning or basic), or of $3
# when given (a SHA-1 or a full name). Fails when none or several distinct
# identities match. QUDS_SIGN_KEYCHAIN limits the search to one keychain,
# which must also be on the user search list (codesign looks only there).
resolve_identity() {
  local policy="$1" prefix="$2" wanted="${3:-}" listing matches
  listing="$(security find-identity -v ${policy:+-p "$policy"} ${QUDS_SIGN_KEYCHAIN:+"$QUDS_SIGN_KEYCHAIN"} \
    | awk '/^ *[0-9]+\)/ {sha=$2; $1=""; $2=""; sub(/^ +/, ""); gsub(/"/, ""); print sha "\t" $0}' | sort -u)"
  if [[ "$wanted" =~ ^[0-9A-Fa-f]{40}$ ]]; then
    matches="$(awk -F'\t' -v w="$(tr a-f A-F <<<"$wanted")" '$1 == w' <<<"$listing")"
  elif [[ -n "$wanted" ]]; then
    matches="$(awk -F'\t' -v w="$wanted" '$2 == w' <<<"$listing")"
  else
    matches="$(awk -F'\t' -v p="$prefix" \
      '{ n = split(p, ps, "|"); for (i = 1; i <= n; i++) if (index($2, ps[i]) == 1) { print; next } }' <<<"$listing")"
  fi
  if [[ -z "$matches" ]]; then
    echo "no valid signing identity ${wanted:-$prefix*} in the keychain search list" >&2
    return 1
  fi
  if [[ "$(wc -l <<<"$matches" | tr -d ' ')" != 1 ]]; then
    echo "several identities match ${wanted:-$prefix*}; choose one by SHA-1:" >&2
    echo "$matches" >&2
    return 1
  fi
  cut -f1 <<<"$matches"
}

[[ "$(uname -s)" == Darwin ]] || { echo "macOS only" >&2; exit 1; }

if [[ "$SIGN_MODE" != adhoc ]]; then
  log "Signing setup ($SIGN_MODE)"
  BUNDLE_ID="${QUDS_BUNDLE_ID:-com.crispstrobe.crispoffice}"
  SIGN_OUTPUT="${QUDS_SIGN_OUTPUT:-$EXAMPLE/build/macos/signed}"
  PROFILE="${QUDS_PROVISIONING_PROFILE:-}"
  [[ -f "$PROFILE" ]] || { echo "QUDS_PROVISIONING_PROFILE must name the $SIGN_MODE provisioning profile" >&2; exit 64; }
  if [[ "$SIGN_MODE" == appstore ]]; then
    SIGN_IDENTITY="$(resolve_identity codesigning "Apple Distribution: " "${QUDS_SIGN_IDENTITY:-}")"
    INSTALLER_IDENTITY="$(resolve_identity basic \
      "3rd Party Mac Developer Installer: |Mac Installer Distribution: " "${QUDS_INSTALLER_IDENTITY:-}")"
  else
    SIGN_IDENTITY="$(resolve_identity codesigning "Developer ID Application: " "${QUDS_SIGN_IDENTITY:-}")"
    if [[ "${QUDS_NOTARIZE:-1}" != 0 ]]; then
      for name in QUDS_NOTARY_KEY QUDS_NOTARY_KEY_ID QUDS_NOTARY_ISSUER; do
        [[ -n "${!name:-}" ]] || { echo "$name is required for notarization (or QUDS_NOTARIZE=0)" >&2; exit 64; }
      done
      [[ -f "$QUDS_NOTARY_KEY" ]] || { echo "QUDS_NOTARY_KEY is not a file" >&2; exit 64; }
    fi
  fi
  # The profile must authorize this bundle id, team and certificate.
  profile_plist="$(mktemp)"
  security cms -D -i "$PROFILE" >"$profile_plist"
  TEAM_ID="$(plutil -extract TeamIdentifier.0 raw -o - "$profile_plist")"
  profile_app_id="$(plutil -extract 'Entitlements.com\.apple\.application-identifier' raw -o - "$profile_plist")"
  [[ "$profile_app_id" == "$TEAM_ID.$BUNDLE_ID" ]] \
    || { echo "profile is for $profile_app_id, not $TEAM_ID.$BUNDLE_ID" >&2; exit 1; }
  profile_certs=""
  index=0
  while plutil -extract "DeveloperCertificates.$index" raw -o - "$profile_plist" >/dev/null 2>&1; do
    profile_certs+="$(plutil -extract "DeveloperCertificates.$index" raw -o - "$profile_plist" \
      | base64 -D | shasum -a 1 | awk '{print toupper($1)}') "
    index=$((index + 1))
  done
  [[ " $profile_certs" == *" $SIGN_IDENTITY "* ]] \
    || { echo "the profile does not include signing certificate $SIGN_IDENTITY" >&2; exit 1; }
  rm -f "$profile_plist"
  echo "identity $SIGN_IDENTITY, team $TEAM_ID, bundle id $BUNDLE_ID"
  [[ -z "${INSTALLER_IDENTITY:-}" ]] || echo "installer identity $INSTALLER_IDENTITY"
fi

log "Native libraries"
python3 "$PACKAGES/quds_proofing_hunspell/tool/build.py" --native --jobs "$JOBS" >/dev/null
python3 "$PACKAGES/quds_arabic_morph/tool/build.py" --native --jobs "$JOBS" >/dev/null
python3 "$PACKAGES/quds_language_id/tool/build.py" --native --jobs "$JOBS" >/dev/null
python3 "$PACKAGES/quds_language_id/tool/build.py" --verify-model
if [[ "${QUDS_SKIP_HARPER:-0}" != 1 ]]; then
  python3 "$PACKAGES/quds_proofing_harper/tool/build.py" --native >/dev/null
fi
if [[ "${QUDS_SKIP_SPACY:-0}" != 1 ]]; then
  if [[ "$REBUILD_SPACY" == 1 ]]; then
    python3 "$PACKAGES/quds_proofing_spacy/tool/build.py" --native --jobs "$JOBS" >/dev/null
  else
    SPACY_PINNED="$(fetch_pinned_spacy)"
  fi
fi

log "flutter build macos --$BUILD_MODE"
cd "$EXAMPLE"
flutter build macos "--$BUILD_MODE" ${FLUTTER_ARGS[@]+"${FLUTTER_ARGS[@]}"}
[[ -d "$APP" ]] || { echo "missing $APP" >&2; exit 1; }

FRAMEWORKS="$APP/Contents/Frameworks"
RESOURCES="$APP/Contents/Resources"

log "Install into $FRAMEWORKS"
# --install-native rebuilds incrementally and copies only receipt-listed files.
python3 "$PACKAGES/quds_proofing_hunspell/tool/build.py" --native --jobs "$JOBS" \
  --install-native "$FRAMEWORKS" --install-licenses "$RESOURCES/hunspell-licenses" >/dev/null
python3 "$PACKAGES/quds_arabic_morph/tool/build.py" --native --jobs "$JOBS" \
  --install-native "$FRAMEWORKS" --install-licenses "$RESOURCES/arabic-morph-licenses" >/dev/null
python3 "$PACKAGES/quds_language_id/tool/build.py" --native --jobs "$JOBS" \
  --install-native "$FRAMEWORKS" --install-licenses "$RESOURCES/language-id-licenses" >/dev/null
LIBRARIES=(libquds_proofing_hunspell.dylib libquds_arabic_morph.dylib libquds_language_id.dylib)
if [[ "${QUDS_SKIP_HARPER:-0}" != 1 ]]; then
  # Harper's installer puts its notices next to the library; keep code and
  # notices apart in the bundle (Frameworks may hold only code).
  staging="$(mktemp -d)"
  python3 "$PACKAGES/quds_proofing_harper/tool/build.py" --native \
    --install-native "$staging" >/dev/null
  cp "$staging/libquds_proofing_harper.dylib" "$FRAMEWORKS/"
  # Cargo records the build directory as the install name; Studio opens the
  # library by leaf name, which dyld resolves through the app's
  # @executable_path/../Frameworks rpath.
  install_name_tool -id @rpath/libquds_proofing_harper.dylib \
    "$FRAMEWORKS/libquds_proofing_harper.dylib" 2>/dev/null
  rm -rf "$RESOURCES/harper-licenses"
  mkdir -p "$RESOURCES/harper-licenses"
  find "$staging" -mindepth 1 -maxdepth 1 ! -name '*.dylib' -exec cp -R {} "$RESOURCES/harper-licenses/" \;
  rm -rf "$staging"
  LIBRARIES+=(libquds_proofing_harper.dylib)
fi
rm -f "$RESOURCES/spacy-native.json" "$FRAMEWORKS/libcrispembed-spacy.dylib"
if [[ "${QUDS_SKIP_SPACY:-0}" != 1 ]]; then
  # Only the library ships; the model files are verified in-app downloads.
  if [[ "$REBUILD_SPACY" == 1 ]]; then
    python3 "$PACKAGES/quds_proofing_spacy/tool/build.py" --native --jobs "$JOBS" \
      --install-native "$FRAMEWORKS" --install-licenses "$RESOURCES/spacy-licenses" >/dev/null
  else
    cp "$SPACY_PINNED" "$FRAMEWORKS/libcrispembed-spacy.dylib"
    python3 "$PACKAGES/quds_proofing_spacy/tool/build.py" \
      --install-licenses "$RESOURCES/spacy-licenses" >/dev/null
  fi
  LIBRARIES+=(libcrispembed-spacy.dylib)
fi

if [[ "$SIGN_MODE" == adhoc ]]; then
  SIGNED_APP="$APP"
else
  # Sign a renamed copy; the Flutter build product stays as built.
  SIGNED_APP="$SIGN_OUTPUT/${QUDS_APP_NAME:-CrispOffice}.app"
  rm -rf "$SIGNED_APP"
  mkdir -p "$SIGN_OUTPUT"
  ditto "$APP" "$SIGNED_APP"
  FRAMEWORKS="$SIGNED_APP/Contents/Frameworks"
  RESOURCES="$SIGNED_APP/Contents/Resources"
  plutil -replace CFBundleIdentifier -string "$BUNDLE_ID" "$SIGNED_APP/Contents/Info.plist"
  cp "$PROFILE" "$SIGNED_APP/Contents/embedded.provisionprofile"
fi

if [[ "${QUDS_SKIP_SPACY:-0}" != 1 && "$REBUILD_SPACY" != 1 ]]; then
  # The pinned input (SHA-256 and length already verified) is the qualified
  # code: check the runtime's code digest and keep Apple's stripped form of
  # it for the comparison after signing.
  [[ "$(code_sha256 "$FRAMEWORKS/libcrispembed-spacy.dylib")" == "$SPACY_PIN_CODE_SHA256" ]] \
    || { echo "pinned spaCy library: unexpected code digest" >&2; exit 1; }
  # Apple's cross-check is meaningful only with a codesign whose
  # --remove-signature output does not depend on the signature (Xcode 26
  # strips the pinned library to the reference; Xcode 16 does not).
  SPACY_INPUT_UNSIGNED="$(unsigned_sha256 "$FRAMEWORKS/libcrispembed-spacy.dylib")"
  if [[ "$SPACY_INPUT_UNSIGNED" != "$SPACY_PIN_UNSIGNED_SHA256" ]]; then
    echo "note: this codesign strips the pinned library to $SPACY_INPUT_UNSIGNED, not the" \
      "Xcode 26 reference; the codesign cross-check is skipped, the code digest still applies"
    SPACY_INPUT_UNSIGNED=""
  fi
fi

log "Sign ($SIGN_MODE)"
if [[ "$SIGN_MODE" == adhoc ]]; then
  SIGN_ARGS=(--force --sign - --timestamp=none)
  ENTITLEMENTS="$EXAMPLE/macos/Runner/Release.entitlements"
  if [[ "$BUILD_MODE" == debug ]]; then
    ENTITLEMENTS="$EXAMPLE/macos/Runner/DebugProfile.entitlements"
  fi
else
  SIGN_ARGS=(--force --sign "$SIGN_IDENTITY" --options runtime --timestamp)
  # Release entitlements plus the identifiers the profile authorizes (the
  # data protection keychain used for mail credentials needs them).
  ENTITLEMENTS="$SIGN_OUTPUT/entitlements.plist"
  cp "$EXAMPLE/macos/Runner/Release.entitlements" "$ENTITLEMENTS"
  /usr/libexec/PlistBuddy \
    -c "Add :com.apple.application-identifier string $TEAM_ID.$BUNDLE_ID" \
    -c "Add :com.apple.developer.team-identifier string $TEAM_ID" "$ENTITLEMENTS"
fi
for library in "${LIBRARIES[@]}"; do
  # The pinned spaCy library already carries the ad hoc signature it was
  # qualified with; ad hoc re-signing is not reproducible across codesign
  # versions, so ad hoc builds ship those exact bytes.
  if [[ "$SIGN_MODE" == adhoc && "$library" == libcrispembed-spacy.dylib \
    && "$REBUILD_SPACY" != 1 ]]; then
    codesign --verify --strict "$FRAMEWORKS/$library"
    continue
  fi
  codesign "${SIGN_ARGS[@]}" "$FRAMEWORKS/$library"
done
if [[ "$SIGN_MODE" != adhoc ]]; then
  # Flutter and plugin frameworks carry Xcode's ad hoc signature; inside out.
  while IFS= read -r framework; do
    codesign "${SIGN_ARGS[@]}" "$framework"
  done < <(find "$FRAMEWORKS" -name '*.framework' -type d -prune | sort)
fi
if [[ "${QUDS_SKIP_SPACY:-0}" != 1 ]]; then
  # Studio loads the bundled library only with this digest of the signed
  # bytes; the app signature below seals this description. The code digest
  # carries the qualification across signatures (see the header).
  spacy_library="$FRAMEWORKS/libcrispembed-spacy.dylib"
  spacy_sha="$(shasum -a 256 "$spacy_library" | awk '{print $1}')"
  spacy_code="$(code_sha256 "$spacy_library")"
  printf '{"library":"libcrispembed-spacy.dylib","sha256":"%s","code_sha256":"%s"}\n' \
    "$spacy_sha" "$spacy_code" >"$RESOURCES/spacy-native.json"
  if [[ "$spacy_sha" == "$SPACY_PIN_SHA256" ]]; then
    SPACY_NOTE="spaCy library $spacy_sha: qualified (analysis and manual German grammar)"
  elif [[ "$REBUILD_SPACY" != 1 && "$spacy_code" == "$SPACY_PIN_CODE_SHA256" ]] \
    && [[ -z "${SPACY_INPUT_UNSIGNED:-}" \
      || "$(unsigned_sha256 "$spacy_library")" == "$SPACY_INPUT_UNSIGNED" ]]; then
    SPACY_NOTE="spaCy library $spacy_sha: qualified code $spacy_code re-signed ($SIGN_MODE; analysis and manual German grammar)"
  elif [[ "$REBUILD_SPACY" == 1 ]]; then
    SPACY_NOTE="spaCy library $spacy_sha: UNQUALIFIED rebuild (analysis only; no grammar suggestions)"
  else
    echo "pinned spaCy library changed while signing: $spacy_sha (code $spacy_code)" >&2
    exit 1
  fi
fi
APP_IDENTITY_ARGS=()
if [[ "$SIGN_MODE" != adhoc ]]; then
  # Match local development builds so ordinary updates retain scoped grants.
  APP_IDENTITY_ARGS=(--requirements "=designated => anchor apple generic and identifier \"$BUNDLE_ID\" and certificate leaf[subject.OU] = \"$TEAM_ID\"")
fi
codesign "${SIGN_ARGS[@]}" ${APP_IDENTITY_ARGS[@]+"${APP_IDENTITY_ARGS[@]}"} --entitlements "$ENTITLEMENTS" "$SIGNED_APP"

log "Verify"
codesign --verify --deep --strict --verbose=1 "$SIGNED_APP"
APP_MINIMUM_OS="$(plutil -extract LSMinimumSystemVersion raw -o - "$SIGNED_APP/Contents/Info.plist")"
# true when version $1 <= version $2 (dotted, numeric)
version_le() { [[ "$(printf '%s\n%s\n' "$1" "$2" | sort -t. -k1,1n -k2,2n -k3,3n | head -1)" == "$1" ]]; }
for library in "${LIBRARIES[@]}"; do
  path="$FRAMEWORKS/$library"
  # A library whose minimum macOS exceeds the app's would fail to load on
  # older systems the app claims to support (the host SDK leaks in when a
  # build does not pin its deployment target).
  library_minimum="$(vtool -show-build "$path" | awk '/minos/{print $2}' | sort -t. -k1,1n -k2,2n | tail -1)"
  [[ -n "$library_minimum" ]] || { echo "$library declares no minimum macOS" >&2; exit 1; }
  version_le "$library_minimum" "$APP_MINIMUM_OS" \
    || { echo "$library needs macOS $library_minimum, app declares $APP_MINIMUM_OS" >&2; exit 1; }
  # Only system libraries (or the library itself) may be referenced.
  foreign="$(otool -L "$path" | tail -n +2 | awk '{print $1}' \
    | grep -v -e '^/usr/lib/' -e '^/System/' -e "$library\$" || true)"
  [[ -z "$foreign" ]] || { echo "$library links outside the system: $foreign" >&2; exit 1; }
  python3 -c 'import ctypes, sys; ctypes.CDLL(sys.argv[1])' "$path"
  echo "ok  $library"
done
entitlements="$(codesign -d --entitlements - --xml "$SIGNED_APP" 2>/dev/null)"
for key in app-sandbox network.client; do
  grep -q "com.apple.security.$key" <<<"$entitlements" \
    || { echo "$key entitlement missing" >&2; exit 1; }
done
[[ -z "${SPACY_NOTE:-}" ]] || echo "$SPACY_NOTE"

if [[ "$SIGN_MODE" != adhoc ]]; then
  grep -q "$TEAM_ID.$BUNDLE_ID" <<<"$entitlements" \
    || { echo "application identifier entitlement missing" >&2; exit 1; }
  signature="$(codesign -dvv "$SIGNED_APP" 2>&1)"
  grep -q "flags=0x10000(runtime)" <<<"$signature" \
    || { echo "hardened runtime missing" >&2; exit 1; }
  version="$(plutil -extract CFBundleShortVersionString raw -o - "$SIGNED_APP/Contents/Info.plist")"
  build="$(plutil -extract CFBundleVersion raw -o - "$SIGNED_APP/Contents/Info.plist")"
fi

if [[ "$SIGN_MODE" == appstore ]]; then
  log "Installer package"
  PACKAGE="$SIGN_OUTPUT/${QUDS_APP_NAME:-CrispOffice}-$version-$build.pkg"
  rm -f "$PACKAGE"
  productbuild --component "$SIGNED_APP" /Applications \
    --sign "$INSTALLER_IDENTITY" "$PACKAGE"
  pkgutil --check-signature "$PACKAGE"
  echo
  echo "$PACKAGE"
elif [[ "$SIGN_MODE" == developer-id ]]; then
  ARCHIVE="$SIGN_OUTPUT/${QUDS_APP_NAME:-CrispOffice}-$version-$build-macos.zip"
  if [[ "${QUDS_NOTARIZE:-1}" != 0 ]]; then
    log "Notarize"
    submission="$SIGN_OUTPUT/notary-upload.zip"
    rm -f "$submission"
    ditto -c -k --keepParent "$SIGNED_APP" "$submission"
    result="$SIGN_OUTPUT/notary-result.json"
    xcrun notarytool submit "$submission" --wait --output-format json \
      --key "$QUDS_NOTARY_KEY" --key-id "$QUDS_NOTARY_KEY_ID" \
      --issuer "$QUDS_NOTARY_ISSUER" >"$result" || true
    rm -f "$submission"
    status="$(plutil -extract status raw -o - "$result" 2>/dev/null || echo unknown)"
    submission_id="$(plutil -extract id raw -o - "$result" 2>/dev/null || echo '')"
    echo "notarization $submission_id: $status"
    if [[ "$status" != Accepted ]]; then
      [[ -z "$submission_id" ]] || xcrun notarytool log "$submission_id" \
        --key "$QUDS_NOTARY_KEY" --key-id "$QUDS_NOTARY_KEY_ID" \
        --issuer "$QUDS_NOTARY_ISSUER" "$SIGN_OUTPUT/notary-log.json" || true
      echo "notarization failed; see $SIGN_OUTPUT/notary-log.json" >&2
      exit 1
    fi
    xcrun stapler staple "$SIGNED_APP"
    xcrun stapler validate "$SIGNED_APP"
    spctl --assess --type execute -vv "$SIGNED_APP"
  fi
  rm -f "$ARCHIVE"
  ditto -c -k --keepParent "$SIGNED_APP" "$ARCHIVE"
  echo
  echo "$ARCHIVE"
fi
echo
echo "$SIGNED_APP"

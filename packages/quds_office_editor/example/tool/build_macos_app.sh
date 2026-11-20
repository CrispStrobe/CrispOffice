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
# 5. re-signs ad hoc (each library, then the app with Release.entitlements),
#    records the signed spaCy library's digest in
#    Contents/Resources/spacy-native.json (sealed by the app signature) and
#    verifies the signature, the libraries' load commands and that each
#    library opens from inside the bundle.
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
APP="$EXAMPLE/build/macos/Build/Products/Release/quds_office_studio.app"

log() { printf '\n== %s\n' "$*"; }

# Qualified app-bundled spaCy library (see the header). Keep in sync with
# spacyGrammarMacosBundledSha256; a Studio test checks both pins.
SPACY_PIN_REPOSITORY=cstr/crispembed-spacy-de-core-news-sm-3.8.0
SPACY_PIN_REVISION=2aa70083055073adf8d2ffbb0ff203cc4fcafd7e
SPACY_PIN_SHA256=ccc96620e01164d18e8d2e46b9a383677e4430c8889833bedab5b56c16a1b40f
SPACY_PIN_BYTES=2322928
SPACY_PIN_PATH="app-bundled/macos-arm64/$SPACY_PIN_SHA256/libcrispembed-spacy.dylib"

REBUILD_SPACY=0
FLUTTER_ARGS=()
for argument in "$@"; do
  if [[ "$argument" == --rebuild-spacy ]]; then
    REBUILD_SPACY=1
  else
    FLUTTER_ARGS+=("$argument")
  fi
done

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

[[ "$(uname -s)" == Darwin ]] || { echo "macOS only" >&2; exit 1; }

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

log "flutter build macos --release"
cd "$EXAMPLE"
flutter build macos --release ${FLUTTER_ARGS[@]+"${FLUTTER_ARGS[@]}"}
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

log "Sign ad hoc"
for library in "${LIBRARIES[@]}"; do
  codesign --force --sign - --timestamp=none "$FRAMEWORKS/$library"
done
if [[ "${QUDS_SKIP_SPACY:-0}" != 1 ]]; then
  # Studio loads the bundled library only with this digest of the signed
  # bytes; the app signature below seals this description.
  spacy_sha="$(shasum -a 256 "$FRAMEWORKS/libcrispembed-spacy.dylib" | awk '{print $1}')"
  printf '{"library":"libcrispembed-spacy.dylib","sha256":"%s"}\n' "$spacy_sha" \
    >"$RESOURCES/spacy-native.json"
  # Ad hoc signing is deterministic, so re-signing the pinned bytes keeps them.
  if [[ "$spacy_sha" == "$SPACY_PIN_SHA256" ]]; then
    SPACY_NOTE="spaCy library $spacy_sha: qualified (analysis and manual German grammar)"
  elif [[ "$REBUILD_SPACY" == 1 ]]; then
    SPACY_NOTE="spaCy library $spacy_sha: UNQUALIFIED rebuild (analysis only; no grammar suggestions)"
  else
    echo "pinned spaCy library changed while signing: $spacy_sha" >&2
    exit 1
  fi
fi
codesign --force --sign - --timestamp=none \
  --entitlements "$EXAMPLE/macos/Runner/Release.entitlements" "$APP"

log "Verify"
codesign --verify --deep --strict --verbose=1 "$APP"
for library in "${LIBRARIES[@]}"; do
  path="$FRAMEWORKS/$library"
  # Only system libraries (or the library itself) may be referenced.
  foreign="$(otool -L "$path" | tail -n +2 | awk '{print $1}' \
    | grep -v -e '^/usr/lib/' -e '^/System/' -e "$library\$" || true)"
  [[ -z "$foreign" ]] || { echo "$library links outside the system: $foreign" >&2; exit 1; }
  python3 -c 'import ctypes, sys; ctypes.CDLL(sys.argv[1])' "$path"
  echo "ok  $library"
done
codesign -d --entitlements - "$APP" 2>/dev/null | grep -q network.client \
  || { echo "network client entitlement missing" >&2; exit 1; }
[[ -z "${SPACY_NOTE:-}" ]] || echo "$SPACY_NOTE"
echo
echo "$APP"

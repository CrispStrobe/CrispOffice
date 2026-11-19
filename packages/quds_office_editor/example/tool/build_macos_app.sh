#!/usr/bin/env bash
# Build the Studio macOS release app with its native proofing libraries.
#
#   packages/quds_office_editor/example/tool/build_macos_app.sh
#
# 1. builds the pinned native libraries (Hunspell, Arabic morphology, CLD3
#    language ID and, unless QUDS_SKIP_HARPER=1, Harper for English) with each
#    package's tool/build.py;
# 2. checks the bundled CLD3 model against its pin;
# 3. runs `flutter build macos --release`;
# 4. installs the receipt-verified libraries into Contents/Frameworks (where
#    the Studio hosts look for them) and their notices into Contents/Resources;
# 5. re-signs ad hoc (each library, then the app with Release.entitlements)
#    and verifies the signature, the libraries' load commands and that each
#    library opens from inside the bundle.
#
# Flutter 3.47.8 or newer must be on PATH. Rust/Cargo is needed only for
# Harper; set CARGO_TARGET_DIR to share its build directory.
set -euo pipefail

EXAMPLE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PACKAGES="$(cd "$EXAMPLE/../.." && pwd)"
JOBS="${QUDS_BUILD_JOBS:-4}"
APP="$EXAMPLE/build/macos/Build/Products/Release/quds_office_studio.app"

log() { printf '\n== %s\n' "$*"; }

[[ "$(uname -s)" == Darwin ]] || { echo "macOS only" >&2; exit 1; }

log "Native libraries"
python3 "$PACKAGES/quds_proofing_hunspell/tool/build.py" --native --jobs "$JOBS" >/dev/null
python3 "$PACKAGES/quds_arabic_morph/tool/build.py" --native --jobs "$JOBS" >/dev/null
python3 "$PACKAGES/quds_language_id/tool/build.py" --native --jobs "$JOBS" >/dev/null
python3 "$PACKAGES/quds_language_id/tool/build.py" --verify-model
if [[ "${QUDS_SKIP_HARPER:-0}" != 1 ]]; then
  python3 "$PACKAGES/quds_proofing_harper/tool/build.py" --native >/dev/null
fi

log "flutter build macos --release"
cd "$EXAMPLE"
flutter build macos --release "$@"
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

log "Sign ad hoc"
for library in "${LIBRARIES[@]}"; do
  codesign --force --sign - --timestamp=none "$FRAMEWORKS/$library"
done
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
echo
echo "$APP"

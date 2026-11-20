#!/usr/bin/env bash
# Build the native-feature-complete local workspace with a persistent identity.
# No running app is modified. Distribution uses build_macos_app.sh separately.
set -euo pipefail
EXAMPLE="$(cd "$(dirname "$0")/.." && pwd)"
export QUDS_BUILD_MODE="${QUDS_BUILD_MODE:-debug}"
IDENTITY="${QUDS_LOCAL_SIGN_IDENTITY:-}"
if [[ -z "$IDENTITY" ]]; then
  IDENTITY="$(security find-identity -v -p codesigning | awk '/Apple Development:|Mac Developer:/ { print $2 }' | sort -u)"
fi
[[ "$IDENTITY" =~ ^[0-9A-Fa-f]{40}$ ]] || {
  echo "Select one installed development certificate with QUDS_LOCAL_SIGN_IDENTITY (SHA-1)." >&2; exit 1;
}
bash "$EXAMPLE/tool/build_macos_app.sh" --sign adhoc "$@"
case "$QUDS_BUILD_MODE" in debug) CONFIG=Debug ;; release) CONFIG=Release ;; profile) CONFIG=Profile ;; esac
APP="$EXAMPLE/build/macos/Build/Products/$CONFIG/CrispOffice.app"
ENTITLEMENTS="$(mktemp)"
trap 'rm -f "$ENTITLEMENTS"' EXIT
if [[ "$QUDS_BUILD_MODE" == debug ]]; then
  cp "$EXAMPLE/macos/Runner/DebugProfile.entitlements" "$ENTITLEMENTS"
  /usr/libexec/PlistBuddy -c 'Add :com.apple.security.get-task-allow bool true' "$ENTITLEMENTS"
else
  cp "$EXAMPLE/macos/Runner/Release.entitlements" "$ENTITLEMENTS"
fi
# Sign code leaves first, including Debug's executable companion libraries.
while IFS= read -r -d '' leaf; do
  codesign --force --sign "$IDENTITY" --timestamp=none "$leaf"
done < <(find "$APP/Contents" -type f -name '*.dylib' -print0)
while IFS= read -r -d '' framework; do
  codesign --force --sign "$IDENTITY" --timestamp=none "$framework"
done < <(find "$APP/Contents/Frameworks" -type d -name '*.framework' -depth -print0)
# Signing changes the library bytes, not its qualified native code.
if [[ -f "$APP/Contents/Resources/spacy-native.json" ]]; then
  code="$(cd "$EXAMPLE/../../quds_proofing_spacy" && dart run tool/macho_code_digest.dart "$APP/Contents/Frameworks/libcrispembed-spacy.dylib")"
  python3 - "$APP" "$code" <<'PY'
import hashlib,json,pathlib,sys
app=pathlib.Path(sys.argv[1]);p=app/'Contents/Resources/spacy-native.json';record=json.loads(p.read_text())
assert record['code_sha256']==sys.argv[2],'Qualified spaCy native code changed while signing'
record['sha256']=hashlib.sha256((app/'Contents/Frameworks/libcrispembed-spacy.dylib').read_bytes()).hexdigest()
p.write_text(json.dumps(record)+'\n')
PY
fi
codesign --force --sign "$IDENTITY" --timestamp=none --options runtime --entitlements "$ENTITLEMENTS" "$APP"
TEAM="$(codesign -dv --verbose=4 "$APP" 2>&1 | sed -n 's/^TeamIdentifier=//p')"
[[ -n "$TEAM" && "$TEAM" != 'not set' ]] || { echo 'A persistent development identity is required.' >&2; exit 1; }
BUNDLE="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Contents/Info.plist")"
REQUIREMENT="anchor apple generic and identifier \"$BUNDLE\" and certificate leaf[subject.OU] = \"$TEAM\""
codesign --force --sign "$IDENTITY" --timestamp=none --options runtime --entitlements "$ENTITLEMENTS" --requirements "=designated => $REQUIREMENT" "$APP"
codesign --verify --deep --strict --test-requirement "=$REQUIREMENT" "$APP"
printf 'Stable-signed CrispOffice: %s\n' "$APP"

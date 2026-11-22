set -e
mkdir -p build/macros
for suite in word_cell_paragraphs_v1; do
  VBA_CASES_BASE64=$(python3 -c 'import base64,sys; from pathlib import Path; print(base64.b64encode(Path(sys.argv[1]).read_bytes()).decode())' "test/fixtures/vba_conformance/${suite}.json")
  dart --packages=../../.dart_tool/package_config.json -DVBA_CONFORMANCE_BASE64="$VBA_CASES_BASE64" tool/macros/web_vba_conformance.dart > "build/macros/${suite}-vm.json"
  dart compile js -O1 --packages=../../.dart_tool/package_config.json -DVBA_CONFORMANCE_BASE64="$VBA_CASES_BASE64" tool/macros/web_vba_conformance.dart -o "build/macros/${suite}.js"
  node -e 'globalThis.self = globalThis; require(process.argv[1])' "./build/macros/${suite}.js" > "build/macros/${suite}-js.json"
  cmp "build/macros/${suite}-vm.json" "build/macros/${suite}-js.json"
done

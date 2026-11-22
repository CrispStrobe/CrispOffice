set -e
mkdir -p build/macros
WORD_CELL_PARAGRAPHS_BAS_BASE64=$(python3 -c 'import base64; from pathlib import Path; print(base64.b64encode(Path("example/macros/word_table_paragraphs.bas").read_bytes()).decode())')
dart -DWORD_CELL_PARAGRAPHS_BAS_BASE64="$WORD_CELL_PARAGRAPHS_BAS_BASE64" tool/macros/web_vba_word_cell_paragraphs_smoke.dart > build/macros/word-cell-paragraphs-vm.json
dart compile js -O1 -DWORD_CELL_PARAGRAPHS_BAS_BASE64="$WORD_CELL_PARAGRAPHS_BAS_BASE64" tool/macros/web_vba_word_cell_paragraphs_smoke.dart -o build/macros/word-cell-paragraphs.js
node -e 'globalThis.self = globalThis; require("./build/macros/word-cell-paragraphs.js")' > build/macros/word-cell-paragraphs-js.json
python3 -c 'import json; from pathlib import Path; assert json.loads(Path("build/macros/word-cell-paragraphs-vm.json").read_text()) == json.loads(Path("build/macros/word-cell-paragraphs-js.json").read_text())'

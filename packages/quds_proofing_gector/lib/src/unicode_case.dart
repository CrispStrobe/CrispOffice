// Full case expansions used by the Apache-2.0 reference decoder.
// Generated from Python 3.12 Unicode 15.0.0; Dart uses simple case mappings.
final RegExp _cased = RegExp(r'^[\p{L}\p{N}]$', unicode: true);
final RegExp _caseIgnorable = RegExp(
  r"^[\p{Mn}\p{Me}\p{Cf}\p{Lm}\p{Sk}'’]$",
  unicode: true,
);

String gectorUpper(String value) => value.runes
    .map((r) => _upperExpansions[r] ?? String.fromCharCode(r).toUpperCase())
    .join();

String gectorLower(String value) {
  final runes = value.runes.toList(growable: false);
  final out = StringBuffer();
  for (var i = 0; i < runes.length; i++) {
    final r = runes[i];
    if (r == 0x130) {
      out.write('i\u0307');
    } else if (r == 0x3a3) {
      bool casedAt(int index, int direction) {
        while (index >= 0 && index < runes.length) {
          final c = String.fromCharCode(runes[index]);
          if (_caseIgnorable.hasMatch(c)) {
            index += direction;
            continue;
          }
          return _cased.hasMatch(c) && c.toUpperCase() != c.toLowerCase();
        }
        return false;
      }

      out.write(casedAt(i - 1, -1) && !casedAt(i + 1, 1) ? 'ς' : 'σ');
    } else {
      out.write(String.fromCharCode(r).toLowerCase());
    }
  }
  return out.toString();
}

String gectorCapital(String value) {
  if (value.isEmpty) return value;
  final first = String.fromCharCode(value.runes.first);
  return gectorUpper(first) + gectorLower(value.substring(first.length));
}

const Map<int, String> _upperExpansions = <int, String>{
  223: "SS",
  329: "ʼN",
  496: "J̌",
  912: "Ϊ́",
  944: "Ϋ́",
  1415: "ԵՒ",
  7830: "H̱",
  7831: "T̈",
  7832: "W̊",
  7833: "Y̊",
  7834: "Aʾ",
  8016: "Υ̓",
  8018: "Υ̓̀",
  8020: "Υ̓́",
  8022: "Υ̓͂",
  8064: "ἈΙ",
  8065: "ἉΙ",
  8066: "ἊΙ",
  8067: "ἋΙ",
  8068: "ἌΙ",
  8069: "ἍΙ",
  8070: "ἎΙ",
  8071: "ἏΙ",
  8072: "ἈΙ",
  8073: "ἉΙ",
  8074: "ἊΙ",
  8075: "ἋΙ",
  8076: "ἌΙ",
  8077: "ἍΙ",
  8078: "ἎΙ",
  8079: "ἏΙ",
  8080: "ἨΙ",
  8081: "ἩΙ",
  8082: "ἪΙ",
  8083: "ἫΙ",
  8084: "ἬΙ",
  8085: "ἭΙ",
  8086: "ἮΙ",
  8087: "ἯΙ",
  8088: "ἨΙ",
  8089: "ἩΙ",
  8090: "ἪΙ",
  8091: "ἫΙ",
  8092: "ἬΙ",
  8093: "ἭΙ",
  8094: "ἮΙ",
  8095: "ἯΙ",
  8096: "ὨΙ",
  8097: "ὩΙ",
  8098: "ὪΙ",
  8099: "ὫΙ",
  8100: "ὬΙ",
  8101: "ὭΙ",
  8102: "ὮΙ",
  8103: "ὯΙ",
  8104: "ὨΙ",
  8105: "ὩΙ",
  8106: "ὪΙ",
  8107: "ὫΙ",
  8108: "ὬΙ",
  8109: "ὭΙ",
  8110: "ὮΙ",
  8111: "ὯΙ",
  8114: "ᾺΙ",
  8115: "ΑΙ",
  8116: "ΆΙ",
  8118: "Α͂",
  8119: "Α͂Ι",
  8124: "ΑΙ",
  8130: "ῊΙ",
  8131: "ΗΙ",
  8132: "ΉΙ",
  8134: "Η͂",
  8135: "Η͂Ι",
  8140: "ΗΙ",
  8146: "Ϊ̀",
  8147: "Ϊ́",
  8150: "Ι͂",
  8151: "Ϊ͂",
  8162: "Ϋ̀",
  8163: "Ϋ́",
  8164: "Ρ̓",
  8166: "Υ͂",
  8167: "Ϋ͂",
  8178: "ῺΙ",
  8179: "ΩΙ",
  8180: "ΏΙ",
  8182: "Ω͂",
  8183: "Ω͂Ι",
  8188: "ΩΙ",
  64256: "FF",
  64257: "FI",
  64258: "FL",
  64259: "FFI",
  64260: "FFL",
  64261: "ST",
  64262: "ST",
  64275: "ՄՆ",
  64276: "ՄԵ",
  64277: "ՄԻ",
  64278: "ՎՆ",
  64279: "ՄԽ",
};

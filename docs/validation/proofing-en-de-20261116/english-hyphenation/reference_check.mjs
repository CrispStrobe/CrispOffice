// Reproducible JavaScript data/reference check; this does not execute Dart.
// The trie and independent flat-pattern oracle check the exact bundled data.
function assert(condition, message) {
  if (!condition) throw new Error(message);
}

function parseSource(source) {
  const clean = source.replace(/%[^\n]*/g, '');
  const patterns = [...clean.matchAll(/\\patterns\{([^}]*)\}/g)];
  const exceptions = [...clean.matchAll(/\\hyphenation\{([^}]*)\}/g)];
  assert(patterns.length === 1 && exceptions.length === 1, 'TeX block inventory');
  return {
    patterns: patterns[0][1].trim().split(/\s+/),
    exceptions: exceptions[0][1].trim().split(/\s+/),
  };
}

function exceptionMap(exceptions) {
  return new Map(exceptions.map(source => {
    const word = source.replace(/-/g, '');
    const pieces = source.split('-');
    let offset = 0;
    const offsets = [];
    for (const piece of pieces.slice(0, -1)) {
      offset += piece.length;
      if (offset >= 2 && offset <= word.length - 3) offsets.push(offset);
    }
    return [word, offsets];
  }));
}

function trieMatcher(patterns, exceptions) {
  const root = {children: new Map(), values: null};
  for (const pattern of patterns) {
    let node = root;
    const values = [0];
    for (const character of pattern) {
      const unit = character.charCodeAt(0);
      if (unit >= 48 && unit <= 57) {
        values[values.length - 1] = unit - 48;
      } else {
        if (!node.children.has(character)) {
          node.children.set(character, {children: new Map(), values: null});
        }
        node = node.children.get(character);
        values.push(0);
      }
    }
    node.values = values;
  }
  const overrides = exceptionMap(exceptions);
  return word => {
    if (!/^[a-zA-Z]+$/.test(word) || word.length < 5 || word.length > 128) return [];
    word = word.toLowerCase();
    if (overrides.has(word)) return overrides.get(word).slice();
    const padded = '.' + word + '.';
    const scores = Array(padded.length + 1).fill(0);
    for (let start = 0; start < padded.length; start++) {
      let node = root;
      for (let at = start; at < padded.length; at++) {
        node = node.children.get(padded[at]);
        if (!node) break;
        if (node.values) {
          for (let j = 0; j < node.values.length; j++) {
            scores[start + j] = Math.max(scores[start + j], node.values[j]);
          }
        }
      }
    }
    return Array.from({length: word.length - 4}, (_, i) => i + 2)
      .filter(cut => scores[cut + 1] % 2 === 1);
  };
}

// Independent oracle: search the full text for each literal pattern. It has
// no trie, prefix walk, cached nodes, or shared score-building code.
function flatMatcher(patterns, exceptions) {
  const unpacked = patterns.map(pattern => {
    const literal = pattern.replace(/\d/g, '');
    const weights = Array(literal.length + 1).fill(0);
    for (const digit of pattern.matchAll(/\d/g)) {
      const boundary = pattern.slice(0, digit.index).replace(/\d/g, '').length;
      weights[boundary] = Number(digit[0]);
    }
    return {literal, weights};
  });
  const overrides = exceptionMap(exceptions);
  return word => {
    word = word.toLowerCase();
    if (overrides.has(word)) return overrides.get(word).slice();
    const padded = '.' + word + '.';
    const scores = Array(padded.length + 1).fill(0);
    for (const {literal, weights} of unpacked) {
      let index = padded.indexOf(literal);
      while (index >= 0) {
        for (let boundary = 0; boundary < weights.length; boundary++) {
          scores[index + boundary] = Math.max(scores[index + boundary], weights[boundary]);
        }
        index = padded.indexOf(literal, index + 1);
      }
    }
    const cuts = [];
    for (let cut = 2; cut + 3 <= word.length; cut++) {
      if (scores[cut + 1] % 2) cuts.push(cut);
    }
    return cuts;
  };
}

function validateEnglishHyphenation({sources, generated, implementation}) {
  const data = Object.fromEntries(Object.entries(sources).map(([key, source]) => [key, parseSource(source)]));
  const matchers = {};
  const result = {
    kind: 'JavaScript data and reference-algorithm validation',
    dart_executed: false,
    variants: {},
    golden_assertions: 0,
    paragraph_assertions: 0,
  };
  const natural = (
    'hyphenation internationalization internationalisation organization organisation ' +
    'English British American behaviour behavior colour color dictionary grammar ' +
    'spellchecking silhouette university universities however manuscript manuscripts ' +
    'reciprocity throughout something associate associates declination obligatory ' +
    'philanthropic present presents project projects recognizance reformation retribution ' +
    'table representation democrat democratic exception alphabet computer algorithm ' +
    'extraordinary revolutionary transatlantic'
  ).split(' ');
  for (const variant of ['us', 'gb']) {
    const {patterns, exceptions} = data[variant];
    assert(patterns.length === (variant === 'us' ? 4938 : 8527), 'pattern count ' + variant);
    assert(exceptions.length === (variant === 'us' ? 14 : 8), 'exception count ' + variant);
    const title = variant === 'us' ? 'Us' : 'Gb';
    const expectedHeader = sources[variant].slice(0, sources[variant].indexOf('\\patterns{'))
      .split('\n').map(line => ('// ' + line.replace(/^%/, '').trim()).trimEnd()).join('\n');
    assert(generated[variant].startsWith(expectedHeader), 'original notices ' + variant);
    const patternMatch = new RegExp("const english" + title + "HyphenationPatterns = r'''\\n([\\s\\S]*?)\\n''';").exec(generated[variant]);
    const exceptionMatch = new RegExp("const english" + title + "HyphenationExceptions = r'''\\n([\\s\\S]*?)\\n''';").exec(generated[variant]);
    assert(patternMatch && exceptionMatch, 'generated constants ' + variant);
    assert(patternMatch[1] === patterns.join('\n'), 'lossless generated patterns ' + variant);
    assert(exceptionMatch[1] === exceptions.join('\n'), 'unchanged exceptions ' + variant);
    assert(patterns.every(pattern => /^[a-z0-9.]+$/.test(pattern)), 'pattern alphabet ' + variant);
    assert(new Set(patterns.map(pattern => pattern.replace(/\d/g, ''))).size === patterns.length, 'unique pattern keys ' + variant);
    const trie = trieMatcher(patterns, exceptions);
    const flat = flatMatcher(patterns, exceptions);
    matchers[variant] = trie;
    const corpus = new Set(natural);
    for (const exception of exceptions) corpus.add(exception.replace(/-/g, ''));
    for (let i = 0; i < patterns.length; i += 17) {
      const word = patterns[i].replace(/[0-9.]/g, '');
      if (word.length >= 5 && word.length <= 128) corpus.add(word);
      const extended = 'pre' + word + 'ation';
      if (extended.length <= 128) corpus.add(extended);
    }
    let comparisons = 0;
    for (const word of corpus) {
      const actual = trie(word);
      assert(JSON.stringify(actual) === JSON.stringify(flat(word)), 'trie/flat mismatch ' + variant + '/' + word);
      assert(actual.every(cut => cut >= 2 && word.length - cut >= 3), 'fragment minima ' + variant + '/' + word);
      comparisons++;
    }
    result.variants[variant] = {
      patterns: patterns.length, exceptions: exceptions.length, oracle_comparisons: comparisons,
      lossless_data: true, original_license_preface: true,
    };
  }
  const golden = [
    ['us', 'dictionary', [3, 6]], ['gb', 'dictionary', [3, 7]],
    ['us', 'hyphenation', [2, 6]], ['gb', 'hyphenation', [2, 6, 7]],
    ['us', 'internationalization', [2, 5, 7, 11, 13, 16]],
    ['gb', 'internationalisation', [2, 5, 7, 11, 13, 16]],
    ['us', 'project', []], ['gb', 'project', [3]],
    ['us', 'present', []], ['us', 'projects', []], ['us', 'presents', []],
    ['us', 'table', [2]], ['gb', 'universities', [3, 6, 9]],
    ['gb', 'manuscript', [2, 4]], ['gb', 'reciprocity', [2, 4, 7]],
    ['us', 'DICTIONARY', [3, 6]], ['us', 'dictionäry', []],
    ['us', 'dic\u00adtionary', []], ['us', "dictionary's", []],
    ['us', 'dictionary’s', []], ['us', 'a'.repeat(129), []],
  ];
  for (const [variant, word, expected] of golden) {
    assert(JSON.stringify(matchers[variant](word)) === JSON.stringify(expected), 'golden ' + variant + '/' + word);
    result.golden_assertions++;
  }
  // Read the actual Dart token expression, retaining its Unicode semantics.
  const expression = /static final RegExp _words = RegExp\(\s*r"([^"]+)"/.exec(implementation);
  assert(expression, 'Dart token expression not found');
  const words = new RegExp(expression[1], 'gu');
  const normalize = language => {
    const normalized = language?.trim().replaceAll('_', '-').toLowerCase();
    return normalized === 'en' ? 'en-us' : normalized;
  };
  const protectedBlock = implementation.split('static final RegExp _protectedTokens = RegExp(')[1].split('unicode: true')[0];
  const protectedSource = [...protectedBlock.matchAll(/r'([^']*)'/g)].map(match => match[1]).join('');
  const protectedTokens = new RegExp(protectedSource, 'giu');
  const neighbor = (text, offset) => {
    let start = offset, end = offset + 1;
    const unit = text.charCodeAt(offset);
    if (unit >= 0xdc00 && unit <= 0xdfff && offset > 0) {
      const before = text.charCodeAt(offset - 1);
      if (before >= 0xd800 && before <= 0xdbff) start--;
    } else if (unit >= 0xd800 && unit <= 0xdbff && end < text.length) {
      const after = text.charCodeAt(end);
      if (after >= 0xdc00 && after <= 0xdfff) end++;
    }
    return /[\p{N}_@\u200c\u200d\u2060\ufeff]/u.test(text.slice(start, end));
  };
  const paragraph = (text, language, languageAt) => {
    const offsets = [];
    const protectedRanges = [...text.matchAll(protectedTokens)].map(match => ({start: match.index, end: match.index + match[0].length}));
    let protectedIndex = 0;
    for (const word of text.matchAll(words)) {
      const start = word.index, end = start + word[0].length;
      while (protectedIndex < protectedRanges.length && protectedRanges[protectedIndex].end <= start) protectedIndex++;
      if (protectedIndex < protectedRanges.length && protectedRanges[protectedIndex].start < end) continue;
      const locale = normalize(languageAt?.(start) ?? language);
      if (!['en', 'en-us', 'en-gb'].includes(locale)) continue;
      if ((start > 0 && neighbor(text, start - 1)) || (end < text.length && neighbor(text, end))) continue;
      if (languageAt) {
        let homogeneous = true;
        for (let at = start; at < end; at++) {
          if (normalize(languageAt(at) ?? language) !== locale) homogeneous = false;
        }
        if (!homogeneous) continue;
      }
      offsets.push(...matchers[locale === 'en-gb' ? 'gb' : 'us'](word[0]).map(cut => start + cut));
    }
    return offsets;
  };
  const checks = [
    ['😀 “dictionary” ‘hyphenation’', 'en-US', null, [7, 10, 19, 23]],
    ["'dictionary'", 'en-US', null, [4, 7]],
    ['dictionary', 'en-CA', null, []],
    ['dictionary', null, null, []],
    ['dictionary', 'en-US', at => at < 4 ? 'en-US' : 'en-GB', []],
    ['dictionary', null, () => 'EN_us', [3, 6]],
    ['dictionary', null, at => at < 4 ? 'en' : 'en-US', [3, 6]],
    ['dictionary Silbentrennung dictionary', null, offset => offset < 11 ? 'en-US' : offset < 25 ? 'de-DE' : 'en-GB', [3, 6, 29, 33]],
    ['dictionary (HTTPS://example.invalid). hyphenation', 'en-US', null, [3, 6, 40, 44]],
    ['`dictionary', 'en-US', null, [4, 7]],
    ['``dictionary`', 'en-US', null, [5, 8]],
    ['dictionary\u200bhyphenation', 'en-US', null, [3, 6, 13, 17]],
    ...['HTTPS://internationalization.example/dictionary', 'www.internationalization.example',
      'internationalization@dictionary.example', '`dictionary`', '``dictionary``',
      '```dictionary\nhyphenation```', '``dictionary `hyphenation` organization``',
      'dictionary\u200chyphenation', 'dictionary\u200dhyphenation',
      'dictionary\u2060hyphenation', 'dictionary\ufeffhyphenation'].map(text => [text, 'en-US', null, []]),
    ...["dictionary's", 'dictionary’s', 'dictionaryʼs', 'dictionary123', '123dictionary',
      'dictionary_name', 'name_dictionary', 'dictionary@grammar',
      '\u{1d7d8}dictionary', 'dictionary\u{1d7d8}'].map(text => [text, 'en-US', null, []]),
  ];
  for (const [text, language, languageAt, expected] of checks) {
    assert(JSON.stringify(paragraph(text, language, languageAt)) === JSON.stringify(expected), 'paragraph ' + text);
    result.paragraph_assertions++;
  }
  return result;
}

// Node CLI only. The evidence run evaluated the identical pure core above in
// functions.exec's V8 runtime; no Node, Dart or Flutter subprocess was run there.
async function main() {
  const {readFile} = await import('node:fs/promises');
  const {createHash} = await import('node:crypto');
  const root = new URL('../../../../', import.meta.url);
  const sourceInputs = JSON.parse(await readFile(new URL('source-inputs.json', import.meta.url), 'utf8'));
  const contents = {};
  for (const [path, entry] of Object.entries(sourceInputs.inputs)) {
    const raw = await readFile(new URL(path, root));
    assert(createHash('sha256').update(raw).digest('hex') === entry.sha256, 'source drift ' + path);
    contents[path] = raw.toString('utf8');
  }
  const prefix = 'packages/quds_office_engine/';
  const result = validateEnglishHyphenation({
    sources: {
      us: contents[prefix + 'third_party/hyphenation/hyph-en-us.tex'],
      gb: contents[prefix + 'third_party/hyphenation/hyph-en-gb.tex'],
    },
    generated: {
      us: contents[prefix + 'lib/src/bidi/english_us_hyphenation_data.dart'],
      gb: contents[prefix + 'lib/src/bidi/english_gb_hyphenation_data.dart'],
    },
    implementation: contents[prefix + 'lib/src/bidi/english_hyphenator.dart'],
  });
  console.log(JSON.stringify({
    source_commit: sourceInputs.source_commit,
    current_checkout_inputs_match: true,
    ...result,
  }, null, 2));
}
await main();

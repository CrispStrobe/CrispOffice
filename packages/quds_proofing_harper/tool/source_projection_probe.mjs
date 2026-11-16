// Independent semantic reference for the Dart Harper source projection.
// Run with: node packages/quds_proofing_harper/tool/source_projection_probe.mjs
// This is not a compiled-Dart, native-Harper, Wasm or browser acceptance test.
const segmenter = new Intl.Segmenter('en', {granularity: 'grapheme'});

function project(source) {
  const scalars = [];
  let offset = 0;
  for (const character of source) {
    if (character !== '\u00ad') {
      scalars.push({character, start: offset, end: offset + character.length});
    }
    offset += character.length;
  }
  const text = scalars.map(scalar => scalar.character).join('');
  const sourceBoundaries = new Set([0]);
  for (const part of segmenter.segment(source)) {
    sourceBoundaries.add(part.index + part.segment.length);
  }
  const checkBoundaries = new Set([0]);
  let scalarOffset = 0;
  for (const part of segmenter.segment(text)) {
    scalarOffset += [...part.segment].length;
    checkBoundaries.add(scalarOffset);
  }
  return {
    text,
    scalarLength: scalars.length,
    range(start, end) {
      if (start < 0 || end < start || end > scalars.length) throw new RangeError();
      if (!checkBoundaries.has(start) || !checkBoundaries.has(end)) return null;
      const from = start === scalars.length ? source.length : scalars[start].start;
      const to = start === end ? from : scalars[end - 1].end;
      return sourceBoundaries.has(from) && sourceBoundaries.has(to)
        ? {start: from, end: to} : null;
    },
  };
}

const checks = [];
function equal(name, actual, expected) {
  if (JSON.stringify(actual) !== JSON.stringify(expected)) {
    throw new Error(name + ': ' + JSON.stringify({actual, expected}));
  }
  checks.push(name);
}
function invalid(name, check) {
  try {
    check();
  } catch (error) {
    if (!(error instanceof RangeError)) throw error;
    checks.push(name);
    return;
  }
  throw new Error(name + ': invalid range was accepted');
}

const marked = project('😀 hy\u00adphen\u00adation.');
equal('normalized word after supplementary character', marked.text, '😀 hyphenation.');
equal('normalized scalar count', marked.scalarLength, 14);
equal('original word source interval', marked.range(2, 13), {start: 3, end: 16});
const edges = project('\u00adab\u00adcd\u00ad');
equal('left word excludes adjacent controls', edges.range(0, 2), {start: 1, end: 3});
equal('right word excludes adjacent controls', edges.range(2, 4), {start: 4, end: 6});
equal('full word includes internal control', edges.range(0, 4), {start: 1, end: 6});
equal('middle insertion follows omitted control', edges.range(2, 2), {start: 4, end: 4});
equal('end insertion follows trailing control', edges.range(4, 4), {start: 7, end: 7});
equal('empty source insertion', project('').range(0, 0), {start: 0, end: 0});
equal('control-only insertion', project('\u00ad\u00ad').range(0, 0), {start: 2, end: 2});
const literal = 'can’t co\u2011operate\u2060.\u00a0Next\r\nline.';
equal('other punctuation and controls preserved', project(literal).text, literal);
for (const source of ['e\u0301', 'e\u00ad\u0301']) {
  const projected = project(source);
  equal('partial accent ' + JSON.stringify(source), projected.range(0, 1), null);
  equal('insertion within accent ' + JSON.stringify(source), projected.range(1, 1), null);
  equal('whole accent ' + JSON.stringify(source), projected.range(0, 2), {start: 0, end: source.length});
}
const joined = project('👩‍💻x');
equal('partial joined emoji omitted', joined.range(0, 1), null);
equal('interior joined emoji omitted', joined.range(1, 2), null);
equal('whole joined emoji kept', joined.range(0, 3), {start: 0, end: 5});
equal('following character kept', joined.range(3, 4), {start: 5, end: 6});
for (const [start, end] of [[-1, 1], [2, 1], [0, 5], [5, 5]]) {
  invalid('invalid scalar interval ' + start + '..' + end, () => edges.range(start, end));
}
const repeatedSource = '😀 ab\u00adcd '.repeat(2000);
const repeated = project(repeatedSource);
for (let i = 0; i < 2000; i++) {
  const range = repeated.range(i * 7 + 2, i * 7 + 6);
  if (range.start !== i * 9 + 3 || range.end !== i * 9 + 8 ||
      repeatedSource.slice(range.start, range.end) !== 'ab\u00adcd') {
    throw new Error('large-source mapping at finding ' + i);
  }
}
checks.push('2000 finding ranges in a supplementary-character source');
const contract = project('😀 hy\u00adphen an test.');
equal('provider word range with segment origin', {
  start: contract.range(2, 8).start + 7,
  end: contract.range(2, 8).end + 7,
}, {start: 10, end: 17});
equal('provider grammar range with segment origin', {
  start: contract.range(9, 11).start + 7,
  end: contract.range(9, 11).end + 7,
}, {start: 18, end: 20});

console.log(JSON.stringify({
  validation_kind: 'Independent JavaScript semantic reference; not compiled Dart',
  passed: checks.length,
  failed: 0,
  range_stress_samples: 2000,
  checks,
}, null, 2));

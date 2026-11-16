#!/usr/bin/env node
// Independent JavaScript probes for a pinned Dart source snapshot.
// This does not compile or execute Dart. No external npm packages are used.
import { readFileSync } from 'node:fs';
import { resolve, dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { createHash } from 'node:crypto';
import { inflateRawSync } from 'node:zlib';

function runGermanAgreementProbes(source, positiveCases, cleanCases) {
  const table = [...source.matchAll(/_GermanPresentParadigm\(\s*'([^']+)',\s*'([^']+)',\s*'([^']+)',\s*'([^']+)',\s*'([^']+)',\s*'([^']+)',?\s*\)/g)].map(m => m.slice(1));
  if (table.length !== 9) throw Error('Expected nine source paradigms');
  const raw = (name, flags = 'iu') => {
    const declaration = source.match(new RegExp('static final RegExp ' + name + ' = RegExp\\(([\\s\\S]*?)\\n  \\);'));
    if (!declaration) throw Error('Missing source regex ' + name);
    const parts = [...declaration[1].matchAll(/r(['"])([\s\S]*?)\1/g)].map(m => m[2]);
    return {parts, expression: new RegExp(parts.join(''), flags)};
  };
  const forms = new Map();
  for (const row of table) for (const form of row.slice(1)) forms.set(form, row);
  const parts = raw('_pronounVerb').parts;
  const matcher = new RegExp(parts[0] + [...forms.keys()].join('|') + parts[1], 'giu');
  const protectedPattern = raw('_protectedTokens', 'gi').expression;
  const comparison = raw('_comparisonPrefix').expression;
  const coordination = raw('_coordinationPrefix').expression;
  const nominal = raw('_nominalPronounPrefix').expression;
  const dative = raw('_dativePrefix').expression;
  const subjectPattern = raw('_followingSubject').expression;
  const nounPattern = raw('_followingNoun', 'u').expression;
  const segmenter = new Intl.Segmenter('de', {granularity: 'grapheme'});
  const check = (text, startOffset = 0) => {
    const boundaries = new Set([0, text.length]);
    for (const item of segmenter.segment(text)) boundaries.add(item.index);
    const protectedRanges = [...text.matchAll(protectedPattern)].map(m => [m.index, m.index + m[0].length]);
    const findings = [];
    for (const match of text.matchAll(matcher)) {
      const start = match.index, end = start + match[0].length;
      if (protectedRanges.some(([a,b]) => a < end && b > start) || !boundaries.has(start)) continue;
      const subject = match[1].toLowerCase(), verb = match[2], lower = verb.toLowerCase();
      const row = forms.get(lower);
      if (!row || subject === 'ihr' && row[0] !== 'sein') continue;
      const replacement = row[({ich:1,du:2,wir:4,ihr:5})[subject]];
      if (replacement === lower) continue;
      const prefix = text.slice(Math.max(0, start - 96), start);
      if (comparison.test(prefix)) continue;
      const coord = coordination.exec(prefix);
      if (coord && (!coord[1] || !prefix.slice(0, coord.index).trimEnd().endsWith(',') || lower === row[4] || lower === row[5])) continue;
      if (match[1] !== subject && (nominal.test(prefix) || lower === 'ist' && ['ich','du'].includes(subject))) continue;
      if (subject === 'ihr') {
        if (lower === 'ist' || dative.test(prefix)) continue;
        const clause = text.slice(end, end + 160).split(/[.!?;:\r\n]/)[0];
        if (subjectPattern.test(clause) || nounPattern.test(clause)) continue;
      }
      const verbStart = end - verb.length;
      if (!boundaries.has(verbStart) || !boundaries.has(end)) continue;
      findings.push({original:verb,start:startOffset+verbStart,end:startOffset+end,replacement:verb === verb.toUpperCase() ? replacement.toUpperCase() : replacement});
    }
    return findings;
  };
  const checks = [];
  const assert = (label, condition, actual) => {
    if (!condition) throw Error(label + ': ' + JSON.stringify(actual));
    checks.push(label);
  };
  for (const [input, replacement] of positiveCases) {
    const text = '🙂 ' + input + ' hier.';
    const verb = input.split(' ').at(-1), actual = check(text,20);
    assert(input, actual.length === 1 && actual[0].replacement === replacement &&
      actual[0].original === verb && actual[0].start === 20+text.indexOf(verb) &&
      actual[0].end === 20+text.indexOf(verb)+verb.length, actual);
  }
  for (const text of cleanCases) {
    const actual = check(text);
    assert('valid: '+text, actual.length === 0, actual);
  }
  for (const row of table) for (const [subject,index] of [['ich',1],['du',2],['wir',4]]) {
    for (const form of new Set(row.slice(1))) {
      const text = subject+' '+form+' hier.';
      const actual = check(text);
      assert('matrix: '+text, form === row[index]
        ? actual.length === 0
        : actual.length === 1 && actual[0].replacement === row[index], actual);
    }
  }
  for (const space of [' ','\t','\u00a0','\u202f']) {
    const actual = check('ICH'+space+'HAST Zeit. WIR'+space+'KANN warten.');
    assert('horizontal/case '+JSON.stringify(space), JSON.stringify(actual.map(x=>x.replacement)) === '["HABE","KÖNNEN"]', actual);
  }
  const tick = String.fromCharCode(96);
  const guardedText = '🙂 '+tick+'ich hast'+tick+' '+tick+tick+'du hat'+tick+tick+' HTTPS://example.invalid/wir kann. ich hast\u200d. ich hast. ihr bist hier.';
  const guarded = check(guardedText);
  assert('protected/source boundaries', JSON.stringify(guarded.map(x=>x.replacement)) === '["habe","seid"]' && guarded[0].start === guardedText.lastIndexOf('hast'), guarded);
  const prior = check('Heute ich ist hier, und du ist dort.');
  assert('comma-separated independent clause',JSON.stringify(prior.map(x=>x.replacement))==='["bin","bist"]',prior);
  const previous = check('ICH BIST HIER. WIR IST DORT. ich IST hier.');
  assert('existing uppercase agreement', JSON.stringify(previous.map(x=>x.replacement))==='["BIN","SIND","BIN"]',previous);
  return {label:'Source-derived JavaScript probe, not compiled Dart',families:table.length,passed:checks.length,checks};
}

function runGermanSpellingProbes(source, dictionaries) {
  const standard = new Set(dictionaries.standard), swissAdditions = new Set(dictionaries.swiss);
  if (standard.size !== 444123 || swissAdditions.size !== 9451) throw Error('Shipped dictionary counts changed');
  const upper = word => word.replaceAll('ß','ss').toUpperCase();
  const title = word => word ? word[0].toUpperCase()+word.slice(1) : word;
  const sharpSCapitals = new Set([...standard].filter(word=>word.includes('ß')).map(upper));
  const alphabet = source.match(/static const String _alphabet = '([^']+)'/)[1];
  const normalize = word => word.normalize('NFC').replaceAll('\u00ad','').replace(/[\u2010\u2011]/g,'-');
  const exact = (word,swiss) => !(swiss && /[ßẞ]/.test(word)) && (standard.has(word) || swiss && swissAdditions.has(word));
  const contains = (word,swiss,sentenceInitial=false) => {
    if (exact(word,swiss)) return true;
    const lower = word.toLowerCase();
    if (word === upper(word) && word !== lower &&
        (!swiss && sharpSCapitals.has(word) || exact(lower,swiss) || exact(title(lower),swiss))) return true;
    if (sentenceInitial && word === title(lower) && exact(lower,swiss)) return true;
    if (word.includes('-')) return word.split('-').every((part,index)=>part && contains(part,swiss,sentenceInitial && index===0));
    return false;
  };
  let candidateVisits = 0;
  const suggest = (word,swiss,maximumSuggestions=5,maximumCandidateChecks=6000) => {
    if (maximumSuggestions===0 || !word || word.length>64) return [];
    if (word.includes('-')) {
      const parts = word.split('-'); let unknown=-1;
      if(parts.length<=8 && parts.every(Boolean)){
        for(let i=0;i<parts.length;i++){
          if(contains(parts[i],swiss,false))continue;
          if(unknown>=0){unknown=-2;break;}unknown=i;
        }
        if(unknown>=0){
          const compounds=[];
          for(const replacement of suggest(parts[unknown],swiss,maximumSuggestions,maximumCandidateChecks)){
            const corrected=[...parts];corrected[unknown]=replacement;const candidate=corrected.join('-');
            if(contains(candidate,swiss,false))compounds.push(candidate);
          }
          return compounds;
        }
      }
    }
    const found=new Set();let examined=0;
    const candidate=value=>{
      if(examined++>=maximumCandidateChecks || found.size>=maximumSuggestions || value===word)return;
      candidateVisits++;
      if(exact(value,swiss))found.add(value);
    };
    const lower=word.toLowerCase(), isUpper=word===upper(word)&&word!==lower, isTitle=word[0]===word[0].toUpperCase();
    const candidateCase=value=>{if(isTitle||isUpper)candidate(title(value));candidate(value);};
    candidate(lower);candidate(title(lower));candidate(word.replaceAll('ß','ss').replaceAll('ẞ','SS'));
    if(lower.includes('ß'))candidateCase(lower.replaceAll('ß','ss'));
    if(!swiss)for(const match of lower.matchAll(/ss/g))candidateCase(lower.slice(0,match.index)+'ß'+lower.slice(match.index+2));
    for(const [from,to] of [['ae','ä'],['oe','ö'],['ue','ü']])if(lower.includes(from))candidateCase(lower.replaceAll(from,to));
    for(let i=0;i+1<lower.length;i++)candidateCase(lower.slice(0,i)+lower[i+1]+lower[i]+lower.slice(i+2));
    for(let i=0;i<lower.length;i++)candidateCase(lower.slice(0,i)+lower.slice(i+1));
    for(let i=0;i<=lower.length&&examined<maximumCandidateChecks&&found.size<maximumSuggestions;i++){
      for(const letter of alphabet){
        if(examined>=maximumCandidateChecks||found.size>=maximumSuggestions)break;
        if(i<lower.length)candidateCase(lower.slice(0,i)+letter+lower.slice(i+1));
        candidateCase(lower.slice(0,i)+letter+lower.slice(i));
      }
    }
    return [...new Set([...found].map(value=>isUpper?upper(value):value))];
  };
  const style=(original,replacements)=>{
    const separators=[...original.matchAll(/[-\u2010\u2011]/g)].map(m=>m[0]);
    if(separators.every(s=>s==='-'))return replacements;
    return replacements.map(replacement=>{
      if((replacement.match(/-/g)||[]).length!==separators.length)return replacement;
      let index=0;return replacement.replace(/-/g,()=>separators[index++]);
    });
  };
  const checks=[], outputs=[];
  const assert=(label,ok,actual)=>{if(!ok)throw Error(label+': '+JSON.stringify(actual));checks.push(label);};
  for(const [original,expected,swiss=false] of [
    ['Huas-Tür','Haus-Tür'],['Haus-Tür-Huas','Haus-Tür-Haus'],
    ['HUAS-TÜR','HAUS-TÜR'],['Huas\u2010Tür','Haus\u2010Tür'],
    ['Huas\u2011Tür','Haus\u2011Tür'],['Huas-Tür\u2011Haus','Haus-Tür\u2011Haus'],
    ['Straße-Tür','Strasse-Tür',true],['STRAẞE-TÜR','STRASSE-TÜR',true],
  ]){
    candidateVisits=0;
    const actual=style(original,suggest(normalize(original),swiss));
    assert(original,actual.includes(expected)&&actual.length<=5&&candidateVisits<=6000,actual);
    outputs.push({original,expected,actual,candidateVisits});
  }
  for(const word of ['Haus-Tür','HAUS-TÜR','Haus-Tür-Haus'])assert('known '+word,contains(word,false),word);
  for(const word of ['haus-Tür','Huas-Türr','Erfundenx-Haus'])assert('unknown '+word,!contains(word,false),word);
  candidateVisits=0;
  const bounded=suggest('Huas-Tür',false,1,100);
  assert('bounded compound',JSON.stringify(bounded)==='["Haus-Tür"]'&&candidateVisits<=100,{bounded,candidateVisits});
  assert('suggestions disabled',suggest('Huas-Tür',false,0).length===0);
  assert('long unknown token',suggest('x'.repeat(65)+'-Tür',false).length===0);
  const decl=source.match(/static final RegExp _protectedTokens = RegExp\(([\s\S]*?)\n  \);/)[1];
  const pattern=[...decl.matchAll(/r(['"])([\s\S]*?)\1/g)].map(m=>m[2]).join('');
  const protectedRegex=new RegExp(pattern,'gi'), tick=String.fromCharCode(96);
  const closed=[
    tick+'Huas'+tick,tick+tick+'Huas '+tick+' inner'+tick+tick,
    tick+tick+tick+'dart\nHuas\n'+tick+tick+tick,
    tick+'HTTPS://example.invalid/Huas Huas'+tick,
    tick+'ich bist ['+tick,tick+tick+'ich bist '+tick+' ['+tick+'x'+tick+tick,
    tick+tick+tick+'dart\nich bist [\n'+tick+tick+tick,
  ];
  for(const code of closed){const actual=[...code.matchAll(protectedRegex)];assert('closed code '+code,actual.length===1&&actual[0][0]===code,actual);}
  for(const code of [tick+'Huas',tick+tick+'Huas'+tick,tick+tick+tick+'Huas'+tick+tick]){
    assert('unclosed code '+code,[...code.matchAll(protectedRegex)].length===0);
  }
  return {label:'Translated spelling algorithm probe against real shipped data; not compiled Dart',standardForms:standard.size,swissAdditions:swissAdditions.size,passed:checks.length,checks,outputs};
}


const root = resolve(process.argv[2] || '.');
const folder = dirname(fileURLToPath(import.meta.url));
const fixtures = JSON.parse(readFileSync(join(folder, 'cases.json'), 'utf8'));
const receipt = JSON.parse(readFileSync(join(folder, 'receipt.json'), 'utf8'));
const content = new Map();
for (const [path, expected] of Object.entries({
  ...receipt.binding.source_files, ...receipt.binding.dictionary_files,
})) {
  const bytes = readFileSync(join(root, path));
  const actual = createHash('sha1')
    .update(Buffer.from('blob ' + bytes.length + '\0')).update(bytes).digest('hex');
  if (actual !== expected) throw Error('Source blob mismatch: ' + path);
  content.set(path, bytes.toString('utf8'));
}
const dictionaries = {standard: [], swiss: []};
let chunks = 0;
for (const path of Object.keys(receipt.binding.dictionary_files)) {
  if (path.endsWith('german_lexicon_data.dart')) continue;
  const body = content.get(path).split('= <String>[')[1];
  const target = path.includes('swiss') ? dictionaries.swiss : dictionaries.standard;
  for (const piece of body.split(',')) {
    const encoded = [...piece.matchAll(/'([A-Za-z0-9+/=]+)'/g)].map(m => m[1]).join('');
    if (!encoded) continue;
    const decoded = inflateRawSync(Buffer.from(encoded, 'base64'), {
      maxOutputLength: 1048576,
    }).toString('utf8');
    target.push(...decoded.split('\n').filter(Boolean));
    chunks++;
  }
}
dictionaries.standard = [...new Set(dictionaries.standard)];
dictionaries.swiss = [...new Set(dictionaries.swiss)];
const grammar = runGermanAgreementProbes(
  content.get('packages/quds_office_engine/lib/src/proofing/german_writing_rules.dart'),
  fixtures.positive, fixtures.valid,
);
const spelling = runGermanSpellingProbes(
  content.get('packages/quds_office_engine/lib/src/proofing/german_spelling.dart'),
  dictionaries,
);
console.log(JSON.stringify({
  method: 'Source-derived grammar and translated spelling probes; not compiled Dart',
  source_commit: receipt.binding.source_commit,
  source_blobs_verified: Object.keys(receipt.binding.source_files).length,
  dictionary_blobs_verified: Object.keys(receipt.binding.dictionary_files).length,
  dictionary_chunks: chunks,
  runtime: process.versions,
  passed: grammar.passed + spelling.passed,
  grammar, spelling,
}, null, 2));

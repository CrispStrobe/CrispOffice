// Source-bound arithmetic checks; this does not compile or execute Dart.
import { readFileSync } from 'node:fs';
import { createHash } from 'node:crypto';

const source = readFileSync(
  new URL('../../../packages/quds_office_engine/lib/src/automation/office_vba_language.dart', import.meta.url),
  'utf8',
);
const expectedBlob = 'a105ddd700c3822cb775d6a5ee9385bc380f4e8f';
const actualBlob = createHash('sha1')
  .update('blob ' + Buffer.byteLength(source, 'utf8') + '\0')
  .update(source, 'utf8')
  .digest('hex');
if (actualBlob !== expectedBlob) {
  throw new Error('Compiler changed: expected ' + expectedBlob + ', got ' + actualBlob);
}
const reviewedBody = "  Object _wordUnitConversion(_Token token, Object value) {\n    // Every allowed integer is exactly representable as binary64. Promote\n    // before scaling so large metric intermediates cannot wrap on the VM.\n    final number = _number(value, token).toDouble();\n    final (unitsPerInput, unitsPerOutput) = _wordUnitConversions[token.lower]!;\n    final toPoints = token.lower.endsWith('topoints');\n    final factor = toPoints\n        ? unitsPerInput / unitsPerOutput\n        : unitsPerOutput / unitsPerInput;\n    final units = number * unitsPerInput;\n    // Use the integral conversion grid only when the input round-trips on it.\n    // This keeps 1.15 lines -> 13.8 points and 2.54 cm -> 72 points canonical\n    // without epsilon rounding or blanket snapping of off-grid inputs.\n    // The destination property's independent precision checks still apply.\n    final onGrid =\n        units.isFinite &&\n        units.abs() <= _maxExactInteger &&\n        units.round() / unitsPerInput == number;\n    final result = onGrid\n        ? units.round() / unitsPerOutput\n        : toPoints\n        ? number * factor\n        : number / factor;\n    if (!result.isFinite || result.abs() > _maxExactInteger) {\n      context.type(\n        token,\n        'Word unit conversion exceeds the finite numeric bound.',\n      );\n    }\n    return result;\n  }\n\n";

function checkArithmetic(source, reviewedBody) {
  const failures=[];
  const totals={sourceAssertions:0,physicalTwipRoundTrips:0,legacyLineComparisons:0,decimalCases:0,boundaryCases:0};
  function check(condition,label,kind) {
    totals[kind]++;
    if(!condition) failures.push(label);
  }
  const tableMatch=/const _wordUnitConversions = <String, \(int, int\)>\{([\s\S]*?)\n\};/.exec(source);
  if(!tableMatch) throw new Error("reviewed conversion table missing");
  const factors=Object.fromEntries([...tableMatch[1].matchAll(/'(\w+)': \((\d+), (\d+)\)/g)].map(m=>[m[1],[Number(m[2]),Number(m[3])]]));
  const wanted={
    linestopoints:[240,20],pointstolines:[20,240],
    inchestopoints:[1440,20],pointstoinches:[20,1440],
    centimeterstopoints:[72000,2540],pointstocentimeters:[2540,72000],
    millimeterstopoints:[7200,2540],pointstomillimeters:[2540,7200],
    picastopoints:[240,20],pointstopicas:[20,240]
  };
  check(JSON.stringify(factors)===JSON.stringify(wanted),"exact reviewed scale map","sourceAssertions");
  const actualBody=source.slice(source.indexOf("  Object _wordUnitConversion("),source.indexOf("  void _requireCompleteWordLineSpacing()"));
  check(actualBody===reviewedBody,"exact reviewed Dart evaluator body","sourceAssertions");
  check((source.match(/_wordUnitConversions\.containsKey\(/g)||[]).length===5,"five checker/reservation/evaluator map lookups","sourceAssertions");
  check(!source.includes("_wordUnitConversions.contains("),"no stale set lookup","sourceAssertions");
  const limit=9007199254740991;
  function round(value) {return value<0?-Math.round(-value):Math.round(value);}
  function finish(value) {
    return !Number.isFinite(value)||Math.abs(value)>limit ? "bound-error" : value;
  }
  function convert(number,name) {
    const [input,output]=factors[name];
    const toPoints=name.endsWith("topoints");
    const factor=toPoints?input/output:output/input;
    const units=number*input;
    const onGrid=Number.isFinite(units)&&Math.abs(units)<=limit&&round(units)/input===number;
    return finish(onGrid?round(units)/output:toPoints?number*factor:number/factor);
  }
  function legacy(number,toPoints) {
    const input=toPoints?240:20;
    const output=toPoints?20:240;
    const units=number*input;
    const onGrid=Number.isFinite(units)&&Math.abs(units)<=limit&&round(units)/input===number;
    return finish(onGrid?round(units)/output:toPoints?number*12:number/12);
  }
  const families=[
    ["inches",1440,1],["centimeters",72000,127],
    ["millimeters",7200,127],["picas",240,1],["lines",240,1]
  ];
  for (const [name,denominator,numerator] of families) {
    for(let twips=-10000;twips<=10000;twips++) {
      const points=twips/20;
      const unitValue=(twips*numerator)/denominator;
      check(convert(unitValue,name+"topoints")===points,name+" to points at "+twips+" twips","physicalTwipRoundTrips");
      check(convert(points,"pointsto"+name)===unitValue,"points to "+name+" at "+twips+" twips","physicalTwipRoundTrips");
    }
  }
  const legacyInputs=[0,-0,1.15,-1.15,13.8,-13.8,71.99999999999999,1.1499999999999997,limit,-limit,Number.MIN_VALUE,-Number.MIN_VALUE];
  let seed=0x51dbeab;
  for(let i=0;i<5000;i++) {
    seed=(Math.imul(seed,1664525)+1013904223)>>>0;
    const exponent=(seed%352)-300;
    seed=(Math.imul(seed,1664525)+1013904223)>>>0;
    const value=(1+seed/4294967296)*2**exponent;
    legacyInputs.push(i%2?value:-value);
  }
  for(const number of legacyInputs) {
    for(const [name,toPoints] of [["linestopoints",true],["pointstolines",false]]) {
      check(Object.is(convert(number,name),legacy(number,toPoints)),name+" legacy "+number,"legacyLineComparisons");
    }
  }
  const decimals=[
    ["inchestopoints",.2,14.4],["inchestopoints",.1,7.2],
    ["inchestopoints",.05,3.6],["picastopoints",1.15,13.8],
    ["centimeterstopoints",.127,3.6],["centimeterstopoints",.254,7.2],
    ["centimeterstopoints",.635,18],["centimeterstopoints",1.27,36],
    ["millimeterstopoints",1.27,3.6],["millimeterstopoints",2.54,7.2],
    ["millimeterstopoints",6.35,18],["millimeterstopoints",12.7,36]
  ];
  for(const [name,input,output] of decimals) check(convert(input,name)===output,name+" decimal "+input,"decimalCases");
  for(const name of ["inches","centimeters","millimeters","picas"]) {
    check(convert(limit,name+"topoints")==="bound-error",name+" positive overflow","boundaryCases");
    check(convert(-limit,name+"topoints")==="bound-error",name+" negative overflow","boundaryCases");
    check(typeof convert(limit,"pointsto"+name)==="number",name+" inverse upper bound","boundaryCases");
  }
  for(const [name,input] of [
    ["inchestopoints",.20000000000000004],
    ["picastopoints",1.1499999999999997],
    ["centimeterstopoints",2.5400000000000005],
    ["millimeterstopoints",25.40000000000001],
    ["centimeterstopoints",1],["millimeterstopoints",1]
  ]) {
    const value=convert(input,name);
    check(typeof value==="number"&&round(value*20)/20!==value,name+" retains native off-grid value "+input,"boundaryCases");
  }
  check(convert(25.400000000000002,"millimeterstopoints")===72,"ordinary binary64 neighbor rounds to canonical 72 without epsilon","boundaryCases");
  return {
    kind:"source-bound JavaScript arithmetic transcription",
    limitations:"Not Dart execution, Dart analysis, compiled Dart JavaScript, native package tests, CLI tests, or installed Microsoft Word differential testing.",
    baselineCompilerBlob:"bc00a76840eb300b5f955c0cf119e70ad4ac5829",
    totals,
    totalAssertions:Object.values(totals).reduce((a,b)=>a+b,0),
    passed:failures.length===0,failures,
    physicalRatios:factors,
    twipProbeRange:{first:-10000,last:10000},
    legacyRandomSeed:"0x51dbeab"
  };
}

function checkIntegerPromotion() {
  const max=9007199254740991n;
  const scales=[20,240,1440,2540,7200,72000];
  let checks=0;
  const failures=[];
  const numbers=[0,1,2,100,100000000000,100000000000000,Number.MAX_SAFE_INTEGER,Math.floor(Number.MAX_SAFE_INTEGER/72000),Math.floor(Number.MAX_SAFE_INTEGER/72000)+1,Math.floor(2**63/72000)-1,Math.floor(2**63/72000),Math.floor(2**63/72000)+1];
  let seed=0x5eeda;
  for(let i=0;i<5000;i++){
    seed=(Math.imul(seed,1664525)+1013904223)>>>0;
    numbers.push(Math.floor(seed/4294967296*Number.MAX_SAFE_INTEGER));
  }
  for(const input of numbers)for(const sign of [1,-1])for(const scale of scales){
    const number=input*sign;
    const raw=BigInt.asIntN(64,BigInt(number)*BigInt(scale));
    const magnitude=raw<0n?-raw:raw;
    const before=magnitude<=max&&Number(raw)/scale===number;
    const units=number*scale;
    const rounded=units<0?-Math.round(-units):Math.round(units);
    const after=Math.abs(units)<=Number.MAX_SAFE_INTEGER&&rounded/scale===number;
    checks++;
    if(before!==after)failures.push({number,scale,before,after,raw:String(raw)});
  }
  return {
    kind:"V8 plus BigInt simulation of signed 64-bit integer scale intermediates",
    cases:checks,
    passed:failures.length===0,
    failures,
    limits:"Arithmetic model only, not Dart execution; checks grid decisions for permitted integer inputs."
  };
}

const report = checkArithmetic(source, reviewedBody);
report.integerPromotion = checkIntegerPromotion();
report.source = {
  path: 'packages/quds_office_engine/lib/src/automation/office_vba_language.dart',
  gitBlob: actualBlob,
  baselineCommit: 'c954d00d2fc85604ae394674bca91ea8a1dede0e',
};
console.log(JSON.stringify(report, null, 2));
if (!report.passed || !report.integerPromotion.passed) process.exitCode = 1;

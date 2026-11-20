import { readFileSync } from 'node:fs';
import { createHash } from 'node:crypto';

// From the repository root: node docs/validation/word-vba-unit-conversions-20261120/check-main-arithmetic.mjs
// Optional first argument: an exact compiler source file to inspect.
const expectedEvaluator = "  Object _evaluateWordUnitCall(_Token token, List<_Expr> arguments) {\n    // The checker has validated the one required positional/named argument.\n    // Evaluate only its value, once, retaining ordinary expression work limits.\n    final argument = arguments.single;\n    final value = argument is _NamedArgument ? argument.value : argument;\n    final number = _number(_evaluate(value), token).toDouble();\n    final conversion = _wordUnitConversions[token.lower]!;\n    final numerator = conversion.numerator;\n    final denominator = conversion.denominator;\n    var result = number * numerator / denominator;\n\n    // Canonicalize an exact native-grid value only when converting it back\n    // reproduces the input double. No epsilon or tolerance snaps near misses.\n    // Bound integer products to the VM/JavaScript common exact-integer range.\n    final toPoints = token.lower.endsWith('topoints');\n    final units = (toPoints ? result : number) * 20;\n    final multiplier = toPoints ? denominator : numerator;\n    if (units.isFinite && units.abs() <= _maxExactInteger / multiplier) {\n      final twips = units.round();\n      if (toPoints) {\n        if (twips * denominator / (20 * numerator) == number) {\n          result = twips / 20;\n        }\n      } else if (twips / 20 == number) {\n        result = twips * numerator / (20 * denominator);\n      }\n    }\n    if (!result.isFinite || result.abs() > _maxExactInteger) {\n      context.type(\n        token,\n        'Word unit conversion exceeds the finite numeric bound.',\n      );\n    }\n    return result;\n  }\n";
const expectedChecker = "  void _wordUnitCall(_Token token, List<_Expr>? arguments) {\n    if (arguments == null || arguments.length != 1) {\n      context.type(token, '${token.text} requires one numeric argument.');\n    }\n    final argument = arguments.single;\n    if (argument is _OmittedArgument) {\n      context.type(argument.token, '${token.text} requires its argument.');\n    }\n    if (argument is _NamedArgument &&\n        argument.token.lower != _wordUnitConversions[token.lower]!.parameter) {\n      context.fail(\n        argument.token,\n        'vba_name_error',\n        'Unknown named argument ${argument.token.text} for ${token.text}.',\n      );\n    }\n    final value = argument is _NamedArgument ? argument.value : argument;\n    _compatible(_Kind.number, _expression(value), value.token);\n  }\n";

function runCurrentChecks(source) {
  const checks = [];
  const add = (category, label, ok, detail = null) => checks.push({category, label, ok, ...(detail === null ? {} : {detail})});
  const capture = (start, end) => {
    const from = source.indexOf(start);
    return from < 0 ? null : source.slice(from, source.indexOf(end, from));
  };
  add('source', 'exact reviewed evaluator body', capture('  Object _evaluateWordUnitCall(', '\n  void _requireCompleteWordLineSpacing()') === expectedEvaluator);
  add('source', 'exact reviewed named checker body', capture('  void _wordUnitCall(', '\n  List<_Expr> _arguments(') === expectedChecker);
  const rawTable = source.match(/const _wordUnitConversions =\s*<String, \(\{String parameter, int numerator, int denominator\}\)>\{([\s\S]*?)\n\s*\};/);
  if (!rawTable) throw new Error('Conversion metadata table not found');
  const table = Object.fromEntries([...rawTable[1].matchAll(/'([a-z]+)':\s*\(\s*parameter:\s*'([a-z]+)',\s*numerator:\s*(\d+),\s*denominator:\s*(\d+),?\s*\)/g)].map(m => [m[1], {parameter:m[2], numerator:Number(m[3]), denominator:Number(m[4])}]));
  const expected = {
    inchestopoints:['inches',72,1], pointstoinches:['points',1,72],
    centimeterstopoints:['centimeters',3600,127], pointstocentimeters:['points',127,3600],
    millimeterstopoints:['millimeters',360,127], pointstomillimeters:['points',127,360],
    picastopoints:['picas',12,1], pointstopicas:['points',1,12],
    linestopoints:['lines',12,1], pointstolines:['points',1,12]
  };
  add('source', 'exact ten-function metadata and official parameter names',
      Object.keys(table).length === 10 && Object.entries(expected).every(([name,[p,n,d]]) => table[name]?.parameter === p && table[name].numerator === n && table[name].denominator === d));
  add('source', 'all five host-aware map lookup sites',
      (source.match(/_wordUnitConversions\.containsKey\(/g) || []).length === 5 &&
      (source.match(/_wordUnitConversions\.contains\(/g) || []).length === 0);
  const max = 9007199254740991;
  const round = n => n < 0 ? -Math.round(-n) : Math.round(n);
  function convert(name, number) {
    name = name.toLowerCase();
    if (!Number.isFinite(number) || Math.abs(number) > max) throw new RangeError('input bound');
    const {numerator,denominator} = table[name];
    let result = number * numerator / denominator;
    const toPoints = name.endsWith('topoints');
    const units = (toPoints ? result : number) * 20;
    const multiplier = toPoints ? denominator : numerator;
    if (Number.isFinite(units) && Math.abs(units) <= max / multiplier) {
      const twips = round(units);
      if (toPoints) {
        if (twips * denominator / (20 * numerator) === number) result = twips / 20;
      } else if (twips / 20 === number) {
        result = twips * numerator / (20 * denominator);
      }
    }
    if (!Number.isFinite(result) || Math.abs(result) > max) throw new RangeError('result bound');
    return result;
  }
  function expression(text) {
    text = text.trim();
    const call = text.match(/^([A-Za-z]+)\((.*)\)$/);
    if (!call) return Number(text);
    return convert(call[1], expression(call[2]));
  }
  const basic = [
    ['InchesToPoints',1,72],['PointsToInches',72,1],
    ['CentimetersToPoints',2.54,72],['PointsToCentimeters',72,2.54],
    ['MillimetersToPoints',25.4,72],['PointsToMillimeters',72,25.4],
    ['PicasToPoints',6,72],['PointsToPicas',72,6],
    ['LinesToPoints',1.15,13.8],['PointsToLines',13.8,1.15]
  ];
  for (const [name,input,want] of basic) {
    add('reference', name, convert(name,input) === want);
    add('reference', name+' zero', convert(name,0) === 0);
    add('reference', name+' negative', convert(name,-input) === -want);
  }
  const canonical = [
    ['InchesToPoints(0.2)',14.4],['InchesToPoints(0.1)',7.2],['InchesToPoints(0.05)',3.6],
    ['PicasToPoints(1.15)',13.8],['CentimetersToPoints(0.127)',3.6],
    ['CentimetersToPoints(0.254)',7.2],['CentimetersToPoints(0.635)',18],['CentimetersToPoints(1.27)',36],
    ['MillimetersToPoints(1.27)',3.6],['MillimetersToPoints(2.54)',7.2],['MillimetersToPoints(6.35)',18],
    ['MillimetersToPoints(12.7)',36],['InchesToPoints(PointsToInches(14.4))',14.4],
    ['CentimetersToPoints(PointsToCentimeters(3.6))',3.6],['MillimetersToPoints(PointsToMillimeters(3.6))',3.6],
    ['PicasToPoints(PointsToPicas(13.8))',13.8],['LinesToPoints(PointsToLines(13.8))',13.8]
  ];
  for (const [text,want] of canonical) add('retained_canonical_fixture',text,expression(text) === want);
  for (const text of [
    'CentimetersToPoints(1)','MillimetersToPoints(1)','InchesToPoints(0.20000000000000004)',
    'PicasToPoints(1.1499999999999997)','CentimetersToPoints(2.5400000000000005)',
    'MillimetersToPoints(25.40000000000001)'
  ]) {
    const value = expression(text);
    add('retained_native_precision_refusal',text,round(value*20)/20 !== value,{value});
  }
  for (const [name,input,want,tolerance] of [
    ['CentimetersToPoints',1,3600/127,1e-12],['MillimetersToPoints',1,360/127,1e-12],
    ['PointsToCentimeters',1,127/3600,1e-15],['PointsToMillimeters',1,127/360,1e-15],
    ['CentimetersToPoints',200000000000000,200000000000000*3600/127,1],
    ['PointsToCentimeters',max,max*127/3600,0.125]
  ]) add('retained_scalar_fixture',name+'('+input+')',Math.abs(convert(name,input)-want) <= tolerance);
  for (const value of [71.99999999999999,1e-20,0.00001,max]) {
    add('legacy_inverse_fallback','PointsToLines('+value+')',convert('PointsToLines',value) === value/12);
  }
  for (const name of ['InchesToPoints','CentimetersToPoints','MillimetersToPoints','PicasToPoints']) {
    let rejected = false;
    try {convert(name,max);} catch (error) {rejected = error instanceof RangeError;}
    add('result_bound',name,rejected);
  }
  for (const value of [NaN,Infinity,-Infinity,max+1,-max-1]) {
    let rejected = false;
    try {convert('PointsToInches',value);} catch (error) {rejected = error instanceof RangeError;}
    add('input_bound',String(value),rejected);
  }
  const twips = [-2147483647,-7201,-1440,-276,-1,0,1,3,7,12,72,127,276,288,1440,7201,2147483647];
  for (const [forward,inverse,denominator,numerator] of [
    ['LinesToPoints','PointsToLines',240,1],['InchesToPoints','PointsToInches',1440,1],
    ['CentimetersToPoints','PointsToCentimeters',72000,127],
    ['MillimetersToPoints','PointsToMillimeters',7200,127],['PicasToPoints','PointsToPicas',240,1]
  ]) {
    for (const t of twips) {
      const unit = t*numerator/denominator,point=t/20;
      add('selected_twip_boundaries',forward+' twip '+t,convert(forward,unit) === point);
      add('selected_twip_boundaries',inverse+' twip '+t,convert(inverse,point) === unit);
    }
  }
  const counts = {};
  for (const c of checks) counts[c.category]=(counts[c.category]||0)+1;
  return {
    schema_version:1,compiler_blob:'07dc3c5737661abaf3b17db24439c71482de22ed',
    source_main:'b01cb23dc1b7bc94b691d68a2507b61dc6d48d7a',
    scope:'Exact-source-bound JavaScript numeric transcription and source-shape checks only. No Dart parsing, compilation, VM, compiled-Dart-JavaScript, native document or test execution.',
    table,assertions:checks.length,counts,passed:checks.every(c=>c.ok),
    failures:checks.filter(c=>!c.ok),
    inspected_native_precision_cases:checks.filter(c=>c.category==='retained_native_precision_refusal').map(c=>({expression:c.label,...c.detail,refused:c.ok})),
    dart_tests_executed:0
  };
}

const sourcePath = process.argv[2] ?? 'packages/quds_office_engine/lib/src/automation/office_vba_language.dart';
const bytes = readFileSync(sourcePath);
const blob = createHash('sha1').update(Buffer.from('blob ' + bytes.length + '\0')).update(bytes).digest('hex');
if (blob !== '07dc3c5737661abaf3b17db24439c71482de22ed') throw new Error('Compiler blob does not match reviewed main source: ' + blob);
const result = runCurrentChecks(bytes.toString('utf8'));
process.stdout.write(JSON.stringify(result, null, 2) + '\n');
if (!result.passed) process.exitCode = 1;

// Arithmetic model for review; not the Dart compiler or runtime.
// Models the adopted named-conversion source blob 07dc3c5737661abaf3b17db24439c71482de22ed.
function convert(name, value) {
  const ratios = {
    linestopoints:[12,1], pointstolines:[1,12],
    inchestopoints:[72,1], pointstoinches:[1,72],
    centimeterstopoints:[3600,127], pointstocentimeters:[127,3600],
    millimeterstopoints:[360,127], pointstomillimeters:[127,360],
    picastopoints:[12,1], pointstopicas:[1,12]
  };
  const max=9007199254740991;
  if(typeof value!=="number"||!Number.isFinite(value)||Math.abs(value)>max) throw new Error("input");
  name=name.toLowerCase();
  const [numerator,denominator]=ratios[name];
  let result=value*numerator/denominator;
  const toPoints=name.endsWith("topoints");
  const units=(toPoints?result:value)*20;
  const multiplier=toPoints?denominator:numerator;
  const round=x=>x<0?-Math.round(-x):Math.round(x);
  if(Number.isFinite(units)&&Math.abs(units)<=max/multiplier){
    const twips=round(units);
    if(toPoints){
      if(twips*denominator/(20*numerator)===value) result=twips/20;
    }else if(twips/20===value){
      result=twips*numerator/(20*denominator);
    }
  }
  if(!Number.isFinite(result)||Math.abs(result)>max)throw new Error("overflow");
  return result;
}
const physicalCases = [
  ["InchesToPoints",0.5,36],["PointsToInches",36,0.5],
  ["CentimetersToPoints",2.54,72],["PointsToCentimeters",72,2.54],
  ["MillimetersToPoints",25.4,72],["PointsToMillimeters",72,25.4],
  ["PicasToPoints",1.5,18],["PointsToPicas",18,1.5],
  ["InchesToPoints",0.1,7.2],["InchesToPoints",0.15,10.8],
  ["PicasToPoints",1.15,13.8],["CentimetersToPoints",1.27,36],
  ["MillimetersToPoints",12.7,36],["CentimetersToPoints",0.127,3.6],
  ["MillimetersToPoints",1.27,3.6],
  ["CentimetersToPoints",200000000000000,5669291338582677],
  ["MillimetersToPoints",2000000000000000,5669291338582677],
  ["PointsToMillimeters",9007199254740991,3177539737089183],
  ["InchesToPoints",125099989649180,9007199254740960],
  ["PicasToPoints",750599937895082,9007199254740984],
  ["MillimetersToPoints",3177539737089183,9007199254740991]
];
const results = [];
for (const [name,input,expected] of physicalCases) {
  const actual=convert(name,input);
  if(actual!==expected) throw new Error(name+"("+input+") expected "+expected+" got "+actual);
  results.push({name,input,expected,actual});
  if(convert(name,-input)!==-expected || convert(name,0)!==0) throw new Error("sign/zero "+name);
}
const nativeValues = [-1584,-108,-72,-36,-18,-13.8,-7.2,-3.6,-0.05,0,0.05,3.6,7.2,13.8,18,36,72,108,1584];
let nativeRoundTrips=0;
for(const unit of ["Inches","Centimeters","Millimeters","Picas"])for(const points of nativeValues){
 const result=convert(unit+"ToPoints",convert("PointsTo"+unit,points));
 if(result!==points) throw new Error("round-trip "+unit+" "+points+" "+result);
 nativeRoundTrips++;
}
const nearCases=[
 ["InchesToPoints",0.10000000000000002],
 ["PicasToPoints",1.1499999999999997],
 ["CentimetersToPoints",0.25400000000000006],
 ["MillimetersToPoints",2.5400000000000005],
 ["InchesToPoints",0.20000000000000004],
 ["CentimetersToPoints",2.5400000000000005],
 ["MillimetersToPoints",25.40000000000001],
 ["CentimetersToPoints",1],
 ["MillimetersToPoints",1]
];
const refusedNative=nearCases.map(([name,input])=>{
 const result=convert(name,input);
 if(Math.round(result*20)/20===result)throw new Error("Unexpected native precision: "+name+" "+input);
 return {name,input,result,nativeExact:false};
});
let overflows=0;
for(const [name,input] of [
 ["InchesToPoints",125099989649181],
 ["PicasToPoints",750599937895083],
 ["MillimetersToPoints",3177539737089184],
 ["InchesToPoints",9007199254740991],
 ["PicasToPoints",9007199254740991],
 ["CentimetersToPoints",9007199254740991],
 ["MillimetersToPoints",9007199254740991]
]){
 for(const sign of [1,-1]){
  let rejected=false;try{convert(name,input*sign);}catch(e){if(e.message!=="overflow")throw e;rejected=true;}
  if(!rejected)throw new Error("Expected overflow "+name+" "+input*sign);
  overflows++;
 }
}
const report={
 qualification:"Independent V8 arithmetic model only; no Dart source, compiler, VM, JS compilation or native document runtime executed.",
 physicalCases:results,
 signAndZeroChecks:physicalCases.length*2,
 nativeRoundTrips,
 nativePrecisionRefusals:refusedNative,
 conversionOverflowRefusals:overflows,
 status:"passed"
};


console.log(JSON.stringify(report, null, 2));

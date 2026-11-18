#!/usr/bin/env python3
"""Read-only independent audit of portable, example and timezone results."""
from datetime import datetime,timezone
import ast,collections,gzip,hashlib,json,os
from pathlib import Path,PurePosixPath
import subprocess,tarfile
from urllib.parse import unquote,urlparse

ROOT=Path("/workspace/scratch/eddfdfc8cc56")
REPO=ROOT/"quds_office_suite"
WORK=ROOT/"flutter-qualification/workspace"
RUNS=ROOT/"flutter-qualification/runs"
OUT=ROOT/"flutter-qualification/independent-audit"
SOURCE="9d060658ee6be8ec97d73f56b9aec10d346b7952"
findings=[];checks=0
def sha(data):return hashlib.sha256(data).hexdigest()
def raw(path):
 p=Path(path);return os.readlink(p).encode() if p.is_symlink() else p.read_bytes()
def fsha(path):return sha(raw(path))
def read(path):return json.loads(Path(path).read_text())
def gread(path):return json.loads(gzip.decompress(Path(path).read_bytes()))
def check(value,name,detail=None):
 global checks
 checks+=1
 if not value:findings.append({"check":name,"detail":detail})
 return bool(value)
def git(*args):return subprocess.check_output(["git","-C",str(REPO),*args],env=dict(os.environ,GIT_OPTIONAL_LOCKS="0"))
def events(data):
 result=[]
 for line in data.decode(errors="replace").splitlines():
  try:x=json.loads(line)
  except ValueError:continue
  if isinstance(x,dict):result.append(x)
 return result
def resolved(path,cwd):
 if path.startswith("file:"):path=unquote(urlparse(path).path)
 p=Path(path);return str((p if p.is_absolute() else cwd/p).resolve())
def review_events(data,selected,cwd,summary,expected_count,label):
 ev=events(data)
 starts=[e["test"] for e in ev if e.get("type")=="testStart"]
 ends=[e for e in ev if e.get("type")=="testDone"]
 suites=[e["suite"] for e in ev if e.get("type")=="suite"]
 check(len({x["id"] for x in starts})==len(starts),"unique-start-ids",label)
 check(len({x["testID"] for x in ends})==len(ends),"unique-end-ids",label)
 check({x["id"] for x in starts}=={x["testID"] for x in ends},"every-start-finished",label)
 check(len({x["id"] for x in suites})==len(suites),"unique-suite-ids",label)
 paths=[resolved(s["path"],cwd) for s in suites]
 expected=[str((cwd/p).resolve()) for p in selected]
 check(len(paths)==len(set(paths))==len(expected) and set(paths)==set(expected),"exact-selected-suites",label)
 by_id={x["id"]:x for x in starts}
 completed=[];hidden=0;counts=collections.Counter()
 for e in ends:
  t=by_id[e["testID"]]
  outcome="skipped" if e.get("skipped") else e.get("result","unknown")
  check(outcome=="success","all-visible-and-hidden-events-success",{"gate":label,"name":t["name"],"outcome":outcome})
  if e.get("hidden"):hidden+=1;continue
  counts[outcome]+=1
  completed.append({"test_id":e["testID"],"suite_id":t["suiteID"],"name":t["name"],"outcome":outcome})
 done=[e for e in ev if e.get("type")=="done"]
 check(len(done)==1 and done[0].get("success") is True,"final-successful-done",label)
 check(not [e for e in ev if e.get("type")=="error"],"no-error-events",label)
 check(counts=={"success":expected_count},"expected-success-count",{"gate":label,"counts":dict(counts)})
 check(summary["completed_tests"]==completed and summary["raw_runner_outcomes"]==dict(counts),"summary-exact-raw-events",label)
 check(summary["raw_success_count"]==summary["substantive_success_count"]==expected_count,"summary-substantive-count",label)
 check(summary["passed"] and all(not summary[x] for x in ["allowed_skipped_cases","unexpected_skipped_cases","excluded_success_cases","errors","missing_selected_suites","unexpected_suites"]),"summary-no-skips-errors-exclusions",label)
 return {"selected_suites":len(selected),"observed_suites":len(suites),"started_events":len(starts),
         "completed_events":len(ends),"hidden_events":hidden,"substantive_success_count":expected_count,
         "case_names":[x["name"] for x in completed],"suite_paths":paths,"done":done[0]}

def verify_streams(folder,pins,label):
 streams={}
 for name,pin in pins.items():
  packed=(folder/(name+".gz")).read_bytes();data=gzip.decompress(packed)
  check(sha(packed)==pin["compressed_sha256"] and sha(data)==pin["sha256"] and len(data)==pin["bytes"],"stream-full-hashes",{"gate":label,"stream":name})
  streams[name]=data
 return streams
def archive_audit(name):
 ap=RUNS/(name+"-9d060658.tar.xz");ip=RUNS/(name+"-9d060658.tar.index.json")
 idx=read(ip);indexed={r["path"]:r for r in idx["members"]}
 check(len(indexed)==len(idx["members"])==idx["member_count"],"archive-index-unique",name)
 check(fsha(ap)==idx["sha256"] and ap.stat().st_size==idx["bytes"],"archive-full-hash-size",name)
 rows=[];seen=set()
 with tarfile.open(ap,"r:xz") as tf:
  for m in tf:
   p=PurePosixPath(m.name)
   safe=m.isfile() and not p.is_absolute() and ".." not in p.parts and m.name not in seen
   check(safe,"archive-safe-unique-member",{"gate":name,"path":m.name})
   if not safe:continue
   seen.add(m.name);data=tf.extractfile(m).read();pin=indexed[m.name]
   matches=len(data)==pin["bytes"] and sha(data)==pin["sha256"]
   check(matches,"archive-member-hash",{"gate":name,"path":m.name})
   live=ROOT/"office-retry-20261118/setup/run_supplemental_gates.py" if m.name=="run_supplemental_gates.py" else RUNS/(name+"-9d060658")/m.name
   check(data==live.read_bytes(),"archive-member-live-evidence-identity",{"gate":name,"path":m.name})
   rows.append({"path":m.name,"bytes":len(data),"sha256":sha(data),"matches":matches})
 check(seen==set(indexed),"archive-exact-member-set",name)
 return {"archive":str(ap),"sha256":fsha(ap),"bytes":ap.stat().st_size,"index_sha256":fsha(ip),"members":rows}

started=datetime.now(timezone.utc).isoformat()
check(git("rev-parse","HEAD").decode().strip()==SOURCE and not git("status","--porcelain").decode().strip(),"source-head-clean-at-start")
baseline={k:gread(OUT/v) for k,v in {"source":"source-baseline.json.gz","dependencies":"dependency-baseline.json.gz","runtime":"runtime-baseline.json.gz","workspace":"workspace-baseline.json.gz"}.items()}
portable_script=REPO/"docs/validation/gector-office-resume-20261117/run_portable.py"
tree=ast.parse(portable_script.read_text())
portable_tests=next(ast.literal_eval(n.value) for n in tree.body if isinstance(n,ast.Assign) and any(isinstance(t,ast.Name) and t.id=="TESTS" for t in n.targets))
check(len(portable_tests)==17,"portable-seventeen-source-selected-files")
gates={}
for name in ["portable","editor-example","calendar-timezones"]:
 folder=RUNS/(name+"-9d060658");result=folder/"result"
 receipt=read(result/"receipt.json");outer=read(folder/"orchestration.json")
 before=gread(result/"inputs-before.json.gz");after=gread(result/"inputs-after.json.gz")
 check(outer["source_commit"]==receipt["source_commit"]==SOURCE and outer["exit_code"]==0 and outer["passed"] and receipt["passed"] and receipt["head_unchanged"],"gate-source-outer-child-acceptance",name)
 check(not outer["github_actions_queried_or_awaited"] and not receipt["github_actions_queried_or_awaited"],"no-ci-claims",name)
 check(not receipt.get("historical_results_counted",receipt.get("historical_outcomes_counted",False)),"no-historical-counting",name)
 check(before==after and (result/"inputs-before.json.gz").read_bytes()==(result/"inputs-after.json.gz").read_bytes(),"all-input-maps-byte-identical",name)
 for group in before:
  check(receipt["input_integrity"].get(group+"_unchanged") is True and before[group]==after[group],"every-input-integrity-flag",{"gate":name,"group":group})
  if group in baseline:check(before[group]==baseline[group],"independent-baseline-match",{"gate":name,"group":group})
  if group in ["harness","node"]:
   for path,pin in after[group].items():check(fsha(path)==pin,"live-harness-or-node-hash",{"gate":name,"path":path})
 review={"outer_exit_code":outer["exit_code"],"receipt_sha256":fsha(result/"receipt.json"),"orchestration_sha256":fsha(folder/"orchestration.json"),
         "inputs_before_sha256":fsha(result/"inputs-before.json.gz"),"inputs_after_sha256":fsha(result/"inputs-after.json.gz"),
         "integrity_groups":list(before),"input_maps_identical":before==after,"archive":archive_audit(name)}
 if name!="calendar-timezones":
  check(receipt["exit_code"]==0,"child-zero-exit",name)
  selected=portable_tests if name=="portable" else ["test/widget_test.dart"]
  check(receipt["selected_files"]==selected,"exact-selected-file-list",name)
  streams=verify_streams(result,receipt["outputs"],name)
  count=225 if name=="portable" else 2
  review["events"]=review_events(streams["stdout"],selected,Path(receipt["cwd"]),receipt["test_summary"],count,name)
  check(receipt["command"][-len(selected):]==selected and "--reporter=json" in receipt["command"],"test-command-selection",name)
  if name=="portable":
   check("--platform=node" in receipt["command"],"actual-node-platform-selected")
   check(set(receipt["node_exclusions_retained_on_vm"])=={"test/odt_complex_field_fidelity_test.dart"},"declared-node-exclusion")
   check("test/odt_complex_field_fidelity_test.dart" in read(RUNS/"canonical-9d060658/plan.json")["cohorts"]["engine-integration"]["tests"],"excluded-node-suite-retained-canonically")
  else:
   check(review["events"]["case_names"]==["Review keeps spelling available without the retired AOT action","studio hosts Word, Excel, and PowerPoint workspaces"],"two-exact-example-smokes")
 else:
  zones={"UTC":[0,0,0],"Europe/Berlin":[60,120,60],"America/Los_Angeles":[-480,-420,-480]}
  check([r["timezone"] for r in receipt["runs"]]==list(zones),"exact-three-timezones")
  check(receipt["selected_files"]==["test/sheet_time_period_calendar_test.dart"],"calendar-selected-suite")
  runs=[]
  for row in receipt["runs"]:
   zone=row["timezone"];zf=result/zone.replace("/","_")
   check(read(zf/"receipt.json")==row,"zone-receipt-parent-identity",zone)
   probe=read(zf/"timezone-probe.stdout")
   check(probe==row["timezone_probe"] and [x["offsetMinutes"] for x in probe]==zones[zone] and [x["month"] for x in probe]==[1,7,11],"actual-timezone-probe-offsets",zone)
   check(row["timezone_verified"] and row["expected_offsets_minutes"]==zones[zone] and row["exit_code"]==0 and row["passed"],"zone-exit-and-passed",zone)
   streams=verify_streams(zf,row["logs"],zone)
   event_review=review_events(streams["stdout"],receipt["selected_files"],Path(row["cwd"]),row["test_summary"],8,zone)
   check(row["command"][-1:]==receipt["selected_files"] and "--concurrency=1" in row["command"],"calendar-command-selection",zone)
   runs.append({"timezone":zone,"offsets_minutes":zones[zone],"probe_sha256":fsha(zf/"timezone-probe.stdout"),"events":event_review})
  check(receipt["test_executions"]==sum(r["events"]["substantive_success_count"] for r in runs)==24,"twenty-four-timezone-executions")
  check(all(r["events"]["case_names"]==runs[0]["events"]["case_names"] for r in runs),"same-eight-cases-all-zones")
  ce=events(gzip.decompress((RUNS/"canonical-9d060658/engine-integration/stdout.gz").read_bytes()))
  cs={e["suite"]["id"] for e in ce if e.get("type")=="suite" and e["suite"]["path"].endswith("/sheet_time_period_calendar_test.dart")}
  cn=[e["test"]["name"] for e in ce if e.get("type")=="testStart" and e["test"]["suiteID"] in cs and not e["test"]["name"].startswith("loading ")]
  check(set(cn)==set(runs[0]["events"]["case_names"]),"timezone-cases-overlap-canonical")
  review["runs"]=runs;review["test_executions"]=24;review["additional_unique_tests_claimed"]=0
 gates[name]=review
live_rehashed={}
for group,mapping in [("dependencies",baseline["dependencies"]["sha256_by_path"]),("runtime",baseline["runtime"]),("workspace",baseline["workspace"])]:
 for path,pin in mapping.items():check(fsha(path)==pin,"live-consumed-input",{"group":group,"path":path})
 live_rehashed[group]=len(mapping)
for relative,row in baseline["source"]["files"].items():check(fsha(REPO/relative)==row["sha256"],"live-source-file",relative)
live_rehashed["source"]=len(baseline["source"]["files"])
supplemental=[]
for filename in ["supplemental-runtime-baseline.json","test-cli-bootstrap-baseline.json"]:
 for path,pin in read(OUT/filename)["files"].items():
  same=fsha(path)==pin["sha256"] and Path(path).stat().st_size==pin["bytes"]
  check(same,"supplemental-compiler-node-cli-stable",path)
  supplemental.append({"path":path,"bytes":Path(path).stat().st_size,"sha256":fsha(path),"unchanged":same})
for path,pin in gread(OUT/"workspace-extra-baseline.json.gz").items():check(fsha(path)==pin,"workspace-extra-stable",path)
check(git("rev-parse","HEAD").decode().strip()==SOURCE and not git("status","--porcelain").decode().strip(),"source-head-clean-at-end")
report={"schema":"quds.office.independent_supplemental_review.v1","started_utc":started,"finished_utc":datetime.now(timezone.utc).isoformat(),
        "source_commit":SOURCE,"reviewer_script_sha256":fsha(Path(__file__)),"independent_checks":checks,
        "gates":gates,"portable_substantive_successes":225,"example_substantive_successes":2,"timezone_executions":24,
        "timezone_executions_overlap_canonical":True,"live_input_files_rehashed":live_rehashed,
        "supplemental_runtime_after":supplemental,"findings":findings,"accepted":not findings,
        "overall_office_qualification_accepted":False,"scope":"Portable, editor example and civil-date timezone gates only; native/document-consumer gates remain separate.",
        "no_tests_rerun":True,"source_runtime_mutations":0,"github_actions_endpoints_queried":0}
path=OUT/"supplemental-review.json"
with path.open("x") as f:json.dump(report,f,indent=2,sort_keys=True);f.write("\n")
print(json.dumps({"accepted":not findings,"findings":findings,"checks":checks,"portable":225,"example":2,"timezone":24,"report":str(path)}))
raise SystemExit(0 if not findings else 1)


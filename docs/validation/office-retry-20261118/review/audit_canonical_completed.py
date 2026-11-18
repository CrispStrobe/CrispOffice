#!/usr/bin/env python3
"""Independent read-only audit of the completed 9d060658 canonical run."""
import collections
from datetime import datetime, timezone
import gzip
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import time
from urllib.parse import unquote, urlparse

ROOT=Path("/workspace/scratch/eddfdfc8cc56")
REPO=ROOT/"quds_office_suite"
RUN=ROOT/"flutter-qualification/runs/canonical-9d060658"
OUT=ROOT/"flutter-qualification/independent-audit"
SDK=ROOT/"toolchains/flutter"
WORK=ROOT/"flutter-qualification/workspace"
SOURCE="9d060658ee6be8ec97d73f56b9aec10d346b7952"
DART=str(SDK/"bin/cache/dart-sdk/bin/dart")
PACKAGES={"engine":"quds_office_engine","editor":"quds_office_editor","harper":"quds_proofing_harper","gector":"quds_proofing_gector"}
COHORTS=["engine-zotero","editor-zotero","engine-integration","editor-integration","harper-contract","gector-contract"]
ANALYSES=["engine","editor","harper","gector","proofing-tools"]
PRIVATE="/home/mohammed/Desktop/al_tahreer_profile.pdf"
PRIVATE_CASES={"TrueType subsets without cmap get ToUnicode cmap for the host",
               "JPEG with DCT SMask attaches softMaskJpeg for the host"}
findings=[]
gate_failures=[]
checks=0

def sha(data):return hashlib.sha256(data).hexdigest()
def raw(path):
    path=Path(path)
    return os.readlink(path).encode() if path.is_symlink() else path.read_bytes()
def fsha(path):return sha(raw(path))
def read(path):return json.loads(Path(path).read_text())
def check(ok,name,details=None,gate=False):
    global checks
    checks+=1
    if not ok:(gate_failures if gate else findings).append({"check":name,"details":details})
    return bool(ok)
def git(*args):
    return subprocess.check_output(["git","-C",str(REPO),*args],env=dict(os.environ,GIT_OPTIONAL_LOCKS="0"))
def compressed_read(path):return json.loads(gzip.decompress(Path(path).read_bytes()))
def recorded_path_hashes(mapping,label):
    rows=[]
    for path,expected in mapping.items():
        p=Path(path)
        actual=fsha(p) if p.is_file() or p.is_symlink() else None
        check(actual==expected,label,path)
        rows.append({"path":path,"expected":expected,"actual":actual,"matches":actual==expected})
    return rows

began=time.monotonic()
last=None
while True:
    receipt=read(RUN/"receipt.json")
    state=(receipt["status"],tuple((r["name"],r["status"]) for r in receipt["commands"]))
    if state!=last:
        print(json.dumps({"event":"receipt-state","status":state[0],
                          "commands":[{"name":r["name"],"status":r["status"]} for r in receipt["commands"]]}),flush=True)
        last=state
    if any(r["status"]=="failed" for r in receipt["commands"]):
        print(json.dumps({"event":"gate-failure-observed","failed_commands":[r["name"] for r in receipt["commands"] if r["status"]=="failed"]}),flush=True)
    if receipt["status"] in ("passed","failed"):break
    if time.monotonic()-began>3600:raise SystemExit("Bounded wait ended while run still active; no review acceptance produced")
    time.sleep(5)

started=datetime.now(timezone.utc).isoformat()
report_path=OUT/"canonical-review.json"
if report_path.exists():raise SystemExit("Review already exists; refusing overwrite")
plan=read(RUN/"plan.json")
expected=read(REPO/"docs/validation/office-local-20261118/frozen-plan.json")
expected["source_commit"]=SOURCE
check(plan==expected,"exact-frozen-plan-with-current-evidence-only-source")
check(plan["unique_test_files"]==224,"224-unique-test-files")
check({k:len(v["tests"]) for k,v in plan["cohorts"].items()}==
      {"engine-zotero":19,"editor-zotero":13,"engine-integration":138,"editor-integration":37,"harper-contract":3,"gector-contract":14},"exact-cohort-file-counts")
selected_pairs=[(c["kind"],p) for c in plan["cohorts"].values() for p in c["tests"]]
check(len(selected_pairs)==len(set(selected_pairs))==224,"cohort-disjointness")
check(receipt["source_commit"]==SOURCE and receipt["working_head_after"]==SOURCE,"receipt-source-head")
check(receipt["source_tree"]==git("rev-parse",SOURCE+"^{tree}").decode().strip(),"source-tree-binding")
check(receipt["plan_sha256"]==fsha(RUN/"plan.json"),"plan-receipt-hash")
check(receipt["runner_sha256"]==fsha(RUN/"run-used.py"),"run-used-source-hash")
check(not receipt["historical_qualifications_counted"] and not receipt["github_actions_queried_awaited_or_rerun"],"no-historical-or-ci-results")
expected_names=[name+"-strict-analysis" for name in ANALYSES]+["format","python-controls"]+COHORTS
check([r["name"] for r in receipt["commands"]]==expected_names,"exact-13-command-order",gate=True)
check(receipt["status"]=="passed" and receipt.get("all_passed"),"runner-final-acceptance",gate=True)

before={}
after={}
integrity={}
for group in ["source","dependencies","runtime","workspace","system","harness"]:
    bp,ap=RUN/(group+"-before.json"),RUN/(group+"-after.json")
    check(bp.exists() and ap.exists(),"input-maps-exist",group)
    if not bp.exists() or not ap.exists():continue
    before[group]=read(bp);after[group]=read(ap)
    same=before[group]==after[group]
    integrity[group]={"unchanged":same,"byte_identical":bp.read_bytes()==ap.read_bytes(),
                      "before_sha256":fsha(bp),"after_sha256":fsha(ap)}
    check(same and integrity[group]["byte_identical"],"input-maps-identical",group,gate=True)
    check(receipt["input_integrity"].get(group+"_unchanged")==same,"claimed-integrity-matches-evidence",group)
baseline_names={"source":"source-baseline.json.gz","dependencies":"dependency-baseline.json.gz",
                "runtime":"runtime-baseline.json.gz","workspace":"workspace-baseline.json.gz"}
for group,name in baseline_names.items():
    check(before.get(group)==compressed_read(OUT/name),"run-inputs-match-independent-pre-run-baseline",group)

source=after["source"]
check(not source["commit_mismatches"] and not source["untracked_non_evidence_paths"],"source-reported-clean")
entries={}
for row in git("ls-tree","-r","-z",SOURCE).split(b"\0"):
    if not row:continue
    meta,name=row.split(b"\t",1)
    mode,kind,blob=meta.decode().split()
    relative=name.decode()
    if kind=="blob" and not relative.startswith("docs/"):entries[relative]={"mode":mode,"blob":blob}
check(set(entries)==set(source["files"]) and source["count"]==len(entries),"source-map-complete")
source_live_mismatches=[]
for relative,expected_entry in entries.items():
    p=REPO/relative
    data=raw(p)
    mode="120000" if p.is_symlink() else ("100755" if p.stat().st_mode&0o111 else "100644")
    blob=hashlib.sha1(b"blob "+str(len(data)).encode()+b"\0"+data).hexdigest()
    row=source["files"][relative]
    matches=row["sha256"]==sha(data) and row["git_blob"]==blob==expected_entry["blob"] and row["git_mode"]==mode==expected_entry["mode"]
    if not matches:source_live_mismatches.append(relative)
check(not source_live_mismatches,"live-source-blobs-and-modes",source_live_mismatches)
live_counts={}
for group,values in [("dependencies",after["dependencies"]["sha256_by_path"]),("runtime",after["runtime"]),
                     ("workspace",after["workspace"]),("system",after["system"]),("harness",after["harness"])]:
    rows=recorded_path_hashes(values,"live-"+group+"-hash")
    live_counts[group]=len(rows)
config=REPO/".dart_tool/package_config.json"
original_hash=receipt["original_analyzer_config_sha256"]
check((fsha(config) if config.exists() else None)==original_hash,"analyzer-config-independently-restored")
check(receipt["analysis_config_restored"] and receipt["source_matches_frozen_commit"],"reported-source-and-analyzer-restore")
check(git("rev-parse","HEAD").decode().strip()==SOURCE and not git("status","--porcelain").decode().strip(),"current-head-clean")

supplemental=[]
for filename in ["supplemental-runtime-baseline.json","test-cli-bootstrap-baseline.json"]:
    baseline=read(OUT/filename)
    for path,row in baseline["files"].items():
        actual=fsha(path) if Path(path).is_file() else None
        size=Path(path).stat().st_size if Path(path).is_file() else None
        matches=actual==row["sha256"] and size==row["bytes"]
        check(matches,"supplemental-runtime-unchanged",path)
        supplemental.append({"path":path,"bytes":size,"expected_sha256":row["sha256"],"sha256":actual,"matches":matches,"baseline":filename})
recorded_path_hashes(compressed_read(OUT/"workspace-extra-baseline.json.gz"),"supplemental-workspace-unchanged")

def resolve_suite(path,cwd):
    if path.startswith("file:"):path=unquote(urlparse(path).path)
    p=Path(path)
    return str((p if p.is_absolute() else cwd/p).resolve())

def audit_events(data,name,cwd,selected,reported):
    events=[]
    for line in data.decode(errors="replace").splitlines():
        try:item=json.loads(line)
        except ValueError:continue
        if isinstance(item,dict):events.append(item)
    starts=[e["test"] for e in events if e.get("type")=="testStart"]
    dones=[e for e in events if e.get("type")=="testDone"]
    suites=[e["suite"] for e in events if e.get("type")=="suite"]
    start_counts=collections.Counter(x["id"] for x in starts)
    done_counts=collections.Counter(x["testID"] for x in dones)
    suite_counts=collections.Counter(x["id"] for x in suites)
    check(all(n==1 for n in start_counts.values()),"unique-test-start-ids",name)
    check(all(n==1 for n in done_counts.values()),"unique-test-completion-ids",name)
    check(set(start_counts)==set(done_counts),"every-started-test-completed",name,gate=True)
    check(all(n==1 for n in suite_counts.values()),"unique-suite-ids",name)
    starts_by_id={x["id"]:x for x in starts}
    suites_by_id={x["id"]:x for x in suites}
    actual_paths=[resolve_suite(x["path"],cwd) for x in suites]
    expected_paths=[str((cwd/p).resolve()) for p in selected]
    check(len(actual_paths)==len(set(actual_paths))==len(expected_paths),"exact-suite-count-no-duplicates",name)
    check(set(actual_paths)==set(expected_paths),"exact-selected-suite-identities",name,gate=True)
    outcomes=collections.Counter()
    completed=[];exclusions=[];hidden=0
    for event in dones:
        record=starts_by_id.get(event["testID"])
        if not record:
            check(False,"completion-without-start",{"cohort":name,"event":event})
            continue
        if event.get("hidden"):
            hidden+=1
            check(event.get("result")=="success" and not event.get("skipped"),"hidden-loader-completion",{"cohort":name,"id":event["testID"]},gate=True)
            continue
        outcome="skipped" if event.get("skipped") else event.get("result","unknown")
        outcomes[outcome]+=1
        row={"test_id":event["testID"],"suite_id":record["suiteID"],"name":record["name"],"outcome":outcome}
        completed.append(row)
        case=next((c for c in PRIVATE_CASES if record["name"]==c or record["name"].endswith(" "+c)),None)
        suite=suites_by_id.get(record["suiteID"],{})
        if outcome=="success" and before["system"].get(PRIVATE) is None and case and suite.get("path","").endswith("/pdf_file_test.dart"):
            exclusions.append({"test_id":event["testID"],"matched_case_name":case})
    done=[e for e in events if e.get("type")=="done"]
    errors=[e for e in events if e.get("type")=="error"]
    expected_exclusions=PRIVATE_CASES if before["system"].get(PRIVATE) is None and "test/pdf_file_test.dart" in selected else set()
    check(len(done)==1 and done[0].get("success") is True,"one-successful-final-done-event",name,gate=True)
    check(not errors,"no-error-events",name,gate=True)
    check(not outcomes.get("skipped") and all(k=="success" or v==0 for k,v in outcomes.items()),"all-visible-outcomes-success-no-skips",{"cohort":name,"outcomes":dict(outcomes)},gate=True)
    check(len(exclusions)==len(expected_exclusions) and {x["matched_case_name"] for x in exclusions}==expected_exclusions,"exact-private-fixture-exclusions",name)
    check(reported["completed_tests"]==completed,"reported-completed-tests-match-raw",name)
    check(reported["raw_runner_outcomes"]==dict(outcomes),"reported-outcomes-match-raw",name)
    check(reported["raw_success_count"]==outcomes["success"],"reported-raw-count",name)
    check(reported["substantive_success_count"]==outcomes["success"]-len(exclusions),"reported-substantive-count",name)
    check({(x["test_id"],x["matched_case_name"]) for x in reported["excluded_success_cases"]}=={(x["test_id"],x["matched_case_name"]) for x in exclusions},"reported-exclusions-match-raw",name)
    check(reported["passed"] and not reported["allowed_skipped_cases"] and not reported["unexpected_skipped_cases"]
          and not reported["missing_selected_suites"] and not reported["unexpected_suites"],"reported-test-pass-fields",name,gate=True)
    return {"selected_suites":len(selected),"observed_suites":len(suites),"test_start_events":len(starts),
            "test_done_events":len(dones),"hidden_loader_events":hidden,"raw_outcomes":dict(outcomes),
            "raw_success_count":outcomes["success"],"substantive_success_count":outcomes["success"]-len(exclusions),
            "excluded_private_cases":exclusions,"done_events":done,"error_events":len(errors),
            "selected_suite_identities_sha256":sha(json.dumps(sorted(actual_paths)).encode())}

command_reviews=[]
cohort_reviews={}
for row in receipt["commands"]:
    name=row["name"]
    check(row.get("exit_code")==0 and row.get("timed_out") is False and row["status"]=="passed",
          "command-exit-status",{"name":name,"exit":row.get("exit_code"),"status":row["status"],"timed_out":row.get("timed_out")},gate=True)
    streams={}
    for stream in ["stdout","stderr"]:
        path=RUN/row[stream]
        packed=path.read_bytes();data=gzip.decompress(packed)
        check(sha(packed)==row[stream+"_gzip_sha256"] and sha(data)==row[stream+"_sha256"],
              "raw-and-gzip-command-stream-hashes",{"command":name,"stream":stream})
        streams[stream]=data
    review={"name":name,"exit_code":row.get("exit_code"),"timed_out":row.get("timed_out"),
            "stdout_bytes":len(streams["stdout"]),"stderr_bytes":len(streams["stderr"])}
    if name.endswith("-strict-analysis"):
        kind=name.removesuffix("-strict-analysis")
        check(row["command"]==[DART,"analyze","--fatal-infos",*plan["analysis_targets"][kind]],
              "exact-strict-analysis-command",name)
        check("No issues found!" in streams["stdout"].decode(errors="replace"),"strict-analysis-clean-output",name)
    elif name=="format":
        check(row["command"]==[DART,"format","--language-version=3.12","--output=none","--set-exit-if-changed",*plan["format_targets"]],"exact-format-command")
        check(len(plan["format_targets"])==145 and re.search(r"Formatted 145 files \(0 changed\)",streams["stdout"].decode(errors="replace")) is not None,"exact-format-result")
    elif name=="python-controls":
        py=read(RUN/"python-controls-summary.json")
        check(row["python_summary_sha256"]==fsha(RUN/"python-controls-summary.json") and row["python_summary"]==py,"python-summary-hash-and-receipt")
        check(py["tests_run"]==py["substantive_success_count"]==len(py["selected_test_ids"])==len(py["successful_test_ids"])==117,"117-python-controls")
        check(len(set(py["selected_test_ids"]))==117 and set(py["selected_test_ids"])==set(py["successful_test_ids"]),"python-exact-selected-success-identities")
        check(len(py["modules"])==7,"seven-python-control-modules")
        check(all(not py[k] for k in ["skipped_cases","unexpected_skipped_cases","missing_selected_tests","failures","errors","expected_failures","unexpected_successes"]),"no-python-skips-or-failures",gate=True)
        check(py["passed"] and py["runtime_unchanged"] and py["runtime_before"]==py["runtime_after"],"python-runtime-integrity",gate=True)
        review["python_substantive_success_count"]=117
    elif name in COHORTS:
        selected=plan["cohorts"][name]["tests"]
        cwd=WORK/"packages"/PACKAGES[plan["cohorts"][name]["kind"]]
        check(row["cwd"]==str(cwd),"cohort-cwd",name)
        check(row["command"][-len(selected):]==selected and "--reporter=json" in row["command"] and "--concurrency=2" in row["command"],"exact-cohort-test-argv",name)
        reported=read(RUN/name/"test-summary.json")
        check(reported==row["test_summary"],"test-summary-file-receipt-binding",name)
        cohort_reviews[name]=audit_events(streams["stdout"],name,cwd,selected,reported)
        review["event_review"]=cohort_reviews[name]
    command_reviews.append(review)
raw_total=sum(x["raw_success_count"] for x in cohort_reviews.values())
substantive_total=sum(x["substantive_success_count"] for x in cohort_reviews.values())
check(receipt["raw_runner_success_total"]==raw_total and receipt["substantive_success_total"]==substantive_total,"aggregate-counts-from-raw-events")
check(len(cohort_reviews)==6,"all-six-cohorts-completed",gate=True)
check(receipt["python_controls_summary"]==read(RUN/"python-controls-summary.json"),"final-python-summary-binding")
check(git("rev-parse","HEAD").decode().strip()==SOURCE and not git("status","--porcelain").decode().strip(),"source-still-clean-at-review-end")
report={
 "schema":"quds.office.independent_canonical_review.v1","started_utc":started,"finished_utc":datetime.now(timezone.utc).isoformat(),
 "source_commit":SOURCE,"source_tree":receipt["source_tree"],"run_directory":str(RUN),
 "original_receipt_sha256":fsha(RUN/"receipt.json"),"plan_sha256":fsha(RUN/"plan.json"),
 "reviewer_script_sha256":fsha(Path(__file__)),"independent_checks":checks,
 "command_count":len(receipt["commands"]),"command_reviews":command_reviews,
 "unique_selected_test_files":len(selected_pairs),"cohorts":cohort_reviews,
 "raw_runner_success_total":raw_total,"substantive_success_total":substantive_total,
 "python_controls":117,"input_integrity":integrity,"live_map_files_rehashed":live_counts,
 "source_files_rehashed":len(entries),"supplemental_runtime_after":supplemental,
 "findings":findings,"gate_failures":gate_failures,"evidence_integrity_accepted":not findings,
 "canonical_qualification_accepted":not findings and not gate_failures,
 "overall_office_qualification_accepted":False,
 "scope":"Canonical gate only; portable/example/calendar/document-consumer/native sweep remain separate gates.",
 "no_tests_rerun":True,"source_runtime_mutations":0,"github_actions_endpoints_queried":0
}
with report_path.open("x") as stream:json.dump(report,stream,indent=2,sort_keys=True);stream.write("\n")
print(json.dumps({"event":"review-complete","accepted":report["canonical_qualification_accepted"],
                  "findings":findings,"gate_failures":gate_failures,"raw_successes":raw_total,
                  "substantive_successes":substantive_total,"report":str(report_path)}),flush=True)
raise SystemExit(0 if report["canonical_qualification_accepted"] else 1)


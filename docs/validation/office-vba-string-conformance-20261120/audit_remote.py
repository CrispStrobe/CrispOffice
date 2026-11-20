import collections, datetime, json, pathlib, subprocess
root = pathlib.Path("/workspace/scratch/f0aea33f35d2")
repo = root / "quds_office_suite"
out = root / "remote-audit.json"
audit = json.loads(out.read_text())
prior = json.loads((repo / "docs/validation/office-vba-dynamic-arrays-20261119/initial-reconciliation.json").read_text())
main = audit["main"]
def git(*args, check=True):
    p = subprocess.run(["git",*args],cwd=repo,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
    if check and p.returncode:
        raise RuntimeError(f"git {' '.join(args)}: {p.stderr.decode()}")
    return p
def ancestor(a,b):
    return git("merge-base","--is-ancestor",a,b,check=False).returncode == 0
hist={}
for item in prior["branches"] + prior["recentPullRequests"]:
    if "historicalEquivalence" in item:
        hist[item["sha"]] = item["historicalEquivalence"]
missing=[]
for p in audit["recentPullRequests"]:
    if git("cat-file","-e",p["head"]+"^{commit}",check=False).returncode:
        missing.append(f"{p['head']}:refs/audit/pr/{p['number']}")
if missing:
    git("fetch","--no-tags","origin",*missing)
def classify(sha):
    if sha == main:
        return {"disposition":"main"}
    if ancestor(sha,main):
        return {"disposition":"already_ancestor"}
    if sha not in hist:
        return {"disposition":"incoming_source","uniqueCommits":git("rev-list","--reverse",f"{main}..{sha}").stdout.decode().splitlines()}
    h=hist[sha]
    equiv=h["equivalent"]; base=h["commonBase"]
    paths=git("diff","--name-only","-z",base,sha).stdout.decode().split("\0")
    paths=[p for p in paths if p]
    mismatches=[]
    for path in paths:
        a=git("ls-tree",sha,"--",path).stdout
        b=git("ls-tree",equiv,"--",path).stdout
        if a != b:
            mismatches.append(path)
    proven=ancestor(equiv,main) and not mismatches
    return {"disposition":"historical_equivalent" if proven else "unresolved",
            "historicalEquivalence":{"equivalent":equiv,"commonBase":base,
                "equivalentIsAncestor":ancestor(equiv,main),"deltaPaths":len(paths),
                "deltaMismatches":mismatches,
                "method":"fresh_complete_delta_path_mode_type_blob_identity",
                "passed":proven}}
cache={}
for group,key in [("forkBranches","sha"),("upstreamBranches","sha"),("recentPullRequests","head")]:
    for item in audit[group]:
        sha=item[key]
        if sha not in cache:
            cache[sha]=classify(sha)
        item.update(cache[sha])
audit["observedAt"]=datetime.datetime.now(datetime.timezone.utc).isoformat()
audit["classificationCompletedAt"]=audit["observedAt"]
audit["classificationMethod"]="Fresh local commit ancestry plus exact changed-path Git mode/type/blob identity against already accepted equivalents; no CI used."
audit["historicalEquivalenceMappingsFrom"]="docs/validation/office-vba-dynamic-arrays-20261119/initial-reconciliation.json"
audit["counts"]={g:dict(collections.Counter(x["disposition"] for x in audit[g])) for g in ["forkBranches","upstreamBranches","recentPullRequests"]}
audit["githubActionsQueriedOrAwaited"]=False
audit["fetchedMissingPrRefs"]=missing
out.write_text(json.dumps(audit,indent=2)+"\n")
print(json.dumps({"counts":audit["counts"],"new":{g:[x for x in audit[g] if x["disposition"] in ["incoming_source","unresolved"]] for g in ["forkBranches","upstreamBranches","recentPullRequests"]},"fetchedPrRefs":missing},indent=2))

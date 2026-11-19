import json, pathlib, plistlib, sys
root=pathlib.Path(sys.argv[1])
checks=[]
for name in ("DebugProfile.entitlements", "Release.entitlements"):
    path=root / "packages/quds_office_editor/example/macos/Runner" / name
    data=plistlib.loads(path.read_bytes())
    for key in ("com.apple.security.network.client", "com.apple.security.network.server"):
        checks.append({"path":str(path.relative_to(root)),"key":key,"passed":data.get(key) is True})
print(json.dumps({"checks":checks,"passed":all(c["passed"] for c in checks)},indent=2))
raise SystemExit(0 if all(c["passed"] for c in checks) else 1)

#!/usr/bin/env python3
"""Recreate this gate runtime in a fresh directory and a fresh source checkout.

Usage: python reproduce_runtime.py --repo /path/to/checkout \
       --runtime /path/to/new-runtime --record /path/to/environment.json
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shlex
import shutil
import subprocess
import zipfile

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--repo", type=Path, required=True)
parser.add_argument("--runtime", type=Path, required=True)
parser.add_argument("--record", type=Path, required=True)
args = parser.parse_args()
repo, runtime = args.repo.resolve(), args.runtime.resolve()
record = json.loads(args.record.read_text())
assert not runtime.exists(), "Use a fresh runtime directory"
assert not (repo / ".dart_tool/package_config.json").exists(), "Use a fresh checkout without resolved workspace dependencies"
assert (repo / "packages/quds_office_engine/pubspec.yaml").is_file()
runtime.mkdir(parents=True)
version = record["dart_version"]
archive = runtime / "dartsdk.zip"
subprocess.run([
    "curl", "-fsSL", "--connect-timeout", "10", "--max-time", "300",
    f"https://storage.googleapis.com/dart-archive/channels/stable/release/{version}/sdk/dartsdk-linux-x64-release.zip",
    "-o", str(archive),
], check=True)
assert hashlib.sha256(archive.read_bytes()).hexdigest() == record["dart_archive_sha256"]
with zipfile.ZipFile(archive) as data:
    for item in data.infolist():
        destination = runtime / item.filename
        assert destination.resolve().is_relative_to(runtime)
        data.extract(item, runtime)
        mode = item.external_attr >> 16
        if mode and destination.is_file():
            destination.chmod(mode & 0o777)
dart = runtime / "dart-sdk/bin/dart"
for name in ["pub-cache", "tmp", "config", "cache", "test-runner"]:
    (runtime / name).mkdir(exist_ok=True)
pins = record["hosted_versions"]
isolated = runtime / "engine-validation/packages"
for package in ["quds_office_engine", "legacy_doc_parser"]:
    source = repo / "packages" / package
    destination = isolated / package
    destination.mkdir(parents=True)
    manifest = (source / "pubspec.yaml").read_text().replace("resolution: workspace\n", "")
    if package == "quds_office_engine":
        manifest += "\ndependency_overrides:\n" + "".join(f"  {name}: {value}\n" for name, value in sorted(pins.items()))
    (destination / "pubspec.yaml").write_text(manifest)
    (destination / "lib").symlink_to(source / "lib", target_is_directory=True)
environment = os.environ.copy()
environment.update({
    "PUB_CACHE": str(runtime / "pub-cache"), "TMPDIR": str(runtime / "tmp"),
    "XDG_CONFIG_HOME": str(runtime / "config"), "XDG_CACHE_HOME": str(runtime / "cache"),
    "DART_SUPPRESS_ANALYTICS": "true",
})
engine = isolated / "quds_office_engine"
subprocess.run([str(dart), "pub", "get", f"--directory={engine}"], env=environment, check=True)
config = json.loads((engine / ".dart_tool/package_config.json").read_text())
for entry in config["packages"]:
    if entry["name"] in ["quds_office_engine", "legacy_doc_parser"]:
        entry["rootUri"] = (repo / "packages" / entry["name"]).as_uri()
    elif entry["name"] in pins:
        expected = runtime / "pub-cache/hosted/pub.dev" / f"{entry['name']}-{pins[entry['name']]}"
        assert entry["rootUri"].rstrip("/") == expected.as_uri()
(repo / ".dart_tool").mkdir(exist_ok=True)
package_config = repo / ".dart_tool/package_config.json"
package_config.write_text(json.dumps(config, indent=2) + "\n")
shutil.copyfile(engine / ".dart_tool/package_graph.json", repo / ".dart_tool/package_graph.json")
test_source = runtime / "pub-cache/hosted/pub.dev" / f"test-{pins['test']}" / "bin/test.dart"
kernel = runtime / "test-runner/test-runner.dill"
command = [str(dart), "compile", "kernel", f"--packages={package_config}", str(test_source), "-o", str(kernel)]
subprocess.run(command, env=environment, check=True)
env_script = runtime / "env.sh"
values = {"QUDS_VALIDATION_ROOT": str(repo), "QUDS_DART_ROOT": str(runtime / "dart-sdk"),
          **{key: environment[key] for key in ["PUB_CACHE", "TMPDIR", "XDG_CONFIG_HOME", "XDG_CACHE_HOME", "DART_SUPPRESS_ANALYTICS"]}}
env_script.write_text("".join(f"export {key}={shlex.quote(value)}\n" for key, value in values.items()) + 'export PATH="$QUDS_DART_ROOT/bin:$PATH"\n')
runner = runtime / "run-engine-tests.sh"
runner.write_text(
    "#!/usr/bin/env bash\nset -euo pipefail\n"
    f"source {shlex.quote(str(env_script))}\n"
    'cd "$QUDS_VALIDATION_ROOT/packages/quds_office_engine"\n'
    'exec "$QUDS_DART_ROOT/bin/dart" --old_gen_heap_size=768 '
    '--packages="$QUDS_VALIDATION_ROOT/.dart_tool/package_config.json" '
    f"{shlex.quote(str(kernel))} --compiler source --concurrency=1 --timeout=4x --fail-fast \"$@\"\n"
)
runner.chmod(0o755)
(runtime / "reproduction-command.json").write_text(json.dumps({"kernel_build_command": command}, indent=2) + "\n")
reproduced = dict(record)
reproduced.update({
    "package_config_sha256": hashlib.sha256(package_config.read_bytes()).hexdigest(),
    "runner_kernel_sha256": hashlib.sha256(kernel.read_bytes()).hexdigest(),
    "tmpdir": str(runtime / "tmp"), "runner_script": str(runner),
    "setup": "Recreated from the original recorded SDK/archive and exact hosted pins; package roots map to this fresh source checkout.",
})
(runtime / "environment.json").write_text(json.dumps(reproduced, indent=2) + "\n")
print(f"Runtime recreated; test wrapper: {runner}")

"""Bind effective Dart workspace inputs to the intended source checkout.

The separate validation workspace copies manifests and links source children.
Hashing the checkout alone cannot establish what a stale workspace executes.
Resolve those links and the package configuration before taking each snapshot.
"""
import hashlib
import json
from pathlib import Path, PurePosixPath
import re
from urllib.parse import unquote, urlparse

SCHEMA = 'quds-thesaurus-workspace-v1'
GENERATED = {
    '.git', '.dart_tool', 'build', 'pubspec.yaml', 'pubspec.lock',
    'pubspec_overrides.yaml', '.flutter-plugins', '.flutter-plugins-dependencies',
}
INPUT_DIRECTORIES = {'lib', 'test', 'assets', 'fonts', 'templates', 'web', 'tool'}


def require(condition, message):
    if not condition:
        raise ValueError(message)


def record(path):
    value = path.read_bytes()
    return {'sha256': hashlib.sha256(value).hexdigest(), 'bytes': len(value)}


def workspace_members(repo):
    """Read the explicit workspace list used by this repository, failing closed."""
    members = []
    active = False
    for line in (repo / 'pubspec.yaml').read_text().splitlines():
        if line == 'workspace:':
            require(not active, 'Repeated workspace declaration')
            active = True
            continue
        if not active or not line.strip() or line.lstrip().startswith('#'):
            continue
        if not line[0].isspace():
            break
        match = re.fullmatch(r'\s+- ([A-Za-z0-9_./-]+)\s*(?:#.*)?', line)
        require(match is not None, 'Unsupported workspace member declaration: ' + line)
        name = match[1]
        path = PurePosixPath(name)
        require(not path.is_absolute() and path.parts and '..' not in path.parts
                and str(path) == name, 'Noncanonical workspace member: ' + name)
        require(name not in members, 'Repeated workspace member: ' + name)
        members.append(name)
    require(members, 'An explicit nonempty workspace member list is required')
    return members


def package_name(manifest):
    names = re.findall(r'^name:\s*([a-z][a-z0-9_]*)\s*$', manifest.read_text(), re.M)
    require(len(names) == 1, 'Expected one package name in ' + str(manifest))
    return names[0]


def lock_scalar(value):
    """Read scalar strings emitted by pub's lockfile writer, without YAML dependencies."""
    value = value.strip()
    if value.startswith('"'):
        result = json.loads(value)
        require(isinstance(result, str), 'Expected a lockfile string')
        return result
    if value.startswith("'"):
        require(value.endswith("'"), 'Unclosed lockfile string')
        return value[1:-1].replace("''", "'")
    require(re.fullmatch(r'[A-Za-z0-9_./-]+', value) is not None,
            'Unsupported lockfile scalar: ' + value)
    return value


def locked_path_dependencies(repo):
    """Read repository-relative path entries from pub's generated lock format."""
    blocks = {}
    active = False
    current = None
    for line in (repo / 'pubspec.lock').read_text().splitlines():
        if line in ('packages:', 'packages: {}'):
            require(not active, 'Repeated lockfile packages declaration')
            active = True
            continue
        if not active or not line.strip() or line.lstrip().startswith('#'):
            continue
        if not line[0].isspace():
            break
        match = re.fullmatch(r'  ([a-z_][a-z0-9_]*):', line)
        if match:
            current = match[1]
            require(current not in blocks, 'Duplicate locked dependency: ' + current)
            blocks[current] = []
        else:
            require(current is not None and line.startswith('    '),
                    'Unsupported lockfile package declaration: ' + line)
            blocks[current].append(line)
    require(active, 'Lockfile has no packages declaration')
    result = {}
    for name, lines in blocks.items():
        block = '\n'.join(lines)
        sources = re.findall(r'^    source: (.+)$', block, re.M)
        require(len(sources) == 1, 'Expected one locked dependency source: ' + name)
        if lock_scalar(sources[0]) != 'path':
            continue
        paths = re.findall(r'^      path: (.+)$', block, re.M)
        relatives = re.findall(r'^      relative: (.+)$', block, re.M)
        require(len(paths) == len(relatives) == 1 and relatives[0].strip() == 'true',
                'Locked path dependency must be repository-relative: ' + name)
        relative = lock_scalar(paths[0])
        path = PurePosixPath(relative)
        require(not path.is_absolute() and path.parts and '..' not in path.parts
                and str(path) == relative and relative != '.',
                'Noncanonical locked dependency path: ' + name)
        require((repo / relative).resolve().is_relative_to(repo),
                'Locked dependency path escapes the checkout: ' + name)
        result[name] = relative
    return result


def vendor_inventory(root):
    """Include package source/data and manifest; omit generated pub/build state."""
    result = {}
    for path in sorted(root.rglob('*')):
        relative = path.relative_to(root)
        if relative.parts[0] in GENERATED - {'pubspec.yaml'}:
            continue
        if path.is_file():
            result[relative.as_posix()] = record(path)
    return result


def validate_locked_paths(repo, workspace, config_path, packages, local_names):
    roots, records = {}, {}
    for name, relative in locked_path_dependencies(repo).items():
        require(name not in local_names, 'Locked dependency duplicates a workspace package: ' + name)
        require(name in packages, 'Locked path dependency missing from configuration: ' + name)
        expected = (repo / relative).resolve()
        entry = packages[name]
        root = resolve_uri(config_path.parent, entry.get('rootUri'))
        require(root in {expected, (workspace / relative).resolve()}
                and (root.is_relative_to(repo) or root.is_relative_to(workspace)),
                'Locked path dependency resolves to another checkout: ' + name)
        require(expected.is_dir() and root.is_dir(), 'Missing locked path dependency: ' + name)
        require(package_name(expected / 'pubspec.yaml') == name,
                'Locked path dependency manifest name differs: ' + name)
        require(not (expected / 'pubspec_overrides.yaml').exists()
                and not (root / 'pubspec_overrides.yaml').exists(),
                'Locked path dependency overrides are not qualified: ' + name)
        library = resolve_uri(root, entry.get('packageUri'))
        require((expected / 'lib').is_dir() and library == (root / 'lib').resolve()
                and (library.is_relative_to(repo) or library.is_relative_to(workspace)),
                'Locked dependency library does not resolve to its lib directory: ' + name)
        source_records = vendor_inventory(expected)
        # Separate workspaces may copy vendored packages instead of linking
        # them. Every source/data byte must still match, both before and after.
        require(source_records == vendor_inventory(root),
                'Locked dependency source differs from the checkout: ' + name)
        records.update({relative + '/' + path: value for path, value in source_records.items()})
        roots[name] = {'root': str(root), 'library': str(library), 'source': str(expected),
                       'locked_path': relative, 'mode': 'live' if root == expected else 'verified_copy'}
    return roots, records


def resolve_uri(base, value):
    require(isinstance(value, str) and value, 'Package configuration URI is missing')
    uri = urlparse(value)
    require(uri.scheme in ('', 'file') and uri.netloc in ('', 'localhost')
            and not uri.query and not uri.fragment,
            'Package configuration URI is not a local path: ' + value)
    path = Path(unquote(uri.path))
    require(uri.scheme != 'file' or path.is_absolute(), 'File URI is not absolute')
    return (path if path.is_absolute() else base / path).resolve()


def validate_source_links(repo, workspace, members):
    """Reject copied/redirected source, while permitting nested workspace roots."""
    links = {}
    for member in members:
        source = repo / member
        target = workspace / member
        require(source.is_dir() and target.is_dir(), 'Missing workspace member: ' + member)
        for child in source.iterdir():
            if child.name in GENERATED:
                continue
            relative = child.relative_to(repo).as_posix()
            # An example that is itself a member has its own copied manifest and
            # linked children. Its container must not be replaced by a symlink.
            if any(name == relative or name.startswith(relative + '/') for name in members):
                continue
            actual = target / child.name
            require(actual.exists() and actual.resolve() == child.resolve(),
                    'Workspace source does not resolve to the checkout: ' + relative)
            links[relative] = str(actual.resolve())
        for name in INPUT_DIRECTORIES:
            require((source / name).exists() == (target / name).exists(),
                    'Unexpected or missing workspace source directory: ' + member + '/' + name)
    return dict(sorted(links.items()))


def snapshot_sources(repo, workspace):
    """Verify the effective roots, then inventory the files used by this fixture."""
    repo, workspace = Path(repo).resolve(), Path(workspace).resolve()
    members = workspace_members(repo)
    manifest_paths = ['pubspec.yaml', *[name + '/pubspec.yaml' for name in members]]
    files = set()
    names = {}
    for relative in manifest_paths:
        source, actual = repo / relative, workspace / relative
        require(source.is_file() and actual.is_file() and source.read_bytes() == actual.read_bytes(),
                'Workspace manifest differs from the checkout: ' + relative)
        name = package_name(source)
        require(name not in names, 'Duplicate workspace package name: ' + name)
        names[name] = str(PurePosixPath(relative).parent)
        files.add(source)
        require(not (actual.parent / 'pubspec_overrides.yaml').exists(),
                'Workspace dependency overrides are not qualified: ' + relative)
    require((repo / 'pubspec.lock').read_bytes() == (workspace / 'pubspec.lock').read_bytes(),
            'Workspace lock differs from the checkout')
    links = validate_source_links(repo, workspace, members)
    config_path = workspace / '.dart_tool/package_config.json'
    config = json.loads(config_path.read_text())
    require(config.get('configVersion') == 2 and isinstance(config.get('packages'), list),
            'Unsupported workspace package configuration')
    packages = {}
    for entry in config['packages']:
        require(isinstance(entry, dict) and isinstance(entry.get('name'), str),
                'Malformed package configuration entry')
        require(entry['name'] not in packages, 'Duplicate package configuration entry: ' + entry['name'])
        packages[entry['name']] = entry
    roots = {}
    for name, member in names.items():
        require(name in packages, 'Workspace package missing from configuration: ' + name)
        entry = packages[name]
        root = resolve_uri(config_path.parent, entry.get('rootUri'))
        expected = (repo / member).resolve()
        require(root in {expected, (workspace / member).resolve()},
                'Workspace package resolves to another checkout: ' + name)
        library = resolve_uri(root, entry.get('packageUri'))
        if (expected / 'lib').exists():
            require(library == (expected / 'lib').resolve(),
                    'Workspace package library does not resolve to the checkout: ' + name)
        else:
            require(not (root / 'lib').exists() and library == (root / 'lib').resolve(),
                    'Workspace package gained an unqualified library: ' + name)
        roots[name] = {'root': str(root), 'library': str(library), 'source': str(expected)}
    vendor_roots, vendor_records = validate_locked_paths(repo, workspace, config_path, packages, names)
    roots.update(vendor_roots)
    # Include every verified source child, not just conventional lib/assets
    # folders: tests and package manifests may refer to fonts, native sources,
    # example fixtures or other package-relative files.
    for relative in links:
        path = repo / relative
        if path.is_dir():
            files.update(child for child in path.rglob('*') if child.is_file())
        elif path.is_file():
            files.add(path)
    if (repo / 'lib').exists():
        files.update(path for path in (repo / 'lib').rglob('*') if path.is_file())
    for name in ('.fvmrc', 'pubspec.lock', 'analysis_options.yaml'):
        if (repo / name).is_file():
            files.add(repo / name)
    result = {path.relative_to(repo).as_posix(): record(path) for path in sorted(files)}
    result.update(vendor_records)
    result['__workspace_lock__'] = record(workspace / 'pubspec.lock')
    result['__workspace_package_config__'] = record(config_path)
    result['__workspace_binding__'] = {
        'schema': SCHEMA, 'package_roots': dict(sorted(roots.items())), 'source_links': links,
        'locked_path_dependencies': vendor_roots,
    }
    return result

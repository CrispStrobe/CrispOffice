#!/usr/bin/env python3
"""Negative controls for stale or redirected validation workspaces."""
import copy
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

import workspace_binding


class WorkspaceBindingTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(dir=Path.cwd())
        self.root = Path(self.temporary.name)
        self.repo = self.root / 'quds_office_suite'
        self.workspace = self.root / 'zotero-validation'
        self.repo.mkdir()
        self.workspace.mkdir()
        self.members = ['packages/editor', 'packages/editor/example']
        (self.repo / 'pubspec.yaml').write_text(
            'name: suite\nworkspace:\n' + ''.join('  - ' + name + '\n' for name in self.members))
        (self.repo / 'pubspec.lock').write_text('packages: {}\n')
        (self.repo / '.fvmrc').write_text('{"flutter":"3.47.8"}\n')
        for member, package in zip(self.members, ['editor', 'studio']):
            source, target = self.repo / member, self.workspace / member
            source.mkdir(parents=True, exist_ok=True)
            target.mkdir(parents=True, exist_ok=True)
            (source / 'pubspec.yaml').write_text('name: ' + package + '\nresolution: workspace\n')
            (source / 'README.md').write_text('Package notes\n')
            for name in workspace_binding.INPUT_DIRECTORIES:
                directory = source / name
                directory.mkdir()
                (directory / 'source.txt').write_text(member + '/' + name)
        for relative in ['pubspec.yaml', 'pubspec.lock', *[m + '/pubspec.yaml' for m in self.members]]:
            shutil.copy2(self.repo / relative, self.workspace / relative)
        for member in self.members:
            for child in (self.repo / member).iterdir():
                target = self.workspace / member / child.name
                if child.name != 'pubspec.yaml' and not target.exists():
                    target.symlink_to(child, target_is_directory=child.is_dir())
        self.config = {'configVersion': 2, 'packages': [
            {'name': 'suite', 'rootUri': '../', 'packageUri': 'lib/'},
            {'name': 'editor', 'rootUri': '../packages/editor/', 'packageUri': 'lib/'},
            {'name': 'studio', 'rootUri': '../packages/editor/example/', 'packageUri': 'lib/'},
        ]}
        self.config_path = self.workspace / '.dart_tool/package_config.json'
        self.config_path.parent.mkdir()
        self.write_config(self.config)

    def tearDown(self):
        self.temporary.cleanup()

    def write_config(self, value):
        self.config_path.write_text(json.dumps(value))

    def snapshot(self):
        return workspace_binding.snapshot_sources(self.repo, self.workspace)

    def test_current_live_links_and_nested_member_are_bound(self):
        result = self.snapshot()
        self.assertEqual(result['__workspace_binding__']['schema'], workspace_binding.SCHEMA)
        self.assertEqual(set(result['__workspace_binding__']['package_roots']), {'suite', 'editor', 'studio'})
        for member in self.members:
            for name in workspace_binding.INPUT_DIRECTORIES:
                self.assertIn(member + '/' + name + '/source.txt', result)
        self.assertEqual(result, self.snapshot())

    def test_plain_copied_source_directories_are_rejected_even_with_equal_bytes(self):
        for name in ('lib', 'test', 'assets', 'fonts', 'web'):
            with self.subTest(directory=name):
                path = self.workspace / 'packages/editor' / name
                source = path.resolve()
                path.unlink()
                shutil.copytree(source, path)
                with self.assertRaisesRegex(ValueError, 'does not resolve to the checkout'):
                    self.snapshot()
                shutil.rmtree(path)
                path.symlink_to(source, target_is_directory=True)

    def test_wrong_source_link_is_rejected_on_subsequent_snapshot(self):
        self.snapshot()
        path = self.workspace / 'packages/editor/lib'
        path.unlink()
        path.symlink_to(self.repo / 'packages/editor/test', target_is_directory=True)
        with self.assertRaisesRegex(ValueError, 'does not resolve to the checkout'):
            self.snapshot()

    def test_changed_manifest_or_lock_is_rejected(self):
        for relative in ('pubspec.yaml', 'packages/editor/pubspec.yaml', 'pubspec.lock'):
            with self.subTest(path=relative):
                path = self.workspace / relative
                before = path.read_bytes()
                path.write_bytes(before + b'# changed\n')
                with self.assertRaisesRegex(ValueError, 'differs from the checkout'):
                    self.snapshot()
                path.write_bytes(before)

    def test_configuration_cannot_redirect_a_package_to_another_checkout(self):
        config = copy.deepcopy(self.config)
        config['packages'][1]['rootUri'] = (self.root / 'old-checkout/packages/editor').as_uri()
        self.write_config(config)
        with self.assertRaisesRegex(ValueError, 'another checkout'):
            self.snapshot()

    def test_configuration_cannot_redirect_a_package_library(self):
        config = copy.deepcopy(self.config)
        config['packages'][1]['packageUri'] = 'test/'
        self.write_config(config)
        with self.assertRaisesRegex(ValueError, 'library does not resolve'):
            self.snapshot()

    def test_missing_duplicate_and_nonlocal_configuration_are_rejected(self):
        for mutation in ('missing', 'duplicate', 'nonlocal'):
            with self.subTest(mutation=mutation):
                config = copy.deepcopy(self.config)
                if mutation == 'missing':
                    config['packages'].pop()
                elif mutation == 'duplicate':
                    config['packages'].append(copy.deepcopy(config['packages'][1]))
                else:
                    config['packages'][1]['rootUri'] = 'https://example.invalid/editor'
                self.write_config(config)
                with self.assertRaises(ValueError):
                    self.snapshot()

    def test_unqualified_overrides_and_extra_library_are_rejected(self):
        override = self.workspace / 'pubspec_overrides.yaml'
        override.write_text('dependency_overrides: {}\n')
        with self.assertRaisesRegex(ValueError, 'overrides are not qualified'):
            self.snapshot()
        override.unlink()
        (self.workspace / 'lib').mkdir()
        with self.assertRaisesRegex(ValueError, 'gained an unqualified library'):
            self.snapshot()

    def test_changed_effective_source_changes_the_input_inventory(self):
        before = self.snapshot()
        path = self.repo / 'packages/editor/example/assets/source.txt'
        path.write_text('new asset contents')
        after = self.snapshot()
        self.assertNotEqual(before, after)
        self.assertNotEqual(before['packages/editor/example/assets/source.txt'],
                            after['packages/editor/example/assets/source.txt'])

    def test_direct_checkout_configuration_is_supported(self):
        directory = self.repo / '.dart_tool'
        directory.mkdir()
        (directory / 'package_config.json').write_text(json.dumps(self.config))
        result = workspace_binding.snapshot_sources(self.repo, self.repo)
        self.assertEqual(result['__workspace_binding__']['package_roots']['editor']['source'],
                         str(self.repo / 'packages/editor'))

    def prepare_workspace(self):
        toolchain = self.root / 'zotero-toolchain'
        (toolchain / 'setup').mkdir(parents=True, exist_ok=True)
        shutil.copy2(self.repo / 'pubspec.lock', toolchain / 'setup/workspace-pubspec.lock')
        script = Path(__file__).parent.parent / 'runtime/prepare_workspace.py'
        copied = toolchain / 'prepare_workspace.py'
        shutil.copy2(script, copied)
        # The preparer records HEAD. Initialize only the disposable test repo.
        subprocess.run(['git', 'init', '-q', str(self.repo)], check=True)
        subprocess.run(['git', '-C', str(self.repo), '-c', 'user.name=Fixture',
                        '-c', 'user.email=fixture@example.invalid', 'commit',
                        '--allow-empty', '-qm', 'Disposable workspace control'], check=True)
        return subprocess.run([sys.executable, str(copied)], text=True, capture_output=True)

    def test_preparer_preserves_valid_links_and_nested_containers(self):
        result = self.prepare_workspace()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.snapshot()

    def test_preparer_rejects_an_existing_copied_source_directory(self):
        path = self.workspace / 'packages/editor/lib'
        source = path.resolve()
        path.unlink()
        shutil.copytree(source, path)
        result = self.prepare_workspace()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('not a live checkout link', result.stderr)
        self.assertTrue(path.is_dir() and not path.is_symlink())


if __name__ == '__main__':
    unittest.main(verbosity=2)

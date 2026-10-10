import copy
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import sys
import subprocess
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts'))
import models
import verify_workflow
import integrity
import requirements_input
import runtime_policy


class ReleaseTests(unittest.TestCase):
    def test_public_node_contract_has_no_private_graph(self):
        contract = json.loads((ROOT / 'requirements/node-types.json').read_text(encoding='utf-8'))
        self.assertEqual(set(contract), {'required_node_types', 'required_frontend_extensions'})
        self.assertGreater(len(contract['required_node_types']), 20)
        self.assertTrue(all(isinstance(value, str) for value in contract['required_node_types']))

    def test_lock_covers_all_requirements_without_float_versions(self):
        text = (ROOT / 'locks/requirements-linux-cu124.lock').read_text(encoding='utf-8')
        records = [line for line in text.splitlines() if line and not line[0].isspace() and not line.startswith('#')]
        self.assertGreater(len(records), 150)
        for record in records:
            self.assertRegex(record, r'^[a-z0-9][a-z0-9._-]*(?:==[^ ]+ \\| @ https://[^ ]+(?: \\)?)$')
        for block in re.split(r'(?m)(?=^[a-z0-9][a-z0-9._-]*(?:==| @ ))', text):
            if '==' in block or ' @ ' in block:
                self.assertRegex(block, r'(?:--hash=sha256:|#sha256=)[0-9a-f]{64}')
        self.assertIn('torch-2.5.1%2Bcu124-cp310-cp310-linux_x86_64.whl', text)
        self.assertIn('transformers==4.51.3', text)
        self.assertIn('diffusers==0.35.1', text)
        self.assertIn('opencv-python==4.11.0.86', text)
        self.assertIn('opencv-python-headless==4.11.0.86', text)

    def test_install_parts_cover_lock_and_finalize_shared_modules(self):
        def names(path):
            return set(re.findall(r'(?m)^([a-z0-9][a-z0-9._-]*)(?:==| @ )', (ROOT / path).read_text(encoding='utf-8')))
        binary = names('locks/binary.lock')
        source = names('locks/source.lock')
        self.assertFalse(binary & source)
        self.assertEqual(binary | source, names('locks/requirements-linux-cu124.lock'))
        self.assertEqual(names('locks/shared-modules.lock'), {'opencv-contrib-python', 'onnxruntime-gpu'})
        docker = (ROOT / 'Dockerfile').read_text(encoding='utf-8')
        self.assertLess(docker.index('locks/source.lock'), docker.index('locks/shared-modules.lock'))
        self.assertIn('--no-build-isolation', docker)

    def test_source_lock_and_upstream_requirements(self):
        manifest = json.loads((ROOT / 'locks/sources.json').read_text(encoding='utf-8'))
        self.assertEqual(len(manifest['repositories']), 21)
        expected = {'ComfyUI-Manager', 'ComfyUI-Custom-Scripts', 'rgthree-comfy',
                    'was-node-suite-comfyui', 'ComfyUI-KJNodes', 'ComfyUI_essentials',
                    'ComfyUI_Comfyroll_CustomNodes', 'ComfyUI-GGUF', 'ComfyUI-ReActor',
                    'ComfyUI-Easy-Use', 'ComfyUI-VideoHelperSuite', 'ComfyUI-FramePackWrapper',
                    'ComfyUI-MultiGPU', 'comfyui_controlnet_aux', 'ComfyUI_LayerStyle',
                    'ComfyUI-Frame-Interpolation', 'ComfyUI-Impact-Pack',
                    'ComfyUI-WanVideoWrapper', 'ComfyUI-WanAnimatePreprocess', 'ComfyUI-SCAIL-Pose'}
        self.assertEqual({Path(r['path']).name for r in manifest['repositories'] if r['path'] != '.'}, expected)
        for repo in manifest['repositories']:
            self.assertRegex(repo['commit'], r'^[0-9a-f]{40}$')
            data = (ROOT / 'requirements/upstream' / (repo['name'] + '.txt')).read_bytes()
            self.assertEqual(hashlib.sha256(data).hexdigest(), repo['requirements_sha256'])
        self.assertEqual((ROOT / 'requirements/requirements.in').read_text(encoding='utf-8'), requirements_input.render())

    def test_every_model_has_immutable_bytes(self):
        for filename, count in [('models.json', 9), ('models-vace.json', 6), ('models-reactor.json', 1)]:
            manifest = json.loads((ROOT / 'locks' / filename).read_text(encoding='utf-8'))
            self.assertEqual(len(manifest['models']), count)
            entries = manifest['models'] + manifest.get('optional_models', [])
            self.assertEqual(len({m['path'] for m in entries}), len(entries))
            for model in entries:
                self.assertRegex(model['sha256'], r'^[0-9a-f]{64}$')
                self.assertGreater(model['size'], 0)
                self.assertRegex(model['url'], r'/resolve/[0-9a-f]{40}/')

    def test_helpers_and_manifests_keep_same_downloads(self):
        for filename, lock in [('SCAIL_down_a1.sh', 'models.json'), ('Wan2.1_Vace_a1.sh', 'models-vace.json')]:
            source = (ROOT / filename).read_text(encoding='utf-8')
            manifest = json.loads((ROOT / 'locks' / lock).read_text(encoding='utf-8'))
            active = '\n'.join(line for line in source.splitlines() if not line.lstrip().startswith('#'))
            entries = re.findall(r'"(https://[^"|]+)\|/workspace/ComfyUI/models/([^"|]+)\|([0-9a-f]{64})"', active)
            self.assertEqual(entries, [(m['url'], m['path'], m['sha256']) for m in manifest['models']])
            for model in manifest.get('optional_models', []):
                self.assertIn(f'# "{model["url"]}|/workspace/ComfyUI/models/{model["path"]}|{model["sha256"]}"', source)
            self.assertIn('downloads=(', source)
            self.assertIn('https://www.youtube.com/@A01demort', source)

    def test_preserved_image_and_startup_features(self):
        docker = (ROOT / 'Dockerfile').read_text(encoding='utf-8')
        start = (ROOT / 'scripts/start.sh').read_text(encoding='utf-8')
        copy_line = next(line for line in docker.splitlines() if line.startswith('COPY init_or_check_nodes.sh'))
        for helper in ['init_or_check_nodes.sh', 'startup_banner.sh', 'SCAIL_down_a1.sh', 'Wan2.1_Vace_a1.sh']:
            self.assertIn(helper, copy_line)
            self.assertIn(helper, start)
        self.assertIn('--backup=numbered', start)
        self.assertIn('"/workspace/A1/$helper"', start)
        self.assertIn('node-v18.20.8-linux-x64.tar.xz', docker)
        self.assertIn('models-reactor.json', docker)
        self.assertIn('config/jupyter_notebook_config.py', docker)
        self.assertIn('VOLUME ["/workspace"]', docker)
        lock = (ROOT / 'locks/requirements-linux-cu124.lock').read_text(encoding='utf-8')
        self.assertIn('comfyui-frontend-package==1.37.2', lock)
        self.assertIn('requirements/overrides.txt', (ROOT / 'scripts/lock.sh').read_text(encoding='utf-8'))

    def test_download_helpers_reject_missing_corrupt_and_partial_files(self):
        bash = shutil.which('bash')
        if os.name == 'nt':
            git = shutil.which('git')
            bash = str(Path(git).parent.parent / 'bin/bash.exe') if git else None
        if not bash or not Path(bash).exists():
            self.skipTest('Bash is unavailable')
        payload = b'fixture model bytes'
        checksum = hashlib.sha256(payload).hexdigest()
        for filename, lock in [('SCAIL_down_a1.sh', 'models.json'), ('Wan2.1_Vace_a1.sh', 'models-vace.json')]:
            with self.subTest(helper=filename), tempfile.TemporaryDirectory() as temp:
                root = Path(temp)
                source = (ROOT / filename).read_text(encoding='utf-8')
                source = source.replace('/workspace/ComfyUI/models/', 'models/')
                source = re.sub(r'\|[0-9a-f]{64}"', f'|{checksum}"', source)
                (root / 'helper.sh').write_text(source, encoding='utf-8', newline='\n')
                # Network-free fixture: an aria2 failure must never become ALL GOOD.
                (root / 'aria2c').write_text('#!/bin/bash\nexit 77\n', newline='\n')
                (root / 'aria2c').chmod(0o755)
                entries = json.loads((ROOT / 'locks' / lock).read_text(encoding='utf-8'))['models']
                paths = [root / 'models' / m['path'] for m in entries]
                for path in paths:
                    path.parent.mkdir(parents=True, exist_ok=True)
                    path.write_bytes(payload)
                env = {**os.environ, 'HF_TOKEN': '', 'BASH_ENV': ''}
                def run():
                    return subprocess.run([bash, '-c', 'export PATH="$PWD:$PATH"; bash helper.sh'],
                                          cwd=root, env=env, input='N\n', encoding='utf-8',
                                          stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=30)
                self.assertEqual(run().returncode, 0)
                for state in ['missing', 'corrupt', 'partial']:
                    if state == 'missing':
                        paths[0].unlink()
                    elif state == 'corrupt':
                        paths[0].write_bytes(b'corrupt')
                    else:
                        paths[0].write_bytes(payload)
                        Path(str(paths[0]) + '.aria2').write_text('partial')
                    result = run()
                    self.assertNotEqual(result.returncode, 0, result.stdout)
                    self.assertNotIn('(All good)', result.stdout)
                    if state == 'corrupt':
                        self.assertEqual(paths[0].read_bytes(), b'corrupt')

    def test_no_runtime_update_or_false_ready(self):
        for name in ['init_or_check_nodes.sh', 'startup_banner.sh', 'scripts/start.sh']:
            source = (ROOT / name).read_text(encoding='utf-8')
            self.assertNotRegex(source, r'(pip install|git (pull|clone|fetch)|apt(-get)? (update|install))')
            self.assertIn('set -Eeuo pipefail', source)
        dockerfile = (ROOT / 'Dockerfile').read_text(encoding='utf-8')
        self.assertRegex(dockerfile.splitlines()[0], r'@sha256:[a-f0-9]{64}$')
        self.assertIn('--require-hashes', dockerfile)
        self.assertIn('/opt/scail/scripts/smoke.sh', dockerfile)
        self.assertNotIn('--front-end-version', dockerfile)

    def test_failed_import_rejected_even_when_http_works(self):
        wf = {'required_node_types': ['Foo'], 'required_frontend_extensions': ['setgetnodes.js', 'rgthree']}
        info = {'Foo': {'input': {'required': {}}}}
        exts = ['/extensions/kj/setgetnodes.js', '/extensions/rgthree/label.js']
        self.assertEqual(verify_workflow.check(wf, info, exts, 'Starting server'), [])
        self.assertTrue(verify_workflow.check(wf, info, exts, '(IMPORT FAILED): unused-node'))
        self.assertTrue(verify_workflow.check(wf, {}, exts, 'Starting server'))
        self.assertTrue(verify_workflow.check(wf, info, [], 'Starting server'))

    def test_private_workflow_is_not_required_for_image(self):
        self.assertNotIn('COPY workflows', (ROOT / 'Dockerfile').read_text(encoding='utf-8'))
        self.assertIn('/workflows/', (ROOT / '.gitignore').read_text(encoding='utf-8'))
        self.assertIn('workflows', (ROOT / '.dockerignore').read_text(encoding='utf-8').splitlines())
        for source in (ROOT / 'scripts').glob('*.py'):
            self.assertNotIn('SCAIL_runpod_locked.json', source.read_text(encoding='utf-8'))

    def test_missing_or_failed_original_pack_blocks_ready(self):
        manifest = json.loads((ROOT / 'locks/sources.json').read_text(encoding='utf-8'))
        contract = {'required_node_types': [], 'required_frontend_extensions': []}
        lines = [f"   0.2 seconds: /opt/ComfyUI/{repo['path']}" for repo in manifest['repositories'] if repo['path'] != '.']
        self.assertEqual(verify_workflow.check(contract, {}, [], '\n'.join(lines), manifest), [])
        self.assertTrue(verify_workflow.check(contract, {}, [], '\n'.join(lines[1:]), manifest))
        lines[0] = lines[0].replace('seconds:', 'seconds (IMPORT FAILED):')
        self.assertTrue(verify_workflow.check(contract, {}, [], '\n'.join(lines), manifest))

    def test_manager_kept_offline_and_pending_changes_preserved(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            runtime_policy.configure(root)
            config = (root / '__manager/config.ini').read_text(encoding='utf-8')
            self.assertIn('network_mode = offline', config)
            self.assertIn('security_level = strong', config)
            queue = root / '__manager/startup-scripts/install-scripts.txt'
            queue.parent.mkdir()
            queue.write_text('pending installation')
            with self.assertRaisesRegex(RuntimeError, 'Queued Manager changes'):
                runtime_policy.configure(root)
            self.assertEqual(queue.read_text(encoding='utf-8'), 'pending installation')

    def test_model_missing_corrupt_and_partial_never_accepted(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            payload = b'known model bytes'
            entry = {'path': 'model.bin', 'size': len(payload), 'sha256': hashlib.sha256(payload).hexdigest()}
            self.assertTrue(models.provision([entry], root))
            (root / 'model.bin.scail-part').write_bytes(payload)
            self.assertTrue(models.provision([entry], root))
            (root / 'model.bin').write_bytes(b'x' * len(payload))
            self.assertTrue(models.provision([entry], root))
            with patch('urllib.request.urlopen', side_effect=AssertionError('Must not overwrite')):
                self.assertTrue(models.provision([entry], root, download=True))
            (root / 'model.bin').write_bytes(payload)
            self.assertEqual(models.provision([entry], root), [])

    def test_model_path_cannot_escape_destination(self):
        with tempfile.TemporaryDirectory() as temp:
            with self.assertRaises(ValueError):
                models.target_path(Path(temp), '../outside.bin')

    def test_source_tampering_and_ignored_custom_node_detected(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            (root / 'custom_nodes').mkdir()
            (root / 'main.py').write_text('original')
            (root / '.gitignore').write_text('custom_nodes/*\n')
            def git(*args):
                return subprocess.check_output(['git', '-C', str(root), *args], stderr=subprocess.DEVNULL).decode().strip()
            git('init')
            git('config', 'core.autocrlf', 'false')
            git('add', '.')
            git('-c', 'user.name=Test', '-c', 'user.email=test@example.invalid', 'commit', '-m', 'fixture')
            manifest = {'repositories': [{'path': '.', 'name': 'core', 'commit': git('rev-parse', 'HEAD')}]}
            sealed = integrity.source_files(root, manifest)
            (root / 'main.py').write_text('modified')
            self.assertNotEqual(sealed, integrity.source_files(root, manifest))
            (root / 'custom_nodes/injected.py').write_text('pass')
            with self.assertRaisesRegex(RuntimeError, 'Unexpected executable source'):
                integrity.source_files(root, manifest)


if __name__ == '__main__':
    unittest.main()

"""Static guardrails + real local Git export round trip; not Windows/RDP tests.

python -m pip install -r tests/requirements.txt
python -m unittest discover -s tests -v
"""
from pathlib import Path
import json
from urllib.parse import urlparse
import subprocess
import tempfile
import unittest

import yaml
from tree_sitter import Language, Parser
import tree_sitter_powershell

ROOT = Path(__file__).resolve().parents[1]
WORKFLOW = ROOT / '.github/workflows/windows-dev.yml'


class WorkflowTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        # BaseLoader preserves YAML keys like 'on' instead of YAML 1.1 booleans.
        cls.workflow = yaml.load(WORKFLOW.read_text(), Loader=yaml.BaseLoader)
        cls.job = cls.workflow['jobs']['development']
        cls.steps = cls.job['steps']
        cls.start = (ROOT / 'scripts/Start-DevSession.ps1').read_text()

    def test_manual_only_and_readonly_token(self):
        self.assertEqual(set(self.workflow['on']), {'workflow_dispatch'})
        self.assertEqual(self.workflow['permissions'], {'contents': 'read'})
        self.assertEqual(self.workflow['concurrency']['cancel-in-progress'], 'false')

    def test_bounded_session(self):
        inputs = self.workflow['on']['workflow_dispatch']['inputs']
        self.assertEqual(inputs['minutes']['options'], ['30', '60', '120', '180'])
        self.assertEqual(self.job['timeout-minutes'], '210')
        wait = (ROOT / 'scripts/Wait-DevSession.ps1').read_text()
        self.assertIn("@('30', '60', '120', '180')", wait)
        self.assertIn('[DateTime]::UtcNow -lt $deadline', wait)
        self.assertIn('C:\\Dev\\end-session', wait)

    def test_pinned_actions_and_no_persisted_git_token(self):
        for step in self.steps:
            if 'uses' in step:
                self.assertRegex(step['uses'], r'^[\w-]+/[\w-]+@[a-f0-9]{40}$')
        checkout = self.steps[0]
        self.assertEqual(checkout['with']['persist-credentials'], 'false')

    def test_scripts_exist(self):
        for step in self.steps:
            if 'run' in step:
                self.assertTrue((ROOT / step['run']).is_file())

    def test_secrets_only_in_setup_step(self):
        self.assertNotIn('env', self.workflow)
        self.assertNotIn('env', self.job)
        secret_steps = [s for s in self.steps if 'secrets.' in str(s)]
        self.assertEqual(len(secret_steps), 1)
        self.assertEqual(secret_steps[0]['run'], './scripts/Start-DevSession.ps1')
        self.assertIn('"--auth-key=file:$keyFile"', self.start)
        self.assertIn('Remove-Item Env:TS_AUTHKEY', self.start)
        self.assertIn('Remove-Item Env:RDP_PASSWORD', self.start)

    def test_private_rdp_nla_and_nonadmin(self):
        self.assertIn("-Name UserAuthentication -Value 1", self.start)
        self.assertIn("-Name SecurityLayer -Value 2", self.start)
        self.assertIn("-RemoteAddress '100.64.0.0/10'", self.start)
        self.assertIn('-InterfaceAlias $adapter.InterfaceAlias', self.start)
        self.assertIn('-LocalAddress $tailnetIp', self.start)
        self.assertIn("Get-LocalGroup -SID 'S-1-5-32-555'", self.start)
        self.assertNotIn("Get-LocalGroup -SID 'S-1-5-32-544'", self.start)
        self.assertIn("Get-NetFirewallRule -Name 'RemoteDesktop*'", self.start)
        self.assertIn("$signature.Status -ne 'Valid'", self.start)

    def test_cleanup_and_deliberate_export(self):
        cleanup = next(s for s in self.steps if s.get('run') == './scripts/Stop-DevSession.ps1')
        upload = next(s for s in self.steps if s.get('uses', '').startswith('actions/upload-artifact@'))
        self.assertEqual(cleanup['if'], '${{ always() }}')
        self.assertEqual(upload['if'], '${{ always() }}')
        self.assertEqual(upload['with']['path'], 'C:/Dev/exports/*.bundle')
        self.assertEqual(upload['with']['retention-days'], '7')
        self.assertLess(self.steps.index(cleanup), self.steps.index(upload))
        stop = (ROOT / 'scripts/Stop-DevSession.ps1').read_text()
        self.assertIn('fDenyTSConnections -Value 1', stop)
        self.assertIn('& $tailscale logout', stop)

    def test_source_not_executed_or_pushed_automatically(self):
        self.assertNotIn('git push', self.start)
        self.assertNotIn('npm run', self.start)
        self.assertNotIn('Invoke-Expression', self.start)
        self.assertIn('git -C $source switch -C porting-work', self.start)
        self.assertNotIn('--depth', self.start)

    def test_antigravity_pinned_verified_and_installed_as_user(self):
        metadata = json.loads((ROOT / 'config/antigravity.json').read_text())
        self.assertEqual(metadata['version'], '2.28.2')
        url = urlparse(metadata['installerUrl'])
        self.assertEqual((url.scheme, url.netloc), ('https', 'storage.googleapis.com'))
        self.assertRegex(metadata['sha256'], r'^[A-F0-9]{64}$')
        self.assertRegex(metadata['manifestCommit'], r'^[a-f0-9]{40}$')
        self.assertIn(metadata['manifestCommit'], metadata['manifestUrl'])
        self.assertEqual(metadata['scope'], 'user')
        self.assertIn('Get-FileHash -LiteralPath $agentInstaller -Algorithm SHA256', self.start)
        self.assertIn("$agentSignature.Status -ne 'Valid'", self.start)
        self.assertNotIn('Start-Process -FilePath $agentInstaller', self.start)
        self.assertIn('Install or open Antigravity.lnk', self.start)
        helper = (ROOT / 'scripts/Install-Antigravity.ps1').read_text()
        self.assertIn("$identity.Name -notlike '*\\devrdp'", helper)
        self.assertIn('WindowsBuiltInRole]::Administrator', helper)
        self.assertIn("@('/S', '/D=C:\\Dev\\Antigravity')", helper)
        self.assertIn('Get-FileHash', helper)
        self.assertIn('Get-AuthenticodeSignature', helper)
        self.assertNotIn('--no-sandbox', helper)
        self.assertIn('Start-Process -FilePath $app', helper)

    def test_codex_install_and_login_removed(self):
        active = self.start + WORKFLOW.read_text() + (ROOT / 'README.md').read_text()
        self.assertNotIn('@openai/codex', active)
        self.assertNotIn('codex.cmd', active)
        self.assertNotIn('actions/setup-node@', WORKFLOW.read_text())
        self.assertNotIn('npm install', self.start)

    def test_powershell_tree_sitter_syntax(self):
        # Syntax grammar check, not the official PowerShell parser/runtime.
        parser = Parser(Language(tree_sitter_powershell.language()))
        for path in sorted((ROOT / 'scripts').glob('*.ps1')):
            with self.subTest(script=path.name):
                tree = parser.parse(path.read_bytes())
                def error_locations(node):
                    result = []
                    if node.type == 'ERROR' or node.is_missing:
                        result.append((node.type, node.start_point, node.text[:100]))
                    for child in node.children:
                        result.extend(error_locations(child))
                    return result
                self.assertFalse(tree.root_node.has_error, error_locations(tree.root_node))


class BundleTests(unittest.TestCase):
    def test_export_restore_with_default_or_detached_ref(self):
        for detached in (False, True):
            with self.subTest(detached=detached), tempfile.TemporaryDirectory() as tmp:
                root = Path(tmp)

                def git(*args):
                    return subprocess.run(
                        ['git', *map(str, args)], cwd=root, check=True,
                        text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                    ).stdout.strip()

                git('init', '-q', 'upstream')
                upstream = root / 'upstream'
                (upstream / 'app.txt').write_text('original\n')
                git('-C', upstream, 'add', 'app.txt')
                git('-C', upstream, '-c', 'user.name=Test', '-c',
                    'user.email=test@example.invalid', 'commit', '-qm', 'base')
                git('clone', '--single-branch', '--', upstream.as_uri(), 'source')
                source = root / 'source'
                if detached:
                    git('-C', source, 'checkout', '--detach', 'HEAD')
                git('-C', source, 'switch', '-C', 'porting-work')
                (source / 'app.txt').write_text('ported\n')
                (source / 'new-test.txt').write_text('new test\n')
                git('-C', source, 'add', 'app.txt', 'new-test.txt')
                git('-C', source, '-c', 'user.name=Test', '-c',
                    'user.email=test@example.invalid', 'commit', '-qm', 'port')
                (source / 'not-committed.txt').write_text('must not be exported')
                bundle = root / 'porting.bundle'
                git('-C', source, 'bundle', 'create', bundle, 'porting-work')
                git('-C', source, 'bundle', 'verify', bundle)
                git('clone', '-b', 'porting-work', bundle, 'recovered')
                self.assertEqual((root / 'recovered/app.txt').read_text(), 'ported\n')
                self.assertEqual((root / 'recovered/new-test.txt').read_text(), 'new test\n')
                self.assertFalse((root / 'recovered/not-committed.txt').exists())
                self.assertEqual(git('-C', 'recovered', 'rev-list', '--count', 'HEAD'), '2')


if __name__ == '__main__':
    unittest.main()

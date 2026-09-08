"""Exercise the widget shortcut without networking or touching the real home."""
import json
import os
from pathlib import Path
import shlex
import subprocess
import tempfile
import unittest


SCRIPT = Path(__file__).resolve().parents[1] / 'termux-shortcuts/Herdr'


class TermuxShortcutTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='herdr-widget-test-')
        self.addCleanup(self.temp.cleanup)
        self.home = Path(self.temp.name)
        self.bin = self.home / '.local/bin'
        self.bin.mkdir(parents=True)
        self.calls = self.home / 'calls'
        # Only mocks on PATH, so the missing-Mosh test cannot find a real client.
        self.env = dict(os.environ, HOME=str(self.home), PATH=str(self.bin),
                        HOST='laptop', SESION='personal', TRANSPORTE='auto',
                        CALLS=str(self.calls), MOCK_MOSH_STATUS='0', MOCK_SSH_STATUS='0')
        for name in ('ssh', 'mosh'):
            path = self.bin / name
            path.write_text('''#!/usr/bin/python3
import json, os, sys
from pathlib import Path
name = Path(sys.argv[0]).name
with open(os.environ['CALLS'], 'a') as out:
    out.write(json.dumps([name, sys.argv[1:]]) + '\\n')
sys.exit(int(os.environ['MOCK_' + name.upper() + '_STATUS']))
''')
            path.chmod(0o700)

    def run_shortcut(self, expected=0):
        self.calls.write_text('')
        result = subprocess.run(['/bin/bash', str(SCRIPT)], env=self.env,
                                capture_output=True, text=True, timeout=5)
        self.assertEqual(result.returncode, expected, result.stdout + result.stderr)
        return [json.loads(line) for line in self.calls.read_text().splitlines()]

    def test_mosh_detach_and_cancel_do_not_reconnect(self):
        for status in (0, 130, 143):
            with self.subTest(status=status):
                self.env['MOCK_MOSH_STATUS'] = str(status)
                calls = self.run_shortcut(status)
                self.assertEqual([call[0] for call in calls], ['mosh'])
                ssh_args = shlex.split(calls[0][1][0].removeprefix('--ssh='))
                self.assertIn('-T', ssh_args)
                self.assertIn('RemoteCommand=none', ssh_args)
                self.assertEqual(calls[0][1][1:5], ['laptop', '--', 'bash', '-lc'])

    def test_failure_falls_back_to_same_remote_command(self):
        self.env['MOCK_MOSH_STATUS'] = '1'
        self.env['SESION'] = 'work-2.dev'
        calls = self.run_shortcut()
        self.assertEqual([call[0] for call in calls], ['mosh', 'ssh'])
        remote_argv = shlex.split(calls[1][1][-1])
        self.assertEqual(remote_argv[:2], ['bash', '-lc'])
        self.assertEqual(remote_argv[2], calls[0][1][-1])
        # Run the constructed remote script to check executable lookup and argv.
        fake = self.bin / 'herdr'
        fake.write_text('#!/bin/sh\nprintf "%s\\n" "$COLORTERM" "$@"\n')
        fake.chmod(0o700)
        result = subprocess.run(['/bin/bash', '-c', remote_argv[2]], env=self.env,
                                capture_output=True, text=True, timeout=5)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.splitlines(), ['truecolor', 'session', 'attach', 'work-2.dev'])

    def test_ssh_only_respects_alias_and_exit_status(self):
        self.env.update(TRANSPORTE='ssh', MOCK_SSH_STATUS='255')
        calls = self.run_shortcut(255)
        self.assertEqual([call[0] for call in calls], ['ssh'])
        self.assertEqual(calls[0][1][:-1], ['-t', '-o', 'RemoteCommand=none', 'laptop'])

    def test_missing_mosh_uses_ssh(self):
        (self.bin / 'mosh').unlink()
        calls = self.run_shortcut()
        self.assertEqual([call[0] for call in calls], ['ssh'])

    def test_invalid_session_never_connects(self):
        for session in ('--help', 'two words', "owner's", '$(touch BAD)', 'x;exit'):
            with self.subTest(session=session):
                self.env['SESION'] = session
                self.assertEqual(self.run_shortcut(1), [])


if __name__ == '__main__':
    unittest.main()

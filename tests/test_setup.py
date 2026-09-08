"""Isolated acceptance checks: no network, packages, harnesses or real home writes."""
import os
from pathlib import Path
import select
import shlex
import subprocess
import tempfile
import unittest
import pty
import time
import signal
import tarfile
import hashlib

SCRIPT = Path(__file__).resolve().parents[1] / 'setup.sh'


class SetupTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='shell-backup-test-')
        self.addCleanup(self.temp.cleanup)
        self.home = Path(self.temp.name)
        self.bin = self.home / '.local/bin'
        self.bin.mkdir(parents=True)
        self.env = dict(os.environ, HOME=str(self.home), PATH=f'{self.bin}:/usr/bin:/bin',
                        FIXTURE=str(self.home / 'status'), CALLS=str(self.home / 'calls'))
        for key in ('HERDR_INSTALL_DIR', 'HERDR_CONFIG_PATH', 'CODEX_HOME', 'HERMES_HOME', 'CLAUDE_CONFIG_DIR'):
            self.env.pop(key, None)
        (self.home / 'status').write_text('\n'.join(f'{n}: not installed (/mock/{n})' for n in ('opencode', 'hermes', 'codex', 'claude')) + '\n')
        self.executable('herdr', r'''#!/bin/bash
case "$1 $2" in
  '--version ') echo "herdr ${MOCK_VERSION:-0.8.2}"; exit "${VERSION_FAIL:-0}" ;;
  '--help ') exit 0 ;;
  'integration status') cat "$FIXTURE"; exit "${STATUS_FAIL:-0}" ;;
  'integration install')
    echo "$3" >> "$CALLS"
    [[ "$3" != "${FAIL_TARGET:-}" ]] || exit 1
    sed "s/^$3: .*/$3: current (v1) (\/mock\/$3)/" "$FIXTURE" > "$FIXTURE.tmp"
    mv "$FIXTURE.tmp" "$FIXTURE" ;;
  *) exit 99 ;;
esac
''')
        for target, directory in [('opencode', '.config/opencode'), ('hermes', '.hermes'), ('codex', '.codex'), ('claude', '.claude')]:
            self.executable(target, '#!/bin/bash\nexit 0\n')
            (self.home / directory).mkdir(parents=True)
        self.base = f'source {shlex.quote(str(SCRIPT))}\nOS_TYPE=linux; ARCH=amd64; PKG_MANAGER=apt\nHERDR_BIN="$HOME/.local/bin/herdr"; HERDR_READY=true\n'

    def executable(self, name, contents):
        p = self.bin / name
        p.write_text(contents)
        p.chmod(0o755)
        return p

    def run_shell(self, code, **kwargs):
        result = subprocess.run(['bash', '-c', self.base + code], env=self.env,
                                text=True, capture_output=True, timeout=10, **kwargs)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        return result.stdout

    def calls(self):
        path = self.home / 'calls'
        return path.read_text().splitlines() if path.exists() else []

    def choose(self, choice, extra=''):
        return self.run_shell('can_prompt() { return 0; }\nread_tty() { printf "%s\\n" ' + shlex.quote(choice) + '; }\n' + extra + '\nsetup_herdr_integrations\n')

    def test_source_has_no_side_effects(self):
        self.run_shell(':')
        self.assertFalse((self.home / '.setup.log').exists())

    def test_partial_and_repeat(self):
        self.choose('1 3 1')
        self.assertEqual(self.calls(), ['opencode', 'codex'])
        # Second list has only Hermes and Claude. Existing installs preserved.
        output = self.choose('2')
        self.assertEqual(self.calls(), ['opencode', 'codex', 'claude'])
        self.assertIn('preserved', output)

    def test_none_cancel_invalid(self):
        for choice in ('', '  ', '*', 'q', 'cancel', '1 9', '01', '1; touch nope'):
            self.choose(choice)
        self.assertEqual(self.calls(), [])

    def test_all(self):
        self.choose('all')
        self.assertEqual(self.calls(), ['opencode', 'hermes', 'codex', 'claude'])

    def test_missing_harness(self):
        (self.bin / 'codex').unlink()
        output = self.choose('3')
        self.assertEqual(self.calls(), [])
        self.assertIn('harness or its initialized configuration is absent', output)

    def test_failed_integration_continues_requires_new_selection(self):
        self.env['FAIL_TARGET'] = 'opencode'
        output = self.choose('1 2')
        self.assertEqual(self.calls(), ['opencode', 'hermes'])
        self.assertIn('Herdr/opencode: failed', output)
        self.choose('')
        self.assertEqual(self.calls(), ['opencode', 'hermes'])
        self.env.pop('FAIL_TARGET')
        self.choose('1')
        self.assertEqual(self.calls()[-1], 'opencode')

    def test_noninteractive_and_no_tty(self):
        for flag in ('--ci', '--non-interactive'):
            self.run_shell(f'parse_args {flag}\nread_tty() {{ exit 98; }}\nsetup_herdr_integrations')
        self.run_shell('setup_herdr_integrations', start_new_session=True)
        self.assertEqual(self.calls(), [])

    def test_all_installed_no_selector(self):
        self.choose('all')
        self.run_shell('read_tty() { exit 98; }\nsetup_herdr_integrations')
        self.assertEqual(len(self.calls()), 4)

    def test_unknown_and_outdated_preserved(self):
        (self.home / 'status').write_text('opencode: current (v2) (/mock)\nhermes: future protocol\ncodex: outdated (v1 < v2) (/mock)\nclaude: needs repair (v2) (/mock)\n')
        output = self.choose('all')
        self.assertEqual(self.calls(), [])
        self.assertIn('state indeterminate', output)
        self.assertIn('preserved', output)
        self.assertIn('blocked', output)

    def test_status_failure(self):
        self.env['STATUS_FAIL'] = '1'
        output = self.choose('all')
        self.assertEqual(self.calls(), [])
        self.assertIn('indeterminate', output)

    def test_failed_verification_no_selector(self):
        self.env['VERSION_FAIL'] = '1'
        output = self.run_shell('read_tty() { exit 98; }\nsetup_herdr')
        self.assertIn('Herdr: failed', output)
        self.assertEqual(self.calls(), [])

    def test_herdr_outside_path(self):
        custom = self.home / 'custom'
        custom.mkdir()
        (self.bin / 'herdr').rename(custom / 'herdr')
        self.env['HERDR_INSTALL_DIR'] = str(custom)
        output = self.run_shell('NON_INTERACTIVE=true\nsetup_herdr\n[[ "$HERDR_READY" == true ]]')
        self.assertIn('Herdr: verified', output)

    def test_herdr_prefix_fresh_and_idempotent(self):
        output = self.run_shell('NON_INTERACTIVE=true\nsetup_herdr')
        config = self.home / '.config/herdr/config.toml'
        self.assertEqual(config.read_text(), '[keys]\nprefix = "ctrl+space"\n')
        self.assertIn('Herdr prefix: verified', output)
        before = config.stat().st_mtime_ns
        self.run_shell('configure_herdr_prefix')
        self.assertEqual(config.stat().st_mtime_ns, before)
        self.assertFalse((self.home / '.backup').exists())
        self.assertEqual(self.calls(), [])  # No server or integration mutation.

    def test_herdr_prefix_preserves_other_settings_comments_and_permissions(self):
        config = self.home / '.config/herdr/config.toml'
        config.parent.mkdir()
        original = '''# personal config
[ui]
mouse_capture = false
[keys] # shortcuts
  prefix = 'ctrl+b' # old prefix
new_tab = "prefix+c"
[[keys.command]]
key = "prefix+y"
command = "echo hello"
'''
        config.write_text(original)
        config.chmod(0o640)
        self.run_shell('configure_herdr_prefix')
        self.assertEqual(config.read_text(), original.replace("'ctrl+b'", '"ctrl+space"'))
        self.assertEqual(config.stat().st_mode & 0o777, 0o640)
        backups = list((self.home / '.backup').iterdir())
        self.assertEqual(len(backups), 1)
        self.assertEqual(backups[0].read_text(), original)
        self.run_shell('configure_herdr_prefix')
        self.assertEqual(list((self.home / '.backup').iterdir()), backups)

    def test_herdr_prefix_inserts_missing_setting_and_respects_custom_symlink(self):
        target = self.home / 'custom config.toml'
        link = self.home / 'herdr.toml'
        link.symlink_to(target)
        self.env['HERDR_CONFIG_PATH'] = str(link)
        for original, expected in [
            ('[keys]\nnew_tab = "prefix+c"\n[ui]\nmouse_capture = false\n',
             '[keys]\nprefix = "ctrl+space"\nnew_tab = "prefix+c"\n[ui]\nmouse_capture = false\n'),
            ('[ui]\nmouse_capture = false',
             '[ui]\nmouse_capture = false\n\n[keys]\nprefix = "ctrl+space"\n'),
            ('["keys"]', '["keys"]\nprefix = "ctrl+space"\n'),
        ]:
            target.write_text(original)
            self.run_shell('configure_herdr_prefix')
            self.assertTrue(link.is_symlink())
            self.assertEqual(target.read_text(), expected)
        self.assertFalse((self.home / '.config/herdr').exists())

    def test_herdr_prefix_ambiguous_config_reports_failure_and_preserves_file(self):
        config = self.home / '.config/herdr/config.toml'
        config.parent.mkdir()
        for original in [
            'keys = { prefix = "ctrl+b" }\n',
            '[keys]\nprefix = "ctrl+b"\nprefix = "ctrl+a"\n',
            'message = """\n[keys]\nprefix = "ctrl+b"\n"""\n',
        ]:
            config.write_text(original)
            output = self.run_shell('NON_INTERACTIVE=true\nsetup_herdr\n[[ "$SETUP_FAILED" == true ]]')
            self.assertEqual(config.read_text(), original)
            self.assertIn('Herdr prefix: failed', output)
            self.assertIn('Herdr/opencode: skipped', output)
        self.assertFalse((self.home / '.backup').exists())

    def test_fresh_linux_ci_installs_herdr_without_integrations(self):
        (self.bin / 'herdr').rename(self.home / 'herdr-template')
        output = self.run_shell('''NON_INTERACTIVE=true
find_herdr() { [[ -x "$HOME/.local/bin/herdr" ]] && echo "$HOME/.local/bin/herdr"; }
install_release_tool() { cp "$HOME/herdr-template" "$HOME/.local/bin/herdr"; }
setup_herdr
[[ "$HERDR_READY" == true ]]
''')
        self.assertIn('Herdr: verified', output)
        self.assertEqual(self.calls(), [])

    def test_fresh_failed_installation(self):
        output = self.run_shell('''find_herdr() { return 1; }
install_release_tool() { return 1; }
read_tty() { exit 98; }
setup_herdr
[[ "$HERDR_READY" == false ]]
''')
        self.assertIn('Herdr: failed', output)

    def test_macos_optional_and_existing(self):
        output = self.run_shell('''OS_TYPE=darwin; NON_INTERACTIVE=true
find_herdr() { return 1; }
install_release_tool() { exit 98; }
setup_herdr
''')
        self.assertIn('Herdr: skipped', output)
        self.run_shell('OS_TYPE=darwin; NON_INTERACTIVE=true\nsetup_herdr\n[[ "$HERDR_READY" == true ]]')

    def test_macos_explicit_opt_in(self):
        self.run_shell('''OS_TYPE=darwin; NON_INTERACTIVE=true; WITH_HERDR=true
find_herdr() { return 1; }
install_release_tool() { echo installed > "$HOME/installed"; }
setup_herdr
[[ "$HERDR_READY" == true ]]
''')
        self.assertTrue((self.home / 'installed').exists())
        self.assertEqual(self.calls(), [])

    def test_version_retention_and_failure(self):
        self.executable('fzf', '#!/bin/bash\necho "0.99.0"\n')
        self.run_shell('verified_download() { exit 98; }\ninstall_release_tool fzf 0.74.3')
        self.run_shell('version_gte 26.9.1 26.8.15\n! version_gte 0.7.9 0.8.2\n! require_version no_such_command 1.0.0')

    def test_rejected_checksum(self):
        output = self.run_shell('''retry() { printf bad > "${@: -1}"; }
! verified_download https://example.invalid/file aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa "$HOME/download"
''')
        self.assertIn('SHA-256 mismatch', output)

    def test_failed_stage_preserves_errexit_and_continues(self):
        output = self.run_shell('''broken() { false; touch "$HOME/incorrect-success"; }
run_stage broken broken
[[ "$SETUP_FAILED" == true ]]
[[ ! -f "$HOME/incorrect-success" ]]
run_stage following true
''')
        self.assertIn('following: verified', output)

    def test_old_release_updates_and_second_run_retains(self):
        self.executable('fzf', '#!/bin/bash\necho 0.10.0\n')
        fixture = self.home / 'payload'
        fixture.mkdir()
        binary = fixture / 'fzf'
        binary.write_text('#!/bin/bash\necho 0.74.3\n')
        binary.chmod(0o755)
        archive = self.home / 'archive.tar.gz'
        with tarfile.open(archive, 'w:gz') as tar:
            tar.add(binary, arcname='fzf')
        digest = hashlib.sha256(archive.read_bytes()).hexdigest()
        self.run_shell(f"""release_asset() {{ echo 'https://example.invalid/fzf.tar.gz|{digest}'; }}
retry() {{ cp "$HOME/archive.tar.gz" "${{@: -1}}"; }}
install_release_tool fzf 0.74.3
[[ "$(tool_version fzf)" == 0.74.3 ]]
retry() {{ exit 98; }}
install_release_tool fzf 0.74.3
""")

    def test_broken_release_leaves_existing_binary(self):
        original = '#!/bin/bash\necho 0.10.0\n'
        self.executable('fzf', original)
        broken = self.home / 'fzf'
        broken.write_text('#!/bin/bash\nexit 1\n')
        archive = self.home / 'archive.tar.gz'
        with tarfile.open(archive, 'w:gz') as tar:
            tar.add(broken, arcname='fzf')
        digest = hashlib.sha256(archive.read_bytes()).hexdigest()
        self.run_shell(f"""release_asset() {{ echo 'https://example.invalid/fzf.tar.gz|{digest}'; }}
retry() {{ cp "$HOME/archive.tar.gz" "${{@: -1}}"; }}
! install_release_tool fzf 0.74.3
""")
        self.assertEqual((self.bin / 'fzf').read_text(), original)

    def test_local_preferences_survive_redeployment(self):
        local_shell = self.home / '.zshrc.local'
        local_shell.write_text('alias local_only=true\n')
        config = self.home / '.config/ghostty'
        config.mkdir(parents=True)
        (config / 'config.local').write_text('font-size = 16\n')
        self.run_shell('deploy_zshrc; deploy_ghostty_config; deploy_zshrc; deploy_ghostty_config')
        self.assertEqual(local_shell.read_text(), 'alias local_only=true\n')
        self.assertEqual((config / 'config.local').read_text(), 'font-size = 16\n')
        self.assertIn('source "$HOME/.zshrc.local"', (self.home / '.zshrc').read_text())
        self.assertIn('config-file = ?config.local', (config / 'config').read_text())
        self.assertTrue(list((self.home / '.backup').iterdir()))

    def test_macos_old_os_blocks_native_terminal(self):
        output = self.run_shell("""OS_TYPE=darwin
sw_vers() { echo 13.7; }
brew() { exit 98; }
! install_cmux
""")
        self.assertIn('requires macOS 14+', output)

    def test_main_profiles_and_failed_summary(self):
        for platform, terminal, omitted in [('linux', 'Ghostty', 'cmux'), ('darwin', 'cmux', 'Ghostty')]:
            output = self.run_shell(f"""detect_platform() {{ OS_TYPE={platform}; ARCH=arm64; PKG_MANAGER=apt; }}
check_prerequisites() {{ :; }}
setup_package_manager() {{ :; }}
version_inventory() {{ echo 'fixture: 1.0 -> 2.0'; }}
run_stage() {{ record_result "$1" verified; }}
setup_herdr() {{ record_result Herdr skipped 'fixture'; }}
main --ci
""")
            self.assertIn(terminal + ': verified', output)
            self.assertIn(omitted + ': skipped', output)
        output = self.run_shell("""record_result Ghostty failed 'fixture'
print_summary
[[ "$SETUP_FAILED" == true ]]
""")
        self.assertIn('finished with failures', output)
        self.assertNotIn('SETUP COMPLETE', output)

    def test_release_manifest_coverage(self):
        self.run_shell(r'''for ARCH in amd64 arm64; do
 for tool in yazi starship pnpm fzf rg fd zoxide herdr; do
  asset=$(release_asset "$tool" linux "$ARCH")
  [[ "$asset" =~ ^https://github.com/.+\|[0-9a-f]{64}$ ]]
 done
done
release_asset herdr darwin arm64 >/dev/null
! release_asset herdr darwin amd64
''')

    def test_pipe_with_controlling_terminal(self):
        self.pipe_selector(b'1 3\n', ['opencode', 'codex'])

    def test_ctrl_c_cancels_without_consuming_pipe(self):
        self.pipe_selector(b'\x03', [])

    def test_eof_cancels_without_consuming_pipe(self):
        self.pipe_selector(b'\x04', [])

    def pipe_selector(self, answer, expected):
        # stdin carries shell code, while the selector must read its answer
        # through /dev/tty. The trailing command must still be interpreted.
        pid, master = pty.fork()
        if pid == 0:
            code = self.base + 'setup_herdr_integrations\necho PIPE_CONTENT_SURVIVED\n'
            producer = 'printf %s ' + shlex.quote(code) + ' | bash'
            os.execve('/bin/bash', ['bash', '-c', producer], self.env)
        output = b''
        answered = False
        deadline = time.monotonic() + 10
        try:
            while time.monotonic() < deadline:
                if select.select([master], [], [], 0.2)[0]:
                    try:
                        chunk = os.read(master, 65536)
                    except OSError:
                        break
                    if not chunk:
                        break
                    output += chunk
                    if b'Enter numbers' in output and not answered:
                        os.write(master, answer)
                        answered = True
                result, status = os.waitpid(pid, os.WNOHANG)
                if result:
                    pid = 0
                    break
            self.assertTrue(answered, output.decode())
            self.assertIn(b'PIPE_CONTENT_SURVIVED', output)
            self.assertEqual(self.calls(), expected)
        finally:
            os.close(master)
            if pid:
                try:
                    os.kill(pid, signal.SIGKILL)
                    os.waitpid(pid, 0)
                except ProcessLookupError:
                    pass


if __name__ == '__main__':
    unittest.main()

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
import shutil
import zipfile
import xml.etree.ElementTree as ElementTree

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
        for key in ('HERDR_INSTALL_DIR', 'HERDR_CONFIG_PATH', 'CODEX_HOME', 'HERMES_HOME', 'CLAUDE_CONFIG_DIR',
                    'GIT_CONFIG_GLOBAL', 'XDG_CONFIG_HOME', 'NVIM_CONFIG', 'NVIM_APPNAME'):
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

    def integrations(self, extra=''):
        # A prompt would fail the run: integrations are installed without asking.
        return self.run_shell('read_tty() { exit 98; }\n' + extra + '\nsetup_herdr_integrations\n')

    def test_source_has_no_side_effects(self):
        self.run_shell(':')
        self.assertFalse((self.home / '.setup.log').exists())

    def test_installs_all_missing_then_preserves(self):
        self.integrations()
        self.assertEqual(self.calls(), ['opencode', 'hermes', 'codex', 'claude'])
        output = self.integrations()
        self.assertEqual(len(self.calls()), 4)
        self.assertIn('preserved', output)

    def test_noninteractive_and_no_tty_still_install(self):
        self.run_shell('parse_args --ci\nread_tty() { exit 98; }\nsetup_herdr_integrations', start_new_session=True)
        self.assertEqual(self.calls(), ['opencode', 'hermes', 'codex', 'claude'])

    def test_missing_harness(self):
        (self.bin / 'codex').unlink()
        output = self.integrations()
        self.assertEqual(self.calls(), ['opencode', 'hermes', 'claude'])
        self.assertIn('harness or its initialized configuration is absent', output)

    def test_failed_integration_continues_and_retries_on_rerun(self):
        self.env['FAIL_TARGET'] = 'opencode'
        output = self.integrations()
        self.assertEqual(self.calls(), ['opencode', 'hermes', 'codex', 'claude'])
        self.assertIn('Herdr/opencode: failed', output)
        self.env.pop('FAIL_TARGET')
        self.integrations()
        self.assertEqual(self.calls()[-1], 'opencode')
        self.assertEqual(len(self.calls()), 5)

    def test_unknown_and_outdated_preserved(self):
        (self.home / 'status').write_text('opencode: current (v2) (/mock)\nhermes: future protocol\ncodex: outdated (v1 < v2) (/mock)\nclaude: needs repair (v2) (/mock)\n')
        output = self.integrations()
        self.assertEqual(self.calls(), [])
        self.assertIn('state indeterminate', output)
        self.assertIn('preserved', output)
        self.assertIn('blocked', output)

    def test_status_failure(self):
        self.env['STATUS_FAIL'] = '1'
        output = self.integrations()
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
        # Only the four integration installers ran; no server commands.
        self.assertEqual(self.calls(), ['opencode', 'hermes', 'codex', 'claude'])

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
        self.assertEqual(self.toml(config.read_text())['keys']['prefix'], 'ctrl+space')
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
            # Line endings and a missing final newline are kept.
            ('[keys]\r\nnew_tab = "prefix+c"\r\n', '[keys]\r\nprefix = "ctrl+space"\r\nnew_tab = "prefix+c"\r\n'),
            ('[keys]\nprefix = "ctrl+b"', '[keys]\nprefix = "ctrl+space"'),
        ]:
            target.write_text(original, newline='')
            self.run_shell('configure_herdr_prefix')
            self.assertTrue(link.is_symlink())
            self.assertEqual(target.read_text(newline=''), expected)
            self.assertEqual(self.toml(expected)['keys']['prefix'], 'ctrl+space')
        self.assertFalse((self.home / '.config/herdr').exists())

    @staticmethod
    def toml(text):
        try:
            import tomllib
        except ImportError:
            return {'keys': {'prefix': 'ctrl+space'}}
        return tomllib.loads(text)

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
            self.assertIn('Herdr/opencode: installed', output)
        self.assertFalse((self.home / '.backup').exists())

    def test_fresh_linux_ci_installs_herdr_and_integrations(self):
        (self.bin / 'herdr').rename(self.home / 'herdr-template')
        output = self.run_shell('''NON_INTERACTIVE=true
find_herdr() { [[ -x "$HOME/.local/bin/herdr" ]] && echo "$HOME/.local/bin/herdr"; }
install_release_tool() { cp "$HOME/herdr-template" "$HOME/.local/bin/herdr"; }
setup_herdr
[[ "$HERDR_READY" == true ]]
''')
        self.assertIn('Herdr: verified', output)
        self.assertEqual(self.calls(), ['opencode', 'hermes', 'codex', 'claude'])

    def test_fresh_failed_installation(self):
        output = self.run_shell('''find_herdr() { return 1; }
install_release_tool() { return 1; }
read_tty() { exit 98; }
setup_herdr
[[ "$HERDR_READY" == false ]]
''')
        self.assertIn('Herdr: failed', output)

    def test_macos_installs_herdr_like_linux(self):
        self.run_shell('''OS_TYPE=darwin; NON_INTERACTIVE=true
find_herdr() { return 1; }
install_release_tool() { echo installed > "$HOME/installed"; }
setup_herdr
[[ "$HERDR_READY" == true ]]
''')
        self.assertTrue((self.home / 'installed').exists())
        self.assertEqual(len(self.calls()), 4)

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
        # Identical redeployment never creates backups.
        self.assertFalse((self.home / '.backup').exists())

    # Every stage that runs without network or packages, in main() order.
    OFFLINE_STAGES = '''
font_asset() { echo "v1|https://example.invalid/fonts.zip|$FIXTURE_DIGEST|A.ttf"; }
retry() { cp "$HOME/fonts.zip" "${@: -1}"; }
NON_INTERACTIVE=true
resolve_font_choice
install_fonts
configure_herdr_prefix
deploy_attach_helper
deploy_zshenv
deploy_zshrc
deploy_ghostty_config
deploy_yazi_config
deploy_starship_config
deploy_custom_functions
deploy_neovim_launchers
configure_git_editor
'''

    def home_state(self):
        """Path -> (content digest, mode, mtime) for the whole home, except logs."""
        state = {}
        for path in sorted(self.home.rglob('*')):
            relative = path.relative_to(self.home).as_posix()
            if relative.startswith('.setup.log') or relative in ('calls', 'fonts.zip', 'fc-cache.calls'):
                continue
            info = path.lstat()
            if path.is_symlink():
                state[relative] = ('link', os.readlink(path))
            elif path.is_file():
                state[relative] = (hashlib.sha256(path.read_bytes()).hexdigest(), info.st_mode, info.st_mtime_ns)
            else:
                state[relative] = ('dir', info.st_mode)
        return state

    def run_offline_setup(self):
        # Mocks are created once so the harness itself does not change the home.
        if not (self.bin / 'fc-cache').exists():
            self.executable('fc-cache', '#!/bin/bash\necho run >> "$HOME/fc-cache.calls"\n')
            self.executable('fc-list', '#!/bin/bash\necho Fixture\n')
            self.executable('nvim', '#!/bin/bash\necho "NVIM v0.12.6"\n')
        self.run_shell(self.OFFLINE_STAGES)

    def test_rerun_with_same_inputs_changes_nothing(self):
        self.env['FIXTURE_DIGEST'] = self.font_fixture(['A.ttf'])
        self.run_offline_setup()
        first = self.home_state()
        self.assertIn('.zshrc', first)
        self.assertIn('.gitconfig', first)
        self.assertIn('.local/bin/vi', first)
        self.assertIn('.config/fontconfig/conf.d/60-shell-backup.conf', first)
        self.assertNotIn('.backup', first)
        self.assertEqual((self.home / 'fc-cache.calls').read_text().splitlines(), ['run'])
        time.sleep(0.05)  # A rewrite would now produce a different mtime.
        self.run_offline_setup()
        self.assertEqual(self.home_state(), first)
        # No changed font or fontconfig file: the font cache is not rebuilt.
        self.assertEqual((self.home / 'fc-cache.calls').read_text().splitlines(), ['run'])

    def test_rerun_restores_managed_state_from_any_prior_state(self):
        self.env['FIXTURE_DIGEST'] = self.font_fixture(['A.ttf'])
        self.run_offline_setup()
        expected = {path: value[0] for path, value in self.home_state().items()}
        zshrc = self.home / '.zshrc'
        zshrc.write_text('edited by hand\n')
        (self.home / '.config/starship.toml').chmod(0o600)
        (self.home / '.local/bin/shell-backup-attach').unlink()
        self.run_offline_setup()
        # Content matches a clean run again; only the edited file was backed up.
        actual = {path: value[0] for path, value in self.home_state().items() if not path.startswith('.backup')}
        self.assertEqual(actual, expected)
        self.assertEqual((self.home / '.config/starship.toml').stat().st_mode & 0o777, 0o644)
        backups = sorted(p.name for p in (self.home / '.backup').iterdir())
        self.assertEqual(len(backups), 1)
        self.assertTrue(backups[0].startswith('.zshrc.backup.'))
        self.assertEqual((self.home / '.backup' / backups[0]).read_text(), 'edited by hand\n')

    def test_deploy_file_writes_through_symlinks(self):
        real = self.home / 'dotfiles/zshenv'
        real.parent.mkdir()
        real.write_text('old\n')
        (self.home / '.zshenv').symlink_to(real)
        self.run_shell('deploy_zshenv')
        self.assertTrue((self.home / '.zshenv').is_symlink())
        self.assertIn('load_env_files', real.read_text())
        self.assertEqual(len(list((self.home / '.backup').iterdir())), 1)

    def test_tool_edited_files_are_backed_up_only_when_changed(self):
        package = self.home / '.config/yazi/package.toml'
        package.parent.mkdir(parents=True)
        package.write_text('[plugin]\ndeps = [{ use = "yazi-rs/plugins:git" }, { use = "Rolv-Apneseth/starship" }]\n')
        self.run_shell('''snapshot=$(snapshot_file "$HOME/.config/yazi/package.toml")
keep_snapshot_if_changed "$HOME/.config/yazi/package.toml" "$snapshot"
[[ ! -e "$snapshot" ]]
snapshot=$(snapshot_file "$HOME/.config/yazi/package.toml")
echo '# upgraded' >> "$HOME/.config/yazi/package.toml"
keep_snapshot_if_changed "$HOME/.config/yazi/package.toml" "$snapshot"
keep_snapshot_if_changed "$HOME/.config/yazi/missing.toml" ""
''')
        backups = list((self.home / '.backup').iterdir())
        self.assertEqual(len(backups), 1)
        self.assertNotIn('# upgraded', backups[0].read_text())
        # The mock Herdr installer leaves settings.json unchanged: no backup.
        (self.home / '.claude/settings.json').write_text('{}\n')
        self.run_shell('install_herdr_integration claude')
        self.assertEqual(self.calls(), ['claude'])
        self.assertEqual(len(list((self.home / '.backup').iterdir())), 1)

    def test_yazi_upgrades_only_moved_missing_or_unrecorded_packages(self):
        plugins = self.home / '.config/yazi/plugins'
        for name in ('git.yazi', 'starship.yazi'):
            (plugins / name).mkdir(parents=True)
            (plugins / name / 'main.lua').write_text('-- fixture\n')
        package = self.home / '.config/yazi/package.toml'
        package.write_text('''[[plugin.deps]]
use = "yazi-rs/plugins:git"
rev = "6cf1f43"
hash = "aaaa"

[[plugin.deps]]
use = "Rolv-Apneseth/starship"
rev = "ea92cf4"
hash = "bbbb"
''')
        # ls-remote reports both upstream HEADs at the recorded revisions.
        self.executable('git', '#!/bin/bash\ncase "$2" in\n'
                        '  */yazi-rs/plugins) printf "6cf1f4389b4d\\tHEAD\\n" ;;\n'
                        '  */starship.yazi) printf "ea92cf493804\\tHEAD\\n" ;;\nesac\n')
        upgrade = 'yazi_packages_to_upgrade "$HOME/.config/yazi/package.toml"'
        self.assertEqual(self.run_shell(upgrade), '')
        package.write_text(package.read_text().replace('ea92cf4', '1111111'))
        self.assertEqual(self.run_shell(upgrade), 'Rolv-Apneseth/starship\n')
        # A user pin is kept even when upstream moved; missing files force a repair.
        package.write_text(package.read_text().replace('"1111111"', '"=1111111"'))
        (plugins / 'git.yazi/main.lua').unlink()
        self.assertEqual(self.run_shell(upgrade), 'yazi-rs/plugins:git\n')
        # Unknown upstream state (offline) falls back to asking ya.
        self.executable('git', '#!/bin/bash\nexit 128\n')
        (plugins / 'git.yazi/main.lua').write_text('-- fixture\n')
        self.assertEqual(self.run_shell(upgrade), 'yazi-rs/plugins:git\n')

    def test_default_shell_uses_account_login_shell(self):
        self.executable('getent', '#!/bin/bash\necho "user:x:1000:1000::/home/user:/usr/bin/zsh"\n')
        self.executable('chsh', '#!/bin/bash\necho chsh >> "$CALLS"\nexit 1\n')
        # $SHELL still names bash until the next login; no prompt, no chsh.
        output = self.run_shell('SHELL=/bin/bash; NON_INTERACTIVE=true; setup_shell')
        self.assertIn('already the default shell', output)
        self.assertEqual(self.calls(), [])
        # A failing account lookup falls back to $SHELL instead of aborting.
        self.executable('getent', '#!/bin/bash\nexit 2\n')
        self.assertIn('already the default shell', self.run_shell('SHELL=/usr/bin/zsh; set -e; setup_shell'))
        self.assertIn('chsh -s', self.run_shell('SHELL=/bin/bash; NON_INTERACTIVE=true; set -e; setup_shell || [[ $? == 3 ]]'))

    @unittest.skipUnless(shutil.which('zsh') and shutil.which('fzf'),
                         'zsh and fzf are required for branch selection checks')
    def test_gswf_single_match_does_not_require_picker_input(self):
        self.run_shell('deploy_custom_functions')
        (self.bin / 'fzf').symlink_to(shutil.which('fzf'))
        self.env.update(GIT_CONFIG_GLOBAL='/dev/null', GIT_CONFIG_NOSYSTEM='1',
                        FZF_DEFAULT_OPTS='', FZF_DEFAULT_OPTS_FILE='', TERM='xterm-256color')
        self.run_shell('''cd "$HOME"
git init -q -b main
git -c user.name=Test -c user.email=test@example.invalid -c core.hooksPath=/dev/null commit -qm Initial --allow-empty
git branch feature/ISSUE-123
git branch feature/issue-456
''')
        # grep's case-insensitive prefilter sees two branches for ISSUE, while
        # fzf's smart-case query shows only one. Neither query should need Enter.
        for query in ('ISSUE-123', 'ISSUE'):
            with self.subTest(query=query):
                self.run_shell('git -C "$HOME" switch -q main')
                pid, master = pty.fork()
                if pid == 0:
                    os.chdir(self.home)
                    os.execve(shutil.which('zsh'), ['zsh', '-f', '-c',
                              'source "$HOME/.zsh/gswf.zsh"; gswf "$1"',
                              'zsh', query], self.env)
                output = b''
                status = None
                deadline = time.monotonic() + 5
                try:
                    while time.monotonic() < deadline:
                        if select.select([master], [], [], 0.1)[0]:
                            try:
                                output += os.read(master, 65536)
                            except OSError:
                                pass  # PTY closes just before the child exits.
                        result, child_status = os.waitpid(pid, os.WNOHANG)
                        if result:
                            status = child_status
                            pid = 0
                            break
                    self.assertIsNotNone(status, 'gswf waited for picker input')
                    self.assertEqual(os.waitstatus_to_exitcode(status), 0, output.decode())
                    self.assertNotIn(b'\x1b[?1049h', output, 'fzf opened the interactive screen')
                    branch = self.run_shell('git -C "$HOME" branch --show-current')
                    self.assertEqual(branch.strip(), 'feature/ISSUE-123')
                finally:
                    if pid:
                        try:
                            os.killpg(pid, signal.SIGKILL)
                        except ProcessLookupError:
                            pass
                        os.waitpid(pid, 0)
                    os.close(master)

    @unittest.skipUnless(shutil.which('zsh'), 'zsh is required for updater checks')
    def test_managed_updates_use_git_plugins_and_report_fetch_failures(self):
        self.run_shell('deploy_zshrc')
        for name in ('.zshrc', '.zsh/zinit-update.zsh'):
            result = subprocess.run(['zsh', '-n', str(self.home / name)], text=True, capture_output=True)
            self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn('zinit snippet', (self.home / '.zshrc').read_text())
        self.executable('git', r'''#!/bin/bash
echo "git $*" >> "$CALLS"
[[ "$2" != */ohmyzsh---ohmyzsh ]]
''')
        result = subprocess.run(['zsh', '-f', '-c', '''
typeset -A ZINIT
ZINIT[PLUGINS_DIR]="$HOME/plugins"
source "$HOME/.zsh/zinit-update.zsh"
zinit() { print -r -- "zinit $*" >> "$CALLS"; }
shell_backup_update_zinit
'''], env=self.env, text=True, capture_output=True, timeout=10)
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        calls = self.calls()
        self.assertIn(f'git -C {self.home}/plugins/ohmyzsh---ohmyzsh fetch --quiet origin', calls)
        self.assertNotIn('zinit update -q ohmyzsh/ohmyzsh', calls)
        self.assertIn('zinit update -q zsh-users/zsh-autosuggestions', calls)
        self.assertIn('zinit update -q MichaelAquilina/zsh-you-should-use', calls)
        # A checkout already at its upstream needs no `zinit update`.
        self.executable('git', '#!/bin/bash\necho "git $*" >> "$CALLS"\n[[ "$3" != rev-parse ]] || echo 0123abc\n')
        (self.home / 'calls').unlink()
        result = subprocess.run(['zsh', '-f', '-c', '''
typeset -A ZINIT
ZINIT[PLUGINS_DIR]="$HOME/plugins"
source "$HOME/.zsh/zinit-update.zsh"
zinit() { print -r -- "zinit $*" >> "$CALLS"; }
shell_backup_update_zinit
'''], env=self.env, text=True, capture_output=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual([call for call in self.calls() if call.startswith('zinit')], ['zinit self-update -q'])

    @unittest.skipUnless(shutil.which('zsh'), 'zsh is required to read the plugin list')
    def test_zinit_assets_follow_managed_plugin_list(self):
        output = self.run_shell('deploy_zinit_updater; zinit_expected_assets')
        self.assertIn(f'zinit plugin ohmyzsh|{self.home}/.local/share/zinit/plugins/ohmyzsh---ohmyzsh', output)
        self.assertIn(f'zinit plugin zsh-completions|{self.home}/.local/share/zinit/plugins/zsh-users---zsh-completions', output)
        self.assertEqual(len(output.splitlines()), 8)
        self.assertNotIn('snippets', output)
        self.run_shell('rm "$HOME/.zsh/zinit-update.zsh"; ! verify_zinit_assets')

    HOTKEY = """    %s =     {
        enabled = %d;
        value =         {
            parameters =             (
                32,
                49,
                %d
            );
            type = standard;
        };
    };
"""

    def hotkeys_text(self, enabled, with_60=True):
        # The text `defaults read` prints; 61 is Ctrl+Alt+Space, left enabled.
        entries = self.HOTKEY % ('61', 1, 786432)
        if with_60:
            entries = self.HOTKEY % ('60', 1 if enabled else 0, 262144) + entries
        return '{\n' + entries + '}\n'

    def hotkeys(self, enabled):
        (self.home / 'hotkeys.txt').write_text(self.hotkeys_text(enabled))

    def ctrl_space(self, answers):
        self.executable('defaults', '#!/bin/bash\ncat "$HOME/hotkeys.txt"\n')
        (self.home / 'hotkeys-free.txt').write_text(self.hotkeys_text(False))
        # Opening Settings stands in for the user unchecking the shortcut.
        self.executable('open', '#!/bin/bash\necho "open $1" >> "$CALLS"\ncp "$HOME/hotkeys-free.txt" "$HOME/hotkeys.txt"\n')
        (self.home / 'answers').write_text(''.join(a + '\n' for a in answers))
        return self.run_shell(r'''OS_TYPE=darwin
can_prompt() { return 0; }
read_tty() { IFS= read -r line <&3 || exit 1; printf '%s\n' "$line"; }
exec 3< "$HOME/answers"
free_macos_ctrl_space
''')

    def test_macos_ctrl_space_opens_settings_on_yes(self):
        for answer in ('y', 'Y'):
            self.hotkeys(True)
            # An invalid answer asks again; Enter after the change continues.
            output = self.ctrl_space(['maybe', answer, ''])
            self.assertIn('Ctrl+Space for Herdr: verified', output)
        self.assertEqual(self.calls(), ['open x-apple.systempreferences:com.apple.Keyboard-Settings.extension'] * 2)

    def test_macos_ctrl_space_kept_on_no_or_eof(self):
        for answers in (['n'], ['N'], []):
            self.hotkeys(True)
            output = self.ctrl_space(answers)
            self.assertIn('kept bound by macOS at your choice', output)
        self.assertEqual(self.calls(), [])

    def test_macos_ctrl_space_free_or_noninteractive(self):
        self.hotkeys(False)
        output = self.ctrl_space([])
        self.assertNotIn('Ctrl+Space', output)
        # An absent entry is the enabled macOS default, and so is an unreadable
        # hotkey list; CI only warns.
        (self.home / 'hotkeys.txt').write_text(self.hotkeys_text(False, with_60=False))
        output = self.run_shell('OS_TYPE=darwin; NON_INTERACTIVE=true\nread_tty() { exit 98; }\nfree_macos_ctrl_space')
        self.assertIn('Ctrl+Space for Herdr: skipped — still bound by macOS', output)
        self.executable('defaults', '#!/bin/bash\nexit 1\n')
        output = self.run_shell('OS_TYPE=darwin; NON_INTERACTIVE=true\nread_tty() { exit 98; }\nfree_macos_ctrl_space')
        self.assertIn('Ctrl+Space for Herdr: skipped — still bound by macOS', output)
        self.assertEqual(self.calls(), [])

    def test_macos_ghostty_from_cask_and_external_app(self):
        fake_app = r"""fake_app() {
    mkdir -p "$HOME/Applications/Ghostty.app/Contents/MacOS"
    printf '#!/bin/bash\necho "Ghostty %s"\n' "$1" > "$HOME/Applications/Ghostty.app/Contents/MacOS/ghostty"
    chmod +x "$HOME/Applications/Ghostty.app/Contents/MacOS/ghostty"
}
OS_TYPE=darwin
"""
        self.run_shell(fake_app + """brew() {
    echo "brew $*" >> "$CALLS"
    [[ "$1" == install ]] || return 1
    fake_app 1.3.1
}
install_ghostty
install_ghostty
""")
        # The second run keeps the cask's Ghostty without calling Homebrew.
        self.assertEqual(self.calls(), ['brew list --cask ghostty', 'brew install --cask ghostty'])
        output = self.run_shell(fake_app + """fake_app 1.2.0
brew() { [[ "$1" == list ]] && return 1; exit 98; }
! install_ghostty
""")
        self.assertIn('Ghostty outside Homebrew is below target', output)

    def test_macos_old_os_blocks_native_terminal(self):
        output = self.run_shell("""OS_TYPE=darwin
sw_vers() { echo 13.7; }
brew() { exit 98; }
! install_cmux
""")
        self.assertIn('requires macOS 14+', output)

    def test_main_profiles_and_failed_summary(self):
        for platform, flags, cmux in [('linux', '', 'skipped — macOS only'),
                                      ('darwin', '', 'skipped — optional extra'),
                                      ('darwin', ' --with-cmux', 'verified')]:
            output = self.run_shell(f"""detect_platform() {{ OS_TYPE={platform}; ARCH=arm64; PKG_MANAGER=apt; }}
check_prerequisites() {{ :; }}
setup_package_manager() {{ :; }}
version_inventory() {{ echo 'fixture: 1.0 -> 2.0'; }}
run_stage() {{ record_result "$1" verified; }}
setup_herdr() {{ record_result Herdr skipped 'fixture'; }}
find_cmux() {{ return 1; }}
main --ci{flags}
""")
            self.assertIn('Ghostty: verified', output)
            self.assertIn('cmux: ' + cmux, output)
        output = self.run_shell("""record_result Ghostty failed 'fixture'
print_summary
[[ "$SETUP_FAILED" == true ]]
""")
        self.assertIn('finished with failures', output)
        self.assertNotIn('SETUP COMPLETE', output)

    def test_font_flag_saved_profile_and_default(self):
        self.run_shell('parse_args --font=jetbrains; NON_INTERACTIVE=true; resolve_font_choice; [[ "$FONT_CHOICE" == jetbrains ]]')
        profile = self.home / '.config/shell-backup/profile'
        self.assertEqual(profile.read_text(), 'FONT=jetbrains\n')
        # Later --ci runs keep the saved choice; an explicit flag replaces it.
        self.run_shell('parse_args --ci; resolve_font_choice; [[ "$FONT_CHOICE" == jetbrains ]]')
        self.run_shell('parse_args --ci --font=iosevka; resolve_font_choice; [[ "$FONT_CHOICE" == iosevka ]]')
        self.assertEqual(profile.read_text(), 'FONT=iosevka\n')
        profile.unlink()
        self.run_shell('can_prompt() { return 0; }\nread_tty() { echo 2; }\nresolve_font_choice\n[[ "$FONT_CHOICE" == jetbrains ]]')
        profile.unlink()
        self.run_shell('NON_INTERACTIVE=true; resolve_font_choice; [[ "$FONT_CHOICE" == iosevka ]]')
        result = subprocess.run(['bash', '-c', self.base + 'parse_args --font=comic'], env=self.env,
                                text=True, capture_output=True, timeout=10)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Unknown font: comic', result.stdout + result.stderr)

    def test_terminal_config_uses_font_fallback_and_ssh_terminfo(self):
        config = self.home / '.config/ghostty/config'
        self.run_shell('deploy_ghostty_config')
        text = config.read_text()
        self.assertIn('font-family = Iosevka Term SS05\nfont-family = Symbols Nerd Font Mono\n', text)
        self.assertIn('font-feature = +calt', text)
        self.assertIn('shell-integration-features = ssh-terminfo,ssh-env', text)
        self.run_shell('FONT_CHOICE=jetbrains; deploy_ghostty_config')
        self.assertIn('font-family = JetBrainsMono Nerd Font\n', config.read_text())

    def font_fixture(self, names):
        archive = self.home / 'fonts.zip'
        with zipfile.ZipFile(archive, 'w') as bundle:
            for name in names:
                bundle.writestr('nested/' + name, 'font ' + name)
        return hashlib.sha256(archive.read_bytes()).hexdigest()

    def test_font_archive_checksum_marker_and_retention(self):
        digest = self.font_fixture(['A.ttf', 'B.ttf'])
        manifest = f"font_asset() {{ echo 'v1|https://example.invalid/fonts.zip|{digest}|A.ttf B.ttf'; }}\n"
        fetch = 'retry() { cp "$HOME/fonts.zip" "${@: -1}"; }\n'
        self.run_shell(manifest + fetch + 'install_font_archive fixture\nfont_installed fixture')
        installed = self.home / '.local/share/fonts/shell-backup/fixture'
        self.assertEqual(sorted(p.name for p in installed.iterdir()), ['A.ttf', 'B.ttf'])
        self.assertEqual((self.home / '.local/share/shell-backup/fonts/fixture.version').read_text(), f'v1 {digest}\n')
        # A matching marker keeps the font without downloading.
        output = self.run_shell(manifest + 'retry() { exit 98; }\ninstall_font_archive fixture')
        self.assertIn('retained (v1)', output)
        # A new pinned release with a bad download leaves installed files alone.
        bad = manifest.replace(digest, 'a' * 64).replace('v1|', 'v2|')
        self.run_shell(bad + fetch + '! install_font_archive fixture\n! font_installed fixture')
        self.assertEqual((installed / 'A.ttf').read_text(), 'font A.ttf')
        # An archive lacking a listed file fails before replacing anything.
        digest = self.font_fixture(['A.ttf'])
        partial = f"font_asset() {{ echo 'v3|https://example.invalid/fonts.zip|{digest}|A.ttf B.ttf'; }}\n"
        output = self.run_shell(partial + fetch + '! install_font_archive fixture')
        self.assertIn('B.ttf missing', output)
        self.assertEqual((installed / 'A.ttf').read_text(), 'font A.ttf')

    def test_font_manifest_coverage(self):
        self.run_shell(r'''for id in $FONT_IDS; do
 asset=$(font_asset "$id")
 [[ "$asset" =~ ^v[0-9.]+\|https://github.com/[^|]+\.(zip|tar\.xz)\|[0-9a-f]{64}\|[^|]+\.ttf$ ]]
done
! font_asset unknown
''')

    def test_fontconfig_fallback_generated_and_backed_up(self):
        self.run_shell('deploy_fontconfig; FONT_CHOICE=jetbrains; deploy_fontconfig')
        conf = self.home / '.config/fontconfig/conf.d/60-shell-backup.conf'
        root = ElementTree.fromstring(conf.read_text())
        aliases = {alias.findtext('family'): alias for alias in root.findall('alias')}
        prefer = [family.text for family in aliases['monospace'].find('prefer')]
        self.assertEqual(prefer, ['JetBrainsMono Nerd Font', 'Symbols Nerd Font Mono', 'Noto Sans Symbols2', 'Noto Color Emoji'])
        self.assertEqual(aliases['Iosevka Term SS05'].find('accept')[0].text, 'Symbols Nerd Font Mono')
        self.assertTrue(list((self.home / '.backup').glob('60-shell-backup.conf.backup.*')))

    def test_glyph_coverage_reports_missing_codepoints(self):
        self.executable('fc-list', '#!/bin/bash\n[[ "$1" == ":charset=f0349" ]] || echo Fixture\n')
        output = self.run_shell('report_glyph_coverage')
        self.assertIn('No installed font covers: U+f0349', output)
        self.executable('fc-list', '#!/bin/bash\necho Fixture\n')
        self.assertIn('cover the agent', self.run_shell('report_glyph_coverage'))

    def test_attach_helper_validates_session_and_execs_herdr(self):
        self.run_shell('deploy_attach_helper')
        helper = self.bin / 'shell-backup-attach'
        self.executable('herdr', '#!/bin/bash\nprintf "%s\\n" "$LANG" "$@"\n')
        env = dict(self.env, LC_ALL='xx_YY.UTF-8', LANG='C')
        result = subprocess.run([str(helper), 'work-2.dev'], env=env, text=True, capture_output=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stderr)
        lines = result.stdout.splitlines()
        self.assertEqual(lines[1:], ['session', 'attach', 'work-2.dev'])
        self.assertRegex(lines[0], r'(?i)^(en_US|C)\.UTF-8$')
        for session in ('--help', 'two words', '$(touch BAD)', 'x;exit'):
            with self.subTest(session=session):
                result = subprocess.run([str(helper), session], env=self.env, text=True, capture_output=True, timeout=10)
                self.assertEqual(result.returncode, 2)
                self.assertEqual(result.stdout, '')

    def test_zshrc_has_no_forced_locale_or_identity(self):
        self.run_shell('deploy_zshenv; deploy_zshrc')
        zshrc = (self.home / '.zshrc').read_text()
        self.assertNotIn('LC_ALL=', zshrc)
        self.assertNotIn('GIT_SSH_COMMAND', zshrc)
        self.assertIn('zinit light zsh-users/zsh-completions', zshrc)
        self.assertIn('compinit -C', zshrc)
        self.assertNotIn('$(npm root -g', (self.home / '.zshenv').read_text())

    @unittest.skipUnless(shutil.which('zsh'), 'zsh is required for the locale fallback')
    def test_zshenv_locale_fallback(self):
        self.run_shell('deploy_zshenv')
        def locale_in(**variables):
            env = {'HOME': str(self.home), 'PATH': '/usr/bin:/bin', **variables}
            result = subprocess.run(['zsh', '-c', 'print -r -- "${LC_ALL-unset}|${LANG-unset}"'],
                                    env=env, text=True, capture_output=True, timeout=10)
            self.assertEqual(result.returncode, 0, result.stderr)
            return result.stdout.strip()
        # SSH with a forwarded locale this host lacks: drop it, pick UTF-8.
        lc_all, lang = locale_in(SSH_CONNECTION='1 2 3 4', LC_ALL='xx_YY.UTF-8', LANG='C').split('|')
        self.assertEqual(lc_all, 'unset')
        self.assertRegex(lang, r'^(en_US|C)\.UTF-8$')
        # Scripts outside SSH keep an explicit LC_ALL=C.
        self.assertEqual(locale_in(LC_ALL='C'), 'C|unset')

    def test_release_manifest_coverage(self):
        self.run_shell(r'''for ARCH in amd64 arm64; do
 for tool in yazi starship pnpm fzf rg fd zoxide herdr nvim lazygit tree-sitter; do
  asset=$(release_asset "$tool" linux "$ARCH")
  [[ "$asset" =~ ^https://github.com/.+\|[0-9a-f]{64}$ ]]
 done
done
release_asset herdr darwin arm64 >/dev/null
! release_asset herdr darwin amd64
''')

    def test_lazygit_version_is_parsed_after_commit_hash(self):
        self.executable('lazygit', '#!/bin/bash\necho "commit=63ab89f, build date=2026-10-16, build source=binaryRelease, version=0.66.2, os=linux"\n')
        self.assertEqual(self.run_shell('tool_version lazygit'), '0.66.2\n')

    def nvim_archive(self, version):
        payload = self.home / 'payload/nvim-linux-x86_64/bin'
        payload.mkdir(parents=True, exist_ok=True)
        (payload / 'nvim').write_text(f'#!/bin/bash\necho "NVIM v{version}"\n')
        (payload / 'nvim').chmod(0o755)
        archive = self.home / 'nvim.tar.gz'
        with tarfile.open(archive, 'w:gz') as tar:
            tar.add(payload.parent, arcname='nvim-linux-x86_64')
        shutil.rmtree(self.home / 'payload')
        return hashlib.sha256(archive.read_bytes()).hexdigest()

    def test_neovim_tree_is_versioned_linked_and_retained(self):
        opt = self.home / '.local/opt'
        fetch = 'retry() { cp "$HOME/nvim.tar.gz" "${@: -1}"; }\n'
        # A tree that fails its version check is neither kept nor linked.
        digest = self.nvim_archive('0.1.0')
        self.run_shell(f"release_asset() {{ echo 'https://example.invalid/nvim.tar.gz|{digest}'; }}\n" + fetch + '! install_neovim')
        self.assertEqual(list(opt.iterdir()), [])
        self.assertFalse((self.bin / 'nvim').exists())
        digest = self.nvim_archive('0.12.6')
        manifest = f"release_asset() {{ echo 'https://example.invalid/nvim.tar.gz|{digest}'; }}\n"
        self.run_shell(manifest + fetch + 'install_neovim')
        self.assertEqual(os.readlink(opt / 'nvim'), str(opt / 'nvim-0.12.6'))
        self.assertEqual(os.readlink(self.bin / 'nvim'), str(opt / 'nvim/bin/nvim'))
        self.assertEqual(sorted(p.name for p in opt.iterdir()), ['nvim', 'nvim-0.12.6'])
        # Installed: retained without a download. Only unlinked: relinked without one.
        self.assertIn('nvim retained (0.12.6)', self.run_shell('retry() { exit 98; }\ninstall_neovim'))
        (self.bin / 'nvim').unlink()
        self.run_shell(manifest + 'retry() { exit 98; }\ninstall_neovim\n[[ "$(tool_version nvim)" == 0.12.6 ]]')
        # A manual unpack at ~/.local/opt/nvim and a real ~/.local/bin/nvim are
        # moved out of the way instead of being linked into or overwritten.
        (opt / 'nvim').unlink()
        (opt / 'nvim/bin').mkdir(parents=True)
        (opt / 'nvim/bin/nvim').write_text('#!/bin/bash\necho "NVIM v0.9.5"\n')
        (opt / 'nvim/bin/nvim').chmod(0o755)
        (self.bin / 'nvim').unlink()
        (self.bin / 'nvim').write_text('#!/bin/bash\necho "NVIM v0.9.5"\n')
        (self.bin / 'nvim').chmod(0o755)
        output = self.run_shell(manifest + 'retry() { exit 98; }\ninstall_neovim\n[[ "$(tool_version nvim)" == 0.12.6 ]]')
        self.assertIn('Moved the unmanaged', output)
        self.assertEqual(os.readlink(opt / 'nvim'), str(opt / 'nvim-0.12.6'))
        self.assertEqual(os.readlink(self.bin / 'nvim'), str(opt / 'nvim/bin/nvim'))
        backups = sorted(p.name for p in (self.home / '.backup').iterdir())
        self.assertEqual([b.split('.backup.')[0] for b in backups], ['nvim', 'nvim'])
        self.assertTrue(any((self.home / '.backup' / b / 'bin/nvim').exists() for b in backups))

    def test_vi_launcher_follows_nvim_config(self):
        self.executable('nvim', '#!/bin/bash\necho "$NVIM_APPNAME $*"\n')
        self.run_shell('deploy_neovim_launchers')
        vi = str(self.bin / 'vi')
        result = subprocess.run([vi, 'a', 'c'], env=self.env, text=True, capture_output=True)
        self.assertEqual(result.stdout, 'nvim-lazyvim a c\n')
        result = subprocess.run([vi], env=dict(self.env, NVIM_CONFIG='nvim-kickstart'), text=True, capture_output=True)
        self.assertEqual(result.stdout, 'nvim-kickstart \n')
        self.assertIn('source ~/.zsh/nvim.zsh', self.run_shell('deploy_zshrc; cat "$HOME/.zshrc"'))
        if shutil.which('zsh'):
            script = 'source "$HOME/.zsh/nvim.zsh"; print -r -- "$NVIM_CONFIG $EDITOR"; alias kv; eval "kv x"'
            result = subprocess.run(['zsh', '-f', '-c', script], env=dict(self.env, EDITOR='nano'),
                                    text=True, capture_output=True, timeout=10)
            self.assertEqual(result.stdout, "nvim-lazyvim nano\nkv='NVIM_CONFIG=nvim-kickstart vi'\nnvim-kickstart x\n",
                             result.stderr)
        # The managed tree wins over PATH, and a minimal PATH still finds it.
        managed = self.home / '.local/opt/nvim/bin'
        managed.mkdir(parents=True)
        (managed / 'nvim').write_text('#!/bin/bash\necho "managed $NVIM_APPNAME $*"\n')
        (managed / 'nvim').chmod(0o755)
        result = subprocess.run([vi, 'f'], env=dict(self.env, PATH='/usr/bin:/bin'), text=True, capture_output=True)
        self.assertEqual(result.stdout, 'managed nvim-lazyvim f\n')
        # Without any nvim the launcher says so and falls back to the system vi.
        shutil.rmtree(self.home / '.local/opt')
        (self.bin / 'nvim').unlink()
        result = subprocess.run([vi, '-es', '-c', 'q'], env=dict(self.env, PATH='/usr/bin:/bin'), text=True,
                                capture_output=True, input='', timeout=10)
        self.assertIn('vi: nvim not found', result.stderr)

    def test_yazi_edit_opener_uses_vi_launcher(self):
        import tomllib
        self.run_shell('deploy_yazi_config')
        config = tomllib.loads((self.home / '.config/yazi/yazi.toml').read_text())
        edit = config['opener']['edit']
        self.assertEqual(edit, [{'run': '"$HOME/.local/bin/vi" %s', 'block': True, 'desc': 'Neovim (vi)', 'for': 'unix'}])
        self.assertEqual([rule['use'] for rule in config['open']['prepend_rules']], [['edit', 'reveal']])
        self.assertNotIn('dev_open', config['opener'])
        # A GUI editor adds the directory opener in front of the code rule.
        self.executable('zed', '#!/bin/bash\nexit 0\n')
        self.run_shell('deploy_yazi_config')
        config = tomllib.loads((self.home / '.config/yazi/yazi.toml').read_text())
        self.assertEqual(config['open']['prepend_rules'][0], {'url': '*/', 'use': 'dev_open'})
        self.assertEqual(config['opener']['edit'], edit)

    def git_get(self, key):
        return self.run_shell(f'git config --global --get {key}').strip()

    def test_git_editor_skipped_without_a_target_neovim(self):
        gitconfig = self.home / '.gitconfig'
        gitconfig.write_text('[user]\n\tname = Someone\n')
        for nvim in (None, '#!/bin/bash\necho "NVIM v0.11.0"\n'):
            if nvim:
                self.executable('nvim', nvim)
            output = self.run_shell('run_stage "Git editor" configure_git_editor')
            self.assertIn('Git editor: skipped', output)
        self.assertEqual(gitconfig.read_text(), '[user]\n\tname = Someone\n')
        self.assertFalse((self.home / '.backup').exists())

    def test_git_editor_settings_converge_and_back_up_once(self):
        self.executable('nvim', '#!/bin/bash\necho "NVIM v0.12.6"\n')
        gitconfig = self.home / '.gitconfig'
        gitconfig.write_text('[user]\n\tname = Someone\n[merge]\n\ttool = meld\n')
        self.run_shell('configure_git_editor')
        self.assertEqual(self.git_get('merge.tool'), 'nvimdiff')
        self.assertEqual(self.git_get('mergetool.nvimdiff.path'), f'{self.home}/.local/bin/vi')
        self.assertEqual(self.git_get('core.editor'), f'{self.home}/.local/bin/vi')
        self.assertEqual(self.git_get('user.name'), 'Someone')
        self.assertIn(self.git_get('merge.conflictstyle'), ('zdiff3', 'diff3'))
        backups = list((self.home / '.backup').iterdir())
        self.assertEqual(len(backups), 1)
        self.assertIn('tool = meld', backups[0].read_text())
        mtime = gitconfig.stat().st_mtime_ns
        time.sleep(0.05)
        self.assertIn('already uses Neovim', self.run_shell('configure_git_editor'))
        self.assertEqual(gitconfig.stat().st_mtime_ns, mtime)
        self.assertEqual(len(list((self.home / '.backup').iterdir())), 1)
        # Git older than 2.35 cannot read zdiff3.
        self.executable('git', '#!/bin/bash\n[[ "$1" != --version ]] || { echo "git version 2.30.2"; exit; }\nexec /usr/bin/git "$@"\n')
        self.run_shell('configure_git_editor')
        self.assertEqual(self.git_get('merge.conflictstyle'), 'diff3')

    def test_git_editor_uses_xdg_config_when_it_is_the_only_one(self):
        self.executable('nvim', '#!/bin/bash\necho "NVIM v0.12.6"\n')
        xdg = self.home / '.config/git/config'
        xdg.parent.mkdir(parents=True)
        xdg.write_text('[user]\n\tname = Someone\n')
        self.run_shell('configure_git_editor')
        self.assertFalse((self.home / '.gitconfig').exists())
        self.assertIn('tool = nvimdiff', xdg.read_text())
        self.assertEqual(len(list((self.home / '.backup').iterdir())), 1)

    def starter_fixtures(self):
        """Upstream-like repos whose files are the pre-image of each managed patch."""
        git = ['git', '-c', 'user.name=Test', '-c', 'user.email=test@example.invalid', '-c', 'core.hooksPath=/dev/null',
               '-c', 'init.defaultBranch=main', '-c', 'commit.gpgsign=false']
        lines = []
        for name in ('nvim-lazyvim', 'nvim-kickstart'):
            patch = self.run_shell(f'neovim_starter_patch {name}')
            repo = self.home / 'fixtures' / name
            files, current = {}, None
            for line in patch.splitlines():
                if line.startswith('+++ b/'):
                    current = files.setdefault(line[6:], [])
                elif line.startswith('@@'):
                    current.append('-- unrelated upstream line')
                elif current is not None and not line.startswith(('---', '+', 'diff ')):
                    current.append(line[1:])
            files.setdefault('init.lua', ['-- fixture'])
            for path, content in files.items():
                (repo / path).parent.mkdir(parents=True, exist_ok=True)
                (repo / path).write_text('\n'.join(content) + '\n')
            subprocess.run(git + ['init', '-q', str(repo)], check=True)
            subprocess.run(git + ['-C', str(repo), 'add', '-A'], check=True)
            subprocess.run(git + ['-C', str(repo), 'commit', '-qm', 'upstream'], check=True)
            subprocess.run(git + ['-C', str(repo), 'commit', '-qm', 'newer upstream', '--allow-empty'], check=True)
            commit = subprocess.run(['git', '-C', str(repo), 'rev-parse', 'HEAD~1'], check=True, text=True,
                                    capture_output=True).stdout.strip()
            lines.append(f'{name}|{repo}|{commit}')
        return 'neovim_starters() { printf "%s\\n" ' + ' '.join(shlex.quote(line) for line in lines) + '; }\n'

    def config_state(self):
        return {path: value for path, value in self.home_state().items() if path.startswith('.config/')}

    def test_neovim_starters_cloned_at_commit_patched_and_converge(self):
        starters = self.starter_fixtures()
        output = self.run_shell(starters + 'setup_neovim_configs')
        self.assertIn('nvim-lazyvim managed edits applied', output)
        lazyvim, kickstart = self.home / '.config/nvim-lazyvim', self.home / '.config/nvim-kickstart'
        self.assertIn('lazyvim.plugins.extras.lang.python', (lazyvim / 'lua/config/lazy.lua').read_text())
        self.assertIn('vim.g.have_nerd_font = true', (kickstart / 'init.lua').read_text())
        self.assertIn("require 'custom.plugins'", (kickstart / 'init.lua').read_text())
        for path in ('lua/plugins/git.lua', 'lua/plugins/bash.lua', 'lua/plugins/learning.lua'):
            self.assertTrue((lazyvim / path).is_file(), path)
        for path in ('lua/custom/plugins/git.lua', 'lua/custom/plugins/learning.lua'):
            self.assertTrue((kickstart / path).is_file(), path)
        # Cloned at the pinned commit, not at the newer upstream HEAD, with no
        # temporary clone left behind and nothing to back up.
        self.assertEqual(self.run_shell('git -C "$HOME/.config/nvim-kickstart" log --format=%s'), 'upstream\n')
        self.assertEqual([p.name for p in (self.home / '.config').iterdir() if p.name.startswith('.')], [])
        self.assertFalse((self.home / '.backup').exists())
        state = self.config_state()
        time.sleep(0.05)
        self.assertIn('already present', self.run_shell(starters + 'setup_neovim_configs'))
        self.assertEqual(self.config_state(), state)
        # Local edits that conflict with the patch are kept and reported.
        init = kickstart / 'init.lua'
        init.write_text(init.read_text().replace('vim.g.have_nerd_font = true', 'vim.g.have_nerd_font = vim.env.NERD ~= nil'))
        edited = init.read_text()
        self.assertIn('left as is', self.run_shell(starters + 'setup_neovim_configs'))
        self.assertEqual(init.read_text(), edited)

    def test_neovim_starter_patch_ignores_outer_repository(self):
        starters = self.starter_fixtures()
        # A config without .git inside a dotfiles repository is patched in place.
        self.run_shell(starters + 'git clone -q "$(neovim_starters | head -1 | cut -d"|" -f2)" "$HOME/.config/nvim-lazyvim"\n'
                       'rm -rf "$HOME/.config/nvim-lazyvim/.git"\n'
                       'git init -q "$HOME/.config"\n'
                       'setup_neovim_configs\n')
        lazy = self.home / '.config/nvim-lazyvim/lua/config/lazy.lua'
        self.assertIn('lazyvim.plugins.extras.lang.python', lazy.read_text())
        # It existed before setup, so the file was backed up before patching.
        self.assertTrue(list((self.home / '.backup').glob('lazy.lua.backup.*')))

    def test_backups_with_the_same_basename_do_not_collide(self):
        for name in ('one', 'two'):
            (self.home / name).mkdir()
            (self.home / name / 'git.lua').write_text(name + '\n')
        self.run_shell('backup_file "$HOME/one/git.lua"; backup_file "$HOME/two/git.lua"')
        self.assertEqual(sorted(p.read_text() for p in (self.home / '.backup').iterdir()), ['one\n', 'two\n'])

    def test_pipe_with_controlling_terminal(self):
        self.pipe_prompt(b'2\n', 'jetbrains')

    def test_ctrl_c_cancels_without_consuming_pipe(self):
        self.pipe_prompt(b'\x03', 'iosevka')

    def test_eof_cancels_without_consuming_pipe(self):
        self.pipe_prompt(b'\x04', 'iosevka')

    def pipe_prompt(self, answer, expected):
        # stdin carries shell code, while the font question must read its
        # answer through /dev/tty. The trailing command must still be interpreted.
        pid, master = pty.fork()
        if pid == 0:
            code = self.base + 'resolve_font_choice\necho "CHOSEN=$FONT_CHOICE"\necho PIPE_CONTENT_SURVIVED\n'
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
                    if b'Choose 1-2' in output and not answered:
                        os.write(master, answer)
                        answered = True
                result, status = os.waitpid(pid, os.WNOHANG)
                if result:
                    pid = 0
                    break
            self.assertTrue(answered, output.decode())
            self.assertIn(b'PIPE_CONTENT_SURVIVED', output)
            self.assertIn(b'CHOSEN=' + expected.encode(), output)
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

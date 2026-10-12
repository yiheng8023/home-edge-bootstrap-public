#!/bin/sh
set -eu
repo=$(CDPATH= cd "$(dirname "$0")/.." && pwd -P)
tmp=$(mktemp -d "${TMPDIR:-/tmp}/home-edge-launcher-test.XXXXXX")
trap 'rm -rf "$tmp"' 0 HUP INT TERM
# macOS TMPDIR can use /var while the launcher records its physical /private/var
# location. Keep fixture expectations in the same physical directory namespace.
tmp_physical=$(CDPATH= cd "$tmp" && pwd -P) || exit 1
tmp=$tmp_physical
fail() { echo "launcher_fixture_tests=failed: $*" >&2; exit 1; }
project="$tmp/portable copy & 中文"
desktop="$tmp/fixture desktop"
installed="$tmp/registered entry % with spaces"
mkdir -p "$project/scripts/lib" "$desktop"
cp "$repo/PROJECT" "$project/"
echo fixture >"$project/README.md"
cp "$repo/start.sh" "$repo/start.command" "$project/"
cp "$repo/scripts/launch-tui.sh" "$repo/scripts/create-desktop-shortcut.sh" "$repo/scripts/tui.sh" "$project/scripts/"
cp "$repo/scripts/lib/project-location.sh" "$project/scripts/lib/"
cp "$repo/scripts/lib/host-launcher.sh" "$project/scripts/lib/"
for file in doctor.sh run-bootstrap.sh check-no-wall-readiness.sh export-support-bundle.sh decommission-merlin.sh; do
  printf '#!/bin/sh\necho forbidden-operation >&2; exit 99\n' >"$project/scripts/$file"
done
echo vfixture >"$project/VERSION"
(
  cd "$tmp"
  sh "$project/start.sh" --version >"$tmp/local-version"
  printf '0\n' | sh "$project/start.sh" --lang en --no-color >"$tmp/local-menu"
)
grep -Fq 'home-edge-bootstrap vfixture' "$tmp/local-version" || fail 'local entry depends on cwd'
grep -Fq '8. Create or refresh a local desktop launcher' "$tmp/local-menu" || fail 'menu omits local launcher setup'
case "$(uname -s)" in Linux|Darwin) ;; *) echo 'native_desktop_fixture=not_applicable_use_windows_fixture'; echo 'launcher_fixture_tests=ready'; exit 0 ;; esac
sh "$project/scripts/create-desktop-shortcut.sh" --directory "$desktop" --launcher-dir "$installed" >"$tmp/setup"
sh "$project/scripts/create-desktop-shortcut.sh" --directory "$desktop" --launcher-dir "$installed" </dev/null >"$tmp/reused"
grep -Fq 'shortcut_state=reused' "$tmp/reused" || fail 'same target was not reused'
cp "$installed/target.txt" "$tmp/original-target"
second_copy="$tmp/another project copy"
cp -R "$project" "$second_copy"
# A saved registration is not proof that the visible entry still targets it.
other_desktop="$tmp/other desktop"
other_launcher="$tmp/other registered entry"
mkdir "$other_desktop"
sh "$second_copy/scripts/create-desktop-shortcut.sh" --directory "$other_desktop" --launcher-dir "$other_launcher" >"$tmp/other-setup"
case "$(uname -s)" in
  Linux)
    cp "$desktop/home-edge-bootstrap.desktop" "$tmp/expected-desktop"
    cp "$other_desktop/home-edge-bootstrap.desktop" "$desktop/home-edge-bootstrap.desktop"
    cp "$desktop/home-edge-bootstrap.desktop" "$tmp/wrong-desktop"
    ;;
  Darwin)
    expected_link=$(readlink "$desktop/Home Edge Bootstrap.command")
    rm "$desktop/Home Edge Bootstrap.command"
    ln -s "$other_launcher/home-edge.command" "$desktop/Home Edge Bootstrap.command"
    ;;
esac
sh "$project/scripts/create-desktop-shortcut.sh" --directory "$desktop" --launcher-dir "$installed" </dev/null >"$tmp/wrong-entry-cancel"
grep -Fq 'shortcut_state=cancelled' "$tmp/wrong-entry-cancel" || fail 'wrong desktop target was reused without confirmation'
case "$(uname -s)" in
  Linux) cmp -s "$desktop/home-edge-bootstrap.desktop" "$tmp/wrong-desktop" || fail 'cancel changed desktop target' ;;
  Darwin) [ "$(readlink "$desktop/Home Edge Bootstrap.command")" = "$other_launcher/home-edge.command" ] || fail 'cancel changed desktop link' ;;
esac
printf 'REPLACE\nAPPLY\n' | sh "$project/scripts/create-desktop-shortcut.sh" --directory "$desktop" --launcher-dir "$installed" >"$tmp/wrong-entry-repaired"
case "$(uname -s)" in
  Linux) cmp -s "$desktop/home-edge-bootstrap.desktop" "$tmp/expected-desktop" || fail 'confirmed desktop repair has wrong target' ;;
  Darwin) [ "$(readlink "$desktop/Home Edge Bootstrap.command")" = "$expected_link" ] || fail 'confirmed desktop repair has wrong link' ;;
esac
for cancel_input in '' 'REPLACE' 'REPLACE
apply'; do
  printf '%s\n' "$cancel_input" | sh "$second_copy/scripts/create-desktop-shortcut.sh" --directory "$desktop" --launcher-dir "$installed" >"$tmp/retarget-cancel"
  grep -Fq 'shortcut_state=cancelled' "$tmp/retarget-cancel" || fail 'retarget did not cancel'
  cmp -s "$installed/target.txt" "$tmp/original-target" || fail 'retarget cancellation changed target'
done
printf 'REPLACE\nAPPLY\n' | sh "$second_copy/scripts/create-desktop-shortcut.sh" --directory "$desktop" --launcher-dir "$installed" >"$tmp/retargeted"
[ "$(sed -n '2p' "$installed/target.txt")" = "$second_copy" ] || fail 'confirmed retarget did not use chosen copy'
printf 'REPLACE\nAPPLY\n' | sh "$project/scripts/create-desktop-shortcut.sh" --directory "$desktop" --launcher-dir "$installed" >"$tmp/retarget-restored"
[ "$(sed -n '2p' "$installed/target.txt")" = "$project" ] || fail 'confirmed restore did not rebind original copy'
sh "$installed/launch-tui.sh" --version >"$tmp/registered-version"
grep -Fq 'home-edge-bootstrap vfixture' "$tmp/registered-version" || fail 'registered entry cannot launch'
[ ! -e "$installed/.home-edge-launcher.lock" ] || fail 'launcher kept lock after guide startup'
mkdir "$installed/.home-edge-launcher.lock"
printf 'home-edge-bootstrap/launcher-lock/v1\n%s\n' "$$" >"$installed/.home-edge-launcher.lock/owner"
if sh "$installed/launch-tui.sh" --version >"$tmp/busy-launcher" 2>&1; then fail 'registered launcher read through busy setup lock'; fi
grep -Fq 'registration is busy' "$tmp/busy-launcher" || fail 'busy launcher has no retry explanation'
if grep -Fq 'home-edge-bootstrap vfixture' "$tmp/busy-launcher"; then fail 'busy registration executed a project'; fi
rm "$installed/.home-edge-launcher.lock/owner"
rmdir "$installed/.home-edge-launcher.lock"
original_identity=$(sed -n '3p' "$installed/target.txt")
moved="$tmp/moved project"
mv "$project" "$moved"
cp -R "$moved" "$project"
if sh "$installed/launch-tui.sh" --version </dev/null >"$tmp/replaced" 2>&1; then fail 'other copy at old path silently executed'; fi
grep -Fq 'different directory instance' "$tmp/replaced" || fail 'directory-instance change was not detected'
printf '%s\n%s\n' "$tmp" "$moved" | sh "$installed/launch-tui.sh" --version >"$tmp/recovery" 2>&1
grep -Fq 'home-edge-bootstrap vfixture' "$tmp/recovery" || fail 'invalid selection and relocation cannot recover'
[ "$(sed -n '2p' "$installed/target.txt")" = "$moved" ] || fail 'new location not saved'
[ "$(sed -n '3p' "$installed/target.txt")" = "$original_identity" ] || fail 'same-instance rename lost identity'
echo unrelated-project >"$moved/PROJECT"
if sh "$installed/launch-tui.sh" --version </dev/null >"$tmp/wrong-project" 2>&1; then fail 'invalid identity executed'; fi
cp "$repo/PROJECT" "$moved/PROJECT"

foreign="$tmp/foreign-file"
echo user-content >"$foreign"
rm "$installed/target.txt"
ln -s "$foreign" "$installed/target.txt"
if sh "$moved/scripts/create-desktop-shortcut.sh" --directory "$desktop" --launcher-dir "$installed" >"$tmp/link-reject" 2>&1; then fail 'registration symlink accepted'; fi
[ "$(cat "$foreign")" = user-content ] || fail 'registration wrote through a symlink'
rm "$installed/target.txt"
sh "$moved/scripts/create-desktop-shortcut.sh" --directory "$desktop" --launcher-dir "$installed" --replace-registration --registration-confirmation APPLY >"$tmp/restored"
foreign_library="$tmp/foreign library"
mkdir "$foreign_library"
echo untouched >"$foreign_library/user-file"
mv "$installed/lib" "$installed/lib.saved"
ln -s "$foreign_library" "$installed/lib"
if sh "$moved/scripts/create-desktop-shortcut.sh" --directory "$desktop" --launcher-dir "$installed" >"$tmp/lib-link-reject" 2>&1; then fail 'registration library symlink accepted'; fi
[ "$(cat "$foreign_library/user-file")" = untouched ] || fail 'foreign library changed'
rm "$installed/lib"
mv "$installed/lib.saved" "$installed/lib"
(
  cd "$tmp"
  sh "$moved/scripts/create-desktop-shortcut.sh" --directory "$desktop" --launcher-dir relative-launcher >"$tmp/relative-install"
)
sh "$tmp/relative-launcher/launch-tui.sh" --version >"$tmp/relative-version"
grep -Fq 'home-edge-bootstrap vfixture' "$tmp/relative-version" || fail 'relative install destination depends on cwd'
if sh "$moved/scripts/create-desktop-shortcut.sh" --directory "$tmp/no-desktop" --launcher-dir "$tmp/no-desktop-install" >"$tmp/no-desktop" 2>&1; then fail 'missing desktop reported success'; fi
[ ! -e "$tmp/no-desktop-install" ] || fail 'missing desktop mutated registration'
if [ "$(uname -s)" = Linux ]; then
  mkdir "$tmp/failing-bin"
  printf '#!/bin/sh\nexit 1\n' >"$tmp/failing-bin/base64"
  chmod 700 "$tmp/failing-bin/base64"
  if PATH="$tmp/failing-bin:$PATH" sh "$moved/scripts/create-desktop-shortcut.sh" --directory "$desktop" --launcher-dir "$tmp/failing-install" >"$tmp/encoding-failure" 2>&1; then fail 'failed base64 reported success'; fi
  [ ! -e "$tmp/failing-install" ] || fail 'failed base64 mutated registration'
fi
interrupted="$tmp/interrupted setup"
mkdir -p "$interrupted/lib"
sh "$moved/scripts/create-desktop-shortcut.sh" --directory "$desktop" --launcher-dir "$interrupted" >"$tmp/empty-retry"

if [ "$(uname -s)" = Linux ]; then
  if command -v python3 >/dev/null 2>&1; then
    # A real PTY is needed: redirected stdin intentionally disables GUI pickers.
    python3 - "$tmp" "$moved" <<'PY'
import errno, os, pathlib, pty, select, subprocess, sys, time
base, project = map(pathlib.Path, sys.argv[1:])
fakebin = base / "picker-bin"
fakebin.mkdir()
zenity = fakebin / "zenity"
for status in (255, 1):
    zenity.write_text(f"#!/bin/sh\nexit {status}\n")
    zenity.chmod(0o700)
    master, slave = pty.openpty()
    env = dict(os.environ, DISPLAY=":fixture", PATH=str(fakebin) + ":" + os.environ["PATH"])
    proc = subprocess.Popen(["sh", str(project / "scripts/launch-tui.sh"), "--repo", str(base / "absent"), "--version"],
                            stdin=slave, stdout=slave, stderr=slave, env=env)
    os.close(slave)
    output = b""
    sent = False
    deadline = time.monotonic() + 15
    try:
        while time.monotonic() < deadline:
            if select.select([master], [], [], 0.1)[0]:
                try:
                    chunk = os.read(master, 65536)
                except OSError as error:
                    if error.errno == errno.EIO: break
                    raise
                if not chunk: break
                output += chunk
                if status == 255 and b"Folder chooser failed" in output and not sent:
                    os.write(master, (str(project) + "\n").encode())
                    sent = True
            if proc.poll() is not None:
                continue
        code = proc.wait(timeout=2)
        text = output.decode(errors="replace")
        if status == 255:
            assert sent and code == 0 and "home-edge-bootstrap vfixture" in text, text
            print(f"picker_observation=status:{status} exit:{code} text_fallback:{sent} version_resolved:{'home-edge-bootstrap vfixture' in text}")
        else:
            assert code == 2 and "Folder selection cancelled" in text and "home-edge-bootstrap vfixture" not in text, text
            print(f"picker_observation=status:{status} exit:{code} cancelled:{'Folder selection cancelled' in text} no_project_executed:{'home-edge-bootstrap vfixture' not in text}")
    finally:
        if proc.poll() is None: proc.kill(); proc.wait()
        os.close(master)
print("launcher_picker_pty_fixture=ready")
PY
  else echo launcher_picker_pty_fixture=unavailable_no_python3
  fi
  # Native GIO parses and executes a test-only Terminal=false copy; no GUI/TUI is launched.
  if /usr/bin/python3 -c 'import gi; gi.require_version("Gio", "2.0")' >/dev/null 2>&1; then
    cp "$desktop/home-edge-bootstrap.desktop" "$tmp/native.desktop"
    sed 's/^Terminal=true$/Terminal=false/' "$tmp/native.desktop" >"$tmp/native-run.desktop"
    printf '#!/bin/sh\nprintf native-exec-ok >"%s"\n' "$tmp/native-executed" >"$interrupted/launch-tui.sh"
    /usr/bin/python3 - "$tmp/native-run.desktop" "$tmp/native-executed" <<'PY'
import pathlib, sys, time, gi
gi.require_version("Gio", "2.0")
from gi.repository import Gio
entry = Gio.DesktopAppInfo.new_from_filename(sys.argv[1])
assert entry is not None, "native desktop parser rejected the file"
assert entry.launch([], None), "native desktop execution rejected"
for _ in range(100):
    if pathlib.Path(sys.argv[2]).exists(): break
    time.sleep(0.02)
assert pathlib.Path(sys.argv[2]).read_text() == "native-exec-ok", "Exec quoting failed"
PY
    echo native_desktop_exec=verified
  else echo native_desktop_exec=unavailable_no_gio_python
  fi
else
  sh "$desktop/Home Edge Bootstrap.command" --version >"$tmp/mac-desktop"
  grep -Fq 'home-edge-bootstrap vfixture' "$tmp/mac-desktop" || fail 'mac desktop symlink entry cannot resolve registered launcher'
fi
echo launcher_fixture_tests=ready

#!/bin/sh
set -eu
# Existing message assertions are English, independent of the test host locale.
HOME_EDGE_LANGUAGE=en
export HOME_EDGE_LANGUAGE
repo=$(CDPATH= cd "$(dirname "$0")/.." && pwd -P)
tmp=$(mktemp -d "${TMPDIR:-/tmp}/home-edge-launcher-test.XXXXXX")
trap 'rm -rf "$tmp"' 0 HUP INT TERM
# macOS TMPDIR can use /var while the launcher records its physical /private/var
# location. Keep fixture expectations in the same physical directory namespace.
tmp_physical=$(CDPATH= cd "$tmp" && pwd -P) || exit 1
tmp=$tmp_physical
fail() { echo "launcher_fixture_tests=failed: $*" >&2; exit 1; }
# Isolated damaged registrations must reject before locks, target repair or guide execution.
guarded="$tmp/missing-component-entry"
mkdir -p "$guarded/lib"
cp "$repo/scripts/launch-tui.sh" "$guarded/"
printf 'home-edge-bootstrap/registered-launcher/v1\n' >"$guarded/.home-edge-launcher-owned"
printf 'fixture-original-target\n' >"$guarded/target.txt"
for missing in project-location.sh ui-language.sh host-launcher.sh; do
  cp "$repo/scripts/lib/project-location.sh" "$repo/scripts/lib/ui-language.sh" "$repo/scripts/lib/host-launcher.sh" "$guarded/lib/"
  rm "$guarded/lib/$missing"
  find "$guarded" -print | sort >"$tmp/guarded-paths-before"
  find "$guarded" -type f -exec cksum {} \; | sort >"$tmp/guarded-bytes-before"
  if sh "$guarded/launch-tui.sh" --version </dev/null >"$tmp/missing-$missing" 2>&1; then fail 'damaged registration started'; else guard_status=$?; fi
  [ "$guard_status" = 2 ] || fail 'damaged registration lost exit 2'
  grep -Fq 'startup_state=failed' "$tmp/missing-$missing" || fail 'damaged registration omitted startup state'
  grep -Fq "missing_component=lib/$missing" "$tmp/missing-$missing" || fail 'damaged registration omitted exact component'
  grep -Fq '请恢复完整项目' "$tmp/missing-$missing" || fail 'damaged registration omitted Chinese repair hint'
  grep -Fq 'Restore the complete project' "$tmp/missing-$missing" || fail 'damaged registration omitted English repair hint'
  if grep -Fq 'project_location_state=' "$tmp/missing-$missing"; then fail 'damaged registration reached project execution or selection'; fi
  find "$guarded" -print | sort >"$tmp/guarded-paths-after"
  find "$guarded" -type f -exec cksum {} \; | sort >"$tmp/guarded-bytes-after"
  cmp -s "$tmp/guarded-paths-before" "$tmp/guarded-paths-after" && cmp -s "$tmp/guarded-bytes-before" "$tmp/guarded-bytes-after" || fail 'damaged registration wrote files'
done
missing_dispatch="$tmp/missing-component-dispatch"
mkdir -p "$missing_dispatch/adapters/fixture"
cp "$repo/bootstrap.sh" "$missing_dispatch/"
printf '#!/bin/sh\nprintf adapter-must-not-run >"%s"\n' "$missing_dispatch/executed" >"$missing_dispatch/adapters/fixture/bootstrap.sh"
if BOOTSTRAP_ADAPTER=fixture sh "$missing_dispatch/bootstrap.sh" --lang en </dev/null >"$tmp/missing-dispatch" 2>&1; then fail 'bootstrap without language helper executed'; else guard_status=$?; fi
[ "$guard_status" = 2 ] || fail 'bootstrap missing component lost exit 2'
grep -Fq 'startup_state=failed' "$tmp/missing-dispatch" && grep -Fq 'missing_component=scripts/lib/ui-language.sh' "$tmp/missing-dispatch" || fail 'bootstrap omitted exact missing component'
grep -Fq '请恢复完整项目' "$tmp/missing-dispatch" && grep -Fq 'Restore the complete project' "$tmp/missing-dispatch" || fail 'bootstrap omitted bilingual recovery'
[ ! -e "$missing_dispatch/executed" ] || fail 'bootstrap missing component executed adapter'
echo launcher_missing_component_fixtures=ready
if [ "${HOME_EDGE_LAUNCHER_FIXTURE_SCOPE:-}" = missing_components ]; then exit 0; fi
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
cp "$repo/scripts/lib/ui-language.sh" "$project/scripts/lib/"
for file in doctor.sh run-bootstrap.sh check-no-wall-readiness.sh export-support-bundle.sh decommission-merlin.sh; do
  printf '#!/bin/sh\necho forbidden-operation >&2; exit 99\n' >"$project/scripts/$file"
done
echo vfixture >"$project/VERSION"
. "$repo/scripts/lib/ui-language.sh"
[ "$(HOME_EDGE_LANGUAGE=zh-CN LANG=en_US.UTF-8 heb_detect_ui_language en)" = en ] || fail 'explicit language did not override environment'
[ "$(HOME_EDGE_LANGUAGE=en LC_ALL=zh_CN.UTF-8 heb_detect_ui_language '')" = en ] || fail 'language environment did not override locale'
[ "$(HOME_EDGE_LANGUAGE=invalid LC_ALL=zh_TW.UTF-8 heb_detect_ui_language '')" = zh-CN ] || fail 'Chinese locale was not selected'
[ "$(HOME_EDGE_LANGUAGE='' LC_ALL='' LC_MESSAGES=fr_FR.UTF-8 LANG=zh_CN.UTF-8 heb_detect_ui_language '')" = en ] || fail 'LC_MESSAGES priority was lost'
[ "$(HOME_EDGE_LANGUAGE='' LC_ALL='' LC_MESSAGES='' LANG='' heb_detect_ui_language '')" = zh-CN ] || fail 'empty locale did not default to Chinese'
if heb_detect_ui_language invalid >"$tmp/invalid-helper"; then fail 'invalid explicit language accepted'; fi
[ ! -s "$tmp/invalid-helper" ] || fail 'invalid explicit language emitted a valid-looking result'
HOME_EDGE_LANGUAGE=zh-CN sh "$project/start.sh" --lang en --help --router forbidden >"$tmp/en-help"
grep -Fq 'Language priority:' "$tmp/en-help" || fail 'explicit English help did not override environment'
HOME_EDGE_LANGUAGE=en sh "$project/start.sh" --lang zh-CN --help >"$tmp/zh-help"
grep -Fq '语言顺序：' "$tmp/zh-help" || fail 'explicit Chinese help did not override environment'
if sh "$project/scripts/launch-tui.sh" --repo "$tmp/absent" --lang invalid </dev/null >"$tmp/invalid-language" 2>&1; then fail 'invalid language accepted'; fi
if grep -Fq 'needs_selection' "$tmp/invalid-language"; then fail 'invalid language reached project selection'; fi
if HOME_EDGE_LANGUAGE=zh-CN sh "$project/scripts/launch-tui.sh" --repo "$tmp/absent" --version </dev/null >"$tmp/zh-selection" 2>&1; then fail 'EOF started an invalid project'; fi
grep -Fq '输入结束，启动已取消' "$tmp/zh-selection" || fail 'Chinese directory selection EOF is not localized'
# Test only a synthetic adapter: --lang must never reach device dispatch.
dispatch="$tmp/dispatch"
mkdir -p "$dispatch/scripts/lib" "$dispatch/adapters/fixture"
cp "$repo/bootstrap.sh" "$dispatch/"
cp "$repo/scripts/lib/ui-language.sh" "$dispatch/scripts/lib/"
printf '#!/bin/sh\nprintf "argument=%%s\\n" "$@"\n' >"$dispatch/adapters/fixture/bootstrap.sh"
BOOTSTRAP_ADAPTER=fixture sh "$dispatch/bootstrap.sh" --dry-run --lang en '--opaque value' >"$tmp/dispatch-result"
grep -Fq 'argument=--dry-run' "$tmp/dispatch-result" || fail 'bootstrap lost a device argument'
grep -Fq 'argument=--opaque value' "$tmp/dispatch-result" || fail 'bootstrap split an argument'
if grep -Fq 'argument=--lang' "$tmp/dispatch-result" || grep -Fq 'argument=en' "$tmp/dispatch-result"; then fail 'bootstrap leaked UI language to the adapter'; fi
if BOOTSTRAP_ADAPTER=auto sh "$dispatch/bootstrap.sh" --lang zh-CN >"$tmp/dispatch-refusal" 2>&1; then fail 'auto dispatch without a detection match succeeded'; fi
grep -Fq '自动探测未找到唯一候选' "$tmp/dispatch-refusal" || fail 'adapter refusal is not localized'
if BOOTSTRAP_ADAPTER=fixture sh "$dispatch/bootstrap.sh" --lang invalid >"$tmp/dispatch-invalid" 2>&1; then fail 'invalid bootstrap language accepted'; fi
if grep -Fq 'adapter_candidate=' "$tmp/dispatch-invalid"; then fail 'invalid bootstrap language reached dispatch'; fi
(
  cd "$tmp"
  sh "$project/start.sh" --version >"$tmp/local-version"
  printf '0\n' | sh "$project/start.sh" --lang en --no-color >"$tmp/local-menu"
)
grep -Fq 'home-edge-bootstrap vfixture' "$tmp/local-version" || fail 'local entry depends on cwd'
grep -Fq '8. Create or refresh a local desktop launcher' "$tmp/local-menu" || fail 'menu omits local launcher setup'
case "$(uname -s)" in Linux|Darwin) ;; *) echo 'native_desktop_fixture=not_applicable_use_windows_fixture'; echo 'launcher_fixture_tests=ready'; exit 0 ;; esac
sh "$project/scripts/create-desktop-shortcut.sh" --directory "$desktop" --launcher-dir "$installed" >"$tmp/setup"
[ -f "$installed/lib/ui-language.sh" ] || fail 'registered launcher omitted the language helper'
sh "$project/scripts/create-desktop-shortcut.sh" --directory "$desktop" --launcher-dir "$installed" </dev/null >"$tmp/reused"
grep -Fq 'shortcut_state=reused' "$tmp/reused" || fail 'same target was not reused'
# A cached registration needs explicit refresh even when its target is unchanged.
rm "$installed/lib/ui-language.sh"
sh "$project/scripts/create-desktop-shortcut.sh" --directory "$desktop" --launcher-dir "$installed" </dev/null >"$tmp/helper-upgrade-cancel"
grep -Fq 'shortcut_state=cancelled' "$tmp/helper-upgrade-cancel" || fail 'missing helper was reported reused or refreshed without permission'
[ ! -e "$installed/lib/ui-language.sh" ] || fail 'cancelled helper refresh wrote a file'
printf 'REPLACE\nAPPLY\n' | sh "$project/scripts/create-desktop-shortcut.sh" --directory "$desktop" --launcher-dir "$installed" >"$tmp/helper-upgrade"
cmp -s "$project/scripts/lib/ui-language.sh" "$installed/lib/ui-language.sh" || fail 'old registration did not recover a missing language helper'
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

# Launcher and recovery contract

The directory-local entry, registered entry and device workflow are distinct roles.
The initial guide is not a router deployment and does not acquire a proxy service.

## Responsibility and compatibility

| Role | Responsibility | Does not infer |
|---|---|---|
| Common project location | PROJECT identity, required entry files, explicit selection, cancellation and actual location reporting | Git presence, a fixed install path, firmware brand, code authenticity or a complete payload |
| Host adapter | Console startup, physical directory identity, registration storage, native folder picker and desktop integration | Administrator rights, a desktop session, permission to change global security settings |
| Device adapter | Read-only capability detection, plan/apply, device paths, runtime integration, backup and recovery | Support because a model name or one path looks familiar |

Common structural checks live in `scripts/lib/project-location.*`; physical filesystem identity
and registration-path rules live in `scripts/lib/host-launcher.*`. The local entry requires neither
`adapters/merlin` nor a Merlin-specific operation. Optional operations are checked when selected;
their absence reports unavailable capability without preventing the core menu.

`bootstrap.sh` dispatches trusted installed adapter entries using a bounded identifier. Device
candidate detection is supplied by each adapter's read-only `detect.sh`, not brand/path assumptions
in the common dispatcher. Zero or multiple matches require explicit selection. The current real
implementation remains Merlin; synthetic adapter fixtures verify dispatch isolation, not support for
other hardware. Existing deploy, rollback and self-heal workflows still contain reference-adapter
integration; this change does not claim complete separation of all existing device workflows.

## Menu, local help and language

The numbered, line-driven menu uses plain text without ANSI control sequences. It lists 1–9 in order:

| Choice | Action |
|---|---|
| 1 | Start or resume guided bootstrap |
| 2 | Run read-only diagnosis; a configured router may be contacted |
| 3 | View saved session state and next-action hints |
| 4 | Verify the offline runtime bundle |
| 5 | Export a redacted local support bundle |
| 6 / H / ? / help | Open the local help submenu |
| 7 | Open maintenance: refresh or decommission this project |
| 8 | Create or refresh the local desktop entry |
| 9 / L / language | Switch Chinese/English in place |
| 0 | Exit the guide |

Help choices are **1 Getting started, 2 Safety, 3 Recovery, 4 Actual documents,
5 Full help, 0 Back**. Maintenance choices are **1 Refresh this project,
2 Decommission this project, 0 Back**. `R` keeps its old direct route to the project refresh
plan. Command-line `--help` / `-Help` still prints full help without entering a menu.

In either submenu, `0` returns one level; EOF exits the whole guide. Empty input only redraws
the current menu. Invalid input reports that menu's available choices. After an action fails,
read its reason and recovery hint before choosing another action; navigation does not turn
that failure into success. Help, language and menu navigation do not contact the network,
open programs or write project content. The documents page lists only files actually present
in the running copy; a public projection does not acquire an omitted private RUNBOOK.

Every menu exposes the bilingual `Language / 语言` entry. `9` / `L` / `language` switches
immediately, keeps the current page, router and selected session, and writes no global language
setting. Initial language is selected in this order:

1. Explicit `--lang` / `-Language` (`zh-CN` or `en`); another explicit value is rejected.
2. Valid `HOME_EDGE_LANGUAGE` (`zh-CN` or `en`); an invalid environment hint is ignored.
3. On POSIX, `LC_ALL`, then `LC_MESSAGES`, then `LANG`; on Windows, `CurrentUICulture`.
   A Chinese locale beginning with `zh` selects Chinese; a known non-Chinese locale selects English.
4. If no language information is available, use `zh-CN`.

Human-facing startup, folder selection and launcher recovery prompts follow the selected
language. Machine protocol keys, commands and confirmation tokens keep their stable spelling.

## Guarded project refresh and decommission

Menu 1 reads fresh installation evidence for the selected router and path. It defaults to diagnosis and saved-session reuse for `installed` or `partial`. The six-field observation binds schema, router, state, reason, path and replacement permission; malformed, stale-session-only or mismatched evidence cannot authorize deployment. `installed` proves recognizable project-owned presence only, not complete lifecycle or network health. A standalone ShellCrash/Mihomo installation is independent. `not_installed` requires positive absence; unknown ownership, foreign contents or links stop the dependent write.

Maintenance **7 → 1**, or the old `R` shortcut, obtains a project-only deployment plan before requesting exact `REPLACE`, then exact `APPLY`. This refreshes owned project content; it is not an instruction to reinstall the runtime. The existing project tree is backed up to `<project-path>.prev`; an older backup may be replaced. The writer repeats ownership checks under its router write lock. `ProjectOnly` / `--project-only` disables runtime install/replacement, core replacement and persistent bundle copying; project-managed integration/configuration may still be updated. It does not provide a complete runtime rollback. Runtime-only replacement preserves the existing core unless `ReplaceCore` / `BOOTSTRAP_REPLACE_CORE=1` is independently explicit.

Maintenance **7 → 2** shows the project removal plan before requesting exact `DECOMMISSION`.
Entering a menu, viewing help or pressing Enter never authorizes a write. Deployment requires
exact `APPLY`; live self-heal requires exact `ENABLE`. At confirmation prompts, empty input,
EOF or any other token cancels the operation. Tokens are case-sensitive and accept no extra spaces.

The guide checks project structure and physical directory identity at startup and rechecks the project and required action tools before running an operation and around important work. Local menu navigation, help and language switching do not run these probes. A known failure blocks affected work with a reason and recovery route; `H`, `L` and `0` remain usable when these checks find degradation. There is no background watcher, and unknown faults are not all detected. These checks supplement device-state diagnosis rather than accepting a target.

## Conditions, decisions and recovery

| Observed condition | Guided response |
|---|---|
| No Git or unknown clone location | Download and extract a complete release; use the browser's Show in folder action |
| No access to releases on this device | Verify and transfer a complete package from another device; offline startup needs no download |
| Different cwd; spaces, Unicode or apostrophes | Resolve the entry's own location and preserve the original literal path |
| Registered project moved or deleted | Select its new directory using a native picker when available, otherwise a path prompt; validate again |
| Another directory occupies the saved path | Do not silently adopt it; require a new explicit selection |
| Multiple copies | Local entry uses its own copy; registered entry uses the explicitly selected copy; no disk scan or arbitrary guess |
| Invalid selection | Explain identity/structure failure and let the user choose again; EOF or cancellation executes nothing |
| Missing core entry files | Re-extract or update the complete source; do not substitute a different project silently |
| Optional operation absent | Keep local help/menu available; explain the missing capability when selected |
| No desktop or picker | Use the terminal entry and path prompt; do not assume GUI programs exist |
| Missing tool or insufficient write permission | Stop the affected desktop/setup action with a reason; retain the directory-local entry and retry after correction |
| Unexpected path type, symbolic/hard link, reparse or unrelated shortcut | Preserve the unrelated target; choose another empty storage directory or use the local entry |
| Registration setup or location repair already running | Close that instance and retry; use the project's local start entry meanwhile |
| Leftover or unknown POSIX registration lock | Inspect the reported lock and confirm the owner has ended before removing it; otherwise choose a new empty registration directory |
| Empty interrupted initial setup | Retry safely; an unowned nonempty directory is preserved |
| Owned incomplete setup or changed cached launcher | Review the target and type `REPLACE`, then `APPLY`, to refresh; preserve unowned content |
| Same target, matching cached launcher and correct desktop pointer | Report `shortcut_state=reused` and reuse the registration |
| Directory identity, structure or tools change during the guide | Block affected actions and restore the reported source/tool condition; retain help, language and exit |
| Unknown router installation, foreign content or links | Stop deployment and review target/ownership; do not classify it as first installation |
| Linux desktop requests trust | Follow its Allow Launching action after checking the source; the helper does not alter desktop trust |

Windows uses `.cmd` and PowerShell; macOS uses `.command`; Linux uses POSIX shell plus an optional
freedesktop desktop entry. Terminal associations and source-confirmation dialogs remain host
conditions. Initial acquisition and all desktop GUI behavior are not made universal by a file
extension. Help and directory-local startup remain useful when desktop integration is unavailable.
The Linux Exec format follows the [freedesktop desktop-entry specification](https://specifications.freedesktop.org/desktop-entry/latest/exec-variables.html).

## Independent registration

The registration directory contains a project-owned marker, copied launch code and a UTF-8 target
record. It stores the selected directory's filesystem identity alongside the path. Windows uses
volume/file ID and creation time; POSIX hosts use filesystem device/inode and birth time when
reported. This binds an ordinary filesystem instance, not a cryptographic source identity. Filesystem
identity may change after a cross-filesystem transfer; explicit selection rebinds the target.

Copied launch code includes `scripts/lib/ui-language.*`; that helper participates in the
cached-file version comparison. An old owned entry with changed or missing cached files still
requires exact `REPLACE` followed by `APPLY` to refresh. Use the current directory-local entry
while reviewing that update.

Defaults are `%LOCALAPPDATA%/HomeEdgeBootstrap/launcher` on Windows,
`~/Library/Application Support/HomeEdgeBootstrap/launcher` on macOS, and
`${XDG_DATA_HOME:-~/.local/share}/home-edge-bootstrap/launcher` on Linux. Registration does not edit
PATH or shell profiles. It does not store router credentials, subscription URLs or controller keys.

Shortcut creation is an explicit local write. A matching target, cached launcher and correct desktop pointer report
`shortcut_state=reused`. Another owned target, incomplete registration or cached-version update
requires `REPLACE` followed by `APPLY`; unowned contents are not overwritable. It checks the ownership marker, expected leaf types
and links before replacing project-owned files, and creates the desktop entry after copying the
launcher. A partial failure does not report readiness; re-run from the source entry. Target-location
repair uses a temporary record and rename. The multi-file installation is not claimed to be an
atomic crash/power-loss transaction; unrelated nonempty directories are never removed for recovery.

Setup and registered-location checks share `.home-edge-launcher.lock`. Windows uses an exclusive
file handle released by the OS after process exit. POSIX uses an owned directory lock; unknown or
leftover locks are retained. The lock is released before starting the guide. Each installed file
is published with a same-directory temporary file and rename; concurrent writers cannot mix copies.

For a POSIX leftover lock, inspect `cat "<reported-lock-directory>/owner"` and the recorded PID with
`ps -p <pid>`. After independently confirming that the owning setup/launcher process has ended,
remove only its owned record with `rm "<reported-lock-directory>/owner"`, then the empty directory
with `rmdir "<reported-lock-directory>"`. Do not remove unknown contents or a live owner's lock.
When ownership is unclear, use `sh "<project-folder>/start.sh"` or a new empty registration directory.

For custom storage, advanced users can use `-DestinationDirectory` / `-LauncherDirectory` on the
PowerShell helper, or `--directory` / `--launcher-dir` on the POSIX helper. The ordinary menu avoids
these parameters. Deleting the desktop icon removes that convenience entry; it does not remove
the cloned project, router installation or retained operator state.

## Evidence boundaries

Release ZIP and tar archives store `.sh` and `.command` entries with Unix 0755 metadata,
including when built on Windows. Source launcher entries also carry Git executable modes.
These permissions do not prove native desktop associations or trust dialogs have been accepted.

Fixtures cover unrelated cwd, literal paths, structural identity, directory replacement/relocation,
invalid selection, optional-operation absence, shortcut collision, links and interrupted setup.
Linux GIO executes a test-only Terminal=false entry to independently validate Exec parsing; this is
not an acceptance test of every desktop's terminal selection or trust UI. Native host CI and archive
checks supplement fixtures. Existing source, supply-chain, real-device and compatibility claim limits
remain in force.

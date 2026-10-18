---
title: "simba — SMB shares navigator"
author: Teo Espero
date: "Documentation: 18 October 2026 · Script: 3.0.1"
lang: en
---

# About simba

**simba** is a Bash terminal application for discovering Windows domain hints, browsing SMB file shares, and connecting saved network drives from Ubuntu or Debian. Its blue, dual-pane interface takes inspiration from Norton Commander. It uses letter shortcuts, status messages, progress indicators, and keyboard-operated overlay dialogs.

**Author:** Teo Espero. **Script version:** 3.0.1. **Script created and last updated:** 17 October 2026. This guide describes the current script and the offline tests performed during development.

## Contents

- [Capabilities](#capabilities)
- [Requirements and setup](#requirements-and-setup)
- [Startup and discovery](#startup-and-discovery)
- [Interface and controls](#interface-and-controls)
- [Connecting a shared drive](#connecting-a-shared-drive)
- [Code walkthrough](#code-walkthrough)
- [Credentials and saved data](#credentials-and-saved-data)
- [Troubleshooting](#troubleshooting)
- [Simulated domain and share testing](#simulated-domain-and-share-testing)
- [Revision history](#revision-history)

# Capabilities

| Feature | Current behavior |
|:--|:--|
| Domain discovery | Uses DNS suffix hints and saved profiles to look for advertised Active Directory domain controllers. Supports manual DNS domain entry. |
| Share browsing | Authenticates to a specified file server and lists returned disk shares, including names containing spaces. |
| Saved drives | Adds, edits, and removes profiles; connects and disconnects SMB mounts. |
| Terminal interface | Saved drives on the left, discovered shares on the right, persistent menu, status line, and task bar. |
| Dependency setup | Offers to install missing packages on supported apt-based systems. |
| Startup prefetch | Loads profiles, mount state, and DNS discovery results before opening the interface. |

Domain discovery does not enumerate every file server or every storage location in a domain. Browsing shares requires a known server hostname or IPv4 address. Results depend on the server and the permissions of the supplied account.

simba accesses shares; it does not join Active Directory, configure a VPN, alter `/etc/fstab`, or automatically reconnect drives at login.

# Requirements and setup

- Ubuntu or Debian with Bash 4.4 or newer.
- A terminal at least **100 columns × 24 rows**, with a font that supports box-drawing characters.
- Network access to the file server and working name resolution. Office resources may require an office LAN connection or a VPN with internal DNS.
- A Windows account permitted to access the requested share, and a server supporting the required SMB3 encryption.
- Local sudo access for installing dependencies and mounting or unmounting drives.

Run the script as your normal Linux user:

```bash
# ------------------------------------
# Start simba; sudo is requested only when needed.
# ------------------------------------
bash simba.sh
```

Alternatively, make it executable once and run it directly:

```bash
chmod +x simba.sh
./simba.sh
```

The dependency check maps missing commands to packages, removes duplicate package names, and asks before running `sudo apt-get`. Declining exits. A failed package-list refresh or installation stops setup; required commands are checked again after installation. Do not run the entire script with sudo or enable shell tracing around password handling.

| Package | Purpose |
|:--|:--|
| `cifs-utils` | CIFS/SMB mounting helper |
| `smbclient` | Authenticated share enumeration |
| `dnsutils` | DNS SRV lookups using `dig` |
| `dialog` | Bootstrap dialogs; runtime popups use Bash |
| `sudo` | Privileged local operations |
| `util-linux`, `mount` | Mount inspection, instance locking, mounting and unmounting |
| `coreutils`, `findutils`, `gawk` | File handling and text processing |
| `xdg-utils` | Opening mounted folders in a desktop file manager |

On systems without apt, missing dependencies must be installed manually. Desktop folder opening also needs a usable graphical session.

# Startup and discovery

1. Check dependencies and create a private session directory.
2. Acquire a single-instance lock.
3. Display progress in the ordinary terminal while loading valid profiles, inspecting local mounts, and collecting domain hints.
4. Query candidate domains for `_ldap._tcp.dc._msdcs.<domain>.` SRV records.
5. Cache the results, clear the terminal, and open the full-screen interface.

Startup does not ask for Windows credentials or open SMB sessions. Discovery examines a bounded set of DNS suffix candidates rather than scanning the subnet. Advertised controller records are discovery hints, not authenticated proof of domain identity. Empty results can mean missing internal DNS, no usable hints, no domain on the network, or an unavailable network.

Press **G** to view cached domain results, enter a full DNS domain manually, or rescan after changing networks. Selecting a domain helps fill later forms; it does not join the computer to that domain.

## What happens on ordinary WiFi?

The interface still loads on home or guest WiFi. Local profiles remain available, but office resources need a route to the office network, usually through a VPN. A local Windows computer can also share folders without a domain: supply that computer's address and use its computer name as the account domain when using a local Windows account. The server must still meet simba's SMB3 encryption requirements.

# Interface and controls

The **left panel** holds saved drive profiles; the **right panel** holds the most recently browsed server's shares. Tab changes the active panel. The cyan selection marks the current item. Share results retain their own server, domain, and username so changing the selected saved drive does not silently change their connection context.

The top menu stays visible behind native Bash popup overlays. The bottom status line explains the current action or result; the task bar displays progress. Countable work uses a measured percentage. Network operations with unknown duration use animation, because their completion percentage cannot be measured reliably.

| Key | Action |
|:--|:--|
| `Tab` | Switch panels |
| `↑` / `↓`, or `k` / `j` | Select an item |
| `Home` / `End` | First or last item |
| `Page Up` / `Page Down` | Scroll through list pages |
| `Enter` | Connect/open a saved drive, or save a selected share as a profile |
| `H` | Open scrollable Help |
| `G` | Discover or select domains |
| `B` | Browse shares on a specified server |
| `A` | Add a drive manually |
| `E` | Edit a saved profile |
| `C` | Connect; from a share, save the profile and then connect |
| `D` | Disconnect the selected saved drive |
| `X` | Remove the selected saved profile |
| `O` | Open the mounted drive in a file manager |
| `R` | Refresh the active list; saved-drive refresh also updates mount state |
| `Q` | Quit |

Editing, removing, and disconnecting operate on the saved-drive panel. Function keys are not required. In forms, Tab moves between fields and buttons, Enter accepts, and Escape cancels. Ctrl+U clears a field. Password input is fully hidden. Help supports scrolling and paging.

Quitting restores terminal settings, resets colors, clears the screen, and prints **“Goodbye! Thanks for using simba.”** Existing mounts remain connected; use **D** before quitting if you want to disconnect them.

# Connecting a shared drive

1. Connect to the appropriate LAN or VPN, if required.
2. Press **G** to select a discovered domain, or enter the account domain when prompted later.
3. Press **B** and enter a file server such as `fs01.corp.example.test`, the domain, and your Windows username.
4. Enter the Windows password in the hidden prompt.
5. Select a returned disk share, such as `Engineering Shared`.
6. Press **Enter** to review and save a profile, or **C** to save and connect.
7. Supply the local sudo password if requested and the Windows password for the connection.
8. Press **O** to open the mounted folder. Close open files before using **D** to disconnect.

The example names above are fictional test data. A successful browse does not guarantee a successful mount: the account, server encryption support, share permissions, or local mount conditions may differ.

The mount folder is `~/NetworkDrives/<folder-ID>`. The default dialect is SMB 3.1.1; SMB 3.0 is also selectable. The connection requires encryption and uses password-based NTLMSSP authentication. The script does not reuse a Kerberos ticket cache.

# Code walkthrough

## Section comments and private defaults

The script uses dashed separators around sections and comments explaining the more complex behavior. These startup settings disable tracing, detect unset variables and pipeline failures, and restrict newly created files:

```bash
# ------------------------------------
# Shell settings and application state
# ------------------------------------
set +x
set -uo pipefail
umask 077
```

## Keeping progress out of command results

The following excerpt is from `run_with_progress`. The worker writes stdout and stderr to separate files while the parent updates the terminal. This prevents progress characters from corrupting parsed DNS and SMB output. Only the worker loses stdin; the parent retains its terminal input descriptor.

```bash
"$@" </dev/null >"$output" 2>"$errors" &
TASK_PID=$!
while kill -0 "$TASK_PID" 2>/dev/null; do
    ((TASK_TICK+=1)); progress_draw
    sleep 0.12
done
if wait "$TASK_PID"; then rc=0; else rc=$?; fi
TASK_PID=''
return "$rc"
```

The final `wait` preserves the command's actual exit status. Completed, failed, and cancelled tasks can therefore produce different status messages instead of all appearing successful.

## Prefetch before opening the interface

This excerpt shows the startup work order:

```bash
task_invoke 'Loading profiles' load_profiles
refresh_mount_cache
refresh_domain_cache
```

During prefetch, progress is drawn in the ordinary terminal. After it finishes, the script clears that screen and opens the full interface. Drawing the interface uses cached mount data for responsiveness; connect, disconnect, and refresh update it.

## Authenticated share enumeration

Share browsing invokes `smbclient` with a temporary credentials file and requires encrypted SMB3. It filters the machine-readable output to disk shares, preserves spaces in names, removes duplicates, and excludes IPC and printer entries. Returned hidden shares ending in `$` are labelled; the server may not reveal every hidden share to the account.

## Mount protection

Mount options include the user's Linux UID/GID, a selected SMB3 dialect, `seal`, `sec=ntlmssp`, `nosuid`, `nodev`, file mode `0600`, and directory mode `0700`. Windows permissions still determine remote access.

Before mounting, simba rejects a symlink or a nonempty mount directory. Before unmounting, it verifies that the mounted filesystem and source match the selected profile. A busy mount reports an error; the script does not force or lazily detach it.

## Preserving the menu

Runtime dialogs are drawn as overlays inside the existing terminal buffer. They do not clear the entire screen or switch alternate-screen buffers while open. Closing an overlay redraws the interface, preserving the top menu and both panels. Bootstrap dependency dialogs are handled separately before the full interface starts.

# Credentials and saved data

| Location | Contents |
|:--|:--|
| `~/.config/windows-drive-ide/` | Saved profiles and the instance lock; historical directory name retained for compatibility |
| `<folder-ID>.drive` | Seven lines: folder ID, display name, server, share, domain, username, SMB dialect |
| `~/NetworkDrives/<folder-ID>` | Local mount directory |
| `/tmp/simba.XXXXXXXX/` | Private session files and temporary credentials |

Passwords are not saved in drive profiles or passed as command-line password arguments. Temporary credential files use mode `0600`; they are removed after connection attempts and during normal cleanup. A forced process kill or system crash can prevent cleanup, so temporary-file deletion is not a guarantee of secure erasure.

# Troubleshooting

| Symptom | What to check |
|:--|:--|
| No domains found | Office/VPN connectivity, internal DNS, and the domain suffix. Try a manual full DNS domain in G. |
| Domain found but no storage listed | B needs a specific file server. Finding controllers does not enumerate all storage. |
| Authentication rejected | Windows username, account domain, password, and permissions. No anonymous retry is attempted. |
| Connection fails | Server address, share name, VPN routing, Windows permissions, and SMB3 encryption support. |
| Mount directory rejected | Use the intended empty directory; do not hide existing files under a new mount. |
| Disconnect says busy | Close files, file-manager windows, and shells using that mount, then retry. |
| Blue panel or cyan highlight | These are the Commander-style interface colors and active selection. |
| Gaps or broken borders | Use a monospace terminal font with box-drawing support and at least 100 × 24 cells. |
| Menu disappears | Use version 3.0.1 with native overlays; resize to a supported terminal size and refresh. |
| Mounted status seems stale | Press R. “Mounted” reflects the local mount table, not a live server-health test. |
| Folder will not open | Check `xdg-open` and that a graphical desktop session is available. |

# Simulated domain and share testing

**Offline simulations passed during development. Live Windows/Active Directory validation remains pending.** The tests substituted controlled responses for DNS, SMB, sudo, mount, and unmount operations. They did not contact a real domain, install real packages, or create real network mounts.

## Test environment

| Component | Fixture |
|:--|:--|
| Domain | `corp.example.test` |
| Controllers | `dc01.corp.example.test`, `dc02.corp.example.test` |
| File server | `fs01.corp.example.test` |
| Disk shares | `Shared`, `Engineering Shared`, `GIS`, `Finance$` |
| Extra entries | IPC and printer entries, which must be excluded |

## Results

| Test area | Verified result |
|:--|:--|
| Bash syntax | `bash -n simba.sh` passed. |
| Domain discovery | One valid domain from two candidates; two controller records retained; unavailable DNS handled. |
| Share browsing | Four disk shares retained; IPC and printers filtered; names with spaces preserved. |
| Browse → profile → mount | Selected share saved correctly and passed to a mocked encrypted mount. |
| Disconnect | Busy unmount reported; later successful unmount handled; mismatched sources rejected. |
| Failure paths | Rejected logon, denied mount, cancelled input, and empty share results handled without connecting an unrelated profile. |
| Credentials | Private file permissions and cleanup checked; password absent from profile and diagnostic outputs checked by the fixtures. |
| Dependency setup | Duplicate packages, declined setup, missing sudo, apt refresh failure, install failure, and recheck paths simulated. |
| Progress | Measured steps, animated waits, separate outputs, and nonzero exit status preservation checked. |
| Startup | Prefetch before the interface, cached discovery, and mount refresh checked. |
| Terminal behavior | Actual pseudo-terminal tests at 24 and 28 rows checked navigation, form editing, hidden passwords, Help scrolling, popup overlays, menu redraw, and clean exit. |

These tests exercise control flow and terminal rendering. They cannot establish compatibility with an organization's real DNS, authentication policies, SMB server, VPN, or Windows ACLs. The next validation step is an authorized live test: discover a known domain, browse a known file server, mount a permitted share, open a file appropriate to the account, and disconnect cleanly.

# Revision history

All script entries below are dated **17 October 2026**. Documentation created **18 October 2026**.

| Version | Change |
|:--|:--|
| 3.0.1 | Comment separators and expanded authorship header |
| 3.0.0 | Native overlay popups preserve the menu and panels |
| 2.4.1 | Restored full-screen buffer after external dialogs; superseded by native overlays |
| 2.4.0 | Terminal startup prefetch |
| 2.3.0 | Task status, measured progress, and animated waits |
| 2.2.2 | Reset colors after leaving the alternate screen |
| 2.2.1 | Sized, scrollable Help viewer |
| 2.2.0 | Letter shortcuts and joined double-line dividers |
| 2.1.1 | Clear exit screen, goodbye message, and comments |
| 2.1.0 | Dependency setup and simba name |
| 2.0.1 | Earlier smbnav name |
| 2.0.0 | Norton Commander layout and dual panels |
| 1.2.0 | Authenticated share browsing and profile creation |
| 1.1.0 | DNS domain discovery |
| 1.0.0 | Initial terminal interface, profiles, and SMB3 mounts |

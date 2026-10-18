---
title: "simba — SMB shares navigator"
author: Teo Espero
date: "Documentation: 18 October 2026 · Script: 3.0.2"
lang: en
---

# About simba

**simba** is a Bash terminal application for discovering Windows domain hints, browsing SMB file shares, and connecting saved network drives from Ubuntu or Debian. Its blue, dual-pane interface takes inspiration from Norton Commander. It uses letter shortcuts, status messages, progress indicators, and keyboard-operated overlay dialogs.

**Author:** Teo Espero. **Script version:** 3.0.2. **Created:** 17 October 2026. **Updated:** 18 October 2026. This guide covers the code first, followed by offline simulations and the Windows/Ubuntu VM test, including issues, fixes, results, and screenshots.

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
- [VM testing: setup, issues, fixes, and results](#vm-testing)
- [Screenshot record](#screenshot-record)
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
8. On a graphical desktop, press **O** to request opening the mounted folder. On Ubuntu Server without a desktop, use `cd` and `ls` in the terminal instead. Close open files before using **D** to disconnect.

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


## Why build this when Ubuntu already has tools?

Ubuntu Files can connect to an `smb://` address, Double Commander supplies a two-panel file manager, and `smbclient` browses shares from the command line. simba brings domain hints, share browsing, saved profiles, connect/disconnect controls, dependency checks, and task status together. It uses established Linux tools underneath. It is a connection manager rather than a full file manager.

## Dependency detection and installation

The following function is copied from version 3.0.2. Entries map commands to packages. `${entry%%:*}` keeps the command and `${entry#*:}` keeps the package. The associative array avoids requesting one package several times when multiple commands are missing.

```bash
collect_missing_dependencies() {
    local entry cmd package
    local -A seen_packages=()
    local -a requirements=(
        sudo:sudo dialog:dialog mount.cifs:cifs-utils dig:dnsutils
        smbclient:smbclient xdg-open:xdg-utils
        findmnt:util-linux flock:util-linux mount:mount umount:mount
        find:findutils awk:gawk
        stty:coreutils mktemp:coreutils timeout:coreutils sort:coreutils
        head:coreutils wc:coreutils tr:coreutils cat:coreutils sleep:coreutils
        rm:coreutils mv:coreutils mkdir:coreutils chmod:coreutils id:coreutils
    )
    MISSING_COMMANDS=(); MISSING_PACKAGES=()
    for entry in "${requirements[@]}"; do
        cmd=${entry%%:*}; package=${entry#*:} # Split command:package without external tools.
        command_available "$cmd" && continue
        MISSING_COMMANDS+=("$cmd")
        # ------------------------------------
        # Several commands belong to coreutils/util-linux: install each package
        # once even if more than one of its commands is missing.
        # ------------------------------------
        if [[ -z ${seen_packages[$package]+present} ]]; then
            seen_packages[$package]=1; MISSING_PACKAGES+=("$package")
        fi
    done
}
```

After confirmation, setup authenticates with `sudo -v`, refreshes repositories, installs the collected packages, and rechecks commands. The installation function stops if authentication, refresh, or installation fails:

```bash
install_dependency_packages() {
    printf '\nsimba: administrator permission is needed to install packages.\n'
    sudo -v || { printf 'Administrator authentication failed or was cancelled.\n' >&2; return 1; }
    printf '\nsimba setup [1/3]: refreshing package lists (download progress below)...\n'
    bootstrap_progress 0 'Refreshing package lists'
    # ------------------------------------
    # -n reuses sudo authorization. Error-Mode=any makes a failed repository
    # refresh stop setup instead of continuing with an incomplete update.
    # ------------------------------------
    sudo -n apt-get -o APT::Update::Error-Mode=any update || {
        printf '\nPackage refresh failed. Check your connection or package repositories, then run simba again.\n' >&2
        return 1
    }
    printf '\nsimba setup [2/3]: installing missing packages (package progress below)...\n'
    bootstrap_progress 1 'Installing packages'
    sudo -n apt-get install --assume-yes -- "${MISSING_PACKAGES[@]}" || {
        printf '\nPackage installation failed. Review the package manager output above, then run simba again.\n' >&2
        return 1
    }
}
```

Automatic installation needs repository connectivity. For an isolated VM network, install dependencies before removing internet access, or provide an appropriate repository route. Installing `xdg-utils` does not provide a desktop or graphical file manager.

## Domain-controller query

```bash
query_controllers() {
    local domain=$1 priority weight port host rest
    valid_dns_name "$domain" || return 1
    # ------------------------------------
    # A trailing dot prevents the resolver appending any search suffix.
    # timeout bounds one lookup even when DNS/VPN is unavailable.
    # ------------------------------------
    while read -r priority weight port host rest; do
        # ------------------------------------
        # SRV fields are priority, weight, port and target hostname. Reject
        # malformed output and accept only LDAP domain-controller records.
        # ------------------------------------
        [[ $priority =~ ^[0-9]+$ && $weight =~ ^[0-9]+$ && $port == 389 && -z $rest ]] || continue
        host=${host%.}; host=${host,,}
        valid_dns_name "$host" && printf '%s\n' "$host"
    # ------------------------------------
    # Process substitution feeds DNS output into read without creating a file.
    # Only record contents are parsed; no DNS response is executed as code.
    # ------------------------------------
    done < <(timeout 6 dig +time=2 +tries=1 +short SRV "_ldap._tcp.dc._msdcs.$domain." 2>/dev/null) | sort -u
}
```

The SRV parser accepts numeric priority and weight, LDAP port 389, and a valid target hostname. It trims the final dot, normalizes case, and removes duplicates. The query's trailing dot prevents search-suffix expansion; timeouts bound the wait. DNS records provide discovery hints rather than authenticated server identity. Discovery does not scan every network address or join Active Directory.

## The SMB browse command

The following excerpt uses a temporary credentials file rather than a password argument. `-g` requests parseable output, `-L` requests the server's shares, encryption is required, and SMB3 is the minimum protocol. This password flow disables ticket-cache Kerberos. The outer timeout bounds the request.

```bash
run_with_progress "$RUN_DIR/browse-output" "$RUN_DIR/browse-error" \
    timeout --kill-after=2 25 smbclient -g -L "$server" \
    -A "$credentials" --client-protection=encrypt -m SMB3 \
    --option='client min protocol=SMB3' --use-kerberos=off -t 8 || rc=$?
```

## Mount options and connection

The current connection code builds these options and invokes `mount` after separate sudo authorization:

```bash
options="credentials=$credentials,uid=$(id -u),gid=$(id -g),vers=${DIALECTS[SELECTED]},seal,sec=ntlmssp,nosuid,nodev,file_mode=0600,dir_mode=0700"
sudo -n mount -t cifs "//${SERVERS[SELECTED]}/${SHARES[SELECTED]}" "$p" -o "$options"
```

`uid`/`gid` associate local ownership with the current user, `vers` selects the configured dialect, `seal` requires encryption, and `sec=ntlmssp` selects authentication. `nosuid`/`nodev` restrict special local behavior. Local modes do not grant Windows permissions; the server still enforces share and filesystem access. `$p` is the selected local mount directory.

## Terminal-size handling in version 3.0.2

```bash
terminal_size() {
    local dimensions='' rows=0 cols=0
    if dimensions=$({ stty size </dev/tty; } 2>/dev/null) ||
        dimensions=$(stty size <&2 2>/dev/null) ||
        dimensions=$(stty size 2>/dev/null); then
        read -r rows cols <<< "$dimensions"
        if [[ $rows =~ ^[0-9]+$ && $cols =~ ^[0-9]+$ ]] &&
            ((rows>0 && cols>0)); then
            printf '%s %s\n' "$rows" "$cols"
            return 0
        fi
    fi
    printf '24 80\n'
}
```

The helper tries `/dev/tty` first so redirected worker input does not determine terminal geometry. It then tries stderr and stdin, validates positive numeric dimensions, and returns a fallback if none can be read. Callers still enforce the minimum 100 × 24 terminal size. This was the code change prompted by the VM startup errors described below.

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
| Menu disappears | Use version 3.0.2 with native overlays; resize to a supported terminal size and refresh. |
| Mounted status seems stale | Press R. “Mounted” reflects the local mount table, not a live server-health test. |
| Folder will not open | Check `xdg-open` and that a graphical desktop session is available. |

# Simulated domain and share testing

**Offline simulations passed during development. Live VM validation subsequently confirmed DNS discovery, authenticated share enumeration, mounting, and directory listing.** The tests substituted controlled responses for DNS, SMB, sudo, mount, and unmount operations. They did not contact a real domain, install real packages, or create real network mounts.

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

These tests exercise control flow and terminal rendering. Their results remain separate from the live VM observations below. They do not establish compatibility with every organization's DNS, authentication policies, SMB server, VPN, or Windows ACLs. File read/write, restricted-share denial, and busy disconnect still require live VM validation.


# VM testing: setup, issues, fixes, and results {#vm-testing}

## Lab setup

The live test used two KVM guests managed through virt-manager on the Ubuntu laptop. It was a separate lab, not a production domain. Windows handled both the domain-controller and file-server roles for this test.

| Item | Actual lab configuration |
|:--|:--|
| Ubuntu guest | Ubuntu Server; VM `simba-client`; user `support` |
| Windows guest | Windows Server 2025 Datacenter Evaluation; VM `simba-server` |
| Windows hostname | `DC01` |
| AD DNS domain | `corp.simba.test` |
| Windows/DNS address | `192.168.100.10` |
| Ubuntu address | `192.168.100.20/24` |
| Ubuntu interface | `enp1s0` |
| Ubuntu DNS/search domain | `192.168.100.10`; `corp.simba.test` |
| Intended guest network | `simba-lab` |
| Windows account | `CORP\simbauser` |
| Test shares | `shared`, `engineering_shared`, `restricted`; encryption enabled |

The screenshot record below follows installation, configuration, transfer, troubleshooting, and successful access. Original filenames are retained beside every image.

## 1. Script transfer and SSH

The laptop initially could not copy the script:

```bash
scp ~/Documents/bash-shell-scripts/simba/simba.sh \
    support@192.168.100.20:~/simba.sh
```

The result was `No route to host`. SSH was also inactive inside Ubuntu Server. These are separate conditions: starting SSH alone does not fix an unreachable network path.

```bash
# Run inside the Ubuntu guest to start and enable SSH.
sudo systemctl enable --now ssh

# Run on the laptop to inspect the guest network attachments.
sudo virsh domiflist simba-client
sudo virsh domiflist simba-server
```

Both guests initially used `default` despite static addresses in the intended lab subnet. The laptop routed that subnet through the separate lab bridge. Correcting the Ubuntu attachment and enabling SSH allowed ping and SCP to succeed; the screenshot shows a completed 73 KB transfer. Assigning a static address does not attach a guest to the corresponding virtual network.

## 2. Startup terminal errors and the 3.0.2 fix

Version 3.0.1 printed repeated `stty: 'standard input': Inappropriate ioctl for device` messages during preparation. Terminal geometry could be read from redirected input. Version 3.0.2 introduced the terminal-size helper shown above, starting with the controlling terminal. The later screenshots show the updated app running with its menus and progress display in place.

The added pseudo-terminal checks exercised 24- and 28-row terminals, including redirected worker input. This verifies the helper behavior locally; the screenshots remain the evidence for the user's VM session.

## 3. DNS query spelling and guest network mismatch

Early commands included a missing period in the SRV name and `.text` instead of `.test`. Correcting those produced a valid response. Later, discovery failed again after moving only Ubuntu to `simba-lab` while Windows remained on `default`.

The lookup used by discovery can be checked outside the app:

```bash
# Use Ubuntu's configured resolver.
dig _ldap._tcp.dc._msdcs.corp.simba.test SRV +short

# Query the Windows DNS server directly.
dig @192.168.100.10 \
    _ldap._tcp.dc._msdcs.corp.simba.test SRV +time=2 +tries=1

# Inspect the DNS settings on Ubuntu Server.
resolvectl status enp1s0
```

Both resolver-based and direct queries timed out during the mismatch. `resolvectl` showed the intended DNS server and suffix, so correct configuration alone did not prove reachability. `127.0.0.53` in the first timeout was Ubuntu's local stub resolver; it did not itself establish a resolver configuration fault.

Putting both guests on `simba-lab` restored the response:

```text
0 100 389 dc01.corp.simba.test.
```

simba then found one domain with one advertised controller record. Selecting it filled the account domain for subsequent profiles; the file server remained a separate field.

## 4. Authenticated share browsing and mounting

The browse form used server `dc01`, domain `corp.simba.test`, and user `simbauser`. Authentication and encrypted SMB3 enumeration succeeded. The app displayed seven disk shares:

```text
ADMIN$
C$
engineering_shared
NETLOGON
restricted
shared
SYSVOL
```

`IPC$` was excluded from the disk-share panel. A returned share name does not establish permission to access its contents. The `restricted` share's access-denial behavior has not yet been confirmed in the VM.

The selected `engineering_shared` share became a saved profile and connected successfully. The interface reported `Mounted`, SMB `3.1.1`, and `/home/support/NetworkDrives/engineering_shared`.

## 5. Open-folder behavior on Ubuntu Server

Pressing O did not produce a window because the guest had no graphical desktop/file manager. The current action requests `xdg-open` in the background; its status text reports a request rather than proving that a window opened. This behavior has been documented, not fixed in 3.0.2.

After quitting simba, the user entered and listed the mounted directory:

```bash
cd ~/NetworkDrives/engineering_shared
ls -al
```

The listing succeeded and showed an empty directory. Combined with the mount observation, this confirms mounted-directory access, not file read/write correctness. Q intentionally leaves mounts connected.

## Issue and fix summary

| Issue | Cause/observation | Action and outcome |
|:--|:--|:--|
| SCP: No route to host | Guest attachment did not match the laptop's lab route | Corrected client attachment; transfer succeeded |
| SSH unavailable | Service inactive | Enabled and started SSH |
| Repeated startup stty errors | Geometry check could read redirected input | Updated `terminal_size` in 3.0.2 |
| Early SRV lookups failed | Typing mistakes in record/domain name | Corrected spelling; controller returned |
| Discovery later timed out | Client on `simba-lab`, Windows on `default` | Connected both to the same lab network; DNS and discovery succeeded |
| O opened no window | Ubuntu Server had no graphical file manager | Terminal directory access succeeded; clearer UI feedback remains future work |

## Observed live results

| Test | Result and limit |
|:--|:--|
| Script transfer | Passed after network/SSH fixes |
| DNS controller lookup | Passed; `dc01.corp.simba.test`, port 389 |
| In-app domain discovery | Passed; one domain/controller record |
| Authentication and encrypted share listing | Passed; seven disk shares shown |
| Profile creation | Passed for `engineering_shared` |
| Mount | Passed; SMB 3.1.1 reported |
| Directory navigation/listing | Passed; share was empty |
| Graphical opening | No window on the server-only installation |
| File creation and read-back | Pending |
| Restricted-share denial | Pending |
| Wrong-password behavior | Covered by simulations; live VM check pending |
| Busy disconnect | Covered by simulations; live VM check pending |
| Network loss/recovery | Live VM check pending |

No throughput measurements or timing benchmarks were collected. The screenshots support functional observations, not performance claims or blanket compatibility with every domain policy.

## Next validation steps

1. Create a uniquely named disposable text file on the mounted lab share, read it back, and verify it from Windows.
2. Confirm denial on `restricted` with the intended nonprivileged test account.
3. Try an incorrect password and check the message and credential-file cleanup.
4. Disconnect normally, then test a busy mount with a shell inside the directory; leave the directory and retry.
5. Test network interruption/recovery and refresh the displayed mount state.
6. Test O on an Ubuntu desktop and improve the no-desktop feedback path.

These are planned checks, not completed results. Keep any disposable file cleanup limited to the file created for the test.

# Screenshot record

Galleries are chronological within each batch. Captions describe only what the screenshots establish. Both documents use the adjacent `simba-images` folder supplied in the documentation bundle. Extract the ZIP and keep that folder beside both documents.

## Batch 1: installation and configuration

### Screenshot 01

**Filename:** `Screenshot from 2026-10-18 14-03-18.png`

![Starting Windows Server setup.](simba-images/01-14-03-18.png)

Starting Windows Server setup.

### Screenshot 02

**Filename:** `Screenshot from 2026-10-18 14-04-16.png`

![Windows Server installation progress.](simba-images/02-14-04-16.png)

Windows Server installation progress.

### Screenshot 03

**Filename:** `Screenshot from 2026-10-18 14-18-55.png`

![Booting the Ubuntu Server installer.](simba-images/03-14-18-55.png)

Booting the Ubuntu Server installer.

### Screenshot 04

**Filename:** `Screenshot from 2026-10-18 14-20-34.png`

![Ubuntu Server installation progress.](simba-images/04-14-20-34.png)

Ubuntu Server installation progress.

### Screenshot 05

**Filename:** `Screenshot from 2026-10-18 14-30-15.png`

![Downloading Ubuntu packages.](simba-images/05-14-30-15.png)

Downloading Ubuntu packages.

### Screenshot 06

**Filename:** `Screenshot from 2026-10-18 14-39-47.png`

![Installing Active Directory Domain Services on DC01.](simba-images/06-14-39-47.png)

Installing Active Directory Domain Services on DC01.

### Screenshot 07

**Filename:** `Screenshot from 2026-10-18 14-59-19(1).png`

![Configuring an inbound SMB firewall rule for the Ubuntu client.](simba-images/07-14-59-19-1.png)

Configuring an inbound SMB firewall rule for the Ubuntu client.

### Screenshot 08

**Filename:** `Screenshot from 2026-10-18 14-59-49(1).png`

![Share paths and encryption enabled for the three test shares.](simba-images/08-14-59-49-1.png)

Share paths and encryption enabled for the three test shares.

### Screenshot 09

**Filename:** `Screenshot from 2026-10-18 15-09-56(1).png`

![Applying Ubuntu networking; an early SRV query contains a typo.](simba-images/09-15-09-56-1.png)

Applying Ubuntu networking; an early SRV query contains a typo.

### Screenshot 10

**Filename:** `Screenshot from 2026-10-18 15-11-26(1).png`

![Hostname resolution works during DNS setup checks.](simba-images/10-15-11-26-1.png)

Hostname resolution works during DNS setup checks.


## Batch 2: transfer, startup, and DNS troubleshooting


### Screenshot 13

**Filename:** `Screenshot from 2026-10-18 15-15-32(1).png`

![Authenticated encrypted SMB3 enumeration lists server shares.](simba-images/13-15-15-32-1.png)

Authenticated encrypted SMB3 enumeration lists server shares.

### Screenshot 14

**Filename:** `Screenshot from 2026-10-18 15-18-51(1).png`

![SCP and reachability failures; SSH is inactive in the guest.](simba-images/14-15-18-51-1.png)

SCP and reachability failures; SSH is inactive in the guest.

### Screenshot 15

**Filename:** `Screenshot from 2026-10-18 15-19-42(1).png`

![Enabling and starting SSH.](simba-images/15-15-19-42-1.png)

Enabling and starting SSH.

### Screenshot 16

**Filename:** `Screenshot from 2026-10-18 15-19-55.png`

![Both guests initially attached to default.](simba-images/16-15-19-55.png)

Both guests initially attached to default.

### Screenshot 17

**Filename:** `Screenshot from 2026-10-18 15-23-28.png`

![Ping and SCP succeed after correcting client connectivity.](simba-images/17-15-23-28.png)

Ping and SCP succeed after correcting client connectivity.

### Screenshot 18

**Filename:** `Screenshot from 2026-10-18 15-24-20.png`

![Initial simba 3.0.1 interface with no saved profiles.](simba-images/18-15-24-20.png)

Initial simba 3.0.1 interface with no saved profiles.

### Screenshot 19

**Filename:** `Screenshot from 2026-10-18 15-24-42.png`

![Startup emits stty input errors.](simba-images/19-15-24-42.png)

Startup emits stty input errors.

### Screenshot 20

**Filename:** `Screenshot from 2026-10-18 15-28-05.png`

![Updated simba 3.0.2 startup progress display.](simba-images/20-15-28-05.png)

Updated simba 3.0.2 startup progress display.

### Screenshot 21

**Filename:** `Screenshot from 2026-10-18 15-28-26(1).png`

![Manual lookup for corp.simba.test.](simba-images/21-15-28-26-1.png)

Manual lookup for corp.simba.test.

### Screenshot 22

**Filename:** `Screenshot from 2026-10-18 15-28-45(1).png`

![No controller records returned during the network mismatch.](simba-images/22-15-28-45-1.png)

No controller records returned during the network mismatch.



## Batch 3: successful discovery and share access

### Screenshot 25

**Filename:** `Screenshot from 2026-10-18 15-35-47(2).png`

![DNS returns DC01 after correcting guest network connectivity.](simba-images/25-15-35-47-2.png)

DNS returns DC01 after correcting guest network connectivity.

### Screenshot 26

**Filename:** `Screenshot from 2026-10-18 15-36-03(2).png`

![Discovery menu includes corp.simba.test and rescan controls.](simba-images/26-15-36-03-2.png)

Discovery menu includes corp.simba.test and rescan controls.

### Screenshot 27

**Filename:** `Screenshot from 2026-10-18 15-36-12(2).png`

![Discovery completed: one candidate and one domain found.](simba-images/27-15-36-12-2.png)

Discovery completed: one candidate and one domain found.

### Screenshot 28

**Filename:** `Screenshot from 2026-10-18 15-36-24(2).png`

![Selected domain and advertised controller details.](simba-images/28-15-36-24-2.png)

Selected domain and advertised controller details.

### Screenshot 29

**Filename:** `Screenshot from 2026-10-18 15-37-47(2).png`

![Browse form with dc01, the lab domain, and simbauser.](simba-images/29-15-37-47-2.png)

Browse form with dc01, the lab domain, and simbauser.

### Screenshot 30

**Filename:** `Screenshot from 2026-10-18 15-38-04(2).png`

![Seven disk shares listed in the right panel.](simba-images/30-15-38-04-2.png)

Seven disk shares listed in the right panel.

### Screenshot 31

**Filename:** `Screenshot from 2026-10-18 15-38-27(2).png`

![Reviewing the engineering_shared profile settings.](simba-images/31-15-38-27-2.png)

Reviewing the engineering_shared profile settings.

### Screenshot 32

**Filename:** `Screenshot from 2026-10-18 15-40-57(2).png`

![engineering_shared shown mounted using SMB 3.1.1.](simba-images/32-15-40-57-2.png)

engineering_shared shown mounted using SMB 3.1.1.

### Screenshot 33

**Filename:** `Screenshot from 2026-10-18 15-42-31(2).png`

![Terminal navigation and listing succeed; the share is empty.](simba-images/33-15-42-31-2.png)

Terminal navigation and listing succeed; the share is empty.


# Revision history

Version **3.0.2** is dated **18 October 2026**. Earlier entries are dated **17 October 2026**. Documentation updated **18 October 2026** with the live VM record and screenshots.

| Version | Change |
|:--|:--|
| 3.0.2 | Read terminal dimensions independently of redirected task input; documented live VM results |
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

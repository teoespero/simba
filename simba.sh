#!/usr/bin/env bash
# ------------------------------------
# Script information and authorship
# ------------------------------------
# Program:  simba — SMB shares navigator
# Author:   Teo Espero
# Platform: Ubuntu/Debian; Bash 4.4 or newer
# Created:  2026-10-17
# Updated:  2026-10-17
# Version:  3.0.1
# ------------------------------------
# Revision history
# ------------------------------------
# Version  Date        Change
# 3.0.1  2026-10-17  Added comment separators and expanded authorship header.
# 3.0.0  2026-10-17  Native overlay popups preserve the menu and drive panels.
# 2.4.1  2026-10-17  Restore full-screen buffer after dialogs close.
# 2.4.0  2026-10-17  Terminal startup prefetch before opening the main interface.
# 2.3.0  2026-10-17  Task status, measured progress and animated network waits.
# 2.2.2  2026-10-17  Reset colors after leaving the alternate screen on exit.
# 2.2.1  2026-10-17  Fixed empty Help with an explicitly sized scrollable viewer.
# 2.2.0  2026-10-17  Letter shortcuts and connected double-line dividers.
#                       Expanded comments around the more complex routines.
# 2.1.1  2026-10-17  Clear exit screen, goodbye message and section comments.
# 2.1.0  2026-10-17  Dependency setup with confirmed apt installs; simba name.
# 2.0.1  2026-10-17  Renamed to smbnav (SMB navigator).
# 2.0.0  2026-10-17  Norton Commander layout, dual panels and function keys.
# 1.2.0  2026-10-17  Authenticated share browsing and profile creation.
# 1.1.0  2026-10-17  DNS domain discovery and domain controller selection list.
# 1.0.0  2026-10-17  Initial boxed terminal UI, profiles and SMB3 mounts.
# ------------------------------------
# Dependencies and startup instructions
# ------------------------------------
# Dependencies: dialog cifs-utils dnsutils smbclient util-linux sudo coreutils.
# dialog is used during bootstrap only; runtime popups are drawn by Bash.
# Optional: xdg-utils, NetworkManager or systemd-resolved for DNS suffix hints.
# Install: sudo apt install dialog cifs-utils dnsutils smbclient
# Run as your normal user, never with sudo or bash -x (passwords are handled).
# This accesses shares; it does not join Active Directory or configure a VPN.
# Startup offers to install missing packages on Ubuntu/Debian. Declining exits.

# ------------------------------------
# Shell settings and application state
# ------------------------------------
set +x
set -uo pipefail
umask 077
# ------------------------------------
# CIFS helpers can live in sbin even for normal users.
# ------------------------------------
PATH="${PATH:-/usr/bin:/bin}:/usr/sbin:/sbin"
VERSION=3.0.1
STATUS='Ready. G: discover domains. B: browse shares. H: help.'
DISCOVERED_DOMAIN=''
declare -a FOUND_DOMAINS=() FOUND_CONTROLLERS=() FOUND_COUNTS=()
declare -a BROWSED_SHARES=() BROWSED_COMMENTS=()
PANEL=drives
SHARE_SELECTED=0
SHARE_OFFSET=0
BROWSE_SERVER=''
BROWSE_DOMAIN=''
BROWSE_USER=''
SAVED_ID=''
EXIT_REQUESTED=0
KEY=''
TASK_LABEL='Ready'
TASK_STATE=idle
TASK_TOTAL=0
TASK_DONE=0
TASK_TICK=0
TASK_PID=''
PREFETCH_ACTIVE=0
DOMAIN_CACHE_READY=0
MOUNT_CACHE_READY=0
declare -A MOUNT_STATES=()
declare -a MISSING_COMMANDS=() MISSING_PACKAGES=()
SELECTED=0
OFFSET=0
RUN_DIR=''
ACTIVE=0
declare -a IDS=() NAMES=() SERVERS=() SHARES=() DOMAINS=() USERS=() DIALECTS=()

# ------------------------------------
# Cleanup and exit screen
# ------------------------------------
cleanup() {
    # ------------------------------------
    # A pending background worker must not keep using session files on exit.
    # ------------------------------------
    if [[ -n $TASK_PID ]]; then kill -TERM "$TASK_PID" 2>/dev/null || :; fi
    # ------------------------------------
    # Remove only this session's private files, including any credentials.
    # ------------------------------------
    [[ -n $RUN_DIR ]] && rm -rf -- "$RUN_DIR"
    if ((PREFETCH_ACTIVE)); then
        PREFETCH_ACTIVE=0
        printf '\033[0m\033[39;49m\r\033[2KStartup stopped.\n\033[2K'
    fi
    if (( ACTIVE )); then
        # ------------------------------------
        # Restore the original terminal before clearing the returned screen.
        # Reset ACTIVE so a repeated cleanup does not print goodbye twice.
        # ------------------------------------
        ACTIVE=0
        # ------------------------------------
        # Leaving the alternate screen can restore saved colors. Reset AFTER
        # that switch as well, so clearing cannot paint the normal screen blue.
        # ------------------------------------
        printf '\033[0m\033[?1049l\033[0m\033[39;49m\033[?25h'
        stty "$OLD_STTY" 2>/dev/null || :
        printf '\033[2J\033[HGoodbye! Thanks for using simba.\n'
    fi
}

# ------------------------------------
# Terminal text, borders and layout
# ------------------------------------
# All terminal text is clipped and control characters stripped before printing.
at() {
    local row=$1 col=$2 width=$3 value=$4
    value=${value//[[:cntrl:]]/ }
    # ------------------------------------
    # Bash printf precision counts bytes. Slice by characters before padding
    # so accented names and box characters do not get split mid-byte.
    # ------------------------------------
    value=${value:0:width}
    printf '\033[%s;%sH%s' "$row" "$col" "$value"
    printf '%*s' "$((width-${#value}))" ''
}
line() { local n=$1 ch=$2 s; printf -v s '%*s' "$n" ''; printf '%s' "${s// /$ch}"; }
box() {
    local top=$1 left=$2 height=$3 width=$4 title=$5 r
    printf '\033[%s;%sH╔' "$top" "$left"; line "$((width-2))" '═'; printf '╗'
    for ((r=top+1;r<top+height-1;r++)); do
        printf '\033[%s;%sH║\033[%s;%sH║' "$r" "$left" "$r" "$((left+width-1))"
    done
    printf '\033[%s;%sH╚' "$((top+height-1))" "$left"; line "$((width-2))" '═'; printf '╝'
    local title_width=$((${#title}+2))
    ((title_width > width-4)) && title_width=$((width-4))
    at "$top" "$((left+2))" "$title_width" " $title "
}
divider() {
    local row=$1 left=$2 width=$3
    # ------------------------------------
    # Use matching tees and double horizontal lines so the divider physically
    # joins each double vertical edge instead of stopping beside it.
    # ------------------------------------
    printf '\033[%s;%sH╠' "$row" "$left"
    line "$((width-2))" '═'
    printf '╣'
}
# ------------------------------------
# Dialog windows and color theme
# ------------------------------------
dlg() {
    if ((ACTIVE)); then native_dialog "$@"; return $?; fi
    # ------------------------------------
    # Before the main interface is active, the external program can still be
    # used for bootstrap prompts. Runtime popups never hand it the screen.
    # ------------------------------------
    DIALOGRC="$RUN_DIR/dialogrc" dialog --backtitle "simba $VERSION | Teo Espero" --no-collapse "$@"
}

# ------------------------------------
# Native popup layout and text wrapping
# ------------------------------------
# Popup helpers share UI_* locals through Bash's dynamic function scope. Their
# terminal output always uses stderr; stdout is reserved for returned form data.
modal_wrap() {
    local text=$1 width=$2 segment chunk length
    UI_LINES=()
    text=${text//\\n/$'\n'}
    while IFS= read -r segment || [[ -n $segment ]]; do
        segment=${segment//[[:cntrl:]]/ }
        while ((${#segment}>width)); do
            chunk=${segment:0:width}; length=$width
            if [[ $chunk == *' '* ]]; then
                chunk=${chunk% *}; ((${#chunk}>0)) && length=${#chunk}
            fi
            UI_LINES+=("${segment:0:length}")
            segment=${segment:length}; segment=${segment# }
        done
        UI_LINES+=("$segment")
    done <<< "$text"
}
modal_geometry() {
    local old_rows=${UI_ROWS:-0} old_cols=${UI_COLS:-0} available
    read -r UI_ROWS UI_COLS < <(stty size)
    if ((UI_ROWS<24 || UI_COLS<100)); then draw >&2; return 1; fi
    UI_WIDTH=$UI_REQUEST_WIDTH; UI_HEIGHT=$UI_REQUEST_HEIGHT
    ((UI_WIDTH>UI_COLS-8)) && UI_WIDTH=$((UI_COLS-8))
    ((UI_WIDTH<30)) && UI_WIDTH=30
    ((UI_HEIGHT>UI_ROWS-5)) && UI_HEIGHT=$((UI_ROWS-5))
    ((UI_HEIGHT<8)) && UI_HEIGHT=8
    UI_TOP=$(((UI_ROWS-UI_HEIGHT)/2+1)); UI_LEFT=$(((UI_COLS-UI_WIDTH)/2+1))
    UI_BUTTON_ROW=$((UI_TOP+UI_HEIGHT-2))
    modal_wrap "$UI_TEXT" "$((UI_WIDTH-6))"
    case $UI_KIND in
        inputbox|passwordbox|form)
            available=$((UI_HEIGHT-${#UI_VALUES[@]}-6))
            ((available<1)) && available=1;;
        menu) available=$((UI_HEIGHT-9));;
        *) available=$((UI_HEIGHT-5));;
    esac
    UI_PROMPT_ROWS=${#UI_LINES[@]}
    ((UI_PROMPT_ROWS>available)) && UI_PROMPT_ROWS=$available
    UI_CONTENT_ROW=$((UI_TOP+2+UI_PROMPT_ROWS+1))
    UI_VISIBLE=$((UI_BUTTON_ROW-UI_CONTENT_ROW-1))
    ((UI_VISIBLE<1)) && UI_VISIBLE=1
    if ((old_rows!=UI_ROWS || old_cols!=UI_COLS)); then draw >&2; fi
}
modal_button() {
    local col=$1 label=$2 active=$3
    if ((active)); then printf '\033[37;44m'; else printf '\033[30;47m'; fi
    at "$UI_BUTTON_ROW" "$col" "${#label}" "$label"
}
modal_frame() {
    local r i index label_width=0 field_width field_col value start pos selected=0
    printf '\033[?25l\033[30;47m'
    # ------------------------------------
    # Paint only the centered popup rectangle, leaving the menu, panels and
    # bottom commands outside it untouched. No terminal clear or buffer switch.
    # ------------------------------------
    for ((r=UI_TOP;r<UI_TOP+UI_HEIGHT;r++)); do at "$r" "$UI_LEFT" "$UI_WIDTH" ''; done
    box "$UI_TOP" "$UI_LEFT" "$UI_HEIGHT" "$UI_WIDTH" "$UI_TITLE"
    case $UI_KIND in
        msgbox|yesno|textbox)
            for ((i=0;i<UI_HEIGHT-5;i++)); do
                index=$((UI_SCROLL+i)); ((index<${#UI_LINES[@]})) || break
                at "$((UI_TOP+2+i))" "$((UI_LEFT+3))" "$((UI_WIDTH-6))" "${UI_LINES[index]}"
            done;;
        *)
            for ((i=0;i<UI_PROMPT_ROWS;i++)); do
                at "$((UI_TOP+2+i))" "$((UI_LEFT+3))" "$((UI_WIDTH-6))" "${UI_LINES[i]}"
            done;;
    esac
    case $UI_KIND in
        inputbox|passwordbox|form)
            [[ $UI_KIND == form ]] && label_width=16
            field_width=$((UI_WIDTH-6-label_width)); field_col=$((UI_LEFT+3+label_width))
            for ((i=0;i<${#UI_VALUES[@]};i++)); do
                printf '\033[30;47m'
                if ((label_width)); then at "$((UI_CONTENT_ROW+i))" "$((UI_LEFT+3))" "$label_width" "${UI_LABELS[i]}"; fi
                if ((UI_FOCUS==i)); then printf '\033[30;46m'; else printf '\033[37;40m'; fi
                value=${UI_VALUES[i]}; pos=${UI_POSITIONS[i]}; start=0
                ((pos>=field_width)) && start=$((pos-field_width+1))
                [[ $UI_KIND == passwordbox ]] && value=''
                at "$((UI_CONTENT_ROW+i))" "$field_col" "$field_width" "${value:start:field_width}"
            done
            modal_button "$((UI_LEFT+UI_WIDTH/2-13))" '< OK >' "$((UI_FOCUS==${#UI_VALUES[@]}))"
            modal_button "$((UI_LEFT+UI_WIDTH/2+3))" '< Cancel >' "$((UI_FOCUS==${#UI_VALUES[@]}+1))"
            if ((UI_FOCUS<${#UI_VALUES[@]})); then
                pos=${UI_POSITIONS[UI_FOCUS]}; start=0
                ((pos>=field_width)) && start=$((pos-field_width+1))
                [[ $UI_KIND == passwordbox ]] && pos=0 && start=0
                printf '\033[%s;%sH\033[?25h' "$((UI_CONTENT_ROW+UI_FOCUS))" "$((field_col+pos-start))"
            fi;;
        menu)
            ((UI_SELECTED<UI_SCROLL)) && UI_SCROLL=$UI_SELECTED
            ((UI_SELECTED>=UI_SCROLL+UI_VISIBLE)) && UI_SCROLL=$((UI_SELECTED-UI_VISIBLE+1))
            for ((i=0;i<UI_VISIBLE;i++)); do
                index=$((UI_SCROLL+i)); ((index<${#UI_ITEMS[@]})) || break
                if ((index==UI_SELECTED && UI_FOCUS==0)); then printf '\033[30;46m'; else printf '\033[30;47m'; fi
                at "$((UI_CONTENT_ROW+i))" "$((UI_LEFT+3))" "$((UI_WIDTH-6))" "${UI_ITEMS[index]}"
            done
            modal_button "$((UI_LEFT+UI_WIDTH/2-13))" '< OK >' "$((UI_FOCUS==1))"
            modal_button "$((UI_LEFT+UI_WIDTH/2+3))" '< Cancel >' "$((UI_FOCUS==2))";;
        yesno)
            modal_button "$((UI_LEFT+UI_WIDTH/2-13))" '< Yes >' "$((UI_FOCUS==0))"
            modal_button "$((UI_LEFT+UI_WIDTH/2+3))" '< No >' "$((UI_FOCUS==1))";;
        *) modal_button "$((UI_LEFT+UI_WIDTH/2-5))" "< $UI_CLOSE_LABEL >" 1;;
    esac
    printf '\033[30;47m'
    case $UI_KIND in
        inputbox|passwordbox|form)
            at "$((UI_TOP+UI_HEIGHT-3))" "$((UI_LEFT+3))" "$((UI_WIDTH-6))" 'Tab: next | Ctrl+U: clear | Enter: OK | Esc: cancel';;
        menu)
            at "$((UI_TOP+UI_HEIGHT-3))" "$((UI_LEFT+3))" "$((UI_WIDTH-6))" 'Up/Down: select | Tab: buttons | Enter: OK | Esc: cancel';;
        *) at "$((UI_TOP+UI_HEIGHT-3))" "$((UI_LEFT+3))" "$((UI_WIDTH-6))" 'Up/Down: scroll | Enter: select | Esc: cancel';;
    esac
}

# ------------------------------------
# Native popup input and widget dispatch
# ------------------------------------
modal_edit_key() {
    local value=${UI_VALUES[UI_FOCUS]} pos=${UI_POSITIONS[UI_FOCUS]}
    # ------------------------------------
    # Insert/delete at the cursor without eval, Readline, or a child process.
    # Password input goes through the same editor but is never drawn or logged.
    # ------------------------------------
    case $KEY in
        left) ((pos>0)) && ((pos-=1));;
        right) ((pos<${#value})) && ((pos+=1));;
        home) pos=0;; end) pos=${#value};;
        $'\177'|$'\b') if ((pos>0)); then value=${value:0:pos-1}${value:pos}; ((pos-=1)); fi;;
        delete) value=${value:0:pos}${value:pos+1};;
        $'\025') value=''; pos=0;;
        *) if [[ ${#KEY} == 1 && $KEY != *[[:cntrl:]]* ]] && ((${#value}<UI_LIMITS[UI_FOCUS])); then
               value=${value:0:pos}$KEY${value:pos}; ((pos+=1))
           fi;;
    esac
    UI_VALUES[UI_FOCUS]=$value; UI_POSITIONS[UI_FOCUS]=$pos
    return 0
}
native_dialog() {
    local UI_KIND='' UI_TITLE='[ simba ]' UI_TEXT='' UI_CLOSE_LABEL=Close default_item=''
    local UI_REQUEST_HEIGHT=16 UI_REQUEST_WIDTH=76 UI_ROWS=0 UI_COLS=0 UI_WIDTH UI_HEIGHT UI_TOP UI_LEFT
    local UI_BUTTON_ROW UI_CONTENT_ROW UI_PROMPT_ROWS UI_VISIBLE
    local UI_FOCUS=0 UI_SELECTED=0 UI_SCROLL=0 rc=0 accepted=0 frame i limit
    local -a UI_LINES=() UI_VALUES=() UI_LABELS=() UI_LIMITS=() UI_POSITIONS=() UI_TAGS=() UI_ITEMS=()
    # ------------------------------------
    # Accept the small widget vocabulary used by simba's existing callers.
    # Requested form coordinates are intentionally ignored: this renderer lays
    # out fields relative to the popup, keeping it centered after a resize.
    # ------------------------------------
    while (($#)); do
        case $1 in
            --stdout|--no-collapse) shift;;
            --title) UI_TITLE=$2; shift 2;;
            --default-item) default_item=$2; shift 2;;
            --exit-label) UI_CLOSE_LABEL=$2; shift 2;;
            --defaultno) UI_FOCUS=1; shift;;
            --inputbox|--passwordbox)
                UI_KIND=${1#--}; UI_TEXT=$2; UI_REQUEST_HEIGHT=$3; UI_REQUEST_WIDTH=$4
                shift 4; UI_VALUES+=("${1:-}"); UI_LABELS+=(''); UI_LIMITS+=(1024)
                (($#)) && shift;;
            --form)
                UI_KIND=form; UI_TEXT=$2; UI_REQUEST_HEIGHT=$3; UI_REQUEST_WIDTH=$4; shift 5
                while (($#>=8)); do
                    UI_LABELS+=("$1"); UI_VALUES+=("$4"); limit=$8
                    ((limit>0)) || limit=160
                    UI_LIMITS+=("$limit"); shift 8
                done;;
            --menu)
                UI_KIND=menu; UI_TEXT=$2; UI_REQUEST_HEIGHT=$3; UI_REQUEST_WIDTH=$4; shift 5
                while (($#>=2)); do UI_TAGS+=("$1"); UI_ITEMS+=("$2"); shift 2; done;;
            --textbox)
                UI_KIND=textbox; UI_REQUEST_HEIGHT=$3; UI_REQUEST_WIDTH=$4
                [[ -r $2 ]] || return 2
                UI_TEXT=$(<"$2"); shift 4;;
            --msgbox|--yesno)
                UI_KIND=${1#--}; UI_TEXT=$2; UI_REQUEST_HEIGHT=$3; UI_REQUEST_WIDTH=$4; shift 4;;
            *) printf 'Unsupported popup option: %s\n' "$1" >&2; return 2;;
        esac
    done
    [[ -n $UI_KIND ]] || return 2
    # ------------------------------------
    # A deletion confirmation starts on No to avoid accidental acceptance.
    # ------------------------------------
    [[ $UI_KIND == yesno ]] && UI_FOCUS=1
    for ((i=0;i<${#UI_VALUES[@]};i++)); do UI_POSITIONS+=("${#UI_VALUES[i]}"); done
    for ((i=0;i<${#UI_TAGS[@]};i++)); do [[ ${UI_TAGS[i]} == "$default_item" ]] && UI_SELECTED=$i; done
    while :; do
        if ! modal_geometry; then
            if ! read_key || [[ $KEY == escape ]]; then rc=255; break; fi
            continue
        fi
        # ------------------------------------
        # Keep viewport state in this parent scope. modal_frame is captured in
        # a subshell, so changes made only inside that renderer would be lost.
        # ------------------------------------
        if [[ $UI_KIND == menu ]]; then
            ((UI_SELECTED<UI_SCROLL)) && UI_SCROLL=$UI_SELECTED
            ((UI_SELECTED>=UI_SCROLL+UI_VISIBLE)) && UI_SCROLL=$((UI_SELECTED-UI_VISIBLE+1))
        fi
        frame=$(modal_frame); printf '%s' "$frame" >&2
        if ! read_key; then rc=1; break; fi
        [[ $KEY == escape ]] && { rc=255; break; }
        case $UI_KIND in
            inputbox|passwordbox|form)
                case $KEY in
                    tab) UI_FOCUS=$(((UI_FOCUS+1)%(${#UI_VALUES[@]}+2)));;
                    up) UI_FOCUS=$(((UI_FOCUS+${#UI_VALUES[@]}+1)%(${#UI_VALUES[@]}+2)));;
                    down) UI_FOCUS=$(((UI_FOCUS+1)%(${#UI_VALUES[@]}+2)));;
                    enter) if ((UI_FOCUS==${#UI_VALUES[@]}+1)); then rc=1; else accepted=1; fi; break;;
                    *) if ((UI_FOCUS<${#UI_VALUES[@]})); then modal_edit_key; fi;;
                esac;;
            menu)
                case $KEY in
                    tab) UI_FOCUS=$(((UI_FOCUS+1)%3));;
                    up) ((UI_SELECTED>0)) && ((UI_SELECTED-=1));;
                    down) ((UI_SELECTED+1<${#UI_ITEMS[@]})) && ((UI_SELECTED+=1));;
                    home) UI_SELECTED=0;; end) UI_SELECTED=$((${#UI_ITEMS[@]}-1));;
                    pageup) UI_SELECTED=$((UI_SELECTED>UI_VISIBLE ? UI_SELECTED-UI_VISIBLE : 0));;
                    pagedown) UI_SELECTED=$((UI_SELECTED+UI_VISIBLE)); ((UI_SELECTED<${#UI_ITEMS[@]})) || UI_SELECTED=$((${#UI_ITEMS[@]}-1));;
                    enter) if ((UI_FOCUS==2)); then rc=1; else accepted=1; fi; break;;
                esac;;
            yesno)
                case $KEY in
                    y|Y) accepted=1; break;; n|N) rc=1; break;;
                    tab|left|right) UI_FOCUS=$((1-UI_FOCUS));;
                    enter) if ((UI_FOCUS==0)); then accepted=1; else rc=1; fi; break;;
                    up) ((UI_SCROLL>0)) && ((UI_SCROLL-=1));;
                    down) ((UI_SCROLL+UI_HEIGHT-5<${#UI_LINES[@]})) && ((UI_SCROLL+=1));;
                esac;;
            *)
                case $KEY in
                    enter) accepted=1; break;;
                    up) ((UI_SCROLL>0)) && ((UI_SCROLL-=1));;
                    down) ((UI_SCROLL+UI_HEIGHT-5<${#UI_LINES[@]})) && ((UI_SCROLL+=1));;
                    home|g) UI_SCROLL=0;; end|G) UI_SCROLL=$((${#UI_LINES[@]}-UI_HEIGHT+5));;
                    pageup) UI_SCROLL=$((UI_SCROLL-UI_HEIGHT+5));;
                    pagedown) UI_SCROLL=$((UI_SCROLL+UI_HEIGHT-5));;
                esac
                ((UI_SCROLL<0)) && UI_SCROLL=0
                limit=$((${#UI_LINES[@]}-UI_HEIGHT+5)); ((limit<0)) && limit=0
                ((UI_SCROLL>limit)) && UI_SCROLL=$limit;;
        esac
    done
    printf '\033[?25l' >&2
    draw >&2
    if ((accepted)); then
        case $UI_KIND in
            inputbox|passwordbox) printf '%s' "${UI_VALUES[0]}";;
            form) printf '%s\n' "${UI_VALUES[@]}";;
            menu) printf '%s' "${UI_TAGS[UI_SELECTED]}";;
        esac
    fi
    return "$rc"
}
write_dialog_theme() {
    printf '%s\n' 'use_colors = ON' 'use_shadow = ON' \
        'screen_color = (CYAN,BLUE,ON)' 'dialog_color = (BLACK,WHITE,OFF)' \
        'title_color = (BLUE,WHITE,ON)' 'border_color = (WHITE,WHITE,ON)' \
        'menubox_color = (BLACK,WHITE,OFF)' 'item_color = (BLACK,WHITE,OFF)' \
        'item_selected_color = (BLACK,CYAN,OFF)' \
        'button_active_color = (WHITE,BLUE,ON)' > "$RUN_DIR/dialogrc"
}
info() { dlg --title '[ Information ]' --msgbox "$1" 13 72; }
error() { STATUS=$1; task_finish failed; dlg --title '[ Error ]' --msgbox "$1" 15 74; }
ask() { dlg --stdout --title "[ $1 ]" --inputbox "$2" 10 72 "${3:-}"; }

# ------------------------------------
# Bottom task status and progress bar
# ------------------------------------
task_begin() {
    TASK_LABEL=$1; TASK_TOTAL=${2:-0}; TASK_DONE=0; TASK_TICK=0
    TASK_STATE=working
    progress_draw
}
task_step() {
    TASK_DONE=$1
    [[ -n ${2:-} ]] && STATUS=$2
    progress_draw
    return 0
}
task_finish() {
    TASK_STATE=${1:-done}
    [[ $TASK_STATE == done ]] && TASK_DONE=$TASK_TOTAL
    progress_draw
    return 0
}
task_cancel() { STATUS=${1:-'Task cancelled.'}; task_finish cancelled; }
task_progress_line() {
    local width=$1 bar_width percent=0 filled=0 bar='' suffix ch i position
    local -a spinner=('|' '/' '-' '\')
    bar_width=$((width-59)); ((bar_width>36)) && bar_width=36
    ((bar_width<10)) && bar_width=10
    if [[ $TASK_STATE == done ]]; then
        filled=$bar_width; suffix='100% complete'
    elif ((TASK_TOTAL>0)); then
        percent=$((TASK_DONE*100/TASK_TOTAL))
        ((percent>100)) && percent=100
        filled=$((percent*bar_width/100))
        suffix="$percent% ($TASK_DONE/$TASK_TOTAL)"
        [[ $TASK_STATE == working ]] && suffix+=" ${spinner[TASK_TICK%4]}"
    else
        suffix=$TASK_STATE
        [[ $TASK_STATE == working ]] && suffix="waiting ${spinner[TASK_TICK%4]}"
    fi
    # ------------------------------------
    # Real counts drive percentages. Unknown-duration commands show a moving
    # segment instead of a made-up percent that stalls near completion.
    # ------------------------------------
    position=$((TASK_TICK%(bar_width-3)))
    for ((i=0;i<bar_width;i++)); do
        ch='-'
        if [[ $TASK_STATE == working && $TASK_TOTAL == 0 ]]; then
            ((i>=position && i<position+4)) && ch='#'
        elif ((i<filled)); then ch='#'; fi
        bar+=$ch
    done
    case $TASK_STATE in failed|cancelled) suffix=$TASK_STATE;; esac
    printf 'Task: %-24.24s [%s] %s' "$TASK_LABEL" "$bar" "$suffix"
}
progress_draw() {
    if ((PREFETCH_ACTIVE)); then startup_progress_draw; return 0; fi
    # ------------------------------------
    # Partial redraws keep long operations responsive without repainting the
    # drive list or re-running mount checks every animation tick.
    # ------------------------------------
    ((ACTIVE)) && [[ -t 1 ]] || return 0
    local rows cols
    read -r rows cols < <(stty size)
    ((rows>=24 && cols>=100)) || return 0
    printf '\033[37;44m'
    at "$((rows-2))" 2 "$((cols-2))" "Status: $STATUS"
    printf '\033[37;40m'
    at "$((rows-1))" 1 "$cols" "$(task_progress_line "$cols")"
    printf '\033[37;44m'
}
run_with_progress() {
    local output=$1 errors=$2 rc=0
    shift 2
    # ------------------------------------
    # Save stdout/stderr separately so animation never pollutes parsed SMB/DNS
    # output. No passwords are included in the status text or logs.
    # Close stdin only for the worker. The parent still needs its terminal
    # input descriptor for stty and progress sizing while the command runs.
    # ------------------------------------
    "$@" </dev/null >"$output" 2>"$errors" &
    TASK_PID=$!
    while kill -0 "$TASK_PID" 2>/dev/null; do
        ((TASK_TICK+=1)); progress_draw
        sleep 0.12
    done
    if wait "$TASK_PID"; then rc=0; else rc=$?; fi
    TASK_PID=''
    return "$rc"
}
task_invoke() {
    local label=$1 rc=0; shift
    STATUS=$label; task_begin "$label"
    if "$@"; then rc=0; else rc=$?; fi
    # ------------------------------------
    # Specific errors and cancellations set their state in the task itself.
    # ------------------------------------
    if [[ $TASK_STATE == working ]]; then
        if ((rc==0)); then task_finish done; else task_finish failed; fi
    fi
    return 0
}

# ------------------------------------
# Validate profile fields
# ------------------------------------
# Profiles are plain data: one field per line. Never source/eval saved settings.
valid_id() { [[ $1 =~ ^[a-zA-Z0-9][a-zA-Z0-9_-]{0,39}$ ]]; }
valid_text() { [[ -n $1 && $1 != *[[:cntrl:]]* && ${#1} -le 160 ]]; }
valid_server() { [[ $1 =~ ^[a-zA-Z0-9][a-zA-Z0-9.-]*$ && ${#1} -le 253 ]]; }
valid_share() { valid_text "$1" && [[ $1 != *[\\/,]* && $1 != '.' && $1 != '..' ]]; }

# ------------------------------------
# Domain discovery through DNS
# ------------------------------------
# DNS discovery starts with suffix hints; it does not probe address ranges.
# A DNS suffix alone is NOT proof of an Active Directory domain.
valid_dns_name() {
    local label
    [[ ${#1} -le 253 && $1 == *.* && $1 != *[!a-zA-Z0-9.-]* ]] || return 1
    local -a labels; IFS=. read -r -a labels <<< "$1"
    # ------------------------------------
    # Validate each dot-separated label; an allowed character alone is not
    # enough because labels also have length and leading-hyphen restrictions.
    # ------------------------------------
    for label in "${labels[@]}"; do
        [[ ${#label} -ge 1 && ${#label} -le 63 && $label != -* && $label != *- ]] || return 1
    done
    [[ $1 != *. ]]
}
normalize_suffixes() {
    local word
    # ------------------------------------
    # Remove VPN routing markers and normalize repeated DNS suffixes.
    # ------------------------------------
    while read -r word; do
        word=${word#\~}; word=${word%.}; word=${word,,} # Strip ~, trailing dot; lowercase.
        valid_dns_name "$word" && printf '%s\n' "$word"
    done | sort -u | head -n 24 # Deduplicate hints and bound the number of DNS lookups.
}
dns_candidates() {
    {
        # ------------------------------------
        # resolved includes per-link VPN routing domains, such as ~corp.local.
        # ------------------------------------
        if command -v resolvectl >/dev/null; then
            timeout 3 resolvectl domain 2>/dev/null | awk -F': ' '{print $2}' | tr ' ' '\n'
        fi
        if command -v nmcli >/dev/null; then
            timeout 3 nmcli -g IP4.DOMAIN,IP6.DOMAIN device show 2>/dev/null | tr ', ' '\n\n'
        fi
        awk '$1=="search" || $1=="domain" {for(i=2;i<=NF;i++) {if($i ~ /^#/) break; print $i}}' /etc/resolv.conf
        printf '%s\n' "$DISCOVERED_DOMAIN"
        if ((${#DOMAINS[@]})); then printf '%s\n' "${DOMAINS[@]}"; fi
    } | normalize_suffixes
}
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
scan_candidates() {
    local domain controllers count processed=0
    local -a domains_to_check=()
    # ------------------------------------
    # Keep only candidates with domain-controller records returned by DNS.
    # ------------------------------------
    FOUND_DOMAINS=(); FOUND_CONTROLLERS=(); FOUND_COUNTS=()
    while read -r domain; do
        valid_dns_name "$domain" && domains_to_check+=("$domain")
    done
    task_begin 'Checking DNS domains' "${#domains_to_check[@]}"
    ((ACTIVE)) && draw
    for domain in "${domains_to_check[@]}"; do
        STATUS="Checking domain $((processed+1))/${#domains_to_check[@]}: $domain"
        run_with_progress "$RUN_DIR/dns-output" "$RUN_DIR/dns-error" query_controllers "$domain" || :
        controllers=$(<"$RUN_DIR/dns-output")
        ((processed+=1)); task_step "$processed"
        [[ -n $controllers ]] || continue
        count=$(printf '%s\n' "$controllers" | wc -l)
        FOUND_DOMAINS+=("$domain"); FOUND_CONTROLLERS+=("$controllers"); FOUND_COUNTS+=("$count")
    done
    STATUS="Checked $processed DNS candidates; found ${#FOUND_DOMAINS[@]} domains."
    DOMAIN_CACHE_READY=1
    task_finish done
}
refresh_domain_cache() {
    STATUS='Reading network and VPN DNS suffixes...'
    task_begin 'Reading DNS settings'
    ((ACTIVE)) && draw
    run_with_progress "$RUN_DIR/dns-candidates" "$RUN_DIR/dns-error" dns_candidates || :
    scan_candidates < "$RUN_DIR/dns-candidates"
}
discover_domains() {
    local choice manual i
    command -v dig >/dev/null || { error 'Domain discovery requires dig. Install it with: sudo apt install dnsutils'; return; }
    # ------------------------------------
    # Startup already populated this list. Reuse it until the user asks for a
    # rescan; this avoids repeating slow DNS requests when opening the menu.
    # ------------------------------------
    if ((DOMAIN_CACHE_READY==0)); then refresh_domain_cache; fi
    while :; do
        local -a entries=()
        for ((i=0;i<${#FOUND_DOMAINS[@]};i++)); do
            entries+=("$i" "${FOUND_DOMAINS[i]} (${FOUND_COUNTS[i]} DC DNS records)")
        done
        entries+=(manual 'Look up a domain by name')
        entries+=(rescan 'Rescan current network and VPN DNS')
        choice=$(dlg --stdout --title '[ Discover Windows domain ]' --menu \
            'Select a domain to prefill new drive profiles.\nResults come from DNS records; controller identity and login are not verified.\nNo result? Connect LAN/VPN, check office DNS, or enter the DNS domain.\nA domain controller is not necessarily your file server.' 19 80 7 "${entries[@]}") || {
                task_cancel 'Domain discovery closed.'; return;
            }
        if [[ $choice == rescan ]]; then refresh_domain_cache; continue; fi
        if [[ $choice == manual ]]; then
            manual=$(ask 'DNS domain lookup' 'Enter the full DNS domain name, such as corp.example.local:') || continue
            manual=${manual%.}; manual=${manual,,}
            valid_dns_name "$manual" || { error 'Enter a DNS domain with valid labels, such as corp.example.local. A short name alone is not enough.'; continue; }
            scan_candidates <<< "$manual"
            ((${#FOUND_DOMAINS[@]})) || info 'No AD domain controller SRV records were returned.\nCheck the domain spelling, LAN/VPN connection and DNS settings.\nThis does not prove that the domain does not exist.'
            continue
        fi
        [[ $choice =~ ^[0-9]+$ ]] && ((choice < ${#FOUND_DOMAINS[@]})) || continue
        DISCOVERED_DOMAIN=${FOUND_DOMAINS[choice]}
        STATUS="Selected domain: $DISCOVERED_DOMAIN. Press A to add a drive."
        task_finish done
        info "Selected DNS domain: $DISCOVERED_DOMAIN\n\nDomain controllers advertised by DNS:\n${FOUND_CONTROLLERS[choice]}\n\nNew drive profiles will use this domain. Enter your actual file server separately."
        return
    done
}

# ------------------------------------
# Browse and select Windows shares
# ------------------------------------
# smbclient -g produces TYPE|NAME|COMMENT records. Only disk shares become
# mount profiles; printers, IPC services and workgroup records are ignored.
parse_share_list() {
    local kind share comment
    local -A seen=()
    BROWSED_SHARES=(); BROWSED_COMMENTS=()
    # ------------------------------------
    # Setting IFS only for read preserves spaces inside a share's name.
    # ------------------------------------
    while IFS='|' read -r kind share comment; do
        [[ $kind == Disk ]] && valid_share "$share" || continue
        # ------------------------------------
        # +present tests whether the associative-array key exists. This skips
        # duplicate records without sorting away the server's listing order.
        # ------------------------------------
        [[ -z ${seen[$share]+present} ]] || continue
        seen[$share]=1
        comment=${comment//[[:cntrl:]]/ } # Prevent control codes from moving the cursor.
        comment=${comment//\\/\/}
        [[ $share == *\$ ]] && comment="[hidden/admin share] $comment"
        BROWSED_SHARES+=("$share"); BROWSED_COMMENTS+=("${comment:0:120}")
    done
}
browse_shares() {
    command -v smbclient >/dev/null || {
        error 'Share browsing requires smbclient. Install it with: sudo apt install smbclient'; return;
    }
    local server='' domain=$DISCOVERED_DOMAIN user='' data secret credentials result rc
    if [[ $PANEL == shares && -n $BROWSE_SERVER ]]; then
        server=$BROWSE_SERVER; domain=$BROWSE_DOMAIN; user=$BROWSE_USER
    elif ((${#IDS[@]})); then
        server=${SERVERS[SELECTED]}; user=${USERS[SELECTED]}
        [[ -n $domain ]] || domain=${DOMAINS[SELECTED]}
    fi
    data=$(dlg --stdout --title '[ Browse Windows shares ]' --form \
        'Enter the actual file server, not just the domain controller.\nFor a local Windows account, use the computer name as Domain.\nBrowsing one server does not find all storage across the domain.' 17 78 3 \
        'Server / FQDN' 1 1 "$server" 1 18 52 253 \
        'Domain' 2 1 "$domain" 2 18 52 160 \
        'Username' 3 1 "$user" 3 18 52 160) || { task_cancel 'Share browsing cancelled.'; return; }
    # ------------------------------------
    # dialog returns one field per line. mapfile keeps embedded spaces intact;
    # the field count also distinguishes incomplete form output from a profile.
    # ------------------------------------
    local -a fields; mapfile -t fields <<< "$data"
    ((${#fields[@]} == 3)) || { error 'Enter a server, domain and username.'; return; }
    server=${fields[0]}; domain=${fields[1]}; user=${fields[2]}
    valid_server "$server" && valid_text "$domain" && valid_text "$user" || {
        error 'Enter a valid hostname or IPv4 address and fill the domain and username fields.'; return;
    }
    secret=$(dlg --stdout --title '[ Windows domain password ]' --passwordbox \
        "Password for $domain\\$user\nList shared folders on $server. No administrator password is needed." \
        11 74) || { task_cancel 'Share browsing cancelled.'; return; }
    [[ -n $secret && $secret != *[[:cntrl:]]* ]] || {
        unset secret; error 'An empty password or control characters are not supported.'; return;
    }
    # ------------------------------------
    # umask 077 and mktemp restrict the credential file to the current user.
    # Rejecting line breaks above prevents injecting extra credential fields.
    # ------------------------------------
    credentials=$(mktemp "$RUN_DIR/browse-auth.XXXXXXXX") || {
        unset secret; error 'Cannot prepare temporary credentials.'; return;
    }
    if ! printf 'username=%s\npassword=%s\ndomain=%s\n' "$user" "$secret" "$domain" > "$credentials"; then
        unset secret; rm -f -- "$credentials"; error 'Cannot write temporary credentials.'; return
    fi
    unset secret
    STATUS="Listing shared folders on $server..."; draw
    rc=0 # Preserve the failing command's status instead of losing it in !.
    # ------------------------------------
    # No password on the command line, no anonymous retry, no SMB1 downgrade.
    # A hard timeout prevents an unreachable server from leaving the UI waiting.
    # -A reads the private credential file. SMB3 plus encrypt prevents a silent
    # downgrade. Kerberos is disabled here because this flow uses a password,
    # rather than an existing ticket cache. stdin is closed to prevent prompts.
    # ------------------------------------
    run_with_progress "$RUN_DIR/browse-output" "$RUN_DIR/browse-error" \
        timeout --kill-after=2 25 smbclient -g -L "$server" \
        -A "$credentials" --client-protection=encrypt -m SMB3 \
        --option='client min protocol=SMB3' --use-kerberos=off -t 8 || rc=$?
    result=$(<"$RUN_DIR/browse-output")
    rm -f -- "$credentials" # Delete the temporary password after success or failure.
    if ((rc != 0)); then
        if ((rc == 124 || rc == 137)); then # timeout expired, or its kill grace period ended.
            error 'Share browsing timed out. Check the server name, LAN/VPN connection and DNS.'
        else
            # ------------------------------------
            # smbclient may send login errors to stdout instead of stderr.
            # ------------------------------------
            error "Share browsing failed. Check credentials, server permissions and SMB3 encryption support.\n\n${result:0:800}\n$(head -c 800 "$RUN_DIR/browse-error")"
        fi
        return
    fi
    parse_share_list <<< "$result"
    # ------------------------------------
    # Keep the source account with the list so each selected share is saved
    # against the server that returned it, even after changing the left pane.
    # ------------------------------------
    BROWSE_SERVER=$server; BROWSE_DOMAIN=$domain; BROWSE_USER=$user
    SHARE_SELECTED=0; SHARE_OFFSET=0; PANEL=shares
    ((${#BROWSED_SHARES[@]})) || {
        info 'The server returned no supported disk shares. Enumeration may be restricted, or shares may be hidden. You can still use A to enter a known share manually.'
        STATUS="No disk shares returned by $server."; return;
    }
    STATUS="Listed ${#BROWSED_SHARES[@]} disk shares on $server. Select one, then Enter to save a profile."
}
save_share_profile() {
    # ------------------------------------
    # A share becomes a saved profile only after the user reviews its settings.
    # ------------------------------------
    SAVED_ID=''
    ((${#BROWSED_SHARES[@]})) || { info 'Press B to browse shares first.'; task_cancel 'No share selected.'; return 1; }
    edit_profile add "$BROWSE_SERVER" "${BROWSED_SHARES[SHARE_SELECTED]}" "$BROWSE_DOMAIN" "$BROWSE_USER"
    [[ -n $SAVED_ID ]] || return 1
    PANEL=drives
}
# ------------------------------------
# Load saved profiles and mount status
# ------------------------------------
load_profiles() {
    local f fields processed=0 show_progress=0
    local -a profile_files=()
    for f in "$CONFIG_DIR"/*.drive; do
        [[ -f $f && ! -L $f && -O $f ]] && profile_files+=("$f")
    done
    if ((ACTIVE || PREFETCH_ACTIVE)) && [[ $TASK_LABEL == 'Refreshing profiles' || $TASK_LABEL == 'Loading profiles' ]]; then
        show_progress=1; task_begin 'Loading profiles' "${#profile_files[@]}"
    fi
    IDS=(); NAMES=(); SERVERS=(); SHARES=(); DOMAINS=(); USERS=(); DIALECTS=()
    # ------------------------------------
    # Read owned profile files as data; ignore malformed or linked files.
    # ------------------------------------
    for f in "${profile_files[@]}"; do
        # ------------------------------------
        # Count inspected files, including ones rejected by validation below.
        # ------------------------------------
        if ((show_progress)); then task_step "$processed" "Reading profile $((processed+1))/${#profile_files[@]}"; fi
        ((processed+=1))
        mapfile -t fields < "$f"
        ((${#fields[@]} == 7)) || continue
        valid_id "${fields[0]}" && valid_text "${fields[1]}" &&
            valid_server "${fields[2]}" && valid_share "${fields[3]}" &&
            valid_text "${fields[4]}" && valid_text "${fields[5]}" || continue
        [[ ${fields[6]} == 3.1.1 || ${fields[6]} == 3.0 ]] || continue
        IDS+=("${fields[0]}"); NAMES+=("${fields[1]}")
        SERVERS+=("${fields[2]}"); SHARES+=("${fields[3]}")
        DOMAINS+=("${fields[4]}"); USERS+=("${fields[5]}"); DIALECTS+=("${fields[6]}")
    done
    (( SELECTED < ${#IDS[@]} )) || SELECTED=$((${#IDS[@]}-1))
    (( SELECTED >= 0 )) || SELECTED=0
    if ((show_progress)); then STATUS="Loaded ${#IDS[@]} saved profiles."; task_finish done; fi
    return 0
}
target() { printf '%s/%s' "$DRIVE_ROOT" "${IDS[SELECTED]}"; }
mounted() { findmnt -rn -M "$1" >/dev/null 2>&1; }
matches_profile() {
    local kind source
    kind=$(findmnt -rn -M "$1" -o FSTYPE)
    # ------------------------------------
    # --raw avoids escaped spaces in SOURCE. Compare the exact mountpoint's
    # source, so a similarly named parent mount cannot pass this check.
    # ------------------------------------
    source=$(findmnt -rn -M "$1" -o SOURCE --raw)
    [[ $kind == cifs && $source == "//${SERVERS[SELECTED]}/${SHARES[SELECTED]}" ]]
}
require_selection() { ((${#IDS[@]})) || { info 'Add a drive first using A.'; task_cancel 'No saved drive selected.'; return 1; }; }

# ------------------------------------
# Draw the two-panel Commander screen
# ------------------------------------
draw() {
    local dims rows cols visible frame
    dims=$(stty size); read -r rows cols <<< "$dims"
    if (( rows < 24 || cols < 100 )); then
        printf '\033[37;44m\033[H\033[2J'
        ((cols > 3)) && at 2 2 "$((cols-3))" 'Resize to at least 100 columns x 24 rows. Q quits.'
        return
    fi
    # ------------------------------------
    # Keep both panel selections inside their independent scrolling windows.
    # ------------------------------------
    visible=$((rows-16)) # Reserve rows for titles, headers, summaries and status bars.
    ((SELECTED < OFFSET)) && OFFSET=$SELECTED
    ((SELECTED >= OFFSET+visible)) && OFFSET=$((SELECTED-visible+1))
    ((SHARE_SELECTED < SHARE_OFFSET)) && SHARE_OFFSET=$SHARE_SELECTED
    ((SHARE_SELECTED >= SHARE_OFFSET+visible)) && SHARE_OFFSET=$((SHARE_SELECTED-visible+1))
    # ------------------------------------
    # Compose the complete frame before emitting it. No per-key screen clear.
    # Rendering runs in a subshell, so scrolling offsets must be updated above.
    # ------------------------------------
    frame=$(draw_frame "$rows" "$cols" "$visible")
    printf '%s' "$frame"
}
draw_frame() {
    local rows=$1 cols=$2 visible=$3 left right height sep i idx p state text mounted_count=0
    left=$((cols/2)); right=$((left+1)); height=$((rows-8)); sep=$((rows-9))
    local name_width=$((left-23))
    printf '\033[37;44m\033[H'
    for ((i=1;i<=rows;i++)); do at "$i" 1 "$cols" ''; done
    printf '\033[30;46m'
    at 1 1 "$cols" '  A Add drive     B Browse shares     G Discover domains     H Help     Q Quit'
    printf '\033[37;44m'
    at 2 3 "$((cols-4))" "simba  $VERSION                            Teo Espero"
    local left_title='SAVED DRIVES' right_title=${BROWSE_SERVER:-SERVER SHARES}
    [[ $PANEL == drives ]] && left_title='SAVED DRIVES [active]'
    [[ $PANEL == shares ]] && right_title="$right_title [active]"
    box 4 1 "$height" "$left" "$left_title"
    box 4 "$right" "$height" "$((cols-left))" "$right_title"
    at 5 3 "$name_width" 'Drive name'
    at 5 "$((name_width+4))" 10 'State'
    at 5 "$((left-8))" 7 'SMB'
    at 5 "$((right+2))" "$name_width" 'Share name'
    at 5 "$((cols-10))" 8 'Type'
    divider 6 1 "$left"
    divider 6 "$right" "$((cols-left))"
    for ((i=0;i<${#IDS[@]};i++)); do
        p="$DRIVE_ROOT/${IDS[i]}"; state=Offline
        # ------------------------------------
        # Use the prefetched snapshot while drawing; connect/disconnect and R
        # update it. Actual mount operations still verify the real mountpoint.
        # ------------------------------------
        if ((MOUNT_CACHE_READY)) && [[ -n ${MOUNT_STATES[${IDS[i]}]+present} ]]; then
            if [[ ${MOUNT_STATES[${IDS[i]}]} == 1 ]]; then state=Mounted; ((mounted_count+=1)); fi
        elif mounted "$p"; then state=Mounted; ((mounted_count+=1)); fi
        idx=$((i-OFFSET)); ((idx>=0 && idx<visible)) || continue # Profile index -> screen row.
        [[ $PANEL == drives && $i == "$SELECTED" ]] && printf '\033[30;46m'
        at "$((7+idx))" 3 "$((left-4))" ''
        at "$((7+idx))" 3 "$name_width" "${NAMES[i]}"
        at "$((7+idx))" "$((name_width+4))" 10 "$state"
        at "$((7+idx))" "$((left-8))" 7 "${DIALECTS[i]}"
        printf '\033[37;44m'
    done
    for ((i=0;i<visible;i++)); do
        idx=$((SHARE_OFFSET+i)); ((idx<${#BROWSED_SHARES[@]})) || break # Screen row -> share index.
        [[ $PANEL == shares && $idx == "$SHARE_SELECTED" ]] && printf '\033[30;46m'
        at "$((7+i))" "$((right+2))" "$((cols-left-4))" ''
        at "$((7+i))" "$((right+2))" "$((cols-left-14))" "${BROWSED_SHARES[idx]}"
        at "$((7+i))" "$((cols-10))" 8 Disk
        printf '\033[37;44m'
    done
    if ((${#IDS[@]}==0)); then at 8 3 "$((left-4))" 'A: add your first drive'; fi
    if ((${#BROWSED_SHARES[@]}==0)); then at 8 "$((right+2))" "$((cols-left-4))" 'B: browse a file server'; fi
    divider "$sep" 1 "$left"
    divider "$sep" "$right" "$((cols-left))"
    at "$((sep+1))" 3 "$((left-4))" "${#IDS[@]} saved drives / $mounted_count mounted"
    text="Domain: ${DISCOVERED_DOMAIN:-G to discover}"
    if ((${#IDS[@]})); then text="Domain: ${DOMAINS[SELECTED]}"; fi
    at "$((sep+2))" 3 "$((left-4))" "$text"
    if ((${#IDS[@]})); then at "$((sep+3))" 3 "$((left-4))" "$(target)"; fi
    at "$((sep+1))" "$((right+2))" "$((cols-left-4))" "${#BROWSED_SHARES[@]} disk shares / Enter saves profile"
    at "$((sep+2))" "$((right+2))" "$((cols-left-4))" "Account: ${BROWSE_DOMAIN:-none}\\$BROWSE_USER"
    if ((${#BROWSED_SHARES[@]})); then
        at "$((sep+3))" "$((right+2))" "$((cols-left-4))" "${BROWSED_COMMENTS[SHARE_SELECTED]}"
    fi
    at "$((rows-3))" 2 "$((cols-2))" 'Tab: switch panel   Up/Down: select   Enter: open/save   O: open   R: refresh'
    at "$((rows-2))" 2 "$((cols-2))" "Status: $STATUS"
    printf '\033[37;40m'
    at "$((rows-1))" 1 "$cols" "$(task_progress_line "$cols")"
    local -a keys=('H Help' 'G Domains' 'B Shares' 'E Edit' 'C Connect' 'D Disconn' 'A Add' 'X Remove' 'Q Quit')
    local key_width=$((cols/9)) col=1 width
    for ((i=0;i<9;i++)); do
        width=$key_width; ((i==8)) && width=$((cols-col+1)) # Last item absorbs leftover columns.
        printf '\033[30;46m'; at "$rows" "$col" "$width" "${keys[i]}"
        ((col+=width))
    done
    printf '\033[37;44m'
}

# ------------------------------------
# Create and edit drive profiles
# ------------------------------------
edit_profile() {
    local mode=$1 id='' name='' server=${2:-} share=${3:-} domain=${4:-$DISCOVERED_DOMAIN} user=${5:-} dialect=3.1.1 data tmp
    SAVED_ID=''
    if [[ $mode == edit ]]; then
        require_selection || return
        mounted "$(target)" && { info 'Disconnect this drive before editing its settings.'; return; }
        id=${IDS[SELECTED]}; name=${NAMES[SELECTED]}; server=${SERVERS[SELECTED]}
        share=${SHARES[SELECTED]}; domain=${DOMAINS[SELECTED]}; user=${USERS[SELECTED]}; dialect=${DIALECTS[SELECTED]}
    else
        local suggested=${share//[^a-zA-Z0-9_-]/_}
        suggested=${suggested:0:40}
        valid_id "$suggested" || suggested=''
        id=$(ask 'Add drive' 'Folder ID (letters, numbers, hyphens, underscores; e.g. Engineering):' "$suggested") || { task_cancel 'Profile creation cancelled.'; return 1; }
        valid_id "$id" || { error 'Invalid folder ID. Start with a letter or number; maximum 40 characters.'; return; }
        [[ ! -e $CONFIG_DIR/$id.drive ]] || { error 'That folder ID already exists.'; return; }
        name=${share:-$id}
    fi
    data=$(dlg --stdout --title '[ Drive settings ]' --form 'Use a server name or IPv4 address. Share name only, without slashes.\nEnter domain and username separately (example: MCWD and tespero).' 20 78 7 \
        'Display name' 1 1 "$name" 1 18 52 160 \
        'Server / FQDN' 2 1 "$server" 2 18 52 253 \
        'Share' 3 1 "$share" 3 18 52 160 \
        'Domain' 4 1 "$domain" 4 18 52 160 \
        'Username' 5 1 "$user" 5 18 52 160) || { task_cancel 'Profile settings cancelled.'; return 1; }
    local -a fields; mapfile -t fields <<< "$data"
    ((${#fields[@]} == 5)) || return
    name=${fields[0]}; server=${fields[1]}; share=${fields[2]}; domain=${fields[3]}; user=${fields[4]}
    valid_text "$name" && valid_server "$server" && valid_share "$share" && valid_text "$domain" && valid_text "$user" || {
        error 'Fill every field. Server must be a hostname or IPv4 address. Share cannot contain a slash, backslash or comma.'; return;
    }
    dialect=$(dlg --stdout --title '[ SMB version ]' --default-item "$dialect" --menu 'Encryption is required for both choices. No SMB1 fallback.' 12 70 2 \
        3.1.1 'Modern Windows servers (default)' 3.0 'Older SMB3 server compatibility') || { task_cancel 'SMB version selection cancelled.'; return 1; }
    # ------------------------------------
    # Save through a temporary file so an interrupted write leaves the old
    # profile intact. No passwords are written to the saved profile.
    # ------------------------------------
    tmp=$(mktemp "$CONFIG_DIR/.profile.XXXXXX") || { error 'Cannot create profile file.'; return; }
    STATUS="Saving profile: $name"; progress_draw
    if printf '%s\n' "$id" "$name" "$server" "$share" "$domain" "$user" "$dialect" > "$tmp" && \
        run_with_progress "$RUN_DIR/save-output" "$RUN_DIR/save-error" mv -f -- "$tmp" "$CONFIG_DIR/$id.drive"; then
        load_profiles; SAVED_ID=$id
        local i
        for ((i=0;i<${#IDS[@]};i++)); do [[ ${IDS[i]} == "$id" ]] && SELECTED=$i; done
        STATUS="Saved $name. C connects the drive."
    else rm -f -- "$tmp"; error 'Could not save drive settings.'; fi
}

# ------------------------------------
# Local administrator authentication
# ------------------------------------
# Linux administrator credentials and Windows credentials are separate prompts.
authorize() {
    sudo -n -v 2>/dev/null && return 0 # Reuse valid authorization without a second prompt.
    local secret attempt
    for attempt in 1 2 3; do
        secret=$(dlg --stdout --title '[ Linux administrator ]' --passwordbox 'Enter your LOCAL Ubuntu sudo password to mount or disconnect a drive.\nThis is separate from your Windows domain password.' 11 74) || { task_cancel 'Administrator prompt cancelled.'; return 1; }
        # ------------------------------------
        # -S reads the local password from stdin; it never appears in arguments.
        # ------------------------------------
        if printf '%s\n' "$secret" | sudo -S -p '' -v 2>"$RUN_DIR/sudo-error"; then
            unset secret; return 0
        fi
        unset secret
        info 'Administrator authentication failed. Try again, or Cancel.'
    done
    error 'Could not obtain administrator permission.'; return 1
}
# ------------------------------------
# Connect and disconnect SMB drives
# ------------------------------------
connect_drive() {
    require_selection || return
    local p secret credentials options
    p=$(target)
    if mounted "$p"; then
        MOUNT_STATES[${IDS[SELECTED]}]=1; STATUS='This drive is already mounted.'
        info 'This folder is already mounted. Disconnect it before connecting again.'; return
    fi
    [[ ! -L $p ]] || { error 'The mount folder is a symbolic link. Use a regular folder.'; return; }
    mkdir -p -- "$p" || { error 'Cannot create the local mount folder.'; return; }
    # ------------------------------------
    # Refuse to hide existing local files beneath a mounted share.
    # ------------------------------------
    if [[ -n $(find "$p" -mindepth 1 -maxdepth 1 -print -quit) ]]; then
        error 'The local mount folder is not empty. Move its local files before connecting.'; return
    fi
    authorize || return
    secret=$(dlg --stdout --title '[ Windows domain password ]' --passwordbox "Password for ${DOMAINS[SELECTED]}\\${USERS[SELECTED]}\nConnecting to //${SERVERS[SELECTED]}/${SHARES[SELECTED]}" 11 74) || { task_cancel 'Connection cancelled.'; return 1; }
    [[ -n $secret && $secret != *[[:cntrl:]]* ]] || { unset secret; error 'An empty password or control characters are not supported.'; return; }
    # ------------------------------------
    # A private per-session credential file keeps passwords out of process args.
    # ------------------------------------
    credentials="$RUN_DIR/credentials"
    if ! printf 'username=%s\npassword=%s\ndomain=%s\n' "${USERS[SELECTED]}" "$secret" "${DOMAINS[SELECTED]}" > "$credentials"; then
        unset secret; error 'Cannot prepare credentials.'; return
    fi
    unset secret
    # ------------------------------------
    # uid/gid and modes present files to this Linux user; the server still
    # enforces Windows permissions. seal requires encryption. nosuid/nodev
    # prevent remote files from gaining local setuid or device-file behavior.
    # ------------------------------------
    options="credentials=$credentials,uid=$(id -u),gid=$(id -g),vers=${DIALECTS[SELECTED]},seal,sec=ntlmssp,nosuid,nodev,file_mode=0600,dir_mode=0700"
    STATUS='Connecting... Waiting for the server.'; draw
    if run_with_progress "$RUN_DIR/mount-output" "$RUN_DIR/mount-error" \
        sudo -n mount -t cifs "//${SERVERS[SELECTED]}/${SHARES[SELECTED]}" "$p" -o "$options"; then
        rm -f -- "$credentials"; MOUNT_STATES[${IDS[SELECTED]}]=1
        STATUS="Connected ${NAMES[SELECTED]}. Press O to open."
    else
        rm -f -- "$credentials"
        error "Connection failed. Check VPN/LAN, DNS, share name, permissions and SMB encryption support.\n\n$(cat "$RUN_DIR/mount-error")"
    fi
}
disconnect_drive() {
    require_selection || return
    local p; p=$(target)
    mounted "$p" || { MOUNT_STATES[${IDS[SELECTED]}]=0; STATUS='This drive is already disconnected.'; return; }
    # ------------------------------------
    # Do not unmount a different source that happens to use this folder.
    # ------------------------------------
    matches_profile "$p" || { error 'The mounted source differs from this profile. Disconnect it manually.'; return; }
    authorize || return
    STATUS='Disconnecting...'; draw
    if run_with_progress "$RUN_DIR/unmount-output" "$RUN_DIR/unmount-error" sudo -n umount -- "$p"; then
        MOUNT_STATES[${IDS[SELECTED]}]=0
        STATUS="Disconnected ${NAMES[SELECTED]}."
    else
        error "Could not disconnect. Close files and terminals using the drive, then retry.\n\n$(cat "$RUN_DIR/unmount-error")"
    fi
}
# ------------------------------------
# Open drives and remove saved profiles
# ------------------------------------
open_drive() {
    require_selection || return
    local p; p=$(target)
    mounted "$p" || { info 'Connect this drive first.'; return; }
    command -v xdg-open >/dev/null || { info "Open this folder manually:\n$p"; return; }
    # ------------------------------------
    # Do not block the UI while the desktop file manager starts.
    # Close the inherited lock descriptor in the child, or the file manager
    # could keep simba's single-instance lock held after simba exits.
    # ------------------------------------
    xdg-open "$p" 9>&- >/dev/null 2>&1 &
    STATUS="Asked your file manager to open ${NAMES[SELECTED]}."
}
remove_drive() {
    require_selection || return
    mounted "$(target)" && { info 'Disconnect this drive before removing its profile.'; return; }
    dlg --title '[ Confirm removal ]' --yesno "Remove the saved profile for ${NAMES[SELECTED]}?\nRemote files and local folders are kept." 10 72 || { task_cancel 'Profile removal cancelled.'; return 1; }
    STATUS="Removing profile: ${NAMES[SELECTED]}"; progress_draw
    if run_with_progress "$RUN_DIR/remove-output" "$RUN_DIR/remove-error" rm -- "$CONFIG_DIR/${IDS[SELECTED]}.drive"; then load_profiles; STATUS='Drive profile removed.'
    else error 'Could not remove the profile.'; fi
}
# ------------------------------------
# Help window
# ------------------------------------
help_screen() {
    local rows cols height width help_file="$RUN_DIR/help.txt"
    read -r rows cols < <(stty size)
    height=$((rows-4)); width=$((cols-6))
    ((height>28)) && height=28
    ((width>84)) && width=84
    # ------------------------------------
    # A long auto-sized msgbox can collapse its text area on shorter terminals.
    # Give textbox explicit dimensions and a real multiline file instead.
    # All lines below are static help text; profile data and passwords are omitted.
    # ------------------------------------
    if ! printf '%s\n' \
        'simba - SMB shares navigator' \
        '' \
        'KEYBOARD' \
        'Tab       Switch between saved drives and server shares.' \
        'Up/Down   Move through the active panel.' \
        'Home/End  Jump to the first or last entry.' \
        'PgUp/PgDn Move through entries one page at a time.' \
        'Enter     Drive: connect/open. Share: review and save a profile.' \
        '' \
        'COMMANDS (uppercase or lowercase)' \
        'G  Discover a domain using network/VPN DNS, or look one up.' \
        'B  Browse disk shares on the file server you enter.' \
        'A  Add a drive profile manually.' \
        'E  Edit the selected saved drive.' \
        'C  Connect. On a share, save its profile first, then connect.' \
        'D  Disconnect the selected saved drive.' \
        'O  Open a connected drive in your file manager.' \
        'X  Remove a saved profile; remote files are kept.' \
        'R  Refresh profiles on the left or re-browse on the right.' \
        'H  Open this Help window.' \
        'Q  Exit simba, clear the screen and display goodbye.' \
        '' \
        'Editing, disconnecting and removing require the left panel.' \
        'No function keys are needed.' \
        'The bottom task bar shows completion or a moving wait indicator.' \
        'Percentages measure counted steps; a network wait has no fixed percent.' \
        'Startup preloads profiles, mount status and DNS domain hints.' \
        'G uses the cached domain list; choose Rescan to update it.' \
        'R in saved drives refreshes both profiles and mount status.' \
        '' \
        'CONNECTIONS' \
        'Connect to the office LAN or VPN before accessing office shares.' \
        'Domain discovery needs internal DNS. DNS records do not verify identity.' \
        'Browsing queries one server, not all storage servers in the domain.' \
        'Listed shares may still deny access. Hidden shares can be omitted.' \
        'SMB3 encryption is required. Passwords are requested each time.' \
        'Mounted means a mount exists, not verified server reachability.' \
        '' \
        'EXIT AND SETTINGS' \
        'Quitting keeps drives mounted. Use D first to disconnect if needed.' \
        'No domain join, /etc/fstab changes or automatic reconnect is performed.' \
        'Profiles: ~/.config/windows-drive-ide' \
        'Mounts:   ~/NetworkDrives/<folder-ID>' \
        '' \
        'HELP NAVIGATION' \
        'Use Up/Down or PgUp/PgDn to scroll. Use Close or Esc to return.' \
        > "$help_file"; then
        error 'Cannot prepare the Help text. Check free space and try again.'
        return 1
    fi
    # ------------------------------------
    # The private session directory and its help file are removed on exit.
    # ------------------------------------
    local rc=0
    dlg --title '[ Help - scroll with arrow keys ]' --exit-label Close \
        --textbox "$help_file" "$height" "$width" || rc=$?
    # ------------------------------------
    # Esc is a normal way to close Help, not a failed task.
    # ------------------------------------
    if ((rc==0 || rc==255)); then STATUS='Help closed.'; return 0; fi
    error 'The Help viewer could not open.'; return 1
}

# ------------------------------------
# Read keys and move panel selections
# ------------------------------------
# Decode navigation keys used by common Linux terminals. Actions use letters;
# function-key escape sequences are consumed and ignored.
decode_key() {
    KEY=$1
    case $KEY in
        $'\e[A'|$'\eOA') KEY=up;; $'\e[B'|$'\eOB') KEY=down;;
        $'\e[C'|$'\eOC') KEY=right;; $'\e[D'|$'\eOD') KEY=left;;
        $'\e[3~') KEY=delete;;
        $'\e[H'|$'\eOH'|$'\e[1~'|$'\e[7~') KEY=home;;
        $'\e[F'|$'\eOF'|$'\e[4~'|$'\e[8~') KEY=end;;
        $'\e[5~') KEY=pageup;; $'\e[6~') KEY=pagedown;;
        $'\t'|$'\e[Z') KEY=tab;;
        ''|$'\r'|$'\n') KEY=enter;;
        $'\e') KEY=escape;;
        $'\e'*) KEY=ignore;;
    esac
}
read_key() {
    local raw char seq=''
    IFS= read -rsn1 raw || return 1
    if [[ $raw == $'\e' ]]; then
        # ------------------------------------
        # Escape may stand alone or begin a multi-byte navigation sequence.
        # Brief timed reads collect its remaining bytes without blocking on Esc.
        # ------------------------------------
        while IFS= read -rsn1 -t 0.08 char; do
            seq+=$char
            # ------------------------------------
            # Final CSI/SS3 byte, or an unsupported Alt-letter combination.
            # ------------------------------------
            [[ ${#seq} -ge 2 && $char == [a-zA-Z~] ]] && break
            [[ ${#seq} -eq 1 && $char != '[' && $char != O ]] && break
            ((${#seq} >= 16)) && break
        done
        raw+=$seq
    fi
    decode_key "$raw"
}
move_selection() {
    local delta=$1 size value
    if [[ $PANEL == drives ]]; then size=${#IDS[@]}; value=$((SELECTED+delta))
    else size=${#BROWSED_SHARES[@]}; value=$((SHARE_SELECTED+delta)); fi
    # ------------------------------------
    # Clamp movement at either end, including when the panel has no entries.
    # ------------------------------------
    ((value>=0)) || value=0
    ((value<size)) || value=$((size-1))
    ((value>=0)) || value=0
    if [[ $PANEL == drives ]]; then SELECTED=$value; else SHARE_SELECTED=$value; fi
}
require_drive_panel() {
    [[ $PANEL == drives ]] || { info 'Press Tab to select the saved drives panel first.'; return 1; }
}
# ------------------------------------
# Dispatch keyboard commands
# ------------------------------------
handle_key() {
    local rows cols
    case $1 in
        # ------------------------------------
        # Exit the main loop; the EXIT trap restores and clears the screen.
        # ------------------------------------
        q|Q) EXIT_REQUESTED=1;;
        tab) if [[ $PANEL == drives ]]; then PANEL=shares; else PANEL=drives; fi;;
        up|k|K) move_selection -1;; down|j|J) move_selection 1;;
        home) move_selection -1000000;; end) move_selection 1000000;;
        pageup|pagedown)
            read -r rows cols < <(stty size)
            rows=$((rows>16 ? rows-16 : 1))
            [[ $1 == pageup ]] && rows=$((-rows))
            move_selection "$rows";;
        a|A) task_invoke 'Adding drive profile' edit_profile add; [[ -n $SAVED_ID ]] && PANEL=drives;;
        e|E) if require_drive_panel; then task_invoke 'Editing drive profile' edit_profile edit; fi;;
        g|G) task_invoke 'Discovering domains' discover_domains;;
        b|B) task_invoke 'Browsing server shares' browse_shares;;
        c|C)
            # ------------------------------------
            # Saving can be cancelled. In that case do not connect an unrelated
            # previously selected drive from the other panel.
            # ------------------------------------
            if [[ $PANEL == shares ]]; then
                task_invoke 'Saving share profile' save_share_profile
                [[ -n $SAVED_ID && $PANEL == drives ]] || return 0
            fi
            task_invoke 'Connecting drive' connect_drive;;
        d|D) if require_drive_panel; then task_invoke 'Disconnecting drive' disconnect_drive; fi;;
        o|O) if require_drive_panel; then task_invoke 'Launching file manager' open_drive; fi;;
        x|X) if require_drive_panel; then task_invoke 'Removing drive profile' remove_drive; fi;;
        h|H) task_invoke 'Opening Help' help_screen;;
        r|R) if [[ $PANEL == shares ]]; then task_invoke 'Refreshing server shares' browse_shares
             else task_invoke 'Refreshing profiles' refresh_saved_state; STATUS='Drive profiles and mount status refreshed.'; fi;;
        enter)
            if [[ $PANEL == shares ]]; then task_invoke 'Saving share profile' save_share_profile
            elif ((${#IDS[@]})) && mounted "$(target)"; then task_invoke 'Launching file manager' open_drive
            else task_invoke 'Connecting drive' connect_drive; fi;;
    esac
    return 0
}

# ------------------------------------
# Check and install missing dependencies
# ------------------------------------
# Bootstrap uses only Bash until the required utilities are present. In
# particular, dependency detection cannot depend on dialog already existing.
command_available() { command -v "$1" >/dev/null 2>&1; }
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
apt_supported() { [[ -r /etc/debian_version ]] && command_available apt-get; }
confirm_dependency_install() {
    local answer
    if command_available dialog; then
        dialog --clear --defaultno --title '[ simba: dependency setup ]' --yesno \
            "Missing commands:\n${MISSING_COMMANDS[*]}\n\nPackages to install:\n${MISSING_PACKAGES[*]}\n\nInstall them now? Your Ubuntu administrator password will be requested.\nThis refreshes package lists and installs only the listed packages and their dependencies." 19 78
    else
        printf '\n=== simba: dependency setup ===\n\nMissing commands:\n  %s\n\nPackages to install:\n  %s\n' \
            "${MISSING_COMMANDS[*]}" "${MISSING_PACKAGES[*]}"
        printf '\nInstall these packages and their dependencies now? [y/N] '
        IFS= read -r answer || return 1
        [[ $answer == y || $answer == Y || $answer == yes || $answer == YES ]]
    fi
}
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
bootstrap_progress() {
    # ------------------------------------
    # Bootstrap may be running before dialog/stty are installed. A plain bar
    # uses Bash alone and measures completed setup phases, not download bytes.
    # ------------------------------------
    local completed=$1 label=$2 bar='' i
    for ((i=0;i<24;i++)); do
        if ((i<completed*8)); then bar+='#'; else bar+='-'; fi
    done
    printf 'Setup phases: [%s] %s/3 - %s\n' "$bar" "$completed" "$label"
}
ensure_dependencies() {
    collect_missing_dependencies
    ((${#MISSING_COMMANDS[@]})) || return 0
    if ! apt_supported; then
        printf 'Missing commands: %s\nAutomatic installation supports Ubuntu/Debian with apt-get.\nInstall the matching packages with your system package manager, then rerun simba.\n' "${MISSING_COMMANDS[*]}" >&2
        return 1
    fi
    if ! command_available sudo; then
        printf 'sudo is missing. Ask an administrator to install sudo and authorize your account.\nRemaining packages: %s\nThen run simba as your normal user.\n' "${MISSING_PACKAGES[*]}" >&2
        return 1
    fi
    confirm_dependency_install || { printf '\nDependency setup cancelled. Run simba again when ready.\n'; return 1; }
    install_dependency_packages || return 1
    # ------------------------------------
    # Verify the commands themselves, rather than trusting apt's exit code alone.
    # ------------------------------------
    printf '\nsimba setup [3/3]: verifying installed commands...\n'
    bootstrap_progress 2 'Verifying commands'
    hash -r # Clear Bash's remembered executable locations before checking again.
    collect_missing_dependencies
    if ((${#MISSING_COMMANDS[@]})); then
        printf '\nCommands still unavailable: %s\nCheck package installation and PATH, then rerun simba.\n' "${MISSING_COMMANDS[*]}" >&2
        return 1
    fi
    printf '\nsimba: all dependencies are available. Starting...\n'
    bootstrap_progress 3 'Setup complete'
}

# ------------------------------------
# Prefetch information in the normal terminal
# ------------------------------------
startup_progress_draw() {
    local rows cols text
    read -r rows cols < <(stty size)
    ((cols>10)) || cols=80
    # ------------------------------------
    # Reuse just two terminal lines. This is not the full-screen interface and
    # does not enter the alternate screen while startup work is in progress.
    # ------------------------------------
    text="Status: $STATUS"; text=${text//[[:cntrl:]]/ }
    printf '\r\033[2K%s\n\033[2K%s\033[1A\r' \
        "${text:0:cols-1}" "$(task_progress_line "$((cols-1))")"
}
refresh_mount_cache() {
    local i mounted_count=0
    MOUNT_STATES=()
    task_begin 'Checking saved mounts' "${#IDS[@]}"
    for ((i=0;i<${#IDS[@]};i++)); do
        STATUS="Checking mount $((i+1))/${#IDS[@]}: ${NAMES[i]}"
        MOUNT_STATES[${IDS[i]}]=0
        if mounted "$DRIVE_ROOT/${IDS[i]}"; then
            MOUNT_STATES[${IDS[i]}]=1; ((mounted_count+=1))
        fi
        task_step "$((i+1))"
    done
    MOUNT_CACHE_READY=1
    STATUS="Found $mounted_count mounted drives among ${#IDS[@]} saved profiles."
    task_finish done
}
refresh_saved_state() {
    load_profiles
    refresh_mount_cache
}
prefetch_startup() {
    PREFETCH_ACTIVE=1
    printf '\033[0m\033[39;49m\nsimba %s - preparing your session\n\n\n\033[2A' "$VERSION"
    # ------------------------------------
    # No sign-in prompts or SMB sessions run during prefetch. Local profiles
    # provide server/domain hints; DNS alone supplies controller advertisements.
    # ------------------------------------
    task_invoke 'Loading profiles' load_profiles
    refresh_mount_cache
    refresh_domain_cache
    if ((${#FOUND_DOMAINS[@]}==1)); then DISCOVERED_DOMAIN=${FOUND_DOMAINS[0]}; fi
    STATUS="Ready: ${#IDS[@]} profiles, ${#FOUND_DOMAINS[@]} domains. G selects domains; B browses shares."
    TASK_LABEL='Startup complete'; task_finish done
    PREFETCH_ACTIVE=0
    # ------------------------------------
    # Clear only after all prefetch work finishes, then main opens the UI.
    # ------------------------------------
    printf '\033[0m\033[39;49m\033[2J\033[H'
}

# ------------------------------------
# Application startup and main loop
# ------------------------------------
main() {
    [[ -t 0 && -t 1 ]] || { printf 'Run this script in an interactive terminal.\n' >&2; return 1; }
    ((EUID != 0)) || { printf 'Run as your normal user, without sudo.\n' >&2; return 1; }
    ensure_dependencies || return 1
    # ------------------------------------
    # Physical home paths avoid ambiguous mountpoints through symlinked homes.
    # ------------------------------------
    local real_home; real_home=$(cd -- "$HOME" && pwd -P) || return 1
    # ------------------------------------
    # Retain the existing settings directory so saved profiles keep working.
    # ------------------------------------
    CONFIG_DIR="$real_home/.config/windows-drive-ide"
    DRIVE_ROOT="$real_home/NetworkDrives"
    [[ ! -L $CONFIG_DIR && ! -L $DRIVE_ROOT ]] || { printf 'Configuration or drive root is a symlink. Use regular directories.\n' >&2; return 1; }
    mkdir -p -- "$CONFIG_DIR" "$DRIVE_ROOT" || return 1
    chmod 700 "$CONFIG_DIR" || return 1
    # ------------------------------------
    # Prevent two UI instances modifying the same profiles concurrently.
    # ------------------------------------
    exec 9>"$CONFIG_DIR/.lock" # Keep descriptor 9 open for this application's lifetime.
    flock -n 9 || { printf 'simba is already running.\n' >&2; return 1; }
    RUN_DIR=$(mktemp -d /tmp/simba.XXXXXXXX) || return 1
    write_dialog_theme || { printf 'Cannot create dialog theme.\n' >&2; cleanup; return 1; }
    OLD_STTY=$(stty -g)
    # ------------------------------------
    # Every exit after the UI opens restores the terminal and says goodbye.
    # ------------------------------------
    trap cleanup EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM HUP
    prefetch_startup
    printf '\033[?1049h\033[?25l'; ACTIVE=1
    while :; do
        draw
        read_key || break
        handle_key "$KEY"
        ((EXIT_REQUESTED)) && break
    done
}
# ------------------------------------
# Script entry point
# ------------------------------------
# Keep functions sourceable for offline validation without starting the UI.
if [[ ${BASH_SOURCE[0]} == "$0" ]]; then main "$@"; fi

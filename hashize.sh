#!/bin/bash

VERSION="1.0.12"
AUTHOR="domuji6@gmail.com"
TARGET_DIR=""
MAX_DEPTH=1
SORT_BY="size"
SHOW_TYPE="all"
LIMIT_DIRS=0
LIMIT_FILES=0
USE_COLOR=true

# Cancellation flag
CANCELLED=false

# Handle SIGINT (Ctrl+C) gracefully
handle_sigint() {
    CANCELLED=true
    printf "\n\nOperation cancelled by user.\n" >&2
    exit 130
}

# Scratch directory for command exit statuses and error output
WORK_DIR=""
cleanup() {
    if [ -n "$WORK_DIR" ]; then
        rm -rf -- "$WORK_DIR" 2>/dev/null
    fi
}

trap handle_sigint INT
trap "CANCELLED=true; exit 143" TERM
trap "exit 0" PIPE
trap cleanup EXIT

# Largest value accepted for max_depth, -D and -L
MAX_COUNT=2147483647

# C0 control characters and DEL, used to detect names that need escaping
CTRL_CHARS=""
for ((c = 1; c < 32; c++)); do
    printf -v oct '%03o' "$c"
    printf -v ch "\\$oct"
    CTRL_CHARS+="$ch"
done
CTRL_CHARS+=$'\177'
unset c oct ch

# Set SAFE to a single-line, terminal-safe form of $1 for display.
# Tab/newline/CR become \t \n \r, other controls become \xHH (C1 as
# \u00HH). Printable text, including Hangul and spaces, is kept as is.
safe_text() {
    local s="$1"

    if [[ $s != *["$CTRL_CHARS"]* && $s != *$'\302'[$'\200'-$'\237']* ]]; then
        SAFE="$s"
        return
    fi

    local out="" i ch c1 hex
    if [[ $s == *$'\302'[$'\200'-$'\237']* ]]; then
        for ((c1 = 128; c1 < 160; c1++)); do
            printf -v hex '%02x' "$c1"
            printf -v ch "\\302\\x$hex"
            s="${s//"$ch"/\\u00$hex}"
        done
    fi

    for ((i = 0; i < ${#s}; i++)); do
        ch="${s:i:1}"
        case "$ch" in
            $'\t') out+='\t' ;;
            $'\n') out+='\n' ;;
            $'\r') out+='\r' ;;
            *)
                if [[ $ch == ["$CTRL_CHARS"] ]]; then
                    printf -v hex '\\x%02x' "'$ch"
                    out+="$hex"
                else
                    out+="$ch"
                fi
                ;;
        esac
    done
    SAFE="$out"
}

# Validate a non-negative decimal integer and set PARSED to its value.
# Checked as a string first so huge values cannot overflow Bash arithmetic;
# leading zeros are dropped so "08" means 8, not an octal literal.
parse_count() {
    local label="$1"
    local value="$2"

    if ! [[ "$value" =~ ^[0-9]+$ ]]; then
        echo "Error: $label requires a non-negative integer" >&2
        exit 1
    fi
    value="${value#"${value%%[!0]*}"}"
    [ -z "$value" ] && value=0
    if [ "${#value}" -gt "${#MAX_COUNT}" ] || [ "$value" -gt "$MAX_COUNT" ]; then
        echo "Error: $label must be between 0 and $MAX_COUNT" >&2
        exit 1
    fi
    PARSED="$value"
}

usage() {
    local exit_code="${1:-0}"
    cat << USAGE
hashize v${VERSION} - Directory tree with size visualization
Author: ${AUTHOR}

Usage: hashize [OPTIONS] <directory> [max_depth]

OPTIONS:
  -h, --help       Show this help message
  -v, --version    Show version information
  -s               Sort by size (largest first) - default
  -n               Sort by name (alphabetical)
  -t               Sort by modification time (newest first)
  -f               Show files only (all levels up to max_depth, as paths)
  -d               Show directories only
  -D NUM           Limit directories shown per directory (0=all)
  -L NUM           Limit files shown per directory (0=all; -f: in total)
  -c, --no-color   Disable colored output

EXAMPLES:
  hashize /var/www
  hashize -n /var/www 3
  hashize -t /var/log            # Sort by date with date display
  hashize -f /var/www            # Files only
  hashize -f -L 10 /var 3        # Top 10 files within 3 levels
  hashize -d /var/www            # Directories only
  hashize -D 5 /tmp              # Show top 5 directories
  hashize -D 5 -L 10 /tmp        # Show top 5 dirs and 10 files
  hashize -c /tmp                # No color output
  hashize /tmp | head -20        # Pipe friendly

DESCRIPTION:
  Display directory tree with file/directory sizes in human-readable format.
  - Blue color: Directories (with / suffix)
  - Green color: Files
  - Hidden items shown as: more directory(+N) or more file(+N)
  - When sorted by time (-t), modification date is displayed
  - Hidden (dot) files and directories are included
  - Symbolic links are listed as files and are not followed
  - Press Ctrl+C to cancel operation at any time

NOTES:
  - Sizes are logical (apparent) sizes in bytes, not disk usage. Sparse or
    compressed files and filesystem block rounding make them differ from
    the space actually used (e.g. "du -h").
  - Hard links are counted once per link, so a total can exceed real usage.
  - Directory totals (du) and entries (find) are read in two passes; files
    changing in between can make them disagree.
  - Directory totals need every level below the target, so without -f the
    whole tree is scanned even with a small max_depth. -f skips du.
  - -D and -L only limit what is printed; everything is still scanned.
  - -f lists every non-directory entry (files, symlinks, FIFOs, sockets,
    devices); with -n it sorts by the full relative path.
  - -t sorts by full modification time (sub-second); only seconds are shown.
  - Control characters in names are shown escaped (\t, \n, \r, \xHH,
    \u00HH); backslashes in names are shown as is.

EXIT STATUS:
  0    Success
  1    Error (invalid argument, missing or failing command)
  2    Incomplete results (some paths could not be read, e.g. permissions)
  130  Cancelled with Ctrl+C

REQUIREMENTS:
  - Bash 4.0+ (associative arrays)
  - GNU coreutils (du, numfmt, sort, mktemp) and GNU findutils (find -printf)
  - Linux platform

USAGE
    exit "$exit_code"
}

show_version() {
    echo "hashize version ${VERSION}"
    echo "Author: ${AUTHOR}"
    exit 0
}

while getopts "hvsnftdcD:L:-:" opt; do
    case $opt in
        h) usage ;;
        v) show_version ;;
        s) SORT_BY="size" ;;
        n) SORT_BY="name" ;;
        t) SORT_BY="time" ;;
        f) SHOW_TYPE="files" ;;
        d) SHOW_TYPE="dirs" ;;
        c) USE_COLOR=false ;;
        D)
            parse_count "-D" "$OPTARG"
            LIMIT_DIRS="$PARSED"
            ;;
        L)
            parse_count "-L" "$OPTARG"
            LIMIT_FILES="$PARSED"
            ;;
        -)
            case "${OPTARG}" in
                help) usage ;;
                version) show_version ;;
                no-color) USE_COLOR=false ;;
                *) echo "Unknown option --${OPTARG}" >&2; usage 1 ;;
            esac
            ;;
        *) usage 1 ;;
    esac
done
shift $((OPTIND - 1))

TARGET_DIR="$1"
if [ -z "$TARGET_DIR" ]; then
    echo "Error: Directory path required" >&2
    usage 1
fi

if [ ! -d "$TARGET_DIR" ]; then
    safe_text "$TARGET_DIR"
    echo "Error: Directory '$SAFE' does not exist" >&2
    exit 1
fi

if ! (cd -- "$TARGET_DIR") 2>/dev/null; then
    safe_text "$TARGET_DIR"
    echo "Error: Cannot access directory '$SAFE' (permission denied?)" >&2
    exit 1
fi

MAX_DEPTH_ARG="${2:-}"
if [ -n "$MAX_DEPTH_ARG" ]; then
    parse_count "max_depth" "$MAX_DEPTH_ARG"
    MAX_DEPTH="$PARSED"
fi

# Validate conflicting options
if [ "$SHOW_TYPE" = "files" ] && [ "$LIMIT_DIRS" -gt 0 ]; then
    echo "Warning: -f (files only) and -D (limit directories) are conflicting. Ignoring -D." >&2
    LIMIT_DIRS=0
fi

if [ "$SHOW_TYPE" = "dirs" ] && [ "$LIMIT_FILES" -gt 0 ]; then
    echo "Warning: -d (dirs only) and -L (limit files) are conflicting. Ignoring -L." >&2
    LIMIT_FILES=0
fi

# Set colors based on USE_COLOR flag
if [ "$USE_COLOR" = true ]; then
    BLUE=$'\033[0;34m'
    GREEN=$'\033[0;32m'
    GRAY=$'\033[0;90m'
    RESET=$'\033[0m'
else
    BLUE=''
    GREEN=''
    GRAY=''
    RESET=''
fi

DELIM=$'\t'

declare -A DIR_SIZE=()     # relative dir path -> total bytes (from du)
declare -A REC=()          # sorted position -> "id<TAB>is_dir<TAB>hsize<TAB>mtime<TAB>path"
declare -A GROUP_START=()  # group id -> first position in REC
declare -A GROUP_COUNT=()  # group id -> number of entries in the group

# Emit one sortable record per entry found by find:
#   group<TAB>key<TAB>id<TAB>is_dir<TAB>size<TAB>mtime<TAB>path\0
# group is the parent directory id (root = 0), id is the entry's own
# directory id (-1 for non-directories). path is last, so names containing
# tabs or newlines stay intact. In files-only mode every file is put in
# group 0 so files from all levels are listed together.
emit_records() {
    local rec type rest size mtime mtime_h path parent group id is_dir key frac
    local next_id=1
    local -A dir_id=(["."]=0)

    while IFS= read -r -d '' rec; do
        type="${rec%%$'\t'*}";    rest="${rec#*$'\t'}"
        size="${rest%%$'\t'*}";   rest="${rest#*$'\t'}"
        mtime="${rest%%$'\t'*}";  rest="${rest#*$'\t'}"
        mtime_h="${rest%%$'\t'*}"; path="${rest#*$'\t'}"

        case "$path" in
            */*) parent="${path%/*}" ;;
            *)   parent="." ;;
        esac

        if [ "$type" = "d" ]; then
            [ "$SHOW_TYPE" = "files" ] && continue
            id="$next_id"
            next_id=$((next_id + 1))
            dir_id["$path"]="$id"
            is_dir=1
            size="${DIR_SIZE[$path]:-0}"
        else
            [ "$SHOW_TYPE" = "dirs" ] && continue
            id=-1
            is_dir=0
        fi

        if [ "$SHOW_TYPE" = "files" ]; then
            group=0
        else
            # find lists a directory before its contents, so the parent id exists
            group="${dir_id[$parent]:-}"
            [ -z "$group" ] && continue
        fi

        case "$SORT_BY" in
            size) key="$size" ;;
            time)
                # Integer nanoseconds so sort -n needs no locale decimal point
                # and entries within the same second keep their real order
                if [[ "$mtime" == *.* ]]; then
                    frac="${mtime#*.}0000000000"
                    frac="${frac:0:10}"
                    key="${mtime%%.*}"
                else
                    frac=0000000000
                    key="$mtime"
                fi
                # Before 1970 find prints floor(seconds) plus a positive
                # fraction ("-1.9" is -0.1s), so borrow one second to get
                # -(|sec| - 1).(1 - frac)
                if [[ "$key" == -* ]] && [ "$frac" != 0000000000 ]; then
                    printf -v frac '%010d' $((10000000000 - 10#$frac))
                    key="-$(( ${key#-} - 1 ))"
                fi
                key="$key$frac"
                ;;
            *)    key=0 ;;
        esac

        printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\0' \
            "$group" "$key" "$id" "$is_dir" "$size" "${mtime_h%.*}" "$path"
    done < <(
        { cd -- "$TARGET_DIR" && find . -mindepth 1 -maxdepth "$MAX_DEPTH" \
              -printf '%y\t%s\t%T@\t%TY-%Tm-%Td %TH:%TM:%TS\t%P\0'; } 2>"$WORK_DIR/find.err"
        record_status find $?
    )
}

# Commands run inside process substitutions and pipelines, where their exit
# status is otherwise lost. Each one appends "name status" to a file that is
# checked once all output has been read (the reader only sees EOF after the
# producer, including this line, has finished).
record_status() {
    printf '%s %s\n' "$1" "$2" >> "$WORK_DIR/status"
}

# Print up to 5 lines of a captured stderr file, made terminal-safe.
show_errors() {
    local file="$1"
    local lines=() line n
    [ -s "$file" ] || return 0
    mapfile -t lines < "$file"
    n=0
    for line in "${lines[@]}"; do
        n=$((n + 1))
        if [ "$n" -gt 5 ]; then
            echo "  ... ($(( ${#lines[@]} - 5 )) more)" >&2
            break
        fi
        safe_text "$line"
        echo "  $SAFE" >&2
    done
}

fatal() {
    echo "Error: $1" >&2
    [ -n "${2:-}" ] && show_errors "$2"
    exit 1
}

# Make sure every command this run needs exists and supports the GNU
# options used below, before anything is printed.
check_requirements() {
    local cmds=(find sort numfmt mktemp rm)
    local missing=() cmd

    [ "$SHOW_TYPE" != "files" ] && cmds+=(du)
    for cmd in "${cmds[@]}"; do
        command -v "$cmd" >/dev/null 2>&1 || missing+=("$cmd")
    done
    if [ "${#missing[@]}" -gt 0 ]; then
        fatal "required command(s) not found: ${missing[*]} (see REQUIREMENTS in --help)"
    fi

    find /dev/null -maxdepth 0 -printf '' >/dev/null 2>&1 ||
        fatal "find does not support -printf (GNU findutils required)"
    if [ "$SHOW_TYPE" != "files" ]; then
        du -b -l -0 --max-depth=0 /dev/null >/dev/null 2>&1 ||
            fatal "du does not support -b -l -0 --max-depth (GNU coreutils required)"
    fi
    numfmt --to=iec-i --suffix=B 1024 >/dev/null 2>&1 ||
        fatal "numfmt failed (GNU coreutils required)"
    printf 'a\0' | sort -z -t "$DELIM" -k1,1n -k2,2rn >/dev/null 2>&1 ||
        fatal "sort does not support -z (GNU coreutils required)"
}

# Traverse the filesystem once (one du, one find) instead of running du for
# every item, then sort all entries once by (group, key). Results are kept in
# associative arrays: Bash indexed arrays are linked lists, so random access
# into a large one costs O(N) per lookup.
build_index() {
    local rec size path

    # Files-only mode never shows directory totals, so skip du entirely.
    # -l counts hard-linked files in every directory that holds them, so a
    # directory total never depends on which directory du visited first.
    if [ "$SHOW_TYPE" != "files" ]; then
        while IFS= read -r -d '' rec; do
            size="${rec%%$'\t'*}"
            path="${rec#*$'\t'}"
            [ "$path" != "." ] && path="${path#./}"
            DIR_SIZE["$path"]="$size"
        done < <(
            { cd -- "$TARGET_DIR" && du -b -l -0 --max-depth="$MAX_DEPTH" .; } 2>"$WORK_DIR/du.err"
            record_status du $?
        )

        [ "$CANCELLED" = true ] && return 1

        # Without the root total du did not really run; a non-zero status
        # with a root total means some paths could not be read.
        if [ -z "${DIR_SIZE[.]+set}" ]; then
            fatal "du failed to read '$SAFE_TARGET'" "$WORK_DIR/du.err"
        fi
    fi

    # Siblings share the parent prefix, so comparing the path (field 7 to end)
    # orders them by name; size/time ties fall back to reverse name as in 1.0.9.
    local sort_opts=(-z -t "$DELIM" -k1,1n)
    if [ "$SORT_BY" = "name" ]; then
        sort_opts+=(-k7)
    else
        sort_opts+=(-k2,2rn -k7r)
    fi

    local group pos=0 last_group=""
    while IFS= read -r -d '' rec; do
        group="${rec%%$'\t'*}"
        rec="${rec#*$'\t'}"
        REC[$pos]="${rec#*$'\t'}"
        if [ "$group" != "$last_group" ]; then
            GROUP_START[$group]="$pos"
            GROUP_COUNT[$group]=0
            last_group="$group"
        fi
        GROUP_COUNT[$group]=$((GROUP_COUNT[$group] + 1))
        pos=$((pos + 1))
    done < <(
        { emit_records; record_status emit $?; } |
        { numfmt -z -d "$DELIM" --field=5 --to=iec-i --suffix=B 2>"$WORK_DIR/numfmt.err"
          record_status numfmt $?; } |
        { sort "${sort_opts[@]}" 2>"$WORK_DIR/sort.err"
          record_status sort $?; }
    )

    [ "$CANCELLED" = true ] && return 1

    local -A status=()
    local name rc
    if [ -f "$WORK_DIR/status" ]; then
        while read -r name rc; do
            status[$name]="$rc"
        done < "$WORK_DIR/status"
    fi

    # A missing status means the stage never finished; treat it as failed.
    # Check downstream first: when a later stage dies, earlier ones are
    # killed by SIGPIPE, so the first failure found is the real cause.
    for name in sort numfmt emit; do
        if [ "${status[$name]:-missing}" != 0 ]; then
            fatal "$name stage failed (status ${status[$name]:-missing})" "$WORK_DIR/$name.err"
        fi
    done
    if [ -z "${status[find]:-}" ]; then
        fatal "find did not complete" "$WORK_DIR/find.err"
    fi

    # du/find exit non-zero when some paths could not be read (permission
    # denied, removed during the scan). The listing is still printed, then
    # reported as incomplete.
    [ "${status[find]}" != 0 ] && INCOMPLETE=true
    [ "${status[du]:-0}" != 0 ] && INCOMPLETE=true
    return 0
}

# Warn that some paths could not be read and show why.
report_incomplete() {
    echo "Warning: results are incomplete; some paths could not be read, so entries may be missing and sizes too small:" >&2
    show_errors "$WORK_DIR/du.err"
    show_errors "$WORK_DIR/find.err"
}

print_tree() {
    # Check cancellation at the start of each recursion
    if [ "$CANCELLED" = true ]; then
        return 1
    fi

    local group="$1"
    local depth="$2"
    local prefix="$3"

    if [ "$depth" -ge "$MAX_DEPTH" ]; then
        return 0
    fi

    local start="${GROUP_START[$group]:-}"
    if [ -z "$start" ]; then
        return 0
    fi
    local end=$((start + GROUP_COUNT[$group]))

    # Apply -D / -L limits before drawing so branch connectors match output
    local shown=()
    local shown_dirs=0
    local shown_files=0
    local hidden_dirs=0
    local hidden_files=0

    local pos rec is_dir
    for ((pos = start; pos < end; pos++)); do
        rec="${REC[$pos]#*$'\t'}"
        is_dir="${rec%%$'\t'*}"
        if [ "$is_dir" -eq 1 ]; then
            if [ "$LIMIT_DIRS" -gt 0 ] && [ "$shown_dirs" -ge "$LIMIT_DIRS" ]; then
                hidden_dirs=$((hidden_dirs + 1))
                continue
            fi
            shown_dirs=$((shown_dirs + 1))
        else
            if [ "$LIMIT_FILES" -gt 0 ] && [ "$shown_files" -ge "$LIMIT_FILES" ]; then
                hidden_files=$((hidden_files + 1))
                continue
            fi
            shown_files=$((shown_files + 1))
        fi
        shown+=("$pos")
    done

    local has_summary=0
    if [ "$hidden_dirs" -gt 0 ] || [ "$hidden_files" -gt 0 ]; then
        has_summary=1
    fi

    local total="${#shown[@]}"
    local i=0

    for pos in "${shown[@]}"; do
        # Check cancellation in output loop
        if [ "$CANCELLED" = true ]; then
            return 1
        fi

        i=$((i + 1))
        local branch="├── "
        local next="│   "
        if [ "$i" -eq "$total" ] && [ "$has_summary" -eq 0 ]; then
            branch="└── "
            next="    "
        fi

        # Record: id, is_dir, human size, mtime, relative path
        rec="${REC[$pos]}"
        local item_id="${rec%%$'\t'*}";      rec="${rec#*$'\t'}"
        local item_is_dir="${rec%%$'\t'*}";  rec="${rec#*$'\t'}"
        local item_size="${rec%%$'\t'*}";    rec="${rec#*$'\t'}"
        local item_mtime="${rec%%$'\t'*}";   rec="${rec#*$'\t'}"
        local item_name="$rec"
        # Files-only mode lists every level together, so keep the path
        if [ "$SHOW_TYPE" != "files" ]; then
            item_name="${rec##*/}"
        fi
        [ -z "$item_mtime" ] && item_mtime="N/A"
        safe_text "$item_name"
        item_name="$SAFE"

        # Display format depends on sort type
        local line=""
        if [ "$SORT_BY" = "time" ]; then
            if [ "$item_is_dir" -eq 1 ]; then
                printf -v line "%s%s${BLUE}%s/${RESET} [%s] %s\n" "$prefix" "$branch" "$item_name" "$item_size" "$item_mtime"
            else
                printf -v line "%s%s${GREEN}%s${RESET} [%s] %s\n" "$prefix" "$branch" "$item_name" "$item_size" "$item_mtime"
            fi
        else
            if [ "$item_is_dir" -eq 1 ]; then
                printf -v line "%s%s${BLUE}%s/${RESET} [%s]\n" "$prefix" "$branch" "$item_name" "$item_size"
            else
                printf -v line "%s%s${GREEN}%s${RESET} [%s]\n" "$prefix" "$branch" "$item_name" "$item_size"
            fi
        fi

        if ! printf "%s" "$line" 2>/dev/null; then
            return 0
        fi

        if [ "$item_is_dir" -eq 1 ] && [ $depth -lt $((MAX_DEPTH - 1)) ]; then
            print_tree "$item_id" $((depth + 1)) "$prefix$next"
            # Check if recursion was cancelled
            if [ "$CANCELLED" = true ]; then
                return 1
            fi
        fi
    done

    if [ "$has_summary" -eq 1 ]; then
        local summary=""
        if [ "$hidden_dirs" -gt 0 ]; then
            summary="${GRAY}more directory(+${hidden_dirs})${RESET}"
        fi
        if [ "$hidden_files" -gt 0 ]; then
            if [ -n "$summary" ]; then
                summary="$summary, ${GRAY}more file(+${hidden_files})${RESET}"
            else
                summary="${GRAY}more file(+${hidden_files})${RESET}"
            fi
        fi
        if ! printf "%s└── %b\n" "$prefix" "$summary" 2>/dev/null; then
            return 0
        fi
    fi
}

safe_text "$TARGET_DIR"
SAFE_TARGET="$SAFE"
INCOMPLETE=false

if [ "$MAX_DEPTH" -gt 0 ]; then
    check_requirements
    WORK_DIR=$(mktemp -d 2>/dev/null) || fatal "cannot create a temporary directory"
    build_index || exit 1
fi

printf '%s\n' "$SAFE_TARGET"
if [ "$MAX_DEPTH" -gt 0 ]; then
    print_tree 0 0 ""
fi

if [ "$INCOMPLETE" = true ]; then
    report_incomplete
    exit 2
fi
exit 0

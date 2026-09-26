#!/bin/bash

VERSION="1.0.11"
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

trap handle_sigint INT
trap "CANCELLED=true; exit 143" TERM
trap "exit 0" PIPE

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
  -D NUM           Limit directories to show (0=all)
  -L NUM           Limit files to show (0=all)
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

REQUIREMENTS:
  - Bash 4.0+ (associative arrays)
  - GNU coreutils (du, numfmt, sort) and GNU findutils (find -printf)
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
            if ! [[ "$OPTARG" =~ ^[0-9]+$ ]]; then
                echo "Error: -D requires a numeric argument" >&2
                exit 1
            fi
            LIMIT_DIRS="$OPTARG" 
            ;;
        L) 
            if ! [[ "$OPTARG" =~ ^[0-9]+$ ]]; then
                echo "Error: -L requires a numeric argument" >&2
                exit 1
            fi
            LIMIT_FILES="$OPTARG" 
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
    echo "Error: Directory '$TARGET_DIR' does not exist" >&2
    exit 1
fi

MAX_DEPTH_ARG="${2:-}"
if [ -n "$MAX_DEPTH_ARG" ]; then
    if ! [[ "$MAX_DEPTH_ARG" =~ ^[0-9]+$ ]]; then
        echo "Error: max_depth must be a non-negative integer" >&2
        exit 1
    fi
    # Force base 10 so values like "08" are not parsed as octal
    MAX_DEPTH=$((10#$MAX_DEPTH_ARG))
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
    local rec type rest size mtime mtime_h path parent group id is_dir key
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
            time) key="${mtime%.*}" ;;
            *)    key=0 ;;
        esac

        printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\0' \
            "$group" "$key" "$id" "$is_dir" "$size" "${mtime_h%.*}" "$path"
    done < <(cd -- "$TARGET_DIR" && find . -mindepth 1 -maxdepth "$MAX_DEPTH" \
                -printf '%y\t%s\t%T@\t%TY-%Tm-%Td %TH:%TM:%TS\t%P\0' 2>/dev/null)
}

# Traverse the filesystem once (one du, one find) instead of running du for
# every item, then sort all entries once by (group, key). Results are kept in
# associative arrays: Bash indexed arrays are linked lists, so random access
# into a large one costs O(N) per lookup.
build_index() {
    local rec size path

    # -l counts hard-linked files in every directory that holds them, so a
    # directory total never depends on which directory du visited first.
    while IFS= read -r -d '' rec; do
        size="${rec%%$'\t'*}"
        path="${rec#*$'\t'}"
        [ "$path" != "." ] && path="${path#./}"
        DIR_SIZE["$path"]="$size"
    done < <(cd -- "$TARGET_DIR" && du -b -l -0 --max-depth="$MAX_DEPTH" . 2>/dev/null)

    [ "$CANCELLED" = true ] && return 1

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
    done < <(emit_records |
             numfmt -z -d "$DELIM" --field=5 --to=iec-i --suffix=B --invalid=ignore 2>/dev/null |
             sort "${sort_opts[@]}")

    [ "$CANCELLED" = true ] && return 1
    return 0
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

echo "$TARGET_DIR"
if [ "$MAX_DEPTH" -gt 0 ]; then
    build_index && print_tree 0 0 ""
fi

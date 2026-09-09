#!/bin/bash

VERSION="1.0.9"
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

# Cleanup temp files on exit
TEMP_FILES=()
cleanup() {
    CANCELLED=true
    for f in "${TEMP_FILES[@]}"; do
        rm -f "$f" 2>/dev/null
    done
}

# Handle SIGINT (Ctrl+C) gracefully
handle_sigint() {
    CANCELLED=true
    printf "\n\nOperation cancelled by user.\n" >&2
    exit 130
}

trap handle_sigint INT
trap cleanup EXIT TERM
trap "cleanup; exit 0" PIPE

remove_temp_file() {
    local target="$1"
    local keep=()

    for f in "${TEMP_FILES[@]}"; do
        if [ "$f" != "$target" ]; then
            keep+=("$f")
        fi
    done

    if [ "${#keep[@]}" -gt 0 ]; then
        TEMP_FILES=("${keep[@]}")
    else
        TEMP_FILES=()
    fi

    rm -f "$target" 2>/dev/null
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
  -f               Show files only
  -d               Show directories only
  -D NUM           Limit directories to show (0=all)
  -L NUM           Limit files to show (0=all)
  -c, --no-color   Disable colored output

EXAMPLES:
  hashize /var/www
  hashize -n /var/www 3
  hashize -t /var/log            # Sort by date with date display
  hashize -f /var/www            # Files only
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
  - Press Ctrl+C to cancel operation at any time

REQUIREMENTS:
  - GNU coreutils (du, stat, numfmt)
  - Linux platform (for stat -c format)

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
    MAX_DEPTH="$MAX_DEPTH_ARG"
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

# Use tab as delimiter to avoid conflicts with filenames
DELIM=$'\t'

print_tree() {
    # Check cancellation at the start of each recursion
    if [ "$CANCELLED" = true ]; then
        return 1
    fi
    
    local dir="$1"
    local depth="$2"
    local prefix="$3"
    
    if [ "$depth" -ge "$MAX_DEPTH" ] || [ ! -d "$dir" ]; then
        return 0
    fi
    
    local temp_file
    temp_file=$(mktemp)
    TEMP_FILES+=("$temp_file")
    
    for item in "$dir"/*; do
        # Check cancellation in the loop
        if [ "$CANCELLED" = true ]; then
            remove_temp_file "$temp_file"
            return 1
        fi
        
        [ ! -e "$item" ] && continue
        local name
        name=$(basename "$item")
        local is_dir=0
        [ -d "$item" ] && is_dir=1
        
        if [ "$SHOW_TYPE" = "files" ] && [ "$is_dir" -eq 1 ]; then
            continue
        fi
        if [ "$SHOW_TYPE" = "dirs" ] && [ "$is_dir" -eq 0 ]; then
            continue
        fi
        
        # Get byte size
        local size_bytes
        size_bytes=$(du -sb "$item" 2>/dev/null | cut -f1)
        
        # Check if du was interrupted
        if [ "$CANCELLED" = true ]; then
            remove_temp_file "$temp_file"
            return 1
        fi
        
        # Handle failures
        if [ -z "$size_bytes" ]; then
            size_bytes=0
        fi
        
        local size_human
        size_human=$(numfmt --to=iec-i --suffix=B "$size_bytes" 2>/dev/null)
        if [ -z "$size_human" ]; then
            size_human="${size_bytes}B"
        fi
        
        # Get modification time in a single stat call
        local stat_out
        stat_out=$(stat -c "%Y %y" "$item" 2>/dev/null)
        local mtime="${stat_out%% *}"
        local mtime_human="${stat_out#* }"
        mtime_human="${mtime_human%.*}"
        if [ -z "$mtime" ]; then
            mtime=0
            mtime_human="N/A"
        fi
        
        local sort_key
        if [ "$SORT_BY" = "size" ]; then
            sort_key="$size_bytes"
        elif [ "$SORT_BY" = "time" ]; then
            sort_key="$mtime"
        else
            sort_key="$name"
        fi
        
        # Use tab as delimiter: sort_key, name, size, mtime_human, is_dir
        echo "${sort_key}${DELIM}${name}${DELIM}${size_human}${DELIM}${mtime_human}${DELIM}${is_dir}" >> "$temp_file"
    done
    
    if [ ! -s "$temp_file" ]; then
        remove_temp_file "$temp_file"
        return 0
    fi
    
    if [ "$CANCELLED" = true ]; then
        remove_temp_file "$temp_file"
        return 1
    fi
    
    local count=0
    local dir_count=0
    local file_count=0
    
    while IFS=$'\t' read -r _ item_name item_size item_mtime item_is_dir; do
        ((count++))
        if [ "$item_is_dir" -eq 1 ]; then
            ((dir_count++))
        else
            ((file_count++))
        fi
    done < "$temp_file"
    
    local i=0
    local shown_dirs=0
    local shown_files=0
    local hidden_dirs=0
    local hidden_files=0
    
    while IFS=$'\t' read -r _ item_name item_size item_mtime item_is_dir; do
        # Check cancellation in output loop
        if [ "$CANCELLED" = true ]; then
            remove_temp_file "$temp_file"
            return 1
        fi
        
        ((i++))
        local is_last=$((i == count ? 1 : 0))
        local branch=$([[ $is_last == 1 ]] && echo "└── " || echo "├── ")
        
        local should_show=1
        
        if [ "$item_is_dir" -eq 1 ]; then
            if [ "$LIMIT_DIRS" -gt 0 ] && [ "$shown_dirs" -ge "$LIMIT_DIRS" ]; then
                ((hidden_dirs++))
                should_show=0
            else
                ((shown_dirs++))
            fi
        else
            if [ "$LIMIT_FILES" -gt 0 ] && [ "$shown_files" -ge "$LIMIT_FILES" ]; then
                ((hidden_files++))
                should_show=0
            else
                ((shown_files++))
            fi
        fi
        
        if [ "$should_show" -eq 1 ]; then
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
                remove_temp_file "$temp_file"
                return 0
            fi
            
            local fullpath="$dir/$item_name"
            if [ "$item_is_dir" -eq 1 ] && [ $depth -lt $((MAX_DEPTH - 1)) ]; then
                local next=$([[ $is_last == 1 ]] && echo "    " || echo "│   ")
                print_tree "$fullpath" $((depth + 1)) "$prefix$next"
                # Check if recursion was cancelled
                if [ "$CANCELLED" = true ]; then
                    remove_temp_file "$temp_file"
                    return 1
                fi
            fi
        fi
    done < <(if [ "$SORT_BY" = "name" ]; then sort -t"$DELIM" -k2; else sort -rn; fi < "$temp_file")
    
    if [ "$hidden_dirs" -gt 0 ] || [ "$hidden_files" -gt 0 ]; then
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
            remove_temp_file "$temp_file"
            return 0
        fi
    fi

    remove_temp_file "$temp_file"
}

echo "$TARGET_DIR"
print_tree "$TARGET_DIR" 0 ""

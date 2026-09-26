# hashize

> **Directory tree with human-readable size and modification time visualization**

`hashize` is a lightweight Linux CLI tool that displays directory structures in a tree format with human-readable sizes (e.g., KiB, MiB, GiB) and modification timestamps. It is designed to quickly identify disk space hogs and inspect directory contents.

---

## ✨ Features

- **Size Visualization**: Automatically converts byte sizes into human-readable units (`IEC` format: `KiB`, `MiB`, `GiB`).
- **Flexible Sorting**:
  - Sort by file/directory size (Largest first - Default)
  - Sort by name (Alphabetical)
  - Sort by modification time (Newest first, displays timestamp)
- **Display Filtering**:
  - Filter directories only (`-d`) or files only (`-f`, lists files from every level up to `max_depth` with their relative paths)
  - Limit the number of visible directories (`-D`) and files (`-L`) with fold summaries (`more directory(+N)`)
- **Pipe & Signal Friendly**:
  - Fully handles `SIGPIPE` (safe to pipe into `head`, `tail`, `less`)
  - Gracefully terminates on `Ctrl+C` (`SIGINT`, exit code 130)
- **Single-Pass Scanning**: Sizes and timestamps are collected with one `du` run and one `find` run, so large trees are not re-scanned for every entry.
- **Complete Listing**: Hidden (dot) files and directories are included; symbolic links are listed but not followed.
- **Colorized Output**: Color-coded output for directories, files, and folded items (can be disabled with `-c` / `--no-color`).

---

## 📋 Requirements

- **OS**: Linux
- **Shell**: `/bin/bash` 4.0+ (required for both the script and the pre-built binary)
- **Dependencies**: GNU coreutils (`du`, `numfmt`, `sort`, `mktemp`), GNU findutils (`find`)

Missing or unsupported commands are detected before any output; `hashize` then prints the reason and exits with status 1.

> The pre-built `hashize_static` is **not** a self-contained program. It is an [shc](https://github.com/neurobin/shc) wrapper: the statically linked part only decodes the embedded script and runs it with `/bin/bash`, which then calls the tools above. All requirements apply when running the binary too.

---

## 🚀 Installation

### Option 1. Quick Install (Pre-built Binary - Recommended)
Download the pre-built binary (an shc wrapper around `hashize.sh`). The target system still needs `/bin/bash` 4.0+, GNU coreutils and GNU findutils (see [Requirements](#-requirements)):
```bash
sudo curl -fsSL https://raw.githubusercontent.com/pasart6/hashize/main/hashize_static -o /usr/local/bin/hashize
sudo chmod +x /usr/local/bin/hashize
```

### Option 2. Direct Script Usage
```bash
git clone https://github.com/pasart6/hashize.git
cd hashize
chmod +x hashize.sh
sudo cp hashize.sh /usr/local/bin/hashize
```

### Option 3. Build Binary from Source (Optional)
```bash
# Dynamic binary
shc -r -f hashize.sh
gcc -O2 -o hashize hashize.sh.x.c
strip hashize
sudo cp hashize /usr/local/bin/hashize

# Or statically linked wrapper (still runs the script with /bin/bash)
gcc -static -O2 -o hashize_static hashize.sh.x.c
strip hashize_static
```

---

## 📖 Usage

```bash
hashize [OPTIONS] <directory> [max_depth]
```

### Options

| Option | Description |
| :--- | :--- |
| `-h`, `--help` | Show help message |
| `-v`, `--version` | Show version information |
| `-s` | Sort by size (largest first, default) |
| `-n` | Sort by name (alphabetical) |
| `-t` | Sort by modification time (newest first, displays datetime) |
| `-f` | Show files only (all levels up to `max_depth`, shown as relative paths) |
| `-d` | Show directories only |
| `-D NUM` | Limit directories shown per directory (`0` = all). Output limit only; everything is still scanned |
| `-L NUM` | Limit files shown per directory (`0` = all; with `-f`, in total). Output limit only |
| `-c`, `--no-color` | Disable colored output |

---

## 💡 Examples

```bash
# 1. Inspect current directory (depth 1) sorted by size
hashize .

# 2. Inspect /var/log with depth 3, sorted by modification time
hashize -t /var/log 3

# 3. Show only directories in /var/www
hashize -d /var/www

# 4. Limit to top 5 largest directories and 10 files in /tmp
hashize -D 5 -L 10 /tmp

# 5. Top 10 largest files anywhere within 3 levels of /var
hashize -f -L 10 /var 3

# 6. Pipe to head (No broken pipe errors)
hashize /var/log | head -20
```

---

## ⚠️ Notes & Limitations

- **Logical sizes, not disk usage**: Sizes are apparent sizes in bytes (`du -b` / `find %s`). Sparse or compressed files and block rounding make them differ from the space actually allocated on disk (`du -h`).
- **Hard links**: Counted once per link (`du -l`), so a directory total can exceed its real usage when it contains several links to the same file.
- **Two passes**: Directory totals come from `du` and entries from `find`, run one after the other. Files created, removed or resized in between can make the two disagree.
- **Scan depth**: Directory totals need every level below the target, so outside `-f` the whole tree is scanned even with a small `max_depth`. `-f` does not run `du` and only scans up to `max_depth`.
- **`-D` / `-L`** only limit what is printed; all entries are still scanned and sorted.
- **`-f`** lists every non-directory entry — regular files, symbolic links, FIFOs, sockets and device files — with its path relative to the target. With `-n` it is sorted by that full relative path.
- **`-t`** sorts by the full (sub-second) modification time; only seconds are displayed.
- **Unusual file names**: Names are kept unchanged internally. On screen, control characters are escaped (`\t`, `\n`, `\r`, `\xHH`, C1 as `\u00HH`) so every entry stays on one line and cannot send terminal control sequences. Hangul, spaces and ordinary symbols are shown as is; backslashes are not escaped, so a literal `\n` in a name looks the same as an escaped newline.
- **Incomplete results**: If some paths cannot be read (e.g. permission denied), the tree is still printed, followed by a warning with the reasons on stderr, and the exit status is 2. Affected directories may be missing entries or show sizes that are too small.

### Exit Status

| Code | Meaning |
| :--- | :--- |
| `0` | Success |
| `1` | Error: invalid argument, missing/unsupported command, or a command failed |
| `2` | Incomplete results: some paths could not be read |
| `130` | Cancelled with `Ctrl+C` |

---

## 👤 Author

- **Author**: domuji6@gmail.com
- **Repository**: [https://github.com/pasart6/hashize](https://github.com/pasart6/hashize)

---

## 📄 License

This project is licensed under the MIT License.

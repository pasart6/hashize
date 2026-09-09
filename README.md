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
  - Filter directories only (`-d`) or files only (`-f`)
  - Limit the number of visible directories (`-D`) and files (`-L`) with fold summaries (`more directory(+N)`)
- **Pipe & Signal Friendly**:
  - Fully handles `SIGPIPE` (safe to pipe into `head`, `tail`, `less`)
  - Gracefully terminates and cleans up temporary files on `Ctrl+C` (`SIGINT`)
- **Colorized Output**: Color-coded output for directories, files, and folded items (can be disabled with `-c` / `--no-color`).

---

## 📋 Requirements

- **OS**: Linux
- **Shell**: Bash 4.0+ (when running script directly)
- **Dependencies**: GNU coreutils (`du`, `stat`, `numfmt`)

---

## 🚀 Installation

### Option 1. Quick Install (Pre-built Static Binary - Recommended)
Download the standalone pre-built static binary directly:
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

# Or Static binary
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
| `-f` | Show files only |
| `-d` | Show directories only |
| `-D NUM` | Limit number of directories to show (`0` = all) |
| `-L NUM` | Limit number of files to show (`0` = all) |
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

# 5. Pipe to head (No broken pipe errors)
hashize /var/log | head -20
```

---

## 👤 Author

- **Author**: domuji6@gmail.com
- **Repository**: [https://github.com/pasart6/hashize](https://github.com/pasart6/hashize)

---

## 📄 License

This project is licensed under the MIT License.

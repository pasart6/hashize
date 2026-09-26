#!/bin/bash
# Regression tests for hashize (used for the v1.0.12 release).
#
#   bash tests/regress.sh                         # test ./hashize.sh
#   NEW=./hashize_static RUN= bash tests/regress.sh  # test a built binary
#
# Compatibility checks compare against v1.0.9/v1.0.10/v1.0.11 taken from git
# history. Permission tests need root and runuser (they run as "nobody").
# Requires GNU coreutils/findutils, python3 (fixtures only) and mkfifo.

REPO=$(cd "$(dirname "$0")/.." && pwd)
NEW=${NEW:-$REPO/hashize.sh}
RUN=${RUN-bash}                 # empty to run $NEW directly (binary)
case "$NEW" in /*) ;; *) NEW="$PWD/$NEW" ;; esac

SP=$(mktemp -d) || exit 1
trap 'chmod -R u+rwx "$SP" 2>/dev/null; rm -rf -- "${SP:?}"' EXIT

# --- Reference versions from git history ---
OLD=$SP/v109.sh; V10=$SP/v1010.sh; V11=$SP/v1011.sh
git -C "$REPO" show b032756:hashize.sh > "$OLD" 2>/dev/null &&
git -C "$REPO" show 6254b21:hashize.sh > "$V10" 2>/dev/null &&
git -C "$REPO" show 3ad8e0d:hashize.sh > "$V11" 2>/dev/null || {
    echo "Error: reference versions not found in git history" >&2; exit 1; }

# --- Fixtures ---
T=$SP/cmp; E=$SP/edge; W=$SP/weird; N=$SP/names; P=$SP/pre; O=$SP/old70
# Plain tree, deterministic sizes, whole-second mtimes (comparable with v1.0.9)
python3 - "$T" <<'EOF'
import os, sys
root = sys.argv[1]
n = 0
for d in ["alpha", "beta", "gamma", "with space"]:
    for s in ["s1", "s2", "s3"]:
        os.makedirs(os.path.join(root, d, s, "deep"))
        for f in range(1, 4):
            n += 1
            open(os.path.join(root, d, s, f"f{f}.bin"), "wb").write(b"x" * ((n * 7919) % 90000 + f))
            open(os.path.join(root, d, s, "deep", f"g{f}"), "wb").write(b"y" * ((n * 104729) % 30000))
    n += 1
    open(os.path.join(root, d, "top.dat"), "wb").write(b"z" * ((n * 3571) % 30000))
open(os.path.join(root, "root.txt"), "w").write("hi\n")
i = 0
for dp, dns, fns in os.walk(root, topdown=False):
    for x in fns + dns:
        i += 1
        t = 1700000000 + (i * 7907) % 3000000
        os.utime(os.path.join(dp, x), (t, t), follow_symlinks=False)
EOF
# Hidden, tab/newline names, symlinks, hard links
mkdir -p "$E/.cache/sub" "$E/tab	dir" "$E/real" "$E/hl"
head -c 5000 /dev/zero > "$E/.cache/sub/blob"; echo a > "$E/tab	dir/x	y.txt"
echo b > "$E/new
line.txt"; head -c 3000 /dev/zero > "$E/real/r"
ln -s real "$E/link_to_dir"; ln -s nowhere "$E/broken"
head -c 10000 /dev/zero > "$E/hl/a"; ln "$E/hl/a" "$E/hl/b"
# Shell-special directory names
for d in "@" "*" "a]b" '$(id)' "-n"; do mkdir -p "$W/$d"; head -c 1234 /dev/zero > "$W/$d/f"; done
# Control characters, Hangul, spaces, symbols, FIFO, socket
mkdir -p "$N/한글 폴더"; echo 1 > "$N/한글 폴더/파일 하나.txt"; echo 22 > "$N/공백 있는 이름.txt"
echo 333 > "$N"/$'tab\tname'; echo 4444 > "$N"/$'new\nline'; echo 55555 > "$N"/$'esc\e[2Jclear'
echo 666666 > "$N"/$'c1\302\233x'; echo 7777777 > "$N/sym-bol_(1)+[x].txt"
mkfifo "$N/fifo"; python3 -c "import socket; socket.socket(socket.AF_UNIX).bind('$N/sock')"
ln -s "한글 폴더" "$N/dirlink"
# Same-second and pre-1970 modification times
mkdir -p "$P/sub" "$O"; echo x > "$P/sub/f"; printf 'a' > "$P/esc"$'\e[31m'"red"
touch -d '2026-01-01 00:00:00.100' "$P/older"; touch -d '2026-01-01 00:00:00.900' "$P/newer"
touch -d '2026-01-01 00:00:00.500' "$P/mid"
touch -d '1969-12-31 23:59:59.900 UTC' "$O/a_m0.1"; touch -d '1969-12-31 23:59:59.100 UTC' "$O/b_m0.9"
touch -d '1969-12-31 23:59:58.500 UTC' "$O/c_m1.5"; touch -d '1969-12-31 23:59:58.200 UTC' "$O/d_m1.8"
touch -d '1970-01-01 00:00:00.300 UTC' "$O/e_p0.3"; touch -d '1969-12-01 UTC' "$O/f_m30d"
# Larger tree for signal tests
python3 - "$SP/bench" <<'EOF'
import os, sys
for a in range(40):
    for b in range(10):
        d = os.path.join(sys.argv[1], f"d{a}", f"e{b}", "f")
        os.makedirs(d)
        for c in range(10):
            open(os.path.join(d, f"x{c}"), "w").close()
            open(os.path.join(os.path.dirname(d), f"y{c}"), "w").close()
EOF
# PATH shims: missing commands, a du call logger, and commands that pass the
# /dev/null capability probe but fail on real input. Failing commands are
# written as new files (never through a symlink to the real binary).
# shim_dir NAME [EXCLUDED_CMD]: link the real tools, except one left missing
shim_dir() { local d="$SP/path/$1" skip="${2:-}" c; mkdir -p "$d"; for c in find sort numfmt du mktemp rm cat; do
    [ "$c" = "$skip" ] && continue; [ -e "$d/$c" ] || ln -s "$(command -v "$c")" "$d/$c"; done; }
shim_cmd() { local d="$SP/path/$1" name=$2 body=$3; mkdir -p "$d"; printf '#!/bin/bash\n%s\n' "$body" > "$d/$name"; chmod +x "$d/$name"; }
shim_dir nodu du
shim_dir nonum numfmt
shim_cmd shim du "echo called >> '$SP/du.log'; exec $(command -v du) \"\$@\""; shim_dir shim
shim_cmd fail_sort sort 'for a; do case "$a" in -k7|-k7r) cat >/dev/null; echo "sort: simulated failure" >&2; exit 2;; esac; done; exec '"$(command -v sort)"' "$@"'
shim_dir fail_sort
shim_cmd fail_numfmt numfmt '[ "$1" = "--to=iec-i" ] && exec '"$(command -v numfmt)"' "$@"; cat >/dev/null; echo "numfmt: simulated failure" >&2; exit 2'
shim_dir fail_numfmt
shim_cmd fail_du du 'case "$*" in *"/dev/null"*) exec '"$(command -v du)"' "$@";; esac; echo "du: simulated crash" >&2; exit 1'
shim_dir fail_du
shim_cmd fail_find find 'case "$*" in *"/dev/null"*) exec '"$(command -v find)"' "$@";; esac; echo "find: simulated crash" >&2; exit 1'
shim_dir fail_find
# Permission fixture (root + runuser only)
HAVE_PERM=false
if [ "$(id -u)" = 0 ] && command -v runuser >/dev/null; then
    HAVE_PERM=true
    Q=$SP/perm; mkdir -p "$Q/open" "$Q/locked"; head -c 5000 /dev/zero > "$Q/locked/big"; echo hi > "$Q/open/f"
    chmod 755 "$SP" "$Q" "$Q/open"; chmod 000 "$Q/locked"
    cp "$NEW" "$SP/hz_perm_bin"; chmod 755 "$SP/hz_perm_bin"
fi

pass=0; fail=0; skip=0
ok()  { pass=$((pass+1)); }
bad() { fail=$((fail+1)); echo "FAIL: $*"; }
check() { local name="$1"; shift; if [ "$1" = "!" ]; then shift; if ! "$@"; then ok; else bad "$name"; fi; elif "$@"; then ok; else bad "$name"; fi; }
new() { $RUN "$NEW" "$@"; }
same_as() { local ref=$1; shift; [ "$(bash "$ref" "$@" 2>&1)" = "$(new "$@" 2>&1)" ]; }
# For PATH-shim tests: run the script with an absolute bash, or the binary directly
newp() { if [ -n "$RUN" ]; then /bin/bash "$NEW" "$@"; else "$NEW" "$@"; fi; }
TMPCOUNT() { ls "${TMPDIR:-/tmp}" | grep -c '^tmp\.'; }
TMP_BEFORE=$(TMPCOUNT)

# --- 1. Compatibility with earlier versions (plain trees, integer mtimes) ---
for o in -s -n -t -d "-d -n" "-d -t" "-D 99" "-L 99"; do
  for d in 0 1 3; do check "v1.0.9 compat '$o' $d" same_as $OLD -c $o $T $d; done
done
for o in -s -n -t; do check "v1.0.9 compat -f $o 1" same_as $OLD -c -f $o $T 1; done
for dir in $T $W; do
  for o in -s -n -d "-D 1" "-L 1" "-D 2 -L 1" "-d -D 1" "-n -D 1 -L 2"; do
    for d in 0 1 3; do check "v1.0.10 compat $dir '$o' $d" same_as $V10 -c $o $dir $d; done
  done
done
for o in -s -t -n "-f" "-f -n" "-f -t" "-f -L 3" "-d" "-D 2 -L 1"; do
  for d in 1 3; do check "v1.0.11 compat cmp '$o' $d" same_as $V11 -c $o $T $d; done
done
# edge tree: identical to v1.0.11 except escaped control characters
for o in -s -n -d "-D 1" "-L 1"; do
  check "v1.0.11 compat edge '$o' (escaped)" [ "$(bash $V11 -c $o $E 3 | python3 -c 'import sys; d=sys.stdin.read().replace("\t","\\t").replace("new\nline","new\\nline"); sys.stdout.write(d)')" = "$(new -c $o $E 3)" ]
done
check "color output" same_as $V11 $T 2

# --- 2. Numbers ---
check "depth 08 == 8"        [ "$(new -c $T 08)" = "$(bash $OLD -c $T 8)" ]
check "-D 007 == -D 7"       [ "$(new -c -D 007 $T 2)" = "$(new -c -D 7 $T 2)" ]
check "depth 0 header only"  [ "$(new -c $T 0)" = "$T" ]
check "depth 000 == 0"       [ "$(new -c $T 000)" = "$T" ]
check "-D 0 means all"       [ "$(new -c -D 0 $T 2)" = "$(new -c $T 2)" ]
check "-L 0 means all"       [ "$(new -c -L 0 $T 2)" = "$(new -c $T 2)" ]
check "max 2147483647 ok"    new -c -D 2147483647 -L 2147483647 $T 2147483647 >/dev/null
for a in "-D 2147483648" "-L 99999999999999999999" "-D 18446744073709551617" "-D -1" "-L 1e3" "-D x"; do
  new -c $a $T 1 >/dev/null 2>&1; check "reject $a" [ $? -eq 1 ]
done
for d in 2147483648 99999999999999999999 -1 abc; do
  new -c $T $d >/dev/null 2>&1; check "reject depth $d" [ $? -eq 1 ]
done
check "range error message" grep -q "between 0 and 2147483647" <<<"$(new -D 99999999999999999999 $T 2>&1)"

# --- 3. Time sort precision ---
check "same-second newest first" [ "$(new -c -t $P 1 | grep -oE 'older|newer|mid' | tr '\n' ' ')" = "newer mid older " ]
check "-f -t same-second"        [ "$(new -c -f -t $P 1 | grep -oE 'older|newer|mid' | tr '\n' ' ')" = "newer mid older " ]
check "pre-1970 newest first"    [ "$(new -c -t $O 1 | grep -oE '[a-f]_[mp][0-9.d]+' | tr '\n' ' ')" = "e_p0.3 a_m0.1 b_m0.9 c_m1.5 d_m1.8 f_m30d " ]
check "time display unchanged"   grep -q 'newer \[0B\] 2026-01-01 00:00:00$' <<<"$(new -c -t $P 1)"

# --- 4. Filenames ---
out=$(new -c $N 2)
check "one line per entry"       [ "$(wc -l <<<"$out")" -eq $(( $(cd $N && find . -mindepth 1 -maxdepth 2 -printf '.\n' | wc -l) + 1 )) ]
check "no raw ESC in output"     ! grep -q $'\e' <<<"$out"
check "no raw C1 in output"      ! grep -q $'\302\233' <<<"$out"
check "tab escaped"              grep -qF 'tab\tname' <<<"$out"
check "newline escaped"          grep -qF 'new\nline' <<<"$out"
check "ESC escaped"              grep -qF 'esc\x1b[2Jclear' <<<"$out"
check "C1 escaped"               grep -qF 'c1\u009bx' <<<"$out"
check "Hangul/space kept"        grep -qF '파일 하나.txt' <<<"$out"
check "Hangul dir kept"          grep -qF '한글 폴더/' <<<"$out"
check "symbols kept"             grep -qF 'sym-bol_(1)+[x].txt' <<<"$out"
check "size order w/ odd names"  [ "$(grep -oE '\[[0-9]+B\]' <<<"$(new -c -f $N 2)" | head -5 | tr '\n' ' ')" = "[13B] [8B] [7B] [6B] [5B] " ]
check "name sort w/ odd names"   [ "$(new -c -n $N 1 | sed -n 2p)" = "├── c1\\u009bx [7B]" ]
check "root path escaped"        [ "$(new -c $N/$'new\nline' 1 2>&1 | head -1)" = "Error: Directory '$N/new\\nline' does not exist" ] || true
mkdir -p "$SP/root"$'\e'"x" ; check "root header escaped" [ "$(new -c "$SP/root"$'\e'"x" 1 | head -1)" = "$SP/root\\x1bx" ]
check "no stderr on names"       [ -z "$(new -c $N 2 2>&1 >/dev/null)" ]
LC_ALL=C.UTF-8 check "C.UTF-8 Hangul kept" grep -qF '파일 하나.txt' <<<"$(LC_ALL=C.UTF-8 new -c $N 2)"

# --- 5. -f ---
f3=$(new -c -f $T 3)
check "-f lists all files <=3"   [ "$(grep -c '── ' <<<"$f3")" -eq "$(cd $T && find . -mindepth 1 -maxdepth 3 ! -type d | wc -l)" ]
check "-f no directory lines"    ! grep -q '/ \[' <<<"$f3"
check "-f nested path"           grep -q 'alpha/s1/f1.bin' <<<"$f3"
check "-f excludes depth 4"      ! grep -q 'deep/' <<<"$f3"
check "-f -L fold"               [ "$(new -c -f -L 3 $T 3 | tail -1)" = "└── more file(+38)" ]
check "-f includes fifo/sock/link" [ "$(new -c -f $N 1 | grep -cE '── (fifo|sock|dirlink) ')" -eq 3 ]
check "-f -n by full path"       [ "$(new -c -f -n $T 3 | sed -n '2,3p' | sed 's/ \[.*//' | tr '\n' ' ')" = "├── alpha/s1/f1.bin ├── alpha/s1/f2.bin " ]
check "-f dotfiles"              grep -q '.cache/sub/blob' <<<"$(new -c -f $E 3)"
check "-f -D warning"            grep -q Warning <<<"$(new -f -D 1 $T 2>&1 >/dev/null)"
check "-f same as v1.0.11"       same_as $V11 -c -f $T 3

# --- 6. -d, trees, hidden, links, folds ---
d3=$(new -c -d $T 3)
check "-d dirs only"             [ "$(grep -c '── ' <<<"$d3")" -eq "$(grep -c '/ \[' <<<"$d3")" ]
check "-d recurses"              grep -q 'deep/' <<<"$d3"
e=$(new -c $E 2)
check "hidden dir"               grep -q '\.cache/' <<<"$e"
check "symlink not followed"     grep -q '^├── link_to_dir \[4B\]' <<<"$e"
check "broken symlink listed"    grep -q 'broken \[7B\]' <<<"$e"
check "hardlink counted per link" awk -F'[][]' '/── hl\//{sub(/KiB/,"",$2); exit !($2+0 >= 19.5)}' <<<"$e"
check "fold summary"             [ "$(new -c -D 1 -L 1 $T 1 | tail -1)" = "└── more directory(+3)" ]
check "fold connector"           grep -q "^├── root.txt" <<<"$(new -c -D 1 -L 1 $T 1 | tail -2 | head -1)"

# --- 7. Failures ---
check "missing du -> rc 1"       [ "$(PATH=$SP/path/nodu newp -c $T 1 >/dev/null 2>&1; echo $?)" -eq 1 ]
check "missing du message"       grep -q "not found: du" <<<"$(PATH=$SP/path/nodu newp -c $T 1 2>&1)"
check "missing du no stdout"     [ -z "$(PATH=$SP/path/nodu newp -c $T 1 2>/dev/null)" ]
check "missing numfmt -> rc 1"   [ "$(PATH=$SP/path/nonum newp -c $T 1 >/dev/null 2>&1; echo $?)" -eq 1 ]
check "-f works without du"      [ "$(PATH=$SP/path/nodu newp -c -f $T 2)" = "$(new -c -f $T 2)" ]
rm -f $SP/du.log; PATH=$SP/path/shim:$PATH $RUN $NEW -c -f $T 3 >/dev/null
check "-f does not run du"       [ ! -e $SP/du.log ]
PATH=$SP/path/shim:$PATH $RUN $NEW -c $T 1 >/dev/null
check "normal mode runs du"      [ -e $SP/du.log ]
for c in sort numfmt du; do
  o=$(PATH=$SP/path/fail_$c newp -c $T 2 2>&1); rc=$?
  check "$c mid-run failure rc 1"  [ $rc -eq 1 ]
  check "$c failure names cause"  grep -q "simulated\|stage failed" <<<"$o"
  check "$c failure no tree"      ! grep -q '── ' <<<"$o"
done
o=$(PATH=$SP/path/fail_find newp -c $T 2 2>&1); rc=$?
check "find failure rc 2"        [ $rc -eq 2 ]
check "find failure message"     grep -q "incomplete" <<<"$o"
if [ "$HAVE_PERM" = true ]; then
  o=$(runuser -u nobody -- $RUN $SP/hz_perm_bin -c $Q 2 2>$SP/perm.err); rc=$?
  check "permission rc 2"          [ $rc -eq 2 ]
  check "permission warning"       grep -q "results are incomplete" $SP/perm.err
  check "permission cause shown"   grep -q "Permission denied" $SP/perm.err
  check "permission tree printed"  grep -q 'open/ \[' <<<"$o"
  o=$(runuser -u nobody -- $RUN $SP/hz_perm_bin -c -f $Q 2 2>&1); rc=$?
  check "permission -f rc 2"       [ $rc -eq 2 ]
  chmod 311 $Q/open 2>/dev/null
  o=$(runuser -u nobody -- $RUN $SP/hz_perm_bin -c $Q/open 1 2>&1); rc=$?
  check "unreadable root rc 2"     [ $rc -eq 2 ]
  chmod 755 $Q/open
  chmod 700 $Q/locked; chmod 000 $Q/locked
  o=$(runuser -u nobody -- $RUN $SP/hz_perm_bin -c $Q/locked 1 2>&1); rc=$?
  check "inaccessible target rc 1" [ $rc -eq 1 ]
  check "inaccessible message"     grep -q "Cannot access" <<<"$o"
else
  skip=$((skip+1)); echo "SKIP: permission tests (need root and runuser)"
fi
new $T /nonexistent >/dev/null 2>&1; check "missing dir rc 1" [ $? -eq 1 ]
check "no temp dirs left"        [ "$(TMPCOUNT)" -eq "$TMP_BEFORE" ]

# --- 8. Signals ---
new $SP/bench 3 | head -1 >/dev/null; check "SIGPIPE rc 0" [ "${PIPESTATUS[0]}" -eq 0 ]
check "SIGPIPE no stderr"        [ -z "$(new $SP/bench 3 2>&1 >/dev/null | head -1)" ]
set -m; $RUN $NEW $SP/bench 3 >/dev/null 2>$SP/int.err & p=$!; set +m; sleep 0.3; kill -INT $p; wait $p; rc=$?
check "SIGINT rc 130"            [ $rc -eq 130 ]
check "SIGINT message"           grep -q "cancelled by user" $SP/int.err
sleep 0.2; check "SIGINT cleans temp" [ "$(TMPCOUNT)" -eq "$TMP_BEFORE" ]
set -m; $RUN $NEW $SP/bench 3 >/dev/null 2>&1 & p=$!; set +m; sleep 0.3; kill -TERM $p; wait $p; rc=$?
check "SIGTERM rc 143"           [ $rc -eq 143 ]
check "help rc 0"                new -h >/dev/null
check "version"                  grep -q "version $(grep -m1 '^VERSION=' "$REPO/hashize.sh" | cut -d\" -f2)" <<<"$(new -v)"
echo "PASS=$pass FAIL=$fail SKIP=$skip"
[ "$fail" -eq 0 ]

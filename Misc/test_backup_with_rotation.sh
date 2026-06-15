#!/bin/bash
# Regression tests for backup_with_rotation.sh
# Covers: first backup, rotation after multiple runs, empty directory backup

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BACKUP_SCRIPT="$SCRIPT_DIR/backup_with_rotation.sh"
TEST_ROOT="$(mktemp -d)"
PASS=0
FAIL=0

cleanup() { rm -rf "$TEST_ROOT"; }
trap cleanup EXIT

assert_eq() {
    local label="$1" expected="$2" actual="$3"
    if [ "$expected" = "$actual" ]; then
        echo "  PASS: $label (expected=$expected)"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $label (expected=$expected, got=$actual)"
        FAIL=$((FAIL + 1))
    fi
}

count_backups() {
    find "$1" -maxdepth 1 -type d -name 'backup_[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]_[0-9][0-9]-[0-9][0-9]-[0-9][0-9]' | wc -l | tr -d ' '
}

# =========================================================
echo "=== Test 1: First-time backup ==="
# =========================================================
DIR1="$TEST_ROOT/test1"
mkdir -p "$DIR1"
echo "hello" > "$DIR1/file1.txt"
mkdir -p "$DIR1/subdir"
echo "world" > "$DIR1/subdir/file2.txt"

OUTPUT1=$(bash "$BACKUP_SCRIPT" "$DIR1" 2>&1)
echo "$OUTPUT1"

assert_eq "one backup exists" "1" "$(count_backups "$DIR1")"

# Verify copied content is correct (file1.txt and subdir, no backup_* inside the backup)
BACKUP1=$(find "$DIR1" -maxdepth 1 -type d -name 'backup_*' | head -1)
assert_eq "file1.txt copied" "hello" "$(cat "$BACKUP1/file1.txt")"
assert_eq "subdir/file2.txt copied" "world" "$(cat "$BACKUP1/subdir/file2.txt")"

# The backup dir itself must NOT contain a nested backup_* directory
NESTED=$(find "$BACKUP1" -mindepth 1 -maxdepth 1 -type d -name 'backup_*' | wc -l | tr -d ' ')
assert_eq "no recursive backup inside backup" "0" "$NESTED"

# =========================================================
echo ""
echo "=== Test 2: Repeated runs trigger rotation (keep 3) ==="
# =========================================================
DIR2="$TEST_ROOT/test2"
mkdir -p "$DIR2"
echo "data" > "$DIR2/a.txt"

for i in 1 2 3 4 5; do
    bash "$BACKUP_SCRIPT" "$DIR2" >/dev/null 2>&1
    # small sleep so timestamps differ
    sleep 1
done

BCOUNT=$(count_backups "$DIR2")
assert_eq "only 3 backups retained after 5 runs" "3" "$BCOUNT"

# Verify content in each retained backup
while IFS= read -r b; do
    assert_eq "a.txt present in $b" "data" "$(cat "$b/a.txt")"
done < <(find "$DIR2" -maxdepth 1 -type d -name 'backup_*' | sort)

# Verify that a non-backup file/dir is NOT deleted by rotation
echo "keep_me" > "$DIR2/important.txt"
mkdir -p "$DIR2/my_folder"
bash "$BACKUP_SCRIPT" "$DIR2" >/dev/null 2>&1
sleep 1
bash "$BACKUP_SCRIPT" "$DIR2" >/dev/null 2>&1

assert_eq "important.txt survives rotation" "keep_me" "$(cat "$DIR2/important.txt")"
assert_eq "my_folder survives rotation" "0" "$([ -d "$DIR2/my_folder" ] && echo 0 || echo 1)"

# =========================================================
echo ""
echo "=== Test 3: Empty directory backup ==="
# =========================================================
DIR3="$TEST_ROOT/test3"
mkdir -p "$DIR3"

OUTPUT3=$(bash "$BACKUP_SCRIPT" "$DIR3" 2>&1)
echo "$OUTPUT3"
EXIT3=$?

assert_eq "exit code 0 for empty dir" "0" "$EXIT3"
assert_eq "one backup dir created" "1" "$(count_backups "$DIR3")"

BACKUP3=$(find "$DIR3" -maxdepth 1 -type d -name 'backup_*' | head -1)
# The backup directory should exist but be empty
ITEMS_IN_BACKUP=$(find "$BACKUP3" -mindepth 1 | wc -l | tr -d ' ')
assert_eq "backup dir is empty for empty source" "0" "$ITEMS_IN_BACKUP"

# =========================================================
echo ""
echo "=== Test 4: Hidden files are backed up ==="
# =========================================================
DIR4="$TEST_ROOT/test4"
mkdir -p "$DIR4"
echo "secret" > "$DIR4/.hidden"

bash "$BACKUP_SCRIPT" "$DIR4" >/dev/null 2>&1
BACKUP4=$(find "$DIR4" -maxdepth 1 -type d -name 'backup_*' | head -1)
assert_eq ".hidden file copied" "secret" "$(cat "$BACKUP4/.hidden")"

# =========================================================
echo ""
echo "=== Test 5: Invalid arguments ==="
# =========================================================
# No argument
OUT_NO_ARG=$(bash "$BACKUP_SCRIPT" 2>&1) || true
echo "$OUT_NO_ARG" | grep -qi "usage" && { echo "  PASS: no-arg shows usage"; PASS=$((PASS+1)); } || { echo "  FAIL: no-arg should show usage"; FAIL=$((FAIL+1)); }

# Non-existent path
OUT_BAD=$(bash "$BACKUP_SCRIPT" "/nonexistent_path_xyz" 2>&1) || true
echo "$OUT_BAD" | grep -qi "error" && { echo "  PASS: non-existent path shows error"; PASS=$((PASS+1)); } || { echo "  FAIL: non-existent path should show error"; FAIL=$((FAIL+1)); }

# File instead of directory
TMPFILE="$TEST_ROOT/not_a_dir.txt"
echo "x" > "$TMPFILE"
OUT_FILE=$(bash "$BACKUP_SCRIPT" "$TMPFILE" 2>&1) || true
echo "$OUT_FILE" | grep -qi "not a directory" && { echo "  PASS: file arg shows 'not a directory'"; PASS=$((PASS+1)); } || { echo "  FAIL: file arg should show 'not a directory'"; FAIL=$((FAIL+1)); }

# =========================================================
echo ""
echo "=============================="
echo "Results: $PASS passed, $FAIL failed"
echo "=============================="

[ "$FAIL" -eq 0 ] && exit 0 || exit 1

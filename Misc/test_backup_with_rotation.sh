#!/bin/bash

# Regression tests for Misc/backup_with_rotation.sh
# Run: bash Misc/test_backup_with_rotation.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BACKUP_SCRIPT="$SCRIPT_DIR/backup_with_rotation.sh"
TEST_ROOT=$(mktemp -d)
PASS=0
FAIL=0

cleanup() {
    rm -rf "$TEST_ROOT"
}
trap cleanup EXIT

assert() {
    local desc="$1" condition="$2"
    if eval "$condition"; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc"
        FAIL=$((FAIL + 1))
    fi
}

count_backups() {
    local dir="$1"
    local count=0
    for d in "$dir"/backup_*; do
        [ -d "$d" ] && count=$((count + 1))
    done
    # Handle nullglob-off case: if the literal glob didn't match, count stays 0
    [ -d "$dir/backup_*" ] 2>/dev/null && count=0
    echo "$count"
}

# ============================================================
echo "=== Test 1: First backup of a populated directory ==="
# ============================================================
DIR1="$TEST_ROOT/test1"
mkdir -p "$DIR1"
echo "hello" > "$DIR1/file1.txt"
echo "world" > "$DIR1/file2.txt"
mkdir "$DIR1/subdir"
echo "nested" > "$DIR1/subdir/nested.txt"

OUTPUT=$(bash "$BACKUP_SCRIPT" "$DIR1")
echo "$OUTPUT"

BACKUPS=$(count_backups "$DIR1")
assert "exactly 1 backup exists" '[ "$BACKUPS" -eq 1 ]'

# The backup should contain the original files, not another backup_* dir
LATEST=$(ls -d "$DIR1"/backup_* | head -1)
assert "backup contains file1.txt" '[ -f "$LATEST/file1.txt" ]'
assert "backup contains subdir/nested.txt" '[ -f "$LATEST/subdir/nested.txt" ]'
assert "backup does NOT contain a nested backup_* dir" '! ls -d "$LATEST"/backup_* >/dev/null 2>&1'

# ============================================================
echo ""
echo "=== Test 2: Repeated execution triggers rotation ==="
# ============================================================
DIR2="$TEST_ROOT/test2"
mkdir -p "$DIR2"
echo "data" > "$DIR2/data.txt"

for i in 1 2 3 4 5; do
    bash "$BACKUP_SCRIPT" "$DIR2" >/dev/null
    sleep 1.1  # ensure distinct timestamps
done

BACKUPS=$(count_backups "$DIR2")
assert "exactly 3 backups remain after 5 runs" '[ "$BACKUPS" -eq 3 ]'
assert "data.txt still exists in source" '[ -f "$DIR2/data.txt" ]'

# ============================================================
echo ""
echo "=== Test 3: Empty directory backup ==="
# ============================================================
DIR3="$TEST_ROOT/test3"
mkdir -p "$DIR3"

OUTPUT=$(bash "$BACKUP_SCRIPT" "$DIR3")
echo "$OUTPUT"

BACKUPS=$(count_backups "$DIR3")
assert "exactly 1 backup created for empty dir" '[ "$BACKUPS" -eq 1 ]'

LATEST=$(ls -d "$DIR3"/backup_* | head -1)
# backup folder should exist but be empty (no files copied)
FILE_COUNT=$(find "$LATEST" -mindepth 1 | wc -l | tr -d ' ')
assert "backup folder is empty (no source files)" '[ "$FILE_COUNT" -eq 0 ]'

# ============================================================
echo ""
echo "=== Test 4: Directory with only hidden files ==="
# ============================================================
DIR4="$TEST_ROOT/test4"
mkdir -p "$DIR4"
echo "secret" > "$DIR4/.hidden"

OUTPUT=$(bash "$BACKUP_SCRIPT" "$DIR4")
echo "$OUTPUT"

BACKUPS=$(count_backups "$DIR4")
assert "exactly 1 backup for hidden-file dir" '[ "$BACKUPS" -eq 1 ]'

LATEST=$(ls -d "$DIR4"/backup_* | head -1)
assert "hidden file was backed up" '[ -f "$LATEST/.hidden" ]'

# ============================================================
echo ""
echo "=== Test 5: Invalid arguments ==="
# ============================================================

# No argument
if bash "$BACKUP_SCRIPT" 2>/dev/null; then
    assert "no-arg exits non-zero" 'false'
else
    assert "no-arg exits non-zero" 'true'
fi

# Non-existent path
if bash "$BACKUP_SCRIPT" "/no/such/path" 2>/dev/null; then
    assert "non-existent path exits non-zero" 'false'
else
    assert "non-existent path exits non-zero" 'true'
fi

# A regular file, not a directory
TMPFILE="$TEST_ROOT/afile.txt"
echo "x" > "$TMPFILE"
if bash "$BACKUP_SCRIPT" "$TMPFILE" 2>/dev/null; then
    assert "file-as-arg exits non-zero" 'false'
else
    assert "file-as-arg exits non-zero" 'true'
fi

# ============================================================
echo ""
echo "=== Test 6: Non-backup subdirectories are never deleted ==="
# ============================================================
DIR6="$TEST_ROOT/test6"
mkdir -p "$DIR6"
echo "keep" > "$DIR6/important.txt"
mkdir "$DIR6/my_folder"
echo "safe" > "$DIR6/my_folder/safe.txt"

for i in 1 2 3 4; do
    bash "$BACKUP_SCRIPT" "$DIR6" >/dev/null
    sleep 1.1
done

assert "my_folder still exists" '[ -d "$DIR6/my_folder" ]'
assert "important.txt still exists" '[ -f "$DIR6/important.txt" ]'
BACKUPS=$(count_backups "$DIR6")
assert "exactly 3 backups after 4 runs" '[ "$BACKUPS" -eq 3 ]'

# ============================================================
echo ""
echo "================================"
echo "Results: $PASS passed, $FAIL failed"
echo "================================"

[ "$FAIL" -eq 0 ] && exit 0 || exit 1

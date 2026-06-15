#!/bin/bash

# ------------------------------------------------------------------
# test_file_operations.sh
# Minimal regression tests for file_operations.sh
#
# Run from any directory:
#   bash "Task 1/test_file_operations.sh"
# ------------------------------------------------------------------

set -u

PASS=0
FAIL=0

# Locate script-under-test and assets relative to THIS test file
TEST_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="${TEST_DIR}/file_operations.sh"
ASSETS="${TEST_DIR}/assets"

# ---- helpers -----------------------------------------------------

assert_contains() {
    local description="$1"
    local haystack="$2"
    local needle="$3"
    if echo "$haystack" | grep -qF "$needle"; then
        echo "  PASS: $description"
        (( PASS++ ))
    else
        echo "  FAIL: $description"
        echo "        Expected output to contain: $needle"
        echo "        Actual output:"
        echo "$haystack" | sed 's/^/          /'
        (( FAIL++ ))
    fi
}

assert_not_contains() {
    local description="$1"
    local haystack="$2"
    local needle="$3"
    if echo "$haystack" | grep -qF "$needle"; then
        echo "  FAIL: $description"
        echo "        Expected output NOT to contain: $needle"
        (( FAIL++ ))
    else
        echo "  PASS: $description"
        (( PASS++ ))
    fi
}

assert_exit_code() {
    local description="$1"
    local expected="$2"
    local actual="$3"
    if [ "$actual" -eq "$expected" ]; then
        echo "  PASS: $description"
        (( PASS++ ))
    else
        echo "  FAIL: $description (expected exit $expected, got $actual)"
        (( FAIL++ ))
    fi
}

assert_line_count() {
    local description="$1"
    local output="$2"
    local expected="$3"
    # Count non-empty output lines
    local actual
    if [ -z "$output" ]; then
        actual=0
    else
        actual=$(echo "$output" | wc -l | tr -d ' ')
    fi
    if [ "$actual" -eq "$expected" ]; then
        echo "  PASS: $description"
        (( PASS++ ))
    else
        echo "  FAIL: $description (expected $expected lines, got $actual)"
        echo "        Output:"
        echo "$output" | sed 's/^/          /'
        (( FAIL++ ))
    fi
}

# ==================================================================
echo "=== Test 1: Relative paths resolved from list file's directory ==="
# Run from /tmp so that CWD is completely different from assets dir
output=$(cd /tmp && bash "$SCRIPT" "${ASSETS}/list.txt" 2>&1)
rc=$?

assert_exit_code "script exits 0 on valid input" 0 "$rc"
assert_contains "file_a.txt found with correct size (14 bytes)" \
    "$output" "File: file_a.txt, Size: 14 bytes"
assert_contains "file_b.txt found with correct size (7 bytes)" \
    "$output" "File: file_b.txt, Size: 7 bytes"

# ==================================================================
echo ""
echo "=== Test 2: Blank lines and comment lines are skipped ==========="
# The list file contains 2 valid files, 1 missing file, 2 comments,
# and several blank lines.  Expect exactly 3 output lines (2 found +
# 1 not-found error).
assert_line_count "exactly 3 output lines (2 OK + 1 missing)" "$output" 3
assert_not_contains "no output for comment line" \
    "$output" "This is a comment"
assert_not_contains "no output for blank line" \
    "$output" "Size:  bytes"

# ==================================================================
echo ""
echo "=== Test 3: Missing file produces clear error ===================="
assert_contains "missing file reported as 'not found'" \
    "$output" "Error: File not found: no_such_file.txt"

# ==================================================================
echo ""
echo "=== Test 4: No arguments shows usage and exits non-zero =========="
output_noarg=$(bash "$SCRIPT" 2>&1)
rc_noarg=$?

assert_exit_code "exit code non-zero when no args" 1 "$rc_noarg"
assert_contains "usage message shown" "$output_noarg" "Usage:"

# ==================================================================
echo ""
echo "=== Test 5: Non-existent list file ==============================="
output_nofile=$(bash "$SCRIPT" "/tmp/does_not_exist_list.txt" 2>&1)
rc_nofile=$?

assert_exit_code "exit code non-zero for missing list file" 1 "$rc_nofile"
assert_contains "error mentions 'does not exist'" \
    "$output_nofile" "does not exist"

# ==================================================================
echo ""
echo "=== Test 6: Unreadable list file ================================="
unreadable="/tmp/_test_unreadable_list_$$.txt"
echo "file_a.txt" > "$unreadable"
chmod 000 "$unreadable" 2>/dev/null
output_unread=$(bash "$SCRIPT" "$unreadable" 2>&1)
rc_unread=$?
rm -f "$unreadable"

# Only test if chmod 000 actually took effect (root can bypass)
if [ ! -r "/tmp/_test_unreadable_list_$$.txt" ] 2>/dev/null || [ "$(id -u)" -ne 0 ]; then
    assert_exit_code "exit code non-zero for unreadable list file" 1 "$rc_unread"
    assert_contains "error mentions 'not readable'" \
        "$output_unread" "not readable"
else
    echo "  SKIP: running as root, cannot test unreadable file"
fi

# ==================================================================
echo ""
echo "=== Test 7: Cross-platform — no GNU-only stat flags used ========="
# Grep the script source for the known-bad pattern
if grep -q 'stat --printf' "$SCRIPT"; then
    echo "  FAIL: script still contains 'stat --printf' (GNU-only)"
    (( FAIL++ ))
else
    echo "  PASS: no GNU-only 'stat --printf' found in source"
    (( PASS++ ))
fi

# Also confirm the script doesn't use stat -c (also GNU-only)
if grep -qE 'stat\s+-c\b' "$SCRIPT"; then
    echo "  FAIL: script still contains 'stat -c' (GNU-only)"
    (( FAIL++ ))
else
    echo "  PASS: no GNU-only 'stat -c' found in source"
    (( PASS++ ))
fi

# ==================================================================
echo ""
echo "=== Test 8: Running from a deeply different CWD =================="
# Create a temp dir, run from there with an absolute path to the list
tmpdir=$(mktemp -d)
output_abs=$(cd "$tmpdir" && bash "$SCRIPT" "${ASSETS}/list.txt" 2>&1)
rc_abs=$?
rm -rf "$tmpdir"

assert_exit_code "exit 0 when run from temp dir with absolute list path" 0 "$rc_abs"
assert_contains "file_a.txt resolved correctly from temp CWD" \
    "$output_abs" "File: file_a.txt, Size: 14 bytes"
assert_contains "file_b.txt resolved correctly from temp CWD" \
    "$output_abs" "File: file_b.txt, Size: 7 bytes"

# ==================================================================
echo ""
echo "=============================================================="
echo "Results:  $PASS passed,  $FAIL failed"
echo "=============================================================="

if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
exit 0

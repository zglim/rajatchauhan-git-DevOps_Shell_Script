#!/bin/bash
#
# Regression tests for file_operations.sh
# Verifies: cross-directory execution, blank/comment skipping, portable stat,
#           error messages for missing/unreadable files, and parameter validation.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$SCRIPT_DIR/file_operations.sh"
ASSETS="$SCRIPT_DIR/assets"
PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); echo "  PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL: $1"; }

echo "=== file_operations.sh regression tests ==="
echo ""

# -------------------------------------------------------
# Test 1: No arguments → usage error
# -------------------------------------------------------
echo "Test 1: Missing argument produces usage error"
output=$(bash "$SCRIPT" 2>&1)
rc=$?
if [ $rc -ne 0 ] && echo "$output" | grep -qi "usage\|no manifest\|error"; then
    pass "exit code $rc and error message present"
else
    fail "expected non-zero exit and error message (got rc=$rc)"
fi

# -------------------------------------------------------
# Test 2: Non-existent manifest file
# -------------------------------------------------------
echo "Test 2: Non-existent manifest file"
output=$(bash "$SCRIPT" "/tmp/no_such_manifest_$$" 2>&1)
rc=$?
if [ $rc -ne 0 ] && echo "$output" | grep -qi "does not exist\|not found\|error"; then
    pass "exit code $rc and descriptive error"
else
    fail "expected non-zero exit (got rc=$rc)"
fi

# -------------------------------------------------------
# Test 3: Running from a DIFFERENT working directory
#         with a manifest that uses relative paths.
# -------------------------------------------------------
echo "Test 3: Relative paths resolve against manifest dir, not CWD"
output=$(cd /tmp && bash "$SCRIPT" "$ASSETS/list.txt" 2>&1)
if echo "$output" | grep -q "sample1.txt.*Size:.*bytes"; then
    pass "sample1.txt found from /tmp"
else
    fail "sample1.txt not resolved correctly when CWD=/tmp"
fi
if echo "$output" | grep -q "sample2.txt.*Size:.*bytes"; then
    pass "sample2.txt found from /tmp"
else
    fail "sample2.txt not resolved correctly when CWD=/tmp"
fi

# -------------------------------------------------------
# Test 4: Blank lines and comment lines are skipped
# -------------------------------------------------------
echo "Test 4: Blank lines and comment lines skipped"
output=$(bash "$SCRIPT" "$ASSETS/list.txt" 2>&1)
# The manifest has blank lines & comments; they must NOT produce error lines
# about files named "" or "#..."
if echo "$output" | grep -q "File: .*#"; then
    fail "comment line was treated as a filename"
elif echo "$output" | grep -qP "File: .*, Size:.*bytes" 2>/dev/null || echo "$output" | grep -q "File: .*, Size:.*bytes"; then
    pass "no comment/blank artefacts in output"
else
    fail "unexpected output format"
fi

# -------------------------------------------------------
# Test 5: Non-existent file listed → clear error
# -------------------------------------------------------
echo "Test 5: Non-existent file gets clear error"
output=$(bash "$SCRIPT" "$ASSETS/list.txt" 2>&1)
if echo "$output" | grep -q "nonexistent_file.txt" && echo "$output" | grep -q "not found"; then
    pass "nonexistent_file.txt reported as not found"
else
    fail "missing 'not found' message for nonexistent_file.txt"
fi

# -------------------------------------------------------
# Test 6: File sizes are numeric and non-zero
# -------------------------------------------------------
echo "Test 6: Reported sizes are numeric"
sizes=$(echo "$output" | grep "Size:" | sed 's/.*Size: *//;s/ *bytes.*//')
all_numeric=true
for s in $sizes; do
    if ! [[ "$s" =~ ^[0-9]+$ ]]; then
        all_numeric=false
        break
    fi
done
if $all_numeric && [ -n "$sizes" ]; then
    pass "all sizes are numeric"
else
    fail "non-numeric or empty sizes detected"
fi

# -------------------------------------------------------
# Test 7: Unreadable manifest (permission denied)
# -------------------------------------------------------
echo "Test 7: Unreadable manifest file"
tmp_manifest="/tmp/unreadable_manifest_$$"
echo "sample1.txt" > "$tmp_manifest"
chmod 000 "$tmp_manifest"
output=$(bash "$SCRIPT" "$tmp_manifest" 2>&1)
rc=$?
chmod 644 "$tmp_manifest" 2>/dev/null
rm -f "$tmp_manifest"
if [ $rc -ne 0 ] && echo "$output" | grep -qi "not readable\|error"; then
    pass "unreadable manifest rejected"
else
    fail "expected rejection for unreadable manifest (rc=$rc)"
fi

# -------------------------------------------------------
# Test 8: stat portability — wc -c must not fail
# -------------------------------------------------------
echo "Test 8: Portable size retrieval (no stat --printf)"
output=$(bash "$SCRIPT" "$ASSETS/list.txt" 2>&1)
if echo "$output" | grep -qi "stat\|command not found\|illegal option\|unrecognized"; then
    fail "stat-related error detected — not portable"
else
    pass "no stat errors in output"
fi

# -------------------------------------------------------
# Summary
# -------------------------------------------------------
echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
if [ $FAIL -gt 0 ]; then
    exit 1
fi
exit 0

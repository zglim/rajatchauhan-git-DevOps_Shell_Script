#!/bin/bash
# Regression tests for file_management.sh
# Covers: default mode, custom args, dry-run, conflict, invalid inputs

SCRIPT="$(cd "$(dirname "$0")" && pwd)/file_management.sh"
PASS=0
FAIL=0

assert_eq() {
  local label="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    echo "  PASS: $label"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $label (expected='$expected', got='$actual')"
    FAIL=$((FAIL + 1))
  fi
}

assert_contains() {
  local label="$1" needle="$2" haystack="$3"
  if echo "$haystack" | grep -qF -- "$needle"; then
    echo "  PASS: $label"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $label (output does not contain '$needle')"
    FAIL=$((FAIL + 1))
  fi
}

assert_exit() {
  local label="$1" expected="$2" actual="$3"
  if [ "$expected" -eq "$actual" ]; then
    echo "  PASS: $label (exit $actual)"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $label (expected exit $expected, got $actual)"
    FAIL=$((FAIL + 1))
  fi
}

# ============================================================================
echo "=== Test 1: Default mode (current dir, .txt, file prefix) ==="
tmpdir=$(mktemp -d)
touch "$tmpdir/alpha.txt" "$tmpdir/beta.txt" "$tmpdir/gamma.txt"

output=$(cd "$tmpdir" && bash "$SCRIPT" 2>&1)
rc=$?

assert_exit "exit code 0" 0 "$rc"
assert_eq "file1.txt exists" "yes" "$([ -f "$tmpdir/file1.txt" ] && echo yes || echo no)"
assert_eq "file2.txt exists" "yes" "$([ -f "$tmpdir/file2.txt" ] && echo yes || echo no)"
assert_eq "file3.txt exists" "yes" "$([ -f "$tmpdir/file3.txt" ] && echo yes || echo no)"
assert_contains "summary shows Matched: 3" "Matched: 3" "$output"
assert_contains "summary shows Renamed: 3" "Renamed: 3" "$output"
rm -rf "$tmpdir"

# ============================================================================
echo "=== Test 2: Custom directory, prefix, extension, start ==="
tmpdir=$(mktemp -d)
touch "$tmpdir/a.log" "$tmpdir/b.log"

output=$(bash "$SCRIPT" -d "$tmpdir" -e .log -p log_ -s 5 2>&1)
rc=$?

assert_exit "exit code 0" 0 "$rc"
assert_eq "log_5.log exists" "yes" "$([ -f "$tmpdir/log_5.log" ] && echo yes || echo no)"
assert_eq "log_6.log exists" "yes" "$([ -f "$tmpdir/log_6.log" ] && echo yes || echo no)"
assert_contains "summary shows Renamed: 2" "Renamed: 2" "$output"
rm -rf "$tmpdir"

# ============================================================================
echo "=== Test 3: Dry-run — preview only, no files renamed ==="
tmpdir=$(mktemp -d)
touch "$tmpdir/one.txt" "$tmpdir/two.txt"

output=$(bash "$SCRIPT" -d "$tmpdir" -n 2>&1)
rc=$?

assert_exit "exit code 0" 0 "$rc"
assert_contains "DRY-RUN" "DRY-RUN" "$output"
assert_contains "preview lists mapping" "->" "$output"
# Original files must still exist (not renamed)
assert_eq "one.txt still exists" "yes" "$([ -f "$tmpdir/one.txt" ] && echo yes || echo no)"
assert_eq "two.txt still exists" "yes" "$([ -f "$tmpdir/two.txt" ] && echo yes || echo no)"
# Renamed targets must NOT exist
assert_eq "file1.txt must not exist" "no" "$([ -f "$tmpdir/file1.txt" ] && echo yes || echo no)"
rm -rf "$tmpdir"

# ============================================================================
echo "=== Test 4: Conflict detection — abort when target name exists ==="
tmpdir=$(mktemp -d)
touch "$tmpdir/alpha.txt" "$tmpdir/beta.txt"
touch "$tmpdir/file1.txt"  # pre-existing conflict

output=$(bash "$SCRIPT" -d "$tmpdir" 2>&1)
rc=$?

assert_exit "exit code 1 on conflict" 1 "$rc"
assert_contains "conflict message" "Conflict" "$output"
# Original files must be untouched
assert_eq "alpha.txt still exists" "yes" "$([ -f "$tmpdir/alpha.txt" ] && echo yes || echo no)"
assert_eq "beta.txt still exists" "yes" "$([ -f "$tmpdir/beta.txt" ] && echo yes || echo no)"
rm -rf "$tmpdir"

# ============================================================================
echo "=== Test 5: Non-existent directory ==="
output=$(bash "$SCRIPT" -d /nonexistent_dir_xyz 2>&1)
rc=$?
assert_exit "exit code 1" 1 "$rc"
assert_contains "error message" "does not exist" "$output"

# ============================================================================
echo "=== Test 6: No matching files ==="
tmpdir=$(mktemp -d)
touch "$tmpdir/readme.md"

output=$(bash "$SCRIPT" -d "$tmpdir" -e .txt 2>&1)
rc=$?

assert_exit "exit code 0" 0 "$rc"
assert_contains "no files message" "No files" "$output"
rm -rf "$tmpdir"

# ============================================================================
echo "=== Test 7: Empty extension rejected ==="
output=$(bash "$SCRIPT" -e "" 2>&1)
rc=$?
assert_exit "exit code 1" 1 "$rc"
assert_contains "empty extension error" "must not be empty" "$output"

# ============================================================================
echo "=== Test 8: Invalid start number ==="
output=$(bash "$SCRIPT" -s abc 2>&1)
rc=$?
assert_exit "exit code 1" 1 "$rc"
assert_contains "invalid number error" "not a valid" "$output"

# ============================================================================
echo ""
echo "=============================="
echo "Results: $PASS passed, $FAIL failed"
echo "=============================="

[ "$FAIL" -eq 0 ] && exit 0 || exit 1

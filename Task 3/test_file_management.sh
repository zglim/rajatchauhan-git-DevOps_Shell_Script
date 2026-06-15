#!/bin/bash
# Regression tests for file_management.sh
# Each test creates an isolated temp directory, runs the script, and checks results.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$SCRIPT_DIR/file_management.sh"

PASS=0
FAIL=0
TOTAL=0

# ── Helpers ───────────────────────────────────────────────────────────────────

pass() {
  PASS=$((PASS + 1))
  TOTAL=$((TOTAL + 1))
  echo "  PASS: $1"
}

fail() {
  FAIL=$((FAIL + 1))
  TOTAL=$((TOTAL + 1))
  echo "  FAIL: $1"
  if [[ -n "${2:-}" ]]; then
    echo "        detail: $2"
  fi
}

assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    pass "$desc"
  else
    fail "$desc" "expected='$expected' actual='$actual'"
  fi
}

assert_file_exists() {
  if [[ -f "$2" ]]; then
    pass "$1"
  else
    fail "$1" "file '$2' does not exist"
  fi
}

assert_file_not_exists() {
  if [[ ! -e "$2" ]]; then
    pass "$1"
  else
    fail "$1" "file '$2' should not exist but does"
  fi
}

assert_exit_code() {
  local desc="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    pass "$desc"
  else
    fail "$desc" "expected exit=$expected actual exit=$actual"
  fi
}

assert_output_contains() {
  local desc="$1" needle="$2" output="$3"
  if echo "$output" | grep -qF "$needle"; then
    pass "$desc"
  else
    fail "$desc" "output does not contain '$needle'"
  fi
}

assert_output_not_contains() {
  local desc="$1" needle="$2" output="$3"
  if ! echo "$output" | grep -qF "$needle"; then
    pass "$desc"
  else
    fail "$desc" "output should NOT contain '$needle'"
  fi
}

make_tmpdir() {
  mktemp -d "${TMPDIR:-/tmp}/fm_test.XXXXXX"
}

cleanup() {
  rm -rf "$1"
}

# Helper: run script and capture output + exit code without set -e interference
run_script() {
  local _rc=0
  local _output
  _output=$(bash "$SCRIPT" "$@" 2>&1) || _rc=$?
  echo "$_output"
  return $_rc
}

# ── Test 1: Default mode (no arguments) ──────────────────────────────────────
echo ""
echo "=== Test 1: Default mode (no arguments, .txt, file prefix) ==="
{
  tmpdir=$(make_tmpdir)
  mkdir -p "$tmpdir/work"
  touch "$tmpdir/work/a.txt" "$tmpdir/work/b.txt" "$tmpdir/work/c.txt"

  rc=0; output=$(cd "$tmpdir/work" && bash "$SCRIPT" 2>&1) || rc=$?

  assert_exit_code "exit code is 0" 0 $rc
  assert_file_exists "a.txt renamed to file1.txt" "$tmpdir/work/file1.txt"
  assert_file_exists "b.txt renamed to file2.txt" "$tmpdir/work/file2.txt"
  assert_file_exists "c.txt renamed to file3.txt" "$tmpdir/work/file3.txt"
  assert_output_contains "reports 3 matched" "Found 3 file" "$output"
  assert_output_contains "reports 3 renamed" "Renamed : 3" "$output"
  cleanup "$tmpdir"
}

# ── Test 2: Custom directory, prefix, extension, start ────────────────────────
echo ""
echo "=== Test 2: Custom directory / prefix / extension / start ==="
{
  tmpdir=$(make_tmpdir)
  mkdir -p "$tmpdir/photos"
  touch "$tmpdir/photos/sunset.jpg" "$tmpdir/photos/sunrise.jpg"

  rc=0; output=$(bash "$SCRIPT" -d "$tmpdir/photos" -e .jpg -p img -s 10 2>&1) || rc=$?

  assert_exit_code "exit code is 0" 0 $rc
  assert_file_exists "sunset.jpg -> img10.jpg" "$tmpdir/photos/img10.jpg"
  assert_file_exists "sunrise.jpg -> img11.jpg" "$tmpdir/photos/img11.jpg"
  assert_file_not_exists "sunset.jpg no longer exists" "$tmpdir/photos/sunset.jpg"
  assert_file_not_exists "sunrise.jpg no longer exists" "$tmpdir/photos/sunrise.jpg"
  assert_output_contains "matched 2" "Found 2 file" "$output"
  cleanup "$tmpdir"
}

# ── Test 3: Dry-run previews but does NOT rename ─────────────────────────────
echo ""
echo "=== Test 3: Dry-run (preview only, no disk changes) ==="
{
  tmpdir=$(make_tmpdir)
  mkdir -p "$tmpdir/docs"
  touch "$tmpdir/docs/alpha.md" "$tmpdir/docs/beta.md"

  rc=0; output=$(bash "$SCRIPT" -d "$tmpdir/docs" -e .md -p doc -n 2>&1) || rc=$?

  assert_exit_code "exit code is 0" 0 $rc
  # Original files must still exist
  assert_file_exists "alpha.md still exists" "$tmpdir/docs/alpha.md"
  assert_file_exists "beta.md still exists" "$tmpdir/docs/beta.md"
  # Renamed files must NOT exist
  assert_file_not_exists "doc1.md not created" "$tmpdir/docs/doc1.md"
  assert_file_not_exists "doc2.md not created" "$tmpdir/docs/doc2.md"
  assert_output_contains "DRY-RUN banner shown" "DRY-RUN" "$output"
  assert_output_contains "shows PREVIEW mapping" "PREVIEW" "$output"
  cleanup "$tmpdir"
}

# ── Test 4: Target filename conflict → skip + safe exit ──────────────────────
echo ""
echo "=== Test 4: Target filename conflict → skip, no crash ==="
{
  tmpdir=$(make_tmpdir)
  mkdir -p "$tmpdir/data"
  # Create source files: a.csv and b.csv
  touch "$tmpdir/data/a.csv" "$tmpdir/data/b.csv"
  # Pre-create file2.csv so that b.csv -> file2.csv will conflict
  echo "original" > "$tmpdir/data/file2.csv"

  rc=0; output=$(bash "$SCRIPT" -d "$tmpdir/data" -e .csv -p file 2>&1) || rc=$?

  # Script should complete (exit 0), but skip the conflicting rename
  assert_exit_code "exit code is 0" 0 $rc
  assert_output_contains "conflict message shown" "CONFLICT" "$output"
  assert_output_contains "skipped count >= 1" "Skipped :" "$output"
  # a.csv should be renamed to file1.csv (no conflict)
  assert_file_exists "a.csv -> file1.csv succeeded" "$tmpdir/data/file1.csv"
  # b.csv should still exist because file2.csv conflicted
  assert_file_exists "b.csv still exists (conflict)" "$tmpdir/data/b.csv"
  # The original file2.csv content should be preserved (renamed to file3.csv)
  assert_file_exists "original file2.csv -> file3.csv" "$tmpdir/data/file3.csv"
  cleanup "$tmpdir"
}

# ── Test 5: Non-existent directory → error exit ──────────────────────────────
echo ""
echo "=== Test 5: Non-existent directory → error ==="
{
  rc=0; output=$(bash "$SCRIPT" -d "/nonexistent_dir_abc123" 2>&1) || rc=$?

  assert_exit_code "exit code is non-zero" 1 $rc
  assert_output_contains "error mentions directory" "does not exist" "$output"
}

# ── Test 6: Empty extension → error exit ─────────────────────────────────────
echo ""
echo "=== Test 6: Empty extension → error ==="
{
  tmpdir=$(make_tmpdir)
  rc=0; output=$(bash "$SCRIPT" -d "$tmpdir" -e "" 2>&1) || rc=$?

  assert_exit_code "exit code is non-zero" 1 $rc
  assert_output_contains "error mentions extension" "Extension" "$output"
  cleanup "$tmpdir"
}

# ── Test 7: No matching files → error exit ───────────────────────────────────
echo ""
echo "=== Test 7: No matching files in directory → error ==="
{
  tmpdir=$(make_tmpdir)
  mkdir -p "$tmpdir/empty"

  rc=0; output=$(bash "$SCRIPT" -d "$tmpdir/empty" -e .xyz 2>&1) || rc=$?

  assert_exit_code "exit code is non-zero" 1 $rc
  assert_output_contains "no files message" "No files" "$output"
  cleanup "$tmpdir"
}

# ── Test 8: Self-rename skip (file already has target name) ──────────────────
echo ""
echo "=== Test 8: File already named with target name → skip ==="
{
  tmpdir=$(make_tmpdir)
  mkdir -p "$tmpdir/self"
  touch "$tmpdir/self/file1.txt"

  rc=0; output=$(bash "$SCRIPT" -d "$tmpdir/self" -e .txt -p file 2>&1) || rc=$?

  assert_exit_code "exit code is 0" 0 $rc
  assert_output_contains "SKIP message" "SKIP" "$output"
  assert_file_exists "file1.txt still exists" "$tmpdir/self/file1.txt"
  cleanup "$tmpdir"
}

# ── Test 9: Unknown option → error ───────────────────────────────────────────
echo ""
echo "=== Test 9: Unknown option → error ==="
{
  rc=0; output=$(bash "$SCRIPT" --foobar 2>&1) || rc=$?

  assert_exit_code "exit code is non-zero" 1 $rc
  assert_output_contains "unknown option message" "Unknown option" "$output"
}

# ── Test 10: Summary output includes all counters ────────────────────────────
echo ""
echo "=== Test 10: Summary output has Matched/Renamed/Skipped/Failed ==="
{
  tmpdir=$(make_tmpdir)
  mkdir -p "$tmpdir/sum"
  touch "$tmpdir/sum/x.txt" "$tmpdir/sum/y.txt"

  rc=0; output=$(bash "$SCRIPT" -d "$tmpdir/sum" 2>&1) || rc=$?

  assert_exit_code "exit code is 0" 0 $rc
  assert_output_contains "Matched counter" "Matched :" "$output"
  assert_output_contains "Renamed counter" "Renamed :" "$output"
  assert_output_contains "Skipped counter" "Skipped :" "$output"
  assert_output_contains "Failed counter" "Failed  :" "$output"
  cleanup "$tmpdir"
}

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "======================================="
echo "  TOTAL: $TOTAL  |  PASS: $PASS  |  FAIL: $FAIL"
echo "======================================="

if [[ "$FAIL" -gt 0 ]]; then
  exit 1
fi
exit 0

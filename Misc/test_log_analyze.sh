#!/bin/bash

# test_log_analyze.sh - Minimal regression tests for log_analyze.sh
# Run from the Misc/ directory:  bash test_log_analyze.sh

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LOG_ANALYZE="${SCRIPT_DIR}/log_analyze.sh"
WORK_DIR=$(mktemp -d)
PASS=0
FAIL=0

cleanup() { rm -rf "$WORK_DIR"; }
trap cleanup EXIT

assert_file_exists() {
    local file="$1" label="$2"
    if [ -f "$file" ]; then
        echo "  PASS: $label"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $label (file not found: $file)"
        FAIL=$((FAIL + 1))
    fi
}

assert_file_contains() {
    local file="$1" pattern="$2" label="$3"
    if grep -q "$pattern" "$file" 2>/dev/null; then
        echo "  PASS: $label"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $label (pattern '$pattern' not found in $file)"
        FAIL=$((FAIL + 1))
    fi
}

assert_exit_code() {
    local expected="$1" actual="$2" label="$3"
    if [ "$expected" -eq "$actual" ]; then
        echo "  PASS: $label"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $label (expected exit $expected, got $actual)"
        FAIL=$((FAIL + 1))
    fi
}

# ---------- Prepare sample logs ----------

cat > "$WORK_DIR/app.log" <<'LOGEOF'
2026-06-15 10:00:01 INFO  Application started
2026-06-15 10:00:02 ERROR Database connection failed
2026-06-15 10:00:03 ERROR Database connection failed
2026-06-15 10:00:04 WARN  Slow query detected
2026-06-15 10:00:05 CRITICAL Out of memory
2026-06-15 10:00:06 ERROR Timeout on request /api/users
2026-06-15 10:00:07 INFO  Request completed
2026-06-15 10:00:08 ERROR Null pointer exception in module X
2026-06-15 10:00:09 CRITICAL Disk full on /data
2026-06-15 10:00:10 ERROR Timeout on request /api/orders
LOGEOF

cat > "$WORK_DIR/clean.log" <<'LOGEOF'
2026-06-15 11:00:01 INFO  All systems operational
2026-06-15 11:00:02 INFO  Health check passed
2026-06-15 11:00:03 DEBUG Verbose debug info
LOGEOF

cat > "$WORK_DIR/custom.log" <<'LOGEOF'
2026-06-15 12:00:01 WARN something
2026-06-15 12:00:02 ERR  disk read failure
2026-06-15 12:00:03 ERR  disk read failure
2026-06-15 12:00:04 ERR  network timeout
2026-06-15 12:00:05 FATAL kernel panic
2026-06-15 12:00:06 ERR  permission denied
LOGEOF

# ---------- Test 1: Default parameters ----------
echo ""
echo "=== Test 1: Default parameter analysis ==="
OUT_DIR="$WORK_DIR/out1"
bash "$LOG_ANALYZE" -o "$OUT_DIR" "$WORK_DIR/app.log"
rc=$?
assert_exit_code 0 $rc "script exits 0"
REPORT=$(ls "$OUT_DIR"/summary_app.log_*.txt 2>/dev/null | head -1)
assert_file_exists "$REPORT" "summary report created"
assert_file_contains "$REPORT" "Total lines in log file: 10" "total lines correct"
assert_file_contains "$REPORT" "Total error count (ERROR): 5" "error count correct"
assert_file_contains "$REPORT" "CRITICAL" "critical section present"
assert_file_contains "$REPORT" "Out of memory" "critical event listed"
assert_file_contains "$REPORT" "Top 5 Error Messages" "top N section present"

# ---------- Test 2: Custom keywords and Top N ----------
echo ""
echo "=== Test 2: Custom keywords and Top N ==="
OUT_DIR="$WORK_DIR/out2"
bash "$LOG_ANALYZE" -e "ERR" -c "FATAL" -n 2 -o "$OUT_DIR" "$WORK_DIR/custom.log"
rc=$?
assert_exit_code 0 $rc "script exits 0 with custom keywords"
REPORT=$(ls "$OUT_DIR"/summary_custom.log_*.txt 2>/dev/null | head -1)
assert_file_exists "$REPORT" "summary report created for custom log"
assert_file_contains "$REPORT" "Error keyword    : ERR" "custom error keyword recorded"
assert_file_contains "$REPORT" "Critical keyword : FATAL" "custom critical keyword recorded"
assert_file_contains "$REPORT" "Total error count (ERR): 4" "custom error count correct"
assert_file_contains "$REPORT" "kernel panic" "FATAL event listed"
assert_file_contains "$REPORT" "Top 2 Error Messages" "Top N = 2 section header"

# ---------- Test 3: Archive on success ----------
echo ""
echo "=== Test 3: Successful archiving ==="
OUT_DIR="$WORK_DIR/out3"
ARCH_DIR="$WORK_DIR/archived"
bash "$LOG_ANALYZE" -o "$OUT_DIR" -a --archive-dir "$ARCH_DIR" "$WORK_DIR/app.log"
rc=$?
assert_exit_code 0 $rc "script exits 0 with archive"
assert_file_exists "$ARCH_DIR/app.log" "log file archived"

# Archive same file again — should not overwrite, should get timestamped copy
sleep 1
bash "$LOG_ANALYZE" -o "$OUT_DIR" -a --archive-dir "$ARCH_DIR" "$WORK_DIR/app.log"
rc=$?
assert_exit_code 0 $rc "second archive run exits 0"
ARCHIVE_COUNT=$(ls "$ARCH_DIR"/app.log* 2>/dev/null | wc -l | tr -d ' ')
if [ "$ARCHIVE_COUNT" -ge 2 ]; then
    echo "  PASS: duplicate archive avoided (count=$ARCHIVE_COUNT)"
    PASS=$((PASS + 1))
else
    echo "  FAIL: expected >=2 archived files, got $ARCHIVE_COUNT"
    FAIL=$((FAIL + 1))
fi

# ---------- Test 4: No-error log still produces summary ----------
echo ""
echo "=== Test 4: No-error log generates readable summary ==="
OUT_DIR="$WORK_DIR/out4"
bash "$LOG_ANALYZE" -o "$OUT_DIR" "$WORK_DIR/clean.log"
rc=$?
assert_exit_code 0 $rc "script exits 0 for clean log"
REPORT=$(ls "$OUT_DIR"/summary_clean.log_*.txt 2>/dev/null | head -1)
assert_file_exists "$REPORT" "summary report created for clean log"
assert_file_contains "$REPORT" "Total error count (ERROR): 0" "error count is 0"
assert_file_contains "$REPORT" "(none found)" "none-found placeholder present"

# ---------- Test 5: Edge cases — bad inputs ----------
echo ""
echo "=== Test 5: Edge cases ==="

# Non-existent log file
bash "$LOG_ANALYZE" "$WORK_DIR/no_such_file.log" 2>/dev/null
rc=$?
assert_exit_code 1 $rc "non-existent file exits 1"

# Empty error keyword
bash "$LOG_ANALYZE" -e "" "$WORK_DIR/app.log" 2>/dev/null
rc=$?
assert_exit_code 1 $rc "empty error keyword exits 1"

# Top N = 0
bash "$LOG_ANALYZE" -n 0 "$WORK_DIR/app.log" 2>/dev/null
rc=$?
assert_exit_code 1 $rc "Top N=0 exits 1"

# Top N = negative
bash "$LOG_ANALYZE" -n -3 "$WORK_DIR/app.log" 2>/dev/null
rc=$?
assert_exit_code 1 $rc "Top N=-3 exits 1"

# Top N = non-numeric
bash "$LOG_ANALYZE" -n abc "$WORK_DIR/app.log" 2>/dev/null
rc=$?
assert_exit_code 1 $rc "Top N=abc exits 1"

# Non-writable output dir
PROTECTED_DIR="$WORK_DIR/readonly"
mkdir -p "$PROTECTED_DIR"
chmod 444 "$PROTECTED_DIR"
bash "$LOG_ANALYZE" -o "$PROTECTED_DIR" "$WORK_DIR/app.log" 2>/dev/null
rc=$?
assert_exit_code 1 $rc "non-writable output dir exits 1"
chmod 755 "$PROTECTED_DIR"  # restore for cleanup

# ---------- Test 6: Multiple logs don't overwrite each other ----------
echo ""
echo "=== Test 6: Multiple logs produce distinct summaries ==="
OUT_DIR="$WORK_DIR/out6"
bash "$LOG_ANALYZE" -o "$OUT_DIR" "$WORK_DIR/app.log"
sleep 1  # ensure different timestamp
bash "$LOG_ANALYZE" -o "$OUT_DIR" "$WORK_DIR/clean.log"
SUMMARY_COUNT=$(ls "$OUT_DIR"/summary_*.txt 2>/dev/null | wc -l | tr -d ' ')
if [ "$SUMMARY_COUNT" -ge 2 ]; then
    echo "  PASS: multiple summaries coexist (count=$SUMMARY_COUNT)"
    PASS=$((PASS + 1))
else
    echo "  FAIL: expected >=2 summaries, got $SUMMARY_COUNT"
    FAIL=$((FAIL + 1))
fi

# ---------- Results ----------
echo ""
echo "========================================"
echo "  Results: $PASS passed, $FAIL failed"
echo "========================================"

[ "$FAIL" -eq 0 ] && exit 0 || exit 1

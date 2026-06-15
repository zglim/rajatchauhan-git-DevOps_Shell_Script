#!/bin/bash

# Regression tests for log_analyze.sh
# Run from the Misc/ directory or provide the path to log_analyze.sh

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ANALYZE="${SCRIPT_DIR}/log_analyze.sh"
TEST_DIR=""
PASSED=0
FAILED=0

setup() {
    TEST_DIR="$(mktemp -d)"
    chmod +x "$ANALYZE"
}

teardown() {
    if [ -n "$TEST_DIR" ] && [ -d "$TEST_DIR" ]; then
        rm -rf "$TEST_DIR"
    fi
}

pass() {
    PASSED=$((PASSED + 1))
    echo "  PASS: $1"
}

fail() {
    FAILED=$((FAILED + 1))
    echo "  FAIL: $1"
}

# Create a sample log file with mixed content
create_sample_log() {
    local dest="$1"
    cat > "$dest" <<'LOGEOF'
2024-01-15 10:00:01 INFO Application started
2024-01-15 10:00:02 INFO Loading configuration
2024-01-15 10:01:00 ERROR Failed to connect to database
2024-01-15 10:01:05 ERROR Failed to connect to database
2024-01-15 10:01:10 ERROR Timeout reading from cache
2024-01-15 10:02:00 CRITICAL Database connection pool exhausted
2024-01-15 10:02:01 ERROR Failed to connect to database
2024-01-15 10:03:00 INFO Retrying connection
2024-01-15 10:03:05 ERROR Authentication failed for user admin
2024-01-15 10:04:00 CRITICAL System memory usage above 95%
2024-01-15 10:05:00 INFO Health check passed
2024-01-15 10:06:00 ERROR Disk write failed on /dev/sda1
LOGEOF
}

# Create a log with no errors
create_clean_log() {
    local dest="$1"
    cat > "$dest" <<'LOGEOF'
2024-01-15 10:00:01 INFO Application started
2024-01-15 10:00:02 INFO Loading configuration
2024-01-15 10:01:00 INFO Connection established
2024-01-15 10:02:00 INFO Processing request
2024-01-15 10:03:00 INFO Request completed successfully
2024-01-15 10:04:00 INFO Health check passed
LOGEOF
}

# Create a log with custom keywords
create_custom_keyword_log() {
    local dest="$1"
    cat > "$dest" <<'LOGEOF'
2024-01-15 10:00:01 INFO Application started
2024-01-15 10:01:00 WARN Disk space low
2024-01-15 10:01:05 WARN Memory usage high
2024-01-15 10:02:00 FATAL Process crashed
2024-01-15 10:03:00 WARN Connection pool near limit
2024-01-15 10:04:00 FATAL Unrecoverable state
LOGEOF
}

###############################################################################
# Test 1: Default parameters analysis
###############################################################################
test_default_parameters() {
    echo "Test 1: Default parameters analysis"
    local log_file="${TEST_DIR}/app.log"
    local out_dir="${TEST_DIR}/output1"
    local arc_dir="${TEST_DIR}/archive1"
    mkdir -p "$out_dir" "$arc_dir"
    create_sample_log "$log_file"

    local result
    result=$("$ANALYZE" -o "$out_dir" -a "$arc_dir" "$log_file" 2>&1)

    # Check summary file was created
    local summary
    summary=$(find "$out_dir" -name "summary_app_*.txt" -type f | head -1)
    if [ -z "$summary" ]; then
        fail "No summary file created"
        return
    fi
    pass "Summary file created"

    # Check summary content
    if grep -q "Total lines" "$summary" && grep -q "Total error count: 6" "$summary"; then
        pass "Summary contains correct error count (6)"
    else
        fail "Summary missing or incorrect error count"
    fi

    if grep -q "CRITICAL EVENTS" "$summary" && grep -q "Database connection pool exhausted" "$summary"; then
        pass "Summary contains critical events"
    else
        fail "Summary missing critical events"
    fi

    if grep -q "TOP 5 ERROR MESSAGES" "$summary"; then
        pass "Summary contains Top 5 section"
    else
        fail "Summary missing Top N section"
    fi
}

###############################################################################
# Test 2: Custom keywords and Top N
###############################################################################
test_custom_keywords() {
    echo "Test 2: Custom keywords and Top N"
    local log_file="${TEST_DIR}/custom.log"
    local out_dir="${TEST_DIR}/output2"
    local arc_dir="${TEST_DIR}/archive2"
    mkdir -p "$out_dir" "$arc_dir"
    create_custom_keyword_log "$log_file"

    "$ANALYZE" -e "WARN" -c "FATAL" -n 2 -o "$out_dir" -a "$arc_dir" "$log_file" >/dev/null 2>&1

    local summary
    summary=$(find "$out_dir" -name "summary_custom_*.txt" -type f | head -1)
    if [ -z "$summary" ]; then
        fail "No summary file created with custom keywords"
        return
    fi
    pass "Summary file created with custom keywords"

    if grep -q "Error keyword    : WARN" "$summary"; then
        pass "Custom error keyword used"
    else
        fail "Custom error keyword not reflected in summary"
    fi

    if grep -q "Critical keyword : FATAL" "$summary"; then
        pass "Custom critical keyword used"
    else
        fail "Custom critical keyword not reflected in summary"
    fi

    if grep -q "TOP 2 ERROR MESSAGES" "$summary"; then
        pass "Custom Top N (2) used"
    else
        fail "Custom Top N not reflected in summary"
    fi

    # Verify FATAL events are listed
    if grep -q "Process crashed" "$summary" && grep -q "Unrecoverable state" "$summary"; then
        pass "Critical events found with custom FATAL keyword"
    else
        fail "Critical events not found with custom keyword"
    fi
}

###############################################################################
# Test 3: Successful archive
###############################################################################
test_archive() {
    echo "Test 3: Successful archive"
    local log_file="${TEST_DIR}/archive_test.log"
    local out_dir="${TEST_DIR}/output3"
    local arc_dir="${TEST_DIR}/archive3"
    mkdir -p "$out_dir" "$arc_dir"
    create_sample_log "$log_file"

    "$ANALYZE" -o "$out_dir" -a "$arc_dir" "$log_file" >/dev/null 2>&1

    # Check file was archived
    if [ -f "${arc_dir}/archive_test.log" ]; then
        pass "Log file archived successfully"
    else
        fail "Log file not found in archive directory"
    fi

    # Run again - should detect duplicate and not overwrite
    local result
    result=$("$ANALYZE" -o "$out_dir" -a "$arc_dir" "$log_file" 2>&1)
    if echo "$result" | grep -q "already archived"; then
        pass "Duplicate archive detection works"
    else
        fail "Duplicate archive not detected on re-run"
    fi
}

###############################################################################
# Test 4: No-error log generates valid summary
###############################################################################
test_no_errors() {
    echo "Test 4: No-error log generates valid summary"
    local log_file="${TEST_DIR}/clean.log"
    local out_dir="${TEST_DIR}/output4"
    local arc_dir="${TEST_DIR}/archive4"
    mkdir -p "$out_dir" "$arc_dir"
    create_clean_log "$log_file"

    "$ANALYZE" -o "$out_dir" -a "$arc_dir" "$log_file" >/dev/null 2>&1

    local summary
    summary=$(find "$out_dir" -name "summary_clean_*.txt" -type f | head -1)
    if [ -z "$summary" ]; then
        fail "No summary generated for clean log"
        return
    fi
    pass "Summary generated for clean log"

    if grep -q "Total error count: 0" "$summary"; then
        pass "Error count is 0 for clean log"
    else
        fail "Error count incorrect for clean log"
    fi

    if grep -q "(No critical events found)" "$summary"; then
        pass "No-critical-events message displayed"
    else
        fail "Missing no-critical-events message"
    fi

    if grep -q "(No error messages found)" "$summary"; then
        pass "No-error-messages message displayed"
    else
        fail "Missing no-error-messages message"
    fi
}

###############################################################################
# Test 5: Edge case - missing file
###############################################################################
test_missing_file() {
    echo "Test 5: Edge case - missing log file"
    local out_dir="${TEST_DIR}/output5"
    local arc_dir="${TEST_DIR}/archive5"
    mkdir -p "$out_dir" "$arc_dir"

    local result
    result=$("$ANALYZE" -o "$out_dir" -a "$arc_dir" "${TEST_DIR}/nonexistent.log" 2>&1)
    local rc=$?
    if [ $rc -ne 0 ]; then
        pass "Non-zero exit for missing file"
    else
        fail "Should exit non-zero for missing file"
    fi

    if echo "$result" | grep -q "does not exist"; then
        pass "Error message for missing file"
    else
        fail "Missing error message for nonexistent file"
    fi
}

###############################################################################
# Test 6: Edge case - invalid Top N
###############################################################################
test_invalid_topn() {
    echo "Test 6: Edge case - invalid Top N"
    local log_file="${TEST_DIR}/dummy.log"
    create_sample_log "$log_file"

    local result
    result=$("$ANALYZE" -n 0 "$log_file" 2>&1)
    local rc=$?
    if [ $rc -ne 0 ]; then
        pass "Non-zero exit for Top N = 0"
    else
        fail "Should reject Top N = 0"
    fi

    result=$("$ANALYZE" -n abc "$log_file" 2>&1)
    rc=$?
    if [ $rc -ne 0 ]; then
        pass "Non-zero exit for Top N = abc"
    else
        fail "Should reject Top N = abc"
    fi

    result=$("$ANALYZE" -n -3 "$log_file" 2>&1)
    rc=$?
    if [ $rc -ne 0 ]; then
        pass "Non-zero exit for Top N = -3"
    else
        fail "Should reject negative Top N"
    fi
}

###############################################################################
# Run all tests
###############################################################################
main() {
    echo "========================================"
    echo "  log_analyze.sh Regression Tests"
    echo "========================================"
    echo ""

    setup

    test_default_parameters
    echo ""
    test_custom_keywords
    echo ""
    test_archive
    echo ""
    test_no_errors
    echo ""
    test_missing_file
    echo ""
    test_invalid_topn

    teardown

    echo ""
    echo "========================================"
    echo "  Results: ${PASSED} passed, ${FAILED} failed"
    echo "========================================"

    if [ "$FAILED" -gt 0 ]; then
        exit 1
    fi
    exit 0
}

main "$@"

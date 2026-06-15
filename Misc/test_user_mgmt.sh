#!/bin/bash
# Regression tests for user_mgmt.sh
# Mocks sudo/id to avoid real system changes.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$SCRIPT_DIR/user_mgmt.sh"
PASS=0
FAIL=0
MOCK_DIR=""

setup_mocks() {
    MOCK_DIR="$(mktemp -d)"
    # Mock sudo: just execute the command it's given
    cat > "$MOCK_DIR/sudo" <<'MOCK'
#!/bin/bash
exec "$@"
MOCK
    chmod +x "$MOCK_DIR/sudo"

    # Mock useradd: succeed by default
    cat > "$MOCK_DIR/useradd" <<'MOCK'
#!/bin/bash
exit 0
MOCK
    chmod +x "$MOCK_DIR/useradd"

    # Mock deluser: succeed by default
    cat > "$MOCK_DIR/deluser" <<'MOCK'
#!/bin/bash
exit 0
MOCK
    chmod +x "$MOCK_DIR/deluser"

    # Mock id: user does NOT exist by default
    cat > "$MOCK_DIR/id" <<'MOCK'
#!/bin/bash
exit 1
MOCK
    chmod +x "$MOCK_DIR/id"

    export PATH="$MOCK_DIR:$PATH"
}

teardown_mocks() {
    if [[ -n "$MOCK_DIR" && -d "$MOCK_DIR" ]]; then
        rm -rf "$MOCK_DIR"
    fi
}

assert_eq() {
    local desc="$1" expected="$2" actual="$3"
    if [[ "$expected" == "$actual" ]]; then
        echo "  PASS: $desc"
        ((PASS++))
    else
        echo "  FAIL: $desc (expected=$expected, actual=$actual)"
        ((FAIL++))
    fi
}

assert_contains() {
    local desc="$1" pattern="$2" output="$3"
    if echo "$output" | grep -qi "$pattern"; then
        echo "  PASS: $desc"
        ((PASS++))
    else
        echo "  FAIL: $desc (pattern='$pattern' not found in output)"
        ((FAIL++))
    fi
}

# ---- Tests ----

test_no_args_shows_usage() {
    echo "[Test] No arguments shows usage"
    local out
    out=$(bash "$SCRIPT" 2>&1)
    local rc=$?
    assert_eq "exit code is 1" 1 "$rc"
    assert_contains "output contains usage" "usage" "$out"
}

test_invalid_arg_shows_usage() {
    echo "[Test] Invalid argument shows usage"
    local out
    out=$(bash "$SCRIPT" x 2>&1)
    local rc=$?
    assert_eq "exit code is 1" 1 "$rc"
    assert_contains "output contains usage" "usage" "$out"
}

test_create_empty_username() {
    echo "[Test] Create with empty username"
    setup_mocks
    local out
    out=$(echo "" | bash "$SCRIPT" c 2>&1)
    local rc=$?
    assert_eq "exit code is 1" 1 "$rc"
    assert_contains "error about empty" "empty\|cannot" "$out"
    teardown_mocks
}

test_create_whitespace_username() {
    echo "[Test] Create with whitespace-only username"
    setup_mocks
    local out
    out=$(echo "   " | bash "$SCRIPT" c 2>&1)
    local rc=$?
    assert_eq "exit code is 1" 1 "$rc"
    assert_contains "error about whitespace" "empty\|whitespace\|cannot" "$out"
    teardown_mocks
}

test_create_existing_user() {
    echo "[Test] Create user that already exists"
    setup_mocks
    # Make id return 0 (user exists)
    cat > "$MOCK_DIR/id" <<'MOCK'
#!/bin/bash
exit 0
MOCK
    chmod +x "$MOCK_DIR/id"
    local out
    out=$(echo "existinguser" | bash "$SCRIPT" c 2>&1)
    local rc=$?
    assert_eq "exit code is 1" 1 "$rc"
    assert_contains "error about existing" "already exists" "$out"
    teardown_mocks
}

test_create_success() {
    echo "[Test] Create user successfully"
    setup_mocks
    local out
    out=$(echo "newuser" | bash "$SCRIPT" c 2>&1)
    local rc=$?
    assert_eq "exit code is 0" 0 "$rc"
    assert_contains "success message" "created successfully" "$out"
    teardown_mocks
}

test_create_useradd_fails() {
    echo "[Test] Create user when useradd fails"
    setup_mocks
    cat > "$MOCK_DIR/useradd" <<'MOCK'
#!/bin/bash
exit 1
MOCK
    chmod +x "$MOCK_DIR/useradd"
    local out
    out=$(echo "newuser" | bash "$SCRIPT" c 2>&1)
    local rc=$?
    assert_eq "exit code is 1" 1 "$rc"
    assert_contains "error message" "failed\|error" "$out"
    teardown_mocks
}

test_delete_empty_username() {
    echo "[Test] Delete with empty username"
    setup_mocks
    local out
    out=$(echo "" | bash "$SCRIPT" d 2>&1)
    local rc=$?
    assert_eq "exit code is 1" 1 "$rc"
    assert_contains "error about empty" "empty\|cannot" "$out"
    teardown_mocks
}

test_delete_nonexistent_user() {
    echo "[Test] Delete user that does not exist"
    setup_mocks
    # id already returns 1 (not found) by default
    local out
    out=$(echo "ghostuser" | bash "$SCRIPT" d 2>&1)
    local rc=$?
    assert_eq "exit code is 1" 1 "$rc"
    assert_contains "error about not exist" "does not exist" "$out"
    teardown_mocks
}

test_delete_success() {
    echo "[Test] Delete user successfully"
    setup_mocks
    # Make id return 0 (user exists)
    cat > "$MOCK_DIR/id" <<'MOCK'
#!/bin/bash
exit 0
MOCK
    chmod +x "$MOCK_DIR/id"
    local out
    out=$(echo "realuser" | bash "$SCRIPT" d 2>&1)
    local rc=$?
    assert_eq "exit code is 0" 0 "$rc"
    assert_contains "success message" "deleted successfully" "$out"
    teardown_mocks
}

test_delete_deluser_fails() {
    echo "[Test] Delete user when deluser fails"
    setup_mocks
    cat > "$MOCK_DIR/id" <<'MOCK'
#!/bin/bash
exit 0
MOCK
    chmod +x "$MOCK_DIR/id"
    cat > "$MOCK_DIR/deluser" <<'MOCK'
#!/bin/bash
exit 1
MOCK
    chmod +x "$MOCK_DIR/deluser"
    local out
    out=$(echo "realuser" | bash "$SCRIPT" d 2>&1)
    local rc=$?
    assert_eq "exit code is 1" 1 "$rc"
    assert_contains "error message" "failed\|error" "$out"
    teardown_mocks
}

# ---- Run all tests ----
echo "=== user_mgmt.sh regression tests ==="
test_no_args_shows_usage
test_invalid_arg_shows_usage
test_create_empty_username
test_create_whitespace_username
test_create_existing_user
test_create_success
test_create_useradd_fails
test_delete_empty_username
test_delete_nonexistent_user
test_delete_success
test_delete_deluser_fails

echo ""
echo "Results: $PASS passed, $FAIL failed"
if [[ "$FAIL" -gt 0 ]]; then
    exit 1
fi
exit 0

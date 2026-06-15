#!/bin/bash
# test_user_mgmt.sh - Regression tests for user_mgmt.sh
# Uses mock binaries (sudo, useradd, deluser, id) placed ahead of $PATH
# so no real system users are touched.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TARGET="$SCRIPT_DIR/user_mgmt.sh"

PASS=0
FAIL=0

# --- helpers ------------------------------------------------------------------

setup_env() {
    MOCK_DIR="$(mktemp -d)"
    # Create mock `sudo` that simply executes its arguments (stripping sudo).
    cat > "$MOCK_DIR/sudo" << 'EOF'
#!/bin/bash
"$@"
EOF
    chmod +x "$MOCK_DIR/sudo"

    cp "$TARGET" "$MOCK_DIR/user_mgmt.sh"
    chmod +x "$MOCK_DIR/user_mgmt.sh"

    export PATH="$MOCK_DIR:$PATH"
}

teardown_env() {
    rm -rf "$MOCK_DIR"
}

# Write a mock binary into MOCK_DIR.
mock_bin() {
    local name="$1" body="$2"
    printf '%s\n' "#!/bin/bash" "$body" > "$MOCK_DIR/$name"
    chmod +x "$MOCK_DIR/$name"
}

# Clear all mock binaries except sudo and user_mgmt.sh.
clear_mocks() {
    local f
    for f in "$MOCK_DIR"/*; do
        local base; base="$(basename "$f")"
        case "$base" in
            sudo|user_mgmt.sh) ;;
            *) rm -f "$f" ;;
        esac
    done
}

# Run user_mgmt.sh with action and optional username as $2.
run_script() {
    local action="$1" user="${2:-}"
    bash "$MOCK_DIR/user_mgmt.sh" "$action" "$user" 2>&1
}

assert_exit() {
    local label="$1" expected="$2" actual="$3"
    if [[ "$expected" -eq "$actual" ]]; then
        echo "  PASS: $label (exit=$actual)"
        (( PASS++ ))
    else
        echo "  FAIL: $label — expected exit=$expected, got exit=$actual"
        (( FAIL++ ))
    fi
}

assert_contains() {
    local label="$1" needle="$2" haystack="$3"
    if echo "$haystack" | grep -qF "$needle"; then
        echo "  PASS: $label (output contains '$needle')"
        (( PASS++ ))
    else
        echo "  FAIL: $label — output does not contain '$needle'"
        echo "        got: $haystack"
        (( FAIL++ ))
    fi
}

assert_not_contains() {
    local label="$1" needle="$2" haystack="$3"
    if ! echo "$haystack" | grep -qF "$needle"; then
        echo "  PASS: $label (output does NOT contain '$needle')"
        (( PASS++ ))
    else
        echo "  FAIL: $label — output unexpectedly contains '$needle'"
        echo "        got: $haystack"
        (( FAIL++ ))
    fi
}

# --- tests --------------------------------------------------------------------

test_no_args_shows_usage() {
    echo "[test] No arguments → usage + exit 1"
    local out; out="$(bash "$MOCK_DIR/user_mgmt.sh" 2>&1)"; local rc=$?
    assert_exit  "exit code" 1 $rc
    assert_contains "usage hint" "Usage:" "$out"
}

test_invalid_action_shows_usage() {
    echo "[test] Invalid action 'x' → usage + exit 1"
    local out; out="$(bash "$MOCK_DIR/user_mgmt.sh" "x" 2>&1)"; local rc=$?
    assert_exit  "exit code" 1 $rc
    assert_contains "usage hint" "Usage:" "$out"
}

test_create_empty_username() {
    echo "[test] Create with empty username → error + exit 1"
    clear_mocks
    mock_bin id 'exit 1'
    local out; out="$(run_script "c" "" 2>&1)"; local rc=$?
    assert_exit  "exit code" 1 $rc
    assert_contains "error msg" "empty or blank" "$out"
}

test_create_blank_username() {
    echo "[test] Create with blank (spaces-only) username → error + exit 1"
    clear_mocks
    mock_bin id 'exit 1'
    local out; out="$(run_script "c" "   " 2>&1)"; local rc=$?
    assert_exit  "exit code" 1 $rc
    assert_contains "error msg" "empty or blank" "$out"
}

test_create_duplicate_user() {
    echo "[test] Create already-existing user → error + exit 1"
    clear_mocks
    mock_bin id 'exit 0'
    local out; out="$(run_script "c" "alice" 2>&1)"; local rc=$?
    assert_exit  "exit code" 1 $rc
    assert_contains "error msg" "already exists" "$out"
}

test_create_success() {
    echo "[test] Create new user → success + exit 0"
    clear_mocks
    mock_bin id 'exit 1'
    mock_bin useradd 'exit 0'
    local out; out="$(run_script "c" "bob" 2>&1)"; local rc=$?
    assert_exit  "exit code" 0 $rc
    assert_contains "success msg" "created successfully" "$out"
}

test_create_useradd_fails() {
    echo "[test] Create but useradd fails → error + exit 1"
    clear_mocks
    mock_bin id 'exit 1'
    mock_bin useradd 'exit 1'
    local out; out="$(run_script "c" "charlie" 2>&1)"; local rc=$?
    assert_exit  "exit code" 1 $rc
    assert_contains "error msg" "Failed to create" "$out"
}

test_delete_nonexistent_user() {
    echo "[test] Delete non-existing user → error + exit 1"
    clear_mocks
    mock_bin id 'exit 1'
    local out; out="$(run_script "d" "ghost" 2>&1)"; local rc=$?
    assert_exit  "exit code" 1 $rc
    assert_contains "error msg" "does not exist" "$out"
}

test_delete_success() {
    echo "[test] Delete existing user → success + exit 0"
    clear_mocks
    mock_bin id 'exit 0'
    mock_bin deluser 'exit 0'
    local out; out="$(run_script "d" "dave" 2>&1)"; local rc=$?
    assert_exit  "exit code" 0 $rc
    assert_contains "success msg" "deleted successfully" "$out"
}

test_delete_deluser_fails() {
    echo "[test] Delete but deluser fails → error + exit 1"
    clear_mocks
    mock_bin id 'exit 0'
    mock_bin deluser 'exit 1'
    local out; out="$(run_script "d" "eve" 2>&1)"; local rc=$?
    assert_exit  "exit code" 1 $rc
    assert_contains "error msg" "Failed to delete" "$out"
}

test_no_unconditional_execution() {
    echo "[test] Script does not execute create/delete before dispatch"
    clear_mocks
    # If the script ran create_user or del_user unconditionally,
    # it would call useradd/deluser even for invalid actions.
    # Use a tracker file to detect this.
    local tracker; tracker="$(mktemp)"
    mock_bin useradd "echo called >> '$tracker'; exit 0"
    mock_bin deluser "echo called >> '$tracker'; exit 0"
    mock_bin id 'exit 1'
    # Run with invalid action - should NOT call useradd or deluser.
    bash "$MOCK_DIR/user_mgmt.sh" "x" 2>&1 || true
    if [[ ! -s "$tracker" ]]; then
        echo "  PASS: no unconditional function calls"
        (( PASS++ ))
    else
        echo "  FAIL: useradd/deluser called before dispatch"
        (( FAIL++ ))
    fi
    rm -f "$tracker"
}

# --- run all ------------------------------------------------------------------

setup_env

test_no_args_shows_usage
test_invalid_action_shows_usage
test_create_empty_username
test_create_blank_username
test_create_duplicate_user
test_create_success
test_create_useradd_fails
test_delete_nonexistent_user
test_delete_success
test_delete_deluser_fails
test_no_unconditional_execution

teardown_env

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]] && echo "All tests passed." || { echo "Some tests failed."; exit 1; }

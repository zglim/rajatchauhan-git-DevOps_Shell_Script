#!/bin/bash

# user_mgmt.sh - Create or delete a system user.
# Usage: user_mgmt.sh <action> [username]
#   action:   c (create) | d (delete)
#   username: optional; prompted interactively if omitted.

set -uo pipefail

# --- shared helpers -----------------------------------------------------------

die() { echo "Error: $1" >&2; exit 1; }

usage() { echo "Usage: $0 {c|d} [username]" >&2; exit 1; }

# Resolve username: use $2 if given, otherwise prompt interactively.
# Result is stored in the global variable `username`.
resolve_username() {
    if [[ -n "${1:-}" ]]; then
        username="$1"
    else
        read -rp "Enter Username: " username
    fi
    # Validate: reject empty or whitespace-only names.
    local trimmed="${username// /}"
    [[ -z "$trimmed" ]] && die "Username cannot be empty or blank."
}

# Check whether a user already exists on the system.
user_exists() { id "$1" >/dev/null 2>&1; }

# --- action functions ---------------------------------------------------------

do_create() {
    echo "User creation in progress"
    resolve_username "${1:-}"

    if user_exists "$username"; then
        die "User '$username' already exists."
    fi

    if sudo useradd -m "$username"; then
        echo "User '$username' created successfully."
    else
        die "Failed to create user '$username'."
    fi
}

do_delete() {
    echo "User deletion in progress"
    resolve_username "${1:-}"

    if ! user_exists "$username"; then
        die "User '$username' does not exist."
    fi

    if sudo deluser --remove-home "$username"; then
        echo "User '$username' deleted successfully."
    else
        die "Failed to delete user '$username'."
    fi
}

# --- main dispatch ------------------------------------------------------------

[[ $# -lt 1 ]] && usage

case "$1" in
    c) do_create "${2:-}" ;;
    d) do_delete "${2:-}" ;;
    *) usage ;;
esac
